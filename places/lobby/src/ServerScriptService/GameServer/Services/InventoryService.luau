--!nonstrict
local Players=game:GetService("Players")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Inventory=require(script.Parent.Parent.Data.ObjectiveInventory)
local Service={};Service.__index=Service
function Service.new() return setmetatable({Name="InventoryService",Dependencies={"GameRunService","InteractionService"},_entries={},_sockets={},_players={},_floors={}},Service) end
function Service:Init(deps)
	self._runs=deps.GameRunService;self._interactions=deps.InteractionService;self._scope=Scope.new();self._inventory=Inventory.new()
end
function Service:RegisterFloor(id,runId,bounds,recoveryAnchor,emergencyFrame,boundsFrame)
	assert(typeof(bounds)=="Vector3" and bounds.X>0 and bounds.Y>0 and bounds.Z>0,"Invalid recovery bounds")
	assert(typeof(emergencyFrame)=="CFrame","Emergency recovery point required")
	assert(not self._floors[id],"Duplicate floor scope")
	assert(boundsFrame==nil or typeof(boundsFrame)=="CFrame","Invalid bounds frame")
	self._floors[id]={runId=runId,bounds=bounds,recovery=recoveryAnchor,emergency=emergencyFrame,boundsFrame=boundsFrame or emergencyFrame}
end
function Service:_Recovery(scope)
	local floor=assert(self._floors[scope],"Missing floor scope")
	if floor.recovery and floor.recovery:IsDescendantOf(workspace) then return floor.recovery.CFrame end
	if not floor.warned then floor.warned=true;warn("[ElevatorHorror] Missing recovery anchor; using emergency point: "..scope) end
	return floor.emergency
end
function Service:_InBounds(scope,position)
	local floor=self._floors[scope];if not floor then return false end
	local delta=floor.boundsFrame:PointToObjectSpace(position);local b=floor.bounds/2
	return math.abs(delta.X)<=b.X and math.abs(delta.Y)<=b.Y and math.abs(delta.Z)<=b.Z
end
function Service:_DropFrame(player,scope)
	local c=player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	if root then
		local origin=root.Position+root.CFrame.LookVector*2
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={c}
		local hit=workspace:Raycast(origin,Vector3.new(0,-9,0),params)
		if hit and hit.Normal.Y>.5 and self:_InBounds(scope,hit.Position+Vector3.new(0,1,0)) then return CFrame.new(hit.Position+Vector3.new(0,1,0)) end
	end
	return self:_Recovery(scope)
end
function Service:_ClearCarry(entry)
	if entry.carry then entry.carry:Destroy();entry.carry=nil end
end
function Service:_Publish(entry,frame)
	local item=self._inventory:Get(entry.id);if not item then return end
	local p=entry.part
	p:SetAttribute("EHItemState",item.state);p:SetAttribute("EHItemOwner",item.owner or nil)
	p:SetAttribute("EHItemRevision",item.revision)
	local visible=item.state=="AtSpawn" or item.state=="Dropped" or item.state=="Installed"
	p.Transparency=visible and entry.transparency or 1;p.CanQuery=visible;p.CanCollide=false;p.Anchored=true
	if frame then p.CFrame=frame end
	self._interactions:SetEnabled(entry.id,item.state=="AtSpawn" or item.state=="Dropped")
end
function Service:RegisterItem(id,kind,scope,part)
	local floor=assert(self._floors[scope],"Register floor first")
	assert(part:IsA("BasePart") and part:IsDescendantOf(workspace),"Missing item world representation")
	self._inventory:RegisterItem(id,kind,scope)
	local entry={id=id,scope=scope,part=part,transparency=part.Transparency};self._entries[id]=entry
	entry.unregister=self._interactions:Register({interactionId=id,interactionType="Pickup",target=part,runId=floor.runId,floorInstanceId=scope,
		allowedRunPhases={FloorActive=true,FinaleActive=true},label="Take "..kind,holdDuration=.35,
		canUse=function(player)
			local item=self._inventory:Get(id)
			return item and (item.state=="AtSpawn" or item.state=="Dropped") and not self._inventory:Carried(player.UserId),"AlreadyCarrying"
		end,
		complete=function(player) return self:Pickup(player,id) end})
	self:_Publish(entry)
end
function Service:RegisterSocket(id,kind,scope,part)
	local floor=assert(self._floors[scope],"Register floor first")
	self._inventory:RegisterSocket(id,kind,scope)
	local s={part=part,scope=scope};self._sockets[id]=s
	s.unregister=self._interactions:Register({interactionId=id,interactionType="Socket",target=part,runId=floor.runId,floorInstanceId=scope,
		allowedRunPhases={FloorActive=true,FinaleActive=true},label="Insert "..kind,holdDuration=.7,
		canUse=function(player)
			local item=self._inventory:Get(self._inventory:Carried(player.UserId))
			return item and item.kind==kind and item.scope==scope,"WrongItemKind"
		end,
		complete=function(player) return self:Install(player,id) end})
