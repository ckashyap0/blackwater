--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Http=game:GetService("HttpService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Model=require(script.Parent.Parent.Data.PartyModel)
local Policy=require(script.Parent.Parent.Data.SessionPolicy)
local Directory=require(script.Parent.Parent.Data.SessionDirectory)
local Gateway=require(script.Parent.Parent.Data.TeleportGateway)
local Service={};Service.__index=Service
function Service.new()
	return setmetatable({
		Name="PartyService",
		Dependencies={"EnvironmentService","ProfileService","SessionService"},
		_model=Model.new(),
		_joining={},
		_blocked={},
		_launches={},
		_reconnecting={},
		_collisionState={},
		_countdowns={},
		_doorClosed={},
		_doorTweens={},
	},Service)
end
function Service:Init(deps)
	self._environment=deps.EnvironmentService
	self._profiles=deps.ProfileService
	self._sessions=deps.SessionService
	self._scope=Scope.new()
	self._directory=Directory.new()

	local physics=game:GetService("PhysicsService")
	local function ensureGroup(name)
		for _,group in physics:GetRegisteredCollisionGroups() do
			if group.name==name then return end
		end
		physics:RegisterCollisionGroup(name)
	end
	ensureGroup("EHParty")
	ensureGroup("EHPartyBarrier")
	physics:CollisionGroupSetCollidable("Default","EHPartyBarrier",false)
	physics:CollisionGroupSetCollidable("EHParty","EHPartyBarrier",true)

	local barriers=workspace:FindFirstChild("LobbyBarriers")
	if self._environment.Role=="Lobby" and barriers then
		for i=1,4 do
			local gate=barriers:FindFirstChild("Bay"..i)
			if gate and gate:IsA("BasePart") then
				gate.CollisionGroup="EHPartyBarrier"
			end
		end
	end
end
function Service:_SetCharacterCollision(player,inParty)
	local character=player.Character
	local old=self._collisionState[player]
	if not character then
		if old and old.scope then old.scope:Destroy() end
		self._collisionState[player]=nil
		return
	end

	local group=inParty and "EHParty" or "Default"
	if old and old.character==character and old.group==group then
		return
	end
	if old and old.scope then old.scope:Destroy() end

	local state={character=character,group=group,scope=Scope.new()}
	self._collisionState[player]=state
	local function assign(instance)
		if instance:IsA("BasePart") and instance.CollisionGroup~=group then
			instance.CollisionGroup=group
		end
	end
	state.scope:Add(character.DescendantAdded:Connect(assign))
	for _,instance in character:GetDescendants() do
		assign(instance)
	end
end
function Service:_SetDoor(bay,closed)
	-- The server only decides open/closed. It snaps the door parts to their final state and
	-- stamps the bay with DoorClosed + DoorChangedAt; every client's DoorController then animates
	-- the slide locally each frame (smooth, not limited by replication rate). Doors are cloaked
	-- (invisible, non-collidable) while open.
	if self._doorClosed[bay]==closed then return end
	self._doorClosed[bay]=closed
	local b=self._environment.Model:FindFirstChild("Bay"..bay);if not b then return end
	b:SetAttribute("DoorClosed",closed)
	b:SetAttribute("DoorChangedAt",workspace:GetServerTimeNow())
	for _,side in {"Left","Right"} do
		local door=b:FindFirstChild("Door"..side)
		local mark=b:FindFirstChild("Door"..side..(closed and "Closed" or "Open"))
		if door and mark then
			door.CFrame=mark.CFrame;door.Transparency=closed and 0 or 1;door.CanCollide=closed
			if closed then
				local sfx=door:FindFirstChild("DoorClose")
				if sfx and sfx.SoundId~="" then sfx:Play() end
			end
		end
	end
end
function Service:_Feedback(p,code)
	local messages={Joined="",Left="",Configured="",ReadyChanged="",HostOnly="Only the host can do that.",NotEveryoneReady="Everyone must be ready.",
		FriendsOnly="This elevator is friends only.",PartyChanged="The crew changed. Try again.",PartyUnavailable="That elevator isn't available.",
		PartyNotFull="Wait for the crew to fill up, or lower the crew size.",InvalidSettings="Crew size can't be smaller than the crew here.",Launching="Going down...",PublishedClientRequired="Teleport testing requires the published game.",
		GamePlaceNotConfigured="Can't start right now. Try again soon.",TransferFailed="Couldn't start. Your spot is saved, try again.",
		SessionUnavailable="That game has already ended.",LeavePartyFirst="Leave your crew before reconnecting.",NetworkUnavailable="Connection problem. Try again."}
	p:SetAttribute("EHPartyMessage",messages[code] or "Something went wrong. Try again.")
end
function Service:_Publish()
	if self._environment.Role~="Lobby" then return end
	for i=1,4 do
		local party=self._model:Get(i);local bay=self._environment.Model:FindFirstChild("Bay"..i)
		if bay then
			bay:SetAttribute("PartyState",party and party.state or "Empty")
            local ready=false
            if party then for _,id in party.members do if party.ready[tostring(id)] then ready=true end end end
            local gate=bay:FindFirstChild("ReadyGate")
            if gate then for _,part in gate:GetChildren()do if part:IsA("BasePart")then part.Transparency=ready and .18 or 1 end end end
			bay.Occupancy.Lettering.OccupancyText.Text=party and (#party.members.." / "..party.capacity) or "0 / 4"
		end
	end
	for _,p in Players:GetPlayers() do
		local bay=self._model:ForUser(p.UserId)
		local party=bay and self._model:Get(bay)
		self:_SetCharacterCollision(p,party~=nil)
		local cd=bay and self._countdowns[bay]
		p:SetAttribute("EHPartyView",party and Http:JSONEncode({
			partyId=party.partyId,bayId=party.bayId,hostUserId=party.hostUserId,capacity=party.capacity,
			accessMode=party.accessMode,members=party.members,ready=party.ready,state=party.state,revision=party.revision,
			countdown=cd and math.max(0,math.ceil(cd.deadline-os.clock())) or nil,
		}) or nil)
	end
end
function Service:_InBoardingZone(p,bay)
	local b=self._environment.Model:FindFirstChild("Bay"..bay)
	local zone=b and b:FindFirstChild("BoardingZone")
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then return false end
	local point=zone.CFrame:PointToObjectSpace(root.Position)
	local half=zone.Size/2
	return math.abs(point.X)<=half.X
		and math.abs(point.Y)<=half.Y
		and math.abs(point.Z)<=half.Z
end
function Service:_Inside(p,bay)
	local b=self._environment.Model:FindFirstChild("Bay"..bay)
	local zone=b and b:FindFirstChild("BoardingZone")
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then return false end

	-- The boarding trigger is intentionally small. The containment bounds follow
	-- the full physical cabin so walking around inside it never snaps the avatar.
	local point=zone.CFrame:PointToObjectSpace(root.Position)
	local halfX=zone.Size.X/2+.55
	local back=zone.Size.Z/2+3.55
	local front=zone.Size.Z/2-1.65
	return math.abs(point.X)<=halfX and math.abs(point.Y)<=8 and point.Z>=-back and point.Z<=front
end
-- Admission waits until the player is a full step past the crew barrier line, so joining never
-- coincides with the containment check pulling them backwards (the old "snap" on entry).
function Service:_DeepInside(p,bay)
	if not self:_Inside(p,bay) then return false end
	local zone=self._environment.Model["Bay"..bay].BoardingZone
	local root=p.Character.HumanoidRootPart
	return zone.CFrame:PointToObjectSpace(root.Position).Z<=zone.Size.Z/2-2.85
end
function Service:_Contain(p,bay)
	local b=self._environment.Model:FindFirstChild("Bay"..bay)
	local zone=b and b:FindFirstChild("BoardingZone")
	local character=p.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then return end

	local point=zone.CFrame:PointToObjectSpace(root.Position)
	local halfX=zone.Size.X/2+.55
	local back=zone.Size.Z/2+3.55
	local front=zone.Size.Z/2-1.65
	local targetPoint=Vector3.new(
		math.clamp(point.X,-halfX+.12,halfX-.12),
		math.abs(point.Y)<=8 and point.Y or 0,
		math.clamp(point.Z,-back+.12,front-.12)
	)
	local targetRoot=CFrame.new(zone.CFrame:PointToWorldSpace(targetPoint))*(root.CFrame-root.Position)
	local pivotOffset=root.CFrame:ToObjectSpace(character:GetPivot())
	character:PivotTo(targetRoot*pivotOffset)
	root.AssemblyLinearVelocity=Vector3.new(0,root.AssemblyLinearVelocity.Y,0)
	root.AssemblyAngularVelocity=Vector3.zero
end
function Service:_RefreshAdmissionBlock(p)
    local bay=self._blocked[p]
    if bay and not self:_InBoardingZone(p,bay) then self._blocked[p]=nil end
end
function Service:_Join(p,bay)
	if self._joining[p] or not self._profiles:IsReady(p) then return end
	self._joining[p]=true
	local before=self._model:Get(bay);local friend=true
	if before and before.accessMode=="FriendsOfHost" then local ok,result=pcall(function()return p:IsFriendsWithAsync(before.hostUserId)end);friend=ok and result end
	if p.Parent==Players and self._active and self._blocked[p]~=bay and self:_InBoardingZone(p,bay) and self:_DeepInside(p,bay) and not self._model:ForUser(p.UserId) then
		local ok,code=self._model:Join(p.UserId,bay,friend,before and before.revision,before and before.partyId);self:_Feedback(p,code)
		if not ok then self._blocked[p]=bay end
		self:_Publish()
	end
	self._joining[p]=nil
end
function Service:_Launch(p)
	if RunService:IsStudio() then return false,"PublishedClientRequired" end
	local places=require(Shared.Config.PlaceConfig);if places.GamePlaceId<=0 then return false,"GamePlaceNotConfigured" end
	local ok,party=self._model:Launch(p.UserId);if not ok then return false,party end
	self:_Publish()
	task.spawn(function()
		local ticket
		local allocated,err=pcall(function()
			local code,privateId=Gateway.Reserve()
			ticket=self._directory:Create(Http:GenerateGUID(false),party.members,code,privateId)
		end)
		if not allocated then self._model:Recover(party.bayId,party.partyId);self:_Publish();if p.Parent==Players then self:_Feedback(p,"NetworkUnavailable")end;return end
		local members={};for _,id in party.members do local member=Players:GetPlayerByUserId(id);if member then table.insert(members,member)end end
		self._launches[party.partyId]={party=party,ticket=ticket,deadline=os.time()+45}
		local sent= #members>0 and pcall(function()Gateway.Send(members,ticket)end)
		if not sent then for _,member in members do self:_Feedback(member,"TransferFailed")end end
		-- Do not allocate a second server after an uncertain transport result. Poll this ticket.
	end)
	return true,"Launching"
end
function Service:_Poll()
	for key,launch in self._launches do
		local ok,ticket=pcall(function()return self._directory:Get(launch.ticket.id)end)
		if ok and ticket and ticket.arrivals>0 then
			self._model:Finish(launch.party.bayId,launch.party.partyId);self._launches[key]=nil;self:_Publish()
		elseif os.time()>=launch.deadline then
			local canceled,didCancel=pcall(function()return self._directory:End(launch.ticket.id,true)end)
			if canceled and didCancel then
				self._model:Recover(launch.party.bayId,launch.party.partyId);self._launches[key]=nil;self:_Publish()
			end
		end
	end
	if RunService:IsStudio() then return end
	for _,p in Players:GetPlayers() do self:_CheckReturn(p)end
end
-- Is there a descent this player can go back to? Only while their crew's server is still running the
-- run and holding their place (a solo run ends the moment its player leaves). Only EHReconnectAvailable (the boolean) is published now -- the
-- original bottom Reconnect button in PartyController is the only thing that reads it.
function Service:_CheckReturn(p)
	if RunService:IsStudio() or p.Parent~=Players then return end
	local ok,ticket=pcall(function()return self._directory:ForUser(p.UserId)end)
	local offer=ok and Policy.ReturnOffer(ticket,p.UserId,os.time()) or nil
	if p.Parent~=Players then return end
	p:SetAttribute("EHReconnectAvailable",offer~=nil)
end
-- Exiting dismisses the whole crew and moves them clear of the bay together.
function Service:_ExitBay(p)
	local bayId=self._model:ForUser(p.UserId)
	if not bayId then return false,"NoParty" end
	local party=self._model:Get(bayId)
	if not party then return false,"NoParty" end

	local bay=self._environment.Model:FindFirstChild("Bay"..bayId)
	local landing=bay and bay:FindFirstChild("ExitLanding")
	self._countdowns[bayId]=nil

	for index,memberId in party.members do
		local left,code=self._model:Leave(memberId)
		if not left then return false,code end
		local member=Players:GetPlayerByUserId(memberId)
		if memberId==p.UserId then member=p end
		if member then
			self._blocked[member]=bayId
			self:_SetCharacterCollision(member,false)
			local character=member.Character
			local root=character and character:FindFirstChild("HumanoidRootPart")
			if root and landing then
				local offset=CFrame.new(((index-1)%2)*3,0,math.floor((index-1)/2)*3)
				root.AssemblyLinearVelocity=Vector3.zero
				root.AssemblyAngularVelocity=Vector3.zero
				character:PivotTo(landing.CFrame*offset)
			end
		end
	end
	return true,"Left"
end
function Service:Handle(p,action,payload)
	if not self._active or self._environment.Role~="Lobby" or not self._profiles:IsReady(p) then return false,"Unavailable" end
	local ok,code
	if action=="PartyConfigure" then ok,code=self._model:Configure(p.UserId,payload.capacity,payload.accessMode)
	elseif action=="PartyReady" then ok,code=self._model:Ready(p.UserId,payload.ready)
	elseif action=="PartyLeave" then ok,code=self:_ExitBay(p)
	elseif action=="PartyLaunch" then ok,code=self:_Launch(p)
	elseif action=="ReconnectRun" then
		if self._model:ForUser(p.UserId) then ok,code=false,"LeavePartyFirst"
		elseif self._reconnecting[p] then ok,code=false,"Launching"
		elseif RunService:IsStudio() then ok,code=false,"PublishedClientRequired"
		else
			self._reconnecting[p]=true
			local called=pcall(function()
				local ticket=self._directory:ForUser(p.UserId)
				if Policy.ReturnOffer(ticket,p.UserId,os.time())~="Rejoin" then code="SessionUnavailable";return end
				Gateway.Send({p},ticket);ok=true;code="Launching"
			end)
			if not called then ok=false;code="NetworkUnavailable" end
			if code=="SessionUnavailable" then self:_CheckReturn(p)end
			task.delay(5,function()self._reconnecting[p]=nil end)
		end
	else return false,"UnsupportedAction" end
	self:_Publish();self:_Feedback(p,code);return ok==true,code
end
function Service:Start()
	if self._environment.Role~="Lobby" then return end
	self._active=true;self:_Publish()
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)
		local state=self._collisionState[p]
		if state and state.scope then state.scope:Destroy() end
		self._collisionState[p]=nil
		self._model:Leave(p.UserId,true)
		self._joining[p]=nil
		self._blocked[p]=nil
		self._reconnecting[p]=nil
		self:_Publish()
	end))
	-- Check straight away on arrival (not on the next 5 s poll) so the Reconnect button is there
	-- as soon as the player lands back in the lobby.
	local function arrive(p)
		-- sent back from a descent (e.g. tried to follow a friend into their crew's private run):
		-- show the reason the Game place passed along
		pcall(function()
			local data=p:GetJoinData();local d=data and data.TeleportData
			if type(d)=="table" and type(d.notice)=="string" and #d.notice<=200 then p:SetAttribute("EHPartyMessage",d.notice)end
		end)
		task.delay(1.5,function()pcall(function()self:_CheckReturn(p)end)end)
	end
	self._scope:Add(Players.PlayerAdded:Connect(arrive));for _,p in Players:GetPlayers()do arrive(p)end
	self._scope:Add(game:GetService("TeleportService").TeleportInitFailed:Connect(function(p)
		if p.Parent==Players then self._reconnecting[p]=nil;self:_Feedback(p,"TransferFailed")end
	end))
	local elapsed,poll=0,0
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;poll+=dt
		if elapsed>=.25 then
			elapsed=0
			for _,p in Players:GetPlayers() do
				local current=self._model:ForUser(p.UserId)
				if current then
					self:_SetCharacterCollision(p,true)
					if not self:_Inside(p,current) then
						self:_Contain(p,current)
					end
				else
					self:_SetCharacterCollision(p,false)
					self:_RefreshAdmissionBlock(p)
					for bay=1,4 do
						if self:_InBoardingZone(p,bay) and self._blocked[p]~=bay and self:_DeepInside(p,bay) then
							task.spawn(function()self:_Join(p,bay)end)
							break
						end
					end
				end
			end
		end
		if poll>=5 and not self._polling then poll=0;self._polling=true;task.spawn(function()pcall(function()self:_Poll()end);self._polling=false end)end
		-- Every crew member must be ready before this 5-second auto-departure starts.
		-- Publish each changed second so the editable countdown label stays in sync.
		local countdownChanged=false
		for bay=1,4 do
			local party=self._model:Get(bay)
			local allReady=party~=nil and party.state=="Open" and #party.members==party.capacity
			if allReady then
				for _,memberId in party.members do
					if not party.ready[tostring(memberId)] then
						allReady=false
						break
					end
				end
			end

			local countdown=self._countdowns[bay]
			if allReady then
				if not countdown or countdown.partyId~=party.partyId then
					self._countdowns[bay]={
						deadline=os.clock()+5,
						departAt=workspace:GetServerTimeNow()+5,
						partyId=party.partyId,
						lastShown=5,
					}
					countdownChanged=true
				else
					local seconds=math.max(0,math.ceil(countdown.deadline-os.clock()))
					if countdown.lastShown~=seconds then
						countdown.lastShown=seconds
						countdownChanged=true
					end
					if seconds<=0 then
						self._countdowns[bay]=nil
						countdownChanged=true
						local host=Players:GetPlayerByUserId(party.hostUserId)
						if host and host.Parent==Players then
							local launched,code=self:_Launch(host)
							if not launched then
								-- e.g. Studio (no cross-place teleports): stand the crew down instead of
								-- restarting the countdown forever, and tell every member why.
								for _,memberId in party.members do
									self._model:Ready(memberId,false)
									local member=Players:GetPlayerByUserId(memberId)
									if member then self:_Feedback(member,code) end
								end
							end
						end
					end
				end
			elseif countdown then
				self._countdowns[bay]=nil
				countdownChanged=true
			end

			-- Doors close the instant departure begins -- i.e. as soon as the 5s countdown starts,
			-- not partway through -- and stay shut through the "Launching" state (re-fetched fresh
			-- here since a launch may have just happened above this tick). Any path that cancels
			-- the countdown above (leaving, un-readying, membership changing) already clears
			-- self._countdowns[bay], which reopens the door here too -- no separate case needed.
			local freshParty=self._model:Get(bay)
			local cdNow=self._countdowns[bay]
			self:_SetDoor(bay,freshParty~=nil and (freshParty.state~="Open" or cdNow~=nil))
			-- Clients animate the ready lamp from these (it fades to full green across the countdown).
			local bayModel=self._environment.Model:FindFirstChild("Bay"..bay)
			if bayModel then
				local departAt=cdNow and cdNow.departAt or nil
				if bayModel:GetAttribute("DepartAt")~=departAt then bayModel:SetAttribute("DepartAt",departAt) end
				local state="Off"
				if freshParty and freshParty.state~="Open" then state="Launching"
				elseif freshParty then for _,id in freshParty.members do if freshParty.ready[tostring(id)] then state="Some" break end end end
				if bayModel:GetAttribute("ReadyState")~=state then bayModel:SetAttribute("ReadyState",state) end
				local occupied=freshParty~=nil and #freshParty.members>0
				if bayModel:GetAttribute("Occupied")~=occupied then bayModel:SetAttribute("Occupied",occupied) end
			end
		end
		if countdownChanged then self:_Publish() end
	end))
end
function Service:Destroy()
	self._active=false
	if self._scope then self._scope:Destroy() end
	for player,state in self._collisionState do
		if state.scope then state.scope:Destroy() end
		for _,instance in state.character:GetDescendants() do
			if instance:IsA("BasePart") and instance.CollisionGroup=="EHParty" then
				instance.CollisionGroup="Default"
			end
		end
	end
	table.clear(self._collisionState)
end
return table.freeze(Service)
