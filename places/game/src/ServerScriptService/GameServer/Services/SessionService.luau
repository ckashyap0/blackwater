--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Slots=require(Shared.Utilities.CabinSlots)
local V=require(Shared.Utilities.Validation)
local Places=require(Shared.Config.PlaceConfig)
local Directory=require(script.Parent.Parent.Data.SessionDirectory)
local Policy=require(script.Parent.Parent.Data.SessionPolicy)
local Gateway=require(script.Parent.Parent.Data.TeleportGateway)
local Service={};Service.__index=Service
local finished={Resolving=true,Failed=true,Completed=true,Closing=true}
-- Per-player progress inside one descent session, saved to DataStoreService under the session ID,
-- so a crew member who disconnects can rejoin their friends' still-running server and pick up
-- exactly where they were: same floor, same spot, same stamina and life state.
--  * key "<sessionId>/<userId>" in the EH_SessionProgress_v1 store
--  * written when the player leaves and every 15 s while they play (multi-player sessions only;
--    a solo session ends the moment its only player leaves)
--  * read back when they rejoin if this server has no in-memory copy, removed when the session ends
-- In Studio (or if DataStores are unavailable) it is a server-memory table only.
local Progress={};Progress.__index=Progress
Progress.StoreName="EH_SessionProgress_v1"
function Progress.new(dataStore)
	local ds=dataStore
	if ds==nil and not RunService:IsStudio() then
		local ok,result=pcall(function()return game:GetService("DataStoreService"):GetDataStore(Progress.StoreName)end)
		ds=ok and result or nil
	end
	return setmetatable({_ds=ds,_memory={}},Progress)
end
local function progressKey(sessionId,userId)return tostring(sessionId).."/"..tostring(userId)end
function Progress.Encode(entry)
	if type(entry)~="table" or type(entry.floor)~="string" then return nil end
	local record={floor=entry.floor,completed=entry.completed or 0,stamina=entry.stamina,life=entry.life,savedAt=os.time()}
	if typeof(entry.frame)=="CFrame" then local f=entry.frame;local look=f.LookVector;record.frame={f.X,f.Y,f.Z,math.atan2(-look.X,-look.Z)}end
	return record
end
function Progress.Decode(record)
	if type(record)~="table" or type(record.floor)~="string" then return nil end
	local entry={floor=record.floor,completed=tonumber(record.completed) or 0,stamina=tonumber(record.stamina),life=record.life}
	local f=record.frame
	if type(f)=="table" and #f==4 then entry.frame=CFrame.new(f[1],f[2],f[3])*CFrame.Angles(0,f[4],0)end
	return entry
end
function Progress:Save(sessionId,userId,entry)
	local record=Progress.Encode(entry);if not record then return false end
	local k=progressKey(sessionId,userId);self._memory[k]=record
	if not self._ds then return true end
	return (pcall(function()self._ds:SetAsync(k,record,{userId})end))
end
function Progress:Load(sessionId,userId)
	local k=progressKey(sessionId,userId);local record=self._memory[k]
	if not record and self._ds then local ok,result=pcall(function()return self._ds:GetAsync(k)end);if ok then record=result end end
	return Progress.Decode(record)
end
function Progress:Clear(sessionId,userId)
	local k=progressKey(sessionId,userId);self._memory[k]=nil
	if self._ds then pcall(function()self._ds:RemoveAsync(k)end)end
end
Service.Progress=Progress
function Service.new(options)
	options=options or {}
	return setmetatable({_players=options.players or Players,_clock=options.clock or os.time,_mono=options.monotonic or os.clock,
		_server=options.server or {privateId=game.PrivateServerId,ownerId=game.PrivateServerOwnerId,jobId=game.JobId,universe=game.GameId},
		_requiredOverride=options.required,_providedDirectory=options.directory,_providedProgress=options.progress,Name="SessionService",Dependencies={"EnvironmentService","ProfileService","GameRunService","CharacterService","SurvivalService","InventoryService","InteractionService"},
	_joining={},_ready={},_admitted={},_lastSafe={},_removed={},_pending={},_publishing=false},Service)end
