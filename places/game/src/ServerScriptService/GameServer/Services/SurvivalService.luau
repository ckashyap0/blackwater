--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.SurvivalConfig)
local Model=require(script.Parent.Parent.Data.SurvivalModel)
local Slots=require(game.ReplicatedStorage.Game.Shared.Utilities.CabinSlots)
local Service={};Service.__index=Service
local activePhases={FloorActive=true,FinaleActive=true,Departing=true}
local continuationPhases={Intro=true,PreparingFloor=true,FloorActive=true,FinaleActive=true,Departing=true,Transit=true}
function Service.new(options)
	options=options or {}
	return setmetatable({Name="SurvivalService",Dependencies={"GameRunService","CharacterService","InteractionService","InventoryService","EnvironmentService"},
		_clock=options.clock or function()return workspace:GetServerTimeNow()end,_players=options.players or Players,_states={},_revivals={},_tracked={}},Service)
end
function Service:Init(deps)
	self._runs=deps.GameRunService;self._characters=deps.CharacterService;self._interactions=deps.InteractionService
	self._inventory=deps.InventoryService;self._environment=deps.EnvironmentService;self._scope=Scope.new()
end
function Service:_RemoveRevival(id)
	local r=self._revivals[id];if not r then return end
	self._revivals[id]=nil;r.unregister();if r.part then r.part:Destroy() end
end
function Service:_Publish(id,s)
	local p=self._players:GetPlayerByUserId(id)
	if p then
		p:SetAttribute("EHDownedDeadline",s.downedDeadline);p:SetAttribute("EHProtectionUntil",s.protectionUntil)
		p:SetAttribute("EHRevivesUsed",s.revivesUsedThisFloor)
		-- Re-publishing unchanged life must not cancel an ongoing sprint/hold.
		if p:GetAttribute("EHLifeState")~=s.lifeState then self._characters:SetLifeState(p,s.lifeState) end
	end
end
function Service:_Commit(id,s)
	local previous=self._states[id];self._states[id]=s
	local result=self._runs:SetParticipantSurvival(self._runId,id,s)
	if not result then self._states[id]=previous;return false end
	local p=self._players:GetPlayerByUserId(id)
	if p then
		self._interactions:Cancel(p,"LifeChanged")
		if s.lifeState~="Alive" then self._inventory:Drop(p) end
	end
	self:_RemoveRevival(id);self:_Publish(id,s)
	if s.lifeState=="Downed" and p then self:_RegisterRevival(p) end
	return true
end
function Service:_RegisterRevival(player)
	if self._connectionManaged and not player:GetAttribute("EHSessionAdmitted") then return end
	local s=self._states[player.UserId];local snapshot=self._runs:GetSnapshot()
	local c=player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	if not s or s.lifeState~="Downed" or not root or not snapshot or not activePhases[snapshot.phase] then return end
	self:_RemoveRevival(player.UserId)
	-- Small prompt anchor above the torso avoids the character body blocking the rescue ray.
	local part=Instance.new("Part");part.Name="RevivalTarget";part.Size=Vector3.new(2,2,2)
	part.Transparency=1;part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.Massless=true
	part.CFrame=root.CFrame*CFrame.new(0,1,0);part.Parent=c
	local weld=Instance.new("WeldConstraint");weld.Part0=root;weld.Part1=part;weld.Parent=part
	local targetId=player.UserId;local id="Revive_"..tostring(targetId)
	local unregister=self._interactions:Register({interactionId=id,interactionType="Revive",target=part,lineOfSightModel=c,
		runId=snapshot.runId,floorInstanceId=snapshot.currentFloorInstanceId,holdDuration=Config.ReviveHoldSeconds,
		label="REVIVE "..string.upper(player.DisplayName),allowedRunPhases=activePhases,
		canUse=function(rescuer)
			local t=self._states[targetId];local r=self._states[rescuer.UserId]
			local h=c:FindFirstChildOfClass("Humanoid")
			return rescuer~=player and player.Parent==self._players and player.Character==c and h and h.Health>0 and t and t.lifeState=="Downed" and self._clock()<t.downedDeadline
				and r and r.lifeState=="Alive" and self._clock()>=r.protectionUntil,"RescueUnavailable"
		end,
		complete=function(rescuer)return self:Revive(rescuer.UserId,targetId)end})
	self._revivals[targetId]={part=part,unregister=unregister}
