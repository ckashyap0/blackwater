--!nonstrict
local Players=game:GetService("Players")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Inventory=require(script.Parent.Parent.Data.ObjectiveInventory)
local HeldMotion=require(Shared.Utilities.HeldItemMotion)
local Service={};Service.__index=Service
function Service.new() return setmetatable({Name="InventoryService",Dependencies={"GameRunService","InteractionService"},_entries={},_sockets={},_players={},_floors={}},Service) end
function Service:Init(deps)
	self._runs=deps.GameRunService;self._interactions=deps.InteractionService;self._scope=Scope.new();self._inventory=Inventory.new()
end
-- opts (optional): manual=true (only retired by RetireFloor, never by a run change), phases={Phase=true}
-- (the run phases its items and sockets can be used in; default FloorActive + FinaleActive)
function Service:RegisterFloor(id,runId,bounds,recoveryAnchor,emergencyFrame,boundsFrame,opts)
	assert(typeof(bounds)=="Vector3" and bounds.X>0 and bounds.Y>0 and bounds.Z>0,"Invalid recovery bounds")
	assert(typeof(emergencyFrame)=="CFrame","Emergency recovery point required")
	assert(not self._floors[id],"Duplicate floor scope")
	assert(boundsFrame==nil or typeof(boundsFrame)=="CFrame","Invalid bounds frame")
	self._floors[id]={runId=runId,bounds=bounds,recovery=recoveryAnchor,emergency=emergencyFrame,boundsFrame=boundsFrame or emergencyFrame,manual=opts and opts.manual or nil,phases=opts and opts.phases or nil}
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
-- Where a dropped item leaves the player's hands: in front of the chest, pulled back if a
-- wall is closer, so the throw can never start inside geometry.
-- A client-reported release point is used only if it is near the player's head, inside the
-- floor, reachable without passing through a wall and not overlapping solid geometry.
function Service:_TrustedRelease(player,entry,frame)
	if typeof(frame)~="CFrame" then return nil end
	local c=player.Character;local head=c and (c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart"))
	if not head then return nil end
	local pos=frame.Position;local offset=pos-head.Position
	if offset.Magnitude>5 or offset.Magnitude<.5 or not self:_InBounds(entry.scope,pos) then return nil end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={c,entry.part};params.RespectCanCollide=true
	if workspace:Raycast(head.Position,offset,params) then return nil end
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude;overlap.FilterDescendantsInstances={c,entry.part};overlap.RespectCanCollide=true
	if #workspace:GetPartBoundsInBox(frame,entry.part.Size*.9,overlap)>0 then return nil end
	return frame
end
function Service:_ReleaseFrame(player,entry)
	local c=player.Character;local root=c and c:FindFirstChild("HumanoidRootPart");local head=c and c:FindFirstChild("Head")
	if not root then return nil end
	local eye=(head or root).Position
	local look=Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z).Unit
	local target=eye+look*1.5-Vector3.new(0,.9,0)
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={c,entry.part}
	local reach=math.max(entry.part.Size.X,entry.part.Size.Y,entry.part.Size.Z)*.5+.25
	local hit=workspace:Raycast(eye,(target-eye).Unit*((target-eye).Magnitude+reach),params)
	if hit then
		local back=math.max(0,hit.Distance-reach)
		if back<.6 then return nil end -- hugging a wall: just set it down (no throw)
		target=eye+(target-eye).Unit*back
	end
	if not self:_InBounds(entry.scope,target) then return nil end
	local yaw=math.atan2(-look.X,-look.Z)
	return CFrame.new(target)*CFrame.Angles(0,yaw+math.rad(math.random(-20,20)),0)*CFrame.Angles(math.rad(math.random(-10,10)),0,math.rad(math.random(-12,12))),
		root.AssemblyLinearVelocity*.85+look*3.2+Vector3.new(0,1.6,0)