function Service:Init(deps)
	self._environment=deps.EnvironmentService;self._profiles=deps.ProfileService;self._runs=deps.GameRunService
	self._characters=deps.CharacterService;self._survival=deps.SurvivalService;self._inventory=deps.InventoryService;self._interactions=deps.InteractionService
	self._scope=Scope.new();self._directory=self._providedDirectory or Directory.new()
	self._progress=self._providedProgress or Progress.new()
	self._required=self._environment.Role=="Game" and not RunService:IsStudio()
	if self._requiredOverride~=nil then self._required=self._requiredOverride end
	self._characters:SetAdmissionRequired(self._required)
	self._survival:SetConnectionManaged(self._required)
end
function Service:ClientReady(p)self._ready[p]=true end
function Service:IsReady(p)return not self._required or self._admitted[p]==true end
-- Someone arrived who is not on this descent's crew list, or whose place in it is gone: joining a
-- friend through Roblox's own "Join" lands outside the crew's reserved server, and a run that
-- has already ended cannot be re-entered. Instead of a hard kick they are sent back to the lobby,
-- which tells them why. (Only if that teleport cannot even start are they disconnected.)
local NOT_YOUR_DESCENT="This game is only for its crew. Join your friend's lift in the lobby to play together."
function Service:_Reject(p)
	self._joining[p]=nil;self._admitted[p]=nil
	p:SetAttribute("EHSessionAdmitted",false)
	if p.Parent~=self._players then return end
	p:SetAttribute("EHPartyMessage","Returning you to the lobby...")
	local sent=not RunService:IsStudio() and pcall(function()Gateway.Return(p,NOT_YOUR_DESCENT)end)
	if not sent then p:Kick("This game is only for its crew. Join your friends' lift in the lobby.");return end
	-- the transfer is asynchronous; if it never goes through, fall back to disconnecting
	task.delay(20,function()if p.Parent==self._players and not self._admitted[p] then p:Kick("This game is only for its crew. Join your friends' lift in the lobby.")end end)
end
function Service:_SafeFrame(p)
	local view=self._runs:GetViewFor(p.UserId);local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not root or not view or not view.floorInstanceId then return nil end
	local boundsOK=self._inventory:_InBounds(view.floorInstanceId,root.Position)
	local spawn=self._environment.Spawn
	local cabin=spawn and (root.Position-spawn.Position).Magnitude<10
	if not boundsOK and not cabin then return nil end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={p.Character}
	local hit=workspace:Raycast(root.Position,Vector3.new(0,-8,0),params)
	if hit and hit.Normal.Y>.5 then return root.CFrame end
	return nil
end
function Service:_RestorableFrame(p,frame)
	if typeof(frame)~="CFrame" then return false end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances=p.Character and {p.Character} or {}
	local hit=workspace:Raycast(frame.Position,Vector3.new(0,-8,0),params)
	return hit~=nil and hit.Instance.CanCollide and hit.Normal.Y>.5