end
function Service:RestoreReconnect(player,advanced)
	self:_Sync()
	if advanced and self._states[player.UserId] then self:_Commit(player.UserId,Model.New()) end
end
function Service:RefreshPlayer(player)
	local s=self._states[player.UserId];if not s then return end
	self:_Publish(player.UserId,s)
	if s.lifeState=="Downed" then self:_RegisterRevival(player) end
end
function Service:RecalculateContinuation()self:_CheckWipe()end
function Service:SetConnectionManaged(value)self._connectionManaged=value==true end
function Service:SetCabinProtection(callback)self._cabinProtection=callback end
function Service:Damage(d)
	if not Model.ValidDamage(d) then return false,"InvalidDamage" end
	self:_Sync()
	local snapshot=self._runs:GetSnapshot();local s=self._states[d.targetUserId]
	local player=self._players:GetPlayerByUserId(d.targetUserId)
	if player and self._cabinProtection and self._cabinProtection(player)then return false,"CabinSecured" end
	if not s or not player or not snapshot or not activePhases[snapshot.phase] or self._suspended then return false,"Unavailable" end
	local result,reason=Model.Damage(s,d,self._clock());if not result then return false,reason end
	if not self:_Commit(d.targetUserId,result) then return false,"StaleRun" end
	self:_CheckWipe();return true,result.lifeState
end
function Service:Revive(rescuerId,targetId)
	if rescuerId==targetId or self._suspended then return false,"InvalidRescuer" end
	local snapshot=self._runs:GetSnapshot()
	local r,t=self._states[rescuerId],self._states[targetId]
	if not snapshot or not activePhases[snapshot.phase] or not r or not t
		or not self._players:GetPlayerByUserId(rescuerId) or not self._players:GetPlayerByUserId(targetId) then return false,"Unavailable" end
	-- Called only by InteractionService after its range/LOS/exclusive/hold validation.
	local result,reason=Model.Revive(t,r,self._clock());if not result then return false,reason end
	if not self:_Commit(targetId,result) then return false,"StaleRun" end
	return true,reason
end
function Service:_SetSuspended(value)
	if self._suspended==value then return end
	self._suspended=value
	game.ReplicatedStorage.Game:SetAttribute("EHAwaitingReconnect",value)
	for _,p in self._players:GetPlayers() do
		if self._states[p.UserId] then
			p:SetAttribute("EHAwaitingReconnect",value);self._characters:SetSuspended(p,value)
			if value then self._interactions:Cancel(p,"AwaitingReconnect") end
		end
	end
end
function Service:IsEncounterSuspended() return self._suspended==true end
function Service:_CheckWipe()
	local snapshot=self._runs:GetSnapshot();if not snapshot or not continuationPhases[snapshot.phase] then return end
	local connected={};for _,p in self._players:GetPlayers() do if not self._leaving or not self._leaving[p.UserId] then connected[p.UserId]=true end end
	local participants=snapshot.participants
 -- Dead participants remain dead during transit; there is no departure respawn.
 local condition=Model.Continuation(participants,connected,self._clock())
	self:_SetSuspended(condition=="AwaitingReconnect")
	if condition=="Wipe" then
		for id in self._revivals do self:_RemoveRevival(id) end
		local r=self._runs:Dispatch({token=self._runs:GetToken(),action="Wipe",payload={}})
		if r.ok then self._runs:Dispatch({token=self._runs:GetToken(),action="Resolve",payload={}}) end
	end
end
function Service:_Reset()
	for id in self._revivals do self:_RemoveRevival(id) end
	self:_SetSuspended(false)
	for _,p in self._players:GetPlayers() do
		p:SetAttribute("EHRunId",nil);p:SetAttribute("EHDownedDeadline",nil);p:SetAttribute("EHProtectionUntil",nil);p:SetAttribute("EHRevivesUsed",nil)
	end
	self._states={};self._runId=nil;self._floorId=nil;self._phase=nil;self._leaving={};self._completedCount=0