end
function Service:Pickup(player,id)
	local entry=self._entries[id];if not entry then return false,"UnknownItem" end
	local character=player.Character;local hand=character and (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm") or character:FindFirstChild("HumanoidRootPart"))
	if not hand or player:GetAttribute("EHLifeState")~="Alive" then return false,"NoCharacter" end
	local ok,reason=self._inventory:Pickup(player.UserId,id);if not ok then return false,reason end
	local clone=entry.part:Clone();clone.Name="CarriedObjective";clone:ClearAllChildren()
	for _,tag in game:GetService("CollectionService"):GetTags(clone) do game:GetService("CollectionService"):RemoveTag(clone,tag) end
	for key in clone:GetAttributes() do clone:SetAttribute(key,nil) end
	clone.Anchored=false;clone.CanCollide=false;clone.CanTouch=false;clone.CanQuery=false;clone.Massless=true
	clone.Size=entry.part.Size;clone.CFrame=hand.CFrame*CFrame.new(0,-.65,0);clone.Parent=character
	local weld=Instance.new("WeldConstraint");weld.Part0=hand;weld.Part1=clone;weld.Parent=clone;entry.carry=clone
	player:SetAttribute("EHCarriedItem",id);player:SetAttribute("EHCarriedKind",self._inventory:Get(id).kind)
	self:_Publish(entry);return true,"PickedUp"
end
function Service:Drop(player)
	local id=self._inventory:Carried(player.UserId);if not id then return false,"NothingCarried" end
	local entry=self._entries[id];local frame=self:_DropFrame(player,entry.scope)
	local ok,reason=self._inventory:Drop(player.UserId);if not ok then return false,reason end
	self:_ClearCarry(entry);self:_Publish(entry,frame)
	player:SetAttribute("EHCarriedItem",nil);player:SetAttribute("EHCarriedKind",nil)
	return true,"Dropped"
end
function Service:Install(player,socketId)
	local ok,id=self._inventory:Install(player.UserId,socketId);if not ok then return false,id end
	local entry=self._entries[id];local socket=self._sockets[socketId]
	self:_ClearCarry(entry);self:_Publish(entry,socket.part.CFrame*CFrame.new(0,0,-1))
	socket.part:SetAttribute("EHInstalledItem",id);self._interactions:SetEnabled(socketId,false)
	player:SetAttribute("EHCarriedItem",nil);player:SetAttribute("EHCarriedKind",nil)
	return true,"Installed"
end
function Service:RetireFloor(scope)
	for _,id in self._inventory:RetireScope(scope) do
		local entry=self._entries[id]
		if entry then self:_ClearCarry(entry);entry.unregister();entry.part:Destroy();self._entries[id]=nil end
	end
	for id,s in self._sockets do if s.scope==scope then s.unregister();self._sockets[id]=nil end end
	for _,player in Players:GetPlayers() do if not self._inventory:Carried(player.UserId) then player:SetAttribute("EHCarriedItem",nil);player:SetAttribute("EHCarriedKind",nil) end end
	self._inventory:ForgetRetired(scope);self._floors[scope]=nil
end
function Service:_Track(player)
	if self._players[player] then return end
	local scope=Scope.new();self._players[player]=scope
	scope:Add(player:GetAttributeChangedSignal("EHLifeState"):Connect(function()
		if player:GetAttribute("EHLifeState")=="Dead" then self:Drop(player) end
	end))
	scope:Add(player.CharacterRemoving:Connect(function() self:Drop(player) end))
end
function Service:Start()
	self._scope:Add(Players.PlayerAdded:Connect(function(p) self:_Track(p) end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p) self:Drop(p);if self._players[p] then self._players[p]:Destroy();self._players[p]=nil end end))
	for _,p in Players:GetPlayers() do self:_Track(p) end
	self._scope:Add(self._runs:Subscribe(function()
		local token=self._runs:GetToken()
		for id in self._floors do if not token or token.floorInstanceId~=id then self:RetireFloor(id) end end
	end))
	local elapsed=0
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.5 then return end;elapsed=0
		for id,entry in self._entries do
			local item=self._inventory:Get(id)
			if item and (item.state=="AtSpawn" or item.state=="Dropped") then
				if not entry.part:IsDescendantOf(workspace) then
					-- Deleted targets cannot be silently recreated from an untrusted client description.
					if not entry.missing then entry.missing=true;warn("[ElevatorHorror] Missing item representation: "..id) end
				elseif not self:_InBounds(entry.scope,entry.part.Position) then self:_Publish(entry,self:_Recovery(entry.scope)) end
			end
		end
	end))
end
function Service:Destroy()
	if self._scope then self._scope:Destroy() end
	for _,s in self._players do s:Destroy() end;table.clear(self._players)
	for id in self._floors do self:RetireFloor(id) end
end
return table.freeze(Service)