end
-- Real physics for a dropped item: it leaves the hands with the player's momentum, tumbles,
-- bounces and slides to rest, then is frozen in place and becomes available to pick up again.
function Service:_Toss(entry,frame,velocity,fallback,owner)
	local p=entry.part
	entry.toss=(entry.toss or 0)+1;local serial=entry.toss
	self:_Publish(entry,frame)
	-- The item stays pick-up-able the whole time it is falling or sliding (no lockout).
	-- High friction, no bounce, and the server simulates it so it can damp the roll: a round fuse
	-- lands, scuffs a little and stops instead of rolling away across the floor.
	p.CustomPhysicalProperties=PhysicalProperties.new(1.4,1.2,.02,100,100)
	p.Anchored=false;p.CanCollide=true
	pcall(function()p:SetNetworkOwner(nil)end)
	p.AssemblyLinearVelocity=velocity
	p.AssemblyAngularVelocity=Vector3.new(math.random(-10,10)/10,math.random(-6,6)/10,math.random(-10,10)/10)
	local sound=p:FindFirstChild("DropImpact")
	if not sound then sound=Instance.new("Sound");sound.Name="DropImpact";sound.SoundId="rbxassetid://9117939398";sound.RollOffMaxDistance=45;sound.RollOffMinDistance=5;sound.Parent=p end
	task.spawn(function()
		local started,still,lastImpact,prevY=os.clock(),0,0,p.AssemblyLinearVelocity.Y
		while entry.toss==serial and p.Parent do
			local dt=game:GetService("RunService").Heartbeat:Wait()
			local item=self._inventory:Get(entry.id)
			if not item or item.state~="Dropped" or p.Anchored then return end
			local v=p.AssemblyLinearVelocity
			-- Impact: downward speed suddenly arrested. Louder and lower for harder hits.
			if prevY<-3 and v.Y-prevY>3 and os.clock()-lastImpact>.12 then
				lastImpact=os.clock();local strength=math.clamp(-prevY/14,.15,1)
				sound.Volume=.12+.33*strength;sound.PlaybackSpeed=1.12-strength*.22+math.random(-4,4)/100;sound.TimePosition=0;sound:Play()
			end
			prevY=v.Y
			-- on the ground: kill the roll and bleed off any slide quickly
			local down=RaycastParams.new();down.FilterType=Enum.RaycastFilterType.Exclude;down.FilterDescendantsInstances={p}
			if workspace:Raycast(p.Position,Vector3.new(0,-(math.max(p.Size.Y,p.Size.Z)/2+.15),0),down) and math.abs(v.Y)<2 then
				p.AssemblyAngularVelocity*=math.exp(-dt*14)
				p.AssemblyLinearVelocity=Vector3.new(v.X*math.exp(-dt*7),v.Y,v.Z*math.exp(-dt*7))
			end
			local moving=v.Magnitude+p.AssemblyAngularVelocity.Magnitude*.25
			still=moving<.6 and still+dt or 0
			if still>=.25 or os.clock()-started>5 or not self:_InBounds(entry.scope,p.Position) then break end
		end
		if entry.toss~=serial then return end
		entry.toss=nil
		local item=self._inventory:Get(entry.id)
		if not item or item.state~="Dropped" or not p.Parent then return end
		p.AssemblyLinearVelocity=Vector3.zero;p.AssemblyAngularVelocity=Vector3.zero
		self:_Publish(entry,self:_InBounds(entry.scope,p.Position) and p.CFrame or fallback)
	end)
end
function Service:_ClearCarry(entry)
	if entry.carry then entry.carry:Destroy();entry.carry=nil end