end
function Service:_Join(p)
	if not self._required or self._joining[p] or self._admitted[p] then return end
	if self._ended then self:_Reject(p);return end
	self._joining[p]={deadline=self._clock()+20,loading=true}
	local ok,ticket=pcall(function()
		local data=p:GetJoinData();local d=data.TeleportData
		assert(data.SourceGameId==self._server.universe and data.SourcePlaceId==Places.LobbyPlaceId,"WrongSource")
		assert(type(d)=="table" and V.IsIdentifier(d.sessionId,64),"MissingTicket")
		assert(self._server.ownerId==0 and self._server.privateId~="","ReservedServerRequired")
		if self._ticket then assert(self._ticket.id==d.sessionId,"WrongSession")end
		local claimed=assert(self._directory:Claim(d.sessionId,p.UserId,self._server.privateId,self._server.jobId))
		return claimed
	end)
	if not self._active or not ok or p.Parent~=self._players then self:_Reject(p);return end
	if self._ticket and self._ticket.id~=ticket.id then self:_Reject(p);return end
	self._ticket=ticket;self._removed[p.UserId]=nil
	local run=self._runs:GetSnapshot();local participant=run and run.participants[tostring(p.UserId)]
	if run and (finished[run.phase] or not participant or participant.connectionState=="Abandoned" or Policy.ConnectionExpired(participant,self._clock())) then self:_Reject(p);return end
	local spawn=self._environment.Spawn;local frame=spawn and Slots.Frame(spawn.CFrame,p.UserId,ticket.roster)
	local previous=self._lastSafe[p.UserId]
	if not previous and run then
		-- no copy in this server's memory: fall back to the DataStore record for this session
		previous=self._progress:Load(ticket.id,p.UserId)
		if p.Parent~=self._players or not self._active then self:_Reject(p);return end
		if previous then self._lastSafe[p.UserId]=previous end
	end
	local advanced=run and previous and (previous.floor~=run.currentFloorInstanceId or #run.completedFloorNumbers>(previous.completed or 0))
	local life=participant and participant.lifeState or "Alive"
	if advanced then life="Alive" end
	if previous and not advanced and previous.frame then
		-- Revalidate the saved point against the current server-owned floor bounds.
		if self._inventory:_InBounds(previous.floor,previous.frame.Position) and self:_RestorableFrame(p,previous.frame) then
			frame=previous.frame
		else
			local ok,recovery=pcall(function()return self._inventory:_Recovery(previous.floor)*CFrame.new(0,3,0)end)
			if ok and self:_RestorableFrame(p,recovery) then frame=recovery end
		end
	end
	-- A fresh run starts on the surface: the boarding yard puts each new character straight onto
	-- its own apron spot. Handing it a spot inside the lift as well made it spawn in the cabin and
	-- get moved out again (clipping through the lift walls/floor at the very start).
	if not run and game.ReplicatedStorage.Game:GetAttribute("SurfacePending")==true then frame=nil end
	local deadline=participant and participant.reconnectDeadline or ticket.members[tostring(p.UserId)].deadline
	self._joining[p]={deadline=math.min(self._clock()+20,deadline or math.huge),life=life,advanced=advanced,frame=frame,
		floor=run and run.currentFloorInstanceId,completed=run and #run.completedFloorNumbers or 0,
		stamina=not advanced and previous and previous.stamina or nil}
	self._characters:Admit(p,life,frame,self._joining[p].stamina)
	p:SetAttribute("EHSessionAdmitted",false)
end
function Service:_Publish()
	if not self._active or not self._ticket then return end
	if self._publishing then self._publishDirty=true;return end
	self._publishing=true
	self._publishDirty=false
	task.spawn(function()
		local ok=pcall(function()
			local snapshot=self._runs:GetSnapshot();local members={};local ended=snapshot and finished[snapshot.phase] or false
			if snapshot then
				for id,p in snapshot.participants do
					local player=self._players:GetPlayerByUserId(p.userId)
					members[id]={state=player and self._joining[player] and "Joining" or p.connectionState,deadline=p.reconnectDeadline or 0}
				end
			else
				for id,m in self._ticket.members do
					local uid=tonumber(id);local player=self._players:GetPlayerByUserId(uid)
					members[id]={state=self._removed[uid] and "Disconnected" or (player and self._admitted[player] and "Joining" or m.state),deadline=m.deadline}
				end
			end
			assert(self._directory:Publish(self._ticket.id,self._server.jobId,members,ended),"SessionLeaseLost")
			self._leaseAt=self._clock()
		end)
		if not ok then self._leaseError=true else self._leaseError=false end
		self._publishing=false
		if self._publishDirty and self._active then self:_Publish() end
	end)
end
function Service:_StartRun()
	if self._runs:GetSnapshot() or not self._ticket then return end
	local present={};local count=0
	for _,id in self._ticket.roster do local p=self._players:GetPlayerByUserId(id);if p and self._admitted[p] then present[id]=true;count+=1 end end
	if count==0 and self._clock()>=self._ticket.arrivalDeadline then
		pcall(function()self._directory:End(self._ticket.id)end)
		for _,p in self._players:GetPlayers() do self:_Reject(p)end
		return
	end
	if count==0 or (count<#self._ticket.roster and self._clock()<self._ticket.arrivalDeadline) then return end
	local result=self._runs:CreateSessionRun(self._ticket.id,self._ticket.roster,present,self._ticket.arrivalDeadline+120)
	if not result.ok then return end
	for _,action in {"Queue","BeginIntro"} do self._runs:Dispatch({token=self._runs:GetToken(),action=action,payload={}})end
	self._introUntil=self._mono()+3
	for _,p in self._players:GetPlayers() do if self._admitted[p] then self._characters:SetSuspended(p,false);p:SetAttribute("EHReturnSerial",(p:GetAttribute("EHReturnSerial") or 0)+1)end end
	self:_Publish()
end
function Service:_Step()
	local now=self._clock()
	for p,j in self._joining do
		if now>=j.deadline then self:_Reject(p)
		elseif not j.loading then
			local run=self._runs:GetSnapshot()
			if run then
				local record=run.participants[tostring(p.UserId)]
				if not record or record.connectionState=="Abandoned" or finished[run.phase] or Policy.ConnectionExpired(record,now) then self:_Reject(p);continue end
				if j.floor~=run.currentFloorInstanceId or j.completed<#run.completedFloorNumbers then
					j.floor=run.currentFloorInstanceId;j.completed=#run.completedFloorNumbers;j.advanced=true;j.life="Alive";j.stamina=nil
					j.frame=self._environment.Spawn and Slots.Frame(self._environment.Spawn.CFrame,p.UserId,run.originalRoster)
					self._characters:RetargetAdmission(p,j.life,j.frame)
				elseif not j.advanced and record.lifeState~=j.life then
					j.life=record.lifeState;self._characters:RetargetAdmission(p,j.life,nil)
				end
			end
			-- Before the run exists the surface yard is still pending and characters are deliberately not
			-- created yet (CharacterService.Spawn waits for boarding). Waiting for a character here as
			-- well deadlocked the start: no character -> no admission -> no run -> no boarding -> no
			-- character, until a 15 s safety cap spawned everyone frozen inside the dark lift.
			local deferred=not run and game.ReplicatedStorage.Game:GetAttribute("SurfacePending")==true and game.ReplicatedStorage.Game:GetAttribute("SurfaceBoarding")~=true
			if not self._ready[p] or not self._profiles:IsReady(p) or not (deferred or self._characters:IsCharacterReady(p,j.life)) then continue end
			if run then
				self._survival:RestoreReconnect(p,j.advanced==true)
				self._runs:SetConnection(p.UserId,"Connected",nil)
			end
			self._joining[p]=nil;self._admitted[p]=true;self._characters:SetAdmissionReady(p,true)
			p:SetAttribute("EHSessionAdmitted",true)
			self._characters:RestoreAdmissionStamina(p,j.stamina)
			self._characters:SetSuspended(p,not run);self._survival:RefreshPlayer(p);self:_Publish()
		end
	end
	self:_StartRun()
	local snapshot=self._runs:GetSnapshot()
	if snapshot then
		for _,p in self._players:GetPlayers() do
			if self._admitted[p] and p:GetAttribute("EHLifeState")~="Dead" then
				local frame=self:_SafeFrame(p)
				if frame then self._lastSafe[p.UserId]={floor=snapshot.currentFloorInstanceId,completed=#snapshot.completedFloorNumbers,frame=frame,stamina=p:GetAttribute("EHStamina")} end
			end
		end
		for _,p in snapshot.participants do if Policy.ConnectionExpired(p,now) then self._runs:SetConnection(p.userId,"Abandoned",nil)end end
		if not self._runs.FloorsManaged and self._introUntil and self._mono()>=self._introUntil and snapshot.phase=="Intro" and self._runs:HasConnectedParticipant() then
			self._introUntil=nil
			for _,action in {"PrepareFloor","ActivateFloor"} do self._runs:Dispatch({token=self._runs:GetToken(),action=action,payload={}})end
		end
		if self._leaseError and now-(self._leaseAt or self._ticket.createdAt)>50 and not finished[snapshot.phase] then
			self._runs:Dispatch({token=self._runs:GetToken(),action="TechnicalFailure",payload={reason="InternalError"}})
			self._runs:Dispatch({token=self._runs:GetToken(),action="Resolve",payload={}})
		end
	end
end
function Service:_Leave(p)
	local wasAdmitted=self._admitted[p]
	self._joining[p]=nil;self._admitted[p]=nil;self._ready[p]=nil;self._removed[p.UserId]=true
	local snapshot=self._runs:GetSnapshot()
	if wasAdmitted and snapshot and snapshot.participants[tostring(p.UserId)] and not finished[snapshot.phase] then
		local safe=self:_SafeFrame(p) or (self._lastSafe[p.UserId] and self._lastSafe[p.UserId].frame)
		self._lastSafe[p.UserId]={floor=snapshot.currentFloorInstanceId,completed=#snapshot.completedFloorNumbers,frame=safe,stamina=p:GetAttribute("EHStamina")}
		self._inventory:Drop(p);self._interactions:Cancel(p,"Disconnected")
		self._runs:SetConnection(p.UserId,"Disconnected",self._clock()+120)
		self._survival:RecalculateContinuation()
		local saved=table.clone(self._lastSafe[p.UserId]);saved.life=snapshot.participants[tostring(p.UserId)].lifeState
		if self._ticket then local id=self._ticket.id;task.spawn(function()self._progress:Save(id,p.UserId,saved)end)end
	end
	-- Nobody left on this server (a solo player, or the last of the crew): the session is over.
	-- It is closed in the directory straight away, so nobody can be sent back into a dead run, and
	-- Roblox shuts the now-empty reserved server down (BindToClose -> Destroy).
	local others=0;for _,o in self._players:GetPlayers() do if o~=p and o.Parent==self._players then others+=1 end end
	if others==0 and self._ticket then self:_EndSession();return end
	self:_Publish()
end
function Service:_EndSession()
	if self._ended or not self._ticket then return end
	self._ended=true
	local ticket=self._ticket
	pcall(function()self._directory:End(ticket.id)end)
	for _,uid in ticket.roster do task.spawn(function()self._progress:Clear(ticket.id,uid)end)end
	for _,o in self._players:GetPlayers() do if self._joining[o] then self:_Reject(o)end end
end
function Service:_SaveProgress()
	if self._ended or not self._ticket or #self._ticket.roster<2 then return end
	local snapshot=self._runs:GetSnapshot();if not snapshot or finished[snapshot.phase] then return end
	local id=self._ticket.id
	for _,p in self._players:GetPlayers() do
		local entry=self._admitted[p] and self._lastSafe[p.UserId]
		local record=entry and snapshot.participants[tostring(p.UserId)]
		if record then local saved=table.clone(entry);saved.life=record.lifeState;task.spawn(function()self._progress:Save(id,p.UserId,saved)end)end
	end
end
function Service:ReturnLobby(p)
	local snapshot=self._runs:GetSnapshot()
	if not snapshot or not finished[snapshot.phase] then return false,"RunNotFinished" end
	if RunService:IsStudio() then p:SetAttribute("EHPartyMessage","Returning between Places requires the published game.");return false,"PublishedClientRequired" end
	if self._pending[p] then return false,"Launching" end
	self._pending[p]=true;local ok=pcall(function()Gateway.Return(p)end)
	p:SetAttribute("EHPartyMessage",ok and "Returning to lobby…" or "Return failed. Please try again.")
	task.delay(5,function()self._pending[p]=nil end)
	return ok,ok and "Returning" or "TransferFailed"
end
function Service:Start()
	self._active=true
	if not self._required then
		-- Studio testing: RunService:IsStudio() means no real teleport ever happened, so there is
		-- no session ticket, no reserved server, nothing in SessionDirectory to claim. The
		-- production path below (_Join/_StartRun/Gateway/Directory) depends entirely on that real
		-- ticket and is intentionally left untouched -- this branch instead starts a run directly
		-- from whoever is already in the test server, so gameplay is reachable without needing a
		-- published game or a real private-server teleport at all.
		self._scope:Add(RunService.Heartbeat:Connect(function(dt)
			self._devElapsed=(self._devElapsed or 0)+dt
			if self._devElapsed<1 then return end
			self._devElapsed=0;self:_StepDev()
		end))
		return
	end
	self._scope:Add(self._players.PlayerAdded:Connect(function(p)task.spawn(function()self:_Join(p)end)end))
	self._scope:Add(self._players.PlayerRemoving:Connect(function(p)self:_Leave(p)end))
	self._scope:Add(self._runs:Subscribe(function()self:_Publish()end))
	for _,p in self._players:GetPlayers() do task.spawn(function()self:_Join(p)end)end
	local elapsed,heartbeat=0,0
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;heartbeat+=dt
		if elapsed>=.25 then elapsed=0;self:_Step()end
		if heartbeat>=15 then heartbeat=0;self:_Publish();self:_SaveProgress()end
	end))
end
function Service:_StepDev()
	local snapshot=self._runs:GetSnapshot()
	if not snapshot then
		local roster={}
		for _,p in self._players:GetPlayers() do table.insert(roster,p.UserId) end
		if #roster==0 then return end
		local result=self._runs:CreateRun(roster,0)
		if not result.ok then return end -- e.g. a profile is still loading; retry next tick
		for _,action in {"Queue","BeginIntro"} do self._runs:Dispatch({token=self._runs:GetToken(),action=action,payload={}})end
		for _,p in self._players:GetPlayers() do
			local frame=self._environment.Spawn and Slots.Frame(self._environment.Spawn.CFrame,p.UserId,roster)
			-- (surface start: the boarding yard places the character, never the lift)
			if game.ReplicatedStorage.Game:GetAttribute("SurfacePending")==true or game.ReplicatedStorage.Game:GetAttribute("SurfaceBoarding")==true then frame=nil end
			self._characters:Admit(p,"Alive",frame,nil)
			self._characters:SetAdmissionReady(p,true)
			p:SetAttribute("EHSessionAdmitted",true)
			self._characters:SetSuspended(p,false)
		end
		self._devIntroAt=os.clock();return
	end
	-- Studio shortcut only where no elevator manages floors. In the Game place the elevator runs
	-- the intro and actually loads the floor; jumping straight to FloorActive skipped that and
	-- left an empty "active" floor with no tasks.
	if snapshot.phase=="Intro" and not self._runs.FloorsManaged and os.clock()-(self._devIntroAt or 0)>=3 then
		for _,action in {"PrepareFloor","ActivateFloor"} do self._runs:Dispatch({token=self._runs:GetToken(),action=action,payload={}})end
	end
end
function Service:Destroy()
	self._active=false;if self._scope then self._scope:Destroy()end
	if self._ticket and not self._ended then self._ended=true;pcall(function()self._directory:End(self._ticket.id)end)end
end
return table.freeze(Service)
