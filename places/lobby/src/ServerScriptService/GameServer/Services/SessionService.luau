--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local V=require(Shared.Utilities.Validation)
local Places=require(Shared.Config.PlaceConfig)
local Directory=require(script.Parent.Parent.Data.SessionDirectory)
local Policy=require(script.Parent.Parent.Data.SessionPolicy)
local Gateway=require(script.Parent.Parent.Data.TeleportGateway)
local Service={};Service.__index=Service
local finished={Resolving=true,Failed=true,Completed=true,Closing=true}
function Service.new(options)
	options=options or {}
	return setmetatable({_players=options.players or Players,_clock=options.clock or os.time,_mono=options.monotonic or os.clock,
		_server=options.server or {privateId=game.PrivateServerId,ownerId=game.PrivateServerOwnerId,jobId=game.JobId,universe=game.GameId},
		_requiredOverride=options.required,_providedDirectory=options.directory,Name="SessionService",Dependencies={"EnvironmentService","ProfileService","GameRunService","CharacterService","SurvivalService","InventoryService","InteractionService"},
	_joining={},_ready={},_admitted={},_lastSafe={},_removed={},_pending={},_publishing=false},Service)end
function Service:Init(deps)
	self._environment=deps.EnvironmentService;self._profiles=deps.ProfileService;self._runs=deps.GameRunService
	self._characters=deps.CharacterService;self._survival=deps.SurvivalService;self._inventory=deps.InventoryService;self._interactions=deps.InteractionService
	self._scope=Scope.new();self._directory=self._providedDirectory or Directory.new()
	self._required=self._environment.Role=="Game" and not RunService:IsStudio()
	if self._requiredOverride~=nil then self._required=self._requiredOverride end
	self._characters:SetAdmissionRequired(self._required)
	self._survival:SetConnectionManaged(self._required)
end
function Service:ClientReady(p)self._ready[p]=true end
function Service:IsReady(p)return not self._required or self._admitted[p]==true end
function Service:_Reject(p)
	self._joining[p]=nil;self._admitted[p]=nil
	p:SetAttribute("EHSessionAdmitted",false)
	if p.Parent==self._players then p:Kick("This game isn't available. Go back to the lobby.")end
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
	local spawn=self._environment.Spawn;local frame=spawn and spawn.CFrame*CFrame.new(0,3,0)
	local previous=self._lastSafe[p.UserId]
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
					j.frame=self._environment.Spawn and self._environment.Spawn.CFrame*CFrame.new(0,3,0)
					self._characters:RetargetAdmission(p,j.life,j.frame)
				elseif not j.advanced and record.lifeState~=j.life then
					j.life=record.lifeState;self._characters:RetargetAdmission(p,j.life,nil)
				end
			end
			if not self._ready[p] or not self._profiles:IsReady(p) or not self._characters:IsCharacterReady(p,j.life) then continue end
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
	end
	self:_Publish()
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
	if not self._required then return end
	self._scope:Add(self._players.PlayerAdded:Connect(function(p)task.spawn(function()self:_Join(p)end)end))
	self._scope:Add(self._players.PlayerRemoving:Connect(function(p)self:_Leave(p)end))
	self._scope:Add(self._runs:Subscribe(function()self:_Publish()end))
	for _,p in self._players:GetPlayers() do task.spawn(function()self:_Join(p)end)end
	local elapsed,heartbeat=0,0
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;heartbeat+=dt
		if elapsed>=.25 then elapsed=0;self:_Step()end
		if heartbeat>=15 then heartbeat=0;self:_Publish()end
	end))
end
function Service:Destroy()
	self._active=false;if self._scope then self._scope:Destroy()end
	if self._ticket then pcall(function()self._directory:End(self._ticket.id)end)end
end
return table.freeze(Service)