end
function Service:_Publish(entry,frame)
	local item=self._inventory:Get(entry.id);if not item then return end
	local p=entry.part
	if item.state~="Dropped" then entry.toss=nil end -- picked up / installed / reset mid-fall
	p:SetAttribute("EHItemState",item.state);p:SetAttribute("EHItemOwner",item.owner or nil)
	p:SetAttribute("EHItemRevision",item.revision)
	local visible=(item.state=="AtSpawn" and not entry.hiddenAtSpawn) or item.state=="Dropped" or item.state=="Installed"
	p.Transparency=visible and entry.transparency or 1;p.CanQuery=visible;p.CanCollide=false;p.Anchored=true
	for _,d in p:GetChildren() do if d:IsA("BasePart") and d:GetAttribute("DisplayDetail") then d.Transparency=visible and (d:GetAttribute("DetailTransparency") or 0) or 1 end end
	-- (Nov 3) printed labels (SurfaceGuis, e.g. the keycard's) still draw on an invisible part: they go with it,
	-- or the label is left floating where the card was while someone carries it
	for _,d in p:GetDescendants() do if d:IsA("SurfaceGui") then d.Enabled=visible elseif d:IsA("Decal") then if d:GetAttribute("BaseT")==nil then d:SetAttribute("BaseT",d.Transparency) end;d.Transparency=visible and d:GetAttribute("BaseT") or 1 end end
	if frame then p.CFrame=frame end
	self._interactions:SetEnabled(entry.id,(item.state=="AtSpawn" and not entry.hiddenAtSpawn) or item.state=="Dropped")
end
-- opts (optional): hold (pick-up seconds, default .18), label, hiddenAtSpawn (not shown or takeable until
-- it is first handed to someone with Give - e.g. the keycard you get at the gatehouse)
function Service:RegisterItem(id,kind,scope,part,opts)
	local floor=assert(self._floors[scope],"Register floor first")
	assert(part:IsA("BasePart") and part:IsDescendantOf(workspace),"Missing item world representation")
	self._inventory:RegisterItem(id,kind,scope)
	local entry={id=id,scope=scope,part=part,transparency=part.Transparency,hiddenAtSpawn=opts and opts.hiddenAtSpawn or nil};self._entries[id]=entry
	entry.unregister=self._interactions:Register({interactionId=id,interactionType="Pickup",target=part,runId=floor.runId,floorInstanceId=scope,
		allowedRunPhases=floor.phases or {FloorActive=true,FinaleActive=true},label=(opts and opts.label) or "Take "..kind,holdDuration=(opts and opts.hold) or .18,quick=true, -- (picking an item up is a quick grab, not a long hold)
		canUse=function(player)
			local item=self._inventory:Get(id)
			if player:GetAttribute("EHCarryingMop") then return false,"MopInHand" end
			if item and item.state=="AtSpawn" and entry.hiddenAtSpawn then return false,"Unavailable" end
			return item and (item.state=="AtSpawn" or item.state=="Dropped") and not self._inventory:Carried(player.UserId),"AlreadyCarrying"
		end,
		complete=function(player) return self:Pickup(player,id) end})
	self:_Publish(entry)
end
-- opts (optional): label, hold, canUse (an extra check, e.g. "the gate is ready")
function Service:RegisterSocket(id,kind,scope,part,opts)
	local floor=assert(self._floors[scope],"Register floor first")
	self._inventory:RegisterSocket(id,kind,scope)
	local s={part=part,scope=scope};self._sockets[id]=s
	s.unregister=self._interactions:Register({interactionId=id,interactionType="Socket",target=part,runId=floor.runId,floorInstanceId=scope,
		allowedRunPhases=floor.phases or {FloorActive=true,FinaleActive=true},label=(opts and opts.label) or "Insert "..kind,holdDuration=(opts and opts.hold) or .7,lineOfSightModel=opts and opts.lineOfSightModel or nil,
		canUse=function(player)
			local item=self._inventory:Get(self._inventory:Carried(player.UserId))
			if opts and opts.canUse then local ok,why=opts.canUse(player);if not ok then return false,why or "Unavailable" end end
			return item and item.kind==kind and item.scope==scope,"WrongItemKind"
		end,
		complete=function(player) return self:Install(player,id) end})
end
-- Give: hand an item straight to a player (no interaction) - same carry as picking it up
function Service:Give(player,id) return self:Pickup(player,id,true) end
function Service:Pickup(player,id,given)
	local entry=self._entries[id];if not entry then return false,"UnknownItem" end
	local character=player.Character;local hand=character and (character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm") or character:FindFirstChild("HumanoidRootPart"))
	if not hand or (player:GetAttribute("EHLifeState")~="Alive" and not given) then return false,"NoCharacter" end
	local ok,reason=self._inventory:Pickup(player.UserId,id);if not ok then return false,reason end
	local clone=HeldMotion.CloneDisplayPart(entry.part,"CarriedObjective")
	clone.Anchored=false;clone.CanCollide=false;clone.CanTouch=false;clone.CanQuery=false;clone.Massless=true
	clone.Size=entry.part.Size
	local grip=hand:FindFirstChild("LeftGripAttachment",true)
	local gripFrame=grip and grip:IsA("Attachment")and grip.WorldCFrame or hand.CFrame
	clone.CFrame=HeldMotion.GetCarryFrame(clone,gripFrame,CFrame.new(0,-.65,0));clone.Parent=character
	local weld=Instance.new("WeldConstraint");weld.Part0=hand;weld.Part1=clone;weld.Parent=clone;entry.carry=clone
	player:SetAttribute("EHCarriedItem",id);player:SetAttribute("EHCarriedKind",self._inventory:Get(id).kind)
	self:_Publish(entry);return true,"PickedUp"
end
-- Where a flat item comes to rest below a point: on the first solid surface, face up (its Front face, the
-- printed side), top edge away from the player. HeldItemMotion.FlatRest does the same on the dropping client.
function Service:_FlatRest(player,entry,from)
	local c=player.Character;local root=c and c:FindFirstChild("HumanoidRootPart")
	local look=root and Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z) or Vector3.new(0,0,-1)
	local f=HeldMotion.FlatRest(from,look,entry.part.Size,{c,entry.part})
	if f and self:_InBounds(entry.scope,f.Position) then return f end
end
function Service:Drop(player,clientFrame)
	local id=self._inventory:Carried(player.UserId);if not id then return false,"NothingCarried" end
	local entry=self._entries[id];local frame=self:_DropFrame(player,entry.scope)
	local ok,reason=self._inventory:Drop(player.UserId);if not ok then return false,reason end
	local release,velocity=self:_ReleaseFrame(player,entry)
	local trusted=self:_TrustedRelease(player,entry,clientFrame)
	if trusted then
		-- Same launch the dropping client already started locally, so its view continues seamlessly.
		local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local look=root and Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z).Unit or Vector3.zero
		release=trusted;velocity=(root and root.AssemblyLinearVelocity*.85 or Vector3.zero)+look*2.2+Vector3.new(0,.8,0)
	end
	self:_ClearCarry(entry)
	if entry.part:GetAttribute("DropFlat") then
		-- (Nov 3) a flat item (the site keycard) is not thrown: it drops straight down and lies face up, the
		-- printed side showing - never tumbling, landing on its edge or flipping over
		self:_Publish(entry,self:_FlatRest(player,entry,(release or frame).Position) or frame)
	elseif release then self:_Toss(entry,release,velocity,frame,trusted and player or nil) else self:_Publish(entry,frame) end
	player:SetAttribute("EHCarriedItem",nil);player:SetAttribute("EHCarriedKind",nil)
	return true,"Dropped"
end
function Service:Install(player,socketId)
	local ok,id=self._inventory:Install(player.UserId,socketId);if not ok then return false,id end
	local entry=self._entries[id];local socket=self._sockets[socketId]
	self:_ClearCarry(entry);-- seat the component in its cradle (same part, same scale as when carried)
	self:_Publish(entry,socket.part.CFrame*CFrame.new(0,0,-(socket.part:GetAttribute('SeatDepth') or 1)))
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
		for id,f in self._floors do if not f.manual and (not token or token.floorInstanceId~=id) then self:RetireFloor(id) end end
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