end
function Service:_Sync()
	if self._syncing then return end;self._syncing=true
	local snapshot=self._runs:GetSnapshot()
	if not snapshot then self:_Reset();self._syncing=false;return end
	if snapshot.runId~=self._runId then
		self:_Reset();self._runId=snapshot.runId
		for _,id in snapshot.originalRoster do self._states[id]=Model.New() end
	end
	-- Completion count also catches a fast Transit -> PreparingFloor before a deferred listener runs.
	local enteredTransit=#snapshot.completedFloorNumbers>(self._completedCount or 0)
		and snapshot.phase~="Completed" and snapshot.phase~="Closing"
	self._completedCount=#snapshot.completedFloorNumbers
	local newFloor=snapshot.currentFloorInstanceId and snapshot.currentFloorInstanceId~=self._floorId
	self._phase=snapshot.phase;self._floorId=snapshot.currentFloorInstanceId
	for _,id in snapshot.originalRoster do
		local p=self._players:GetPlayerByUserId(id);local s=self._states[id]
		if p then p:SetAttribute("EHRunId",snapshot.runId) end
		if enteredTransit then
			self:_RemoveRevival(id)
			-- Absent players keep their life/connection state until the reconnect service restores them.
			if p and s.lifeState~="Dead" and not self._leaving[id] and snapshot.participants[tostring(id)].connectionState=="Connected" then
				local wasStanding=s.lifeState=="Alive"
				local restored=Model.New();restored.revivesUsedThisFloor=newFloor and 0 or s.revivesUsedThisFloor
				self:_Commit(id,restored)
				local spawn=self._environment.Spawn
				-- Only fallen crew are returned to a cabin slot (with the eye-open fade); standing crew ride down untouched.
				self._characters:RestoreForFloor(p,(not wasStanding and spawn) and Slots.Frame(spawn.CFrame,p.UserId,snapshot.originalRoster) or nil)
			end
		elseif newFloor then
			local reset=table.clone(s);reset.revivesUsedThisFloor=0;reset.protectionUntil=0
			self:_Commit(id,reset)
		else self:_Publish(id,s) end
	end
	if not activePhases[snapshot.phase] then
		if not continuationPhases[snapshot.phase] then self:_SetSuspended(false) end
		if snapshot.phase~="PreparingFloor" then for id in self._revivals do self:_RemoveRevival(id) end end
	end
	self._syncing=false
end
function Service:_Track(p)
	if self._tracked[p] then return end
	local scope=Scope.new();self._tracked[p]=scope
	-- Engine death (reset button/fall/legacy damage) is final; it cannot resurrect a broken Humanoid.
	scope:Add(p:GetAttributeChangedSignal("EHLifeState"):Connect(function()
		local s=self._states[p.UserId];local snapshot=self._runs:GetSnapshot()
		if s and s.lifeState~="Dead" and p:GetAttribute("EHLifeState")=="Dead" and snapshot and activePhases[snapshot.phase] then
			local dead=table.clone(s);dead.lifeState="Dead";dead.downedDeadline=0;dead.protectionUntil=0
			self:_Commit(p.UserId,dead);self:_CheckWipe()
		end
	end))
end
function Service:_Step()
	self:_Sync()
	local snapshot=self._runs:GetSnapshot();if not snapshot or not continuationPhases[snapshot.phase] then return end
	if not activePhases[snapshot.phase] then self:_CheckWipe();return end
	for id,s in self._states do
		local expired=Model.Expire(s,self._clock());if expired then self:_Commit(id,expired) end
	end
	self:_CheckWipe()
end
function Service:Start()
	self._active=true;self._leaving={}
	for _,p in self._players:GetPlayers() do self:_Track(p) end
	self._scope:Add(self._players.PlayerAdded:Connect(function(p) self._leaving[p.UserId]=nil;self:_Track(p);self:_Sync() end))
	self._scope:Add(self._players.PlayerRemoving:Connect(function(p)
		self._leaving[p.UserId]=true;self:_RemoveRevival(p.UserId)
		if self._tracked[p] then self._tracked[p]:Destroy();self._tracked[p]=nil end
		-- Reservation creation and authenticated re-entry belong to Chunk 7. Preserve any reservation it supplies.
		if not self._connectionManaged then task.defer(function()if self._active then self:_CheckWipe()end end)end
	end))
	self._scope:Add(self._runs:Subscribe(function() self:_Sync();self:_CheckWipe() end))
	local elapsed=0;self._scope:Add(RunService.Heartbeat:Connect(function(dt) elapsed+=dt;if elapsed>=.1 then elapsed=0;self:_Step() end end))
	self:_Sync()
end
function Service:Destroy()
	self._active=false;if self._scope then self._scope:Destroy() end
	for _,scope in self._tracked do scope:Destroy() end;self._tracked={};self:_Reset()
end
return table.freeze(Service)
