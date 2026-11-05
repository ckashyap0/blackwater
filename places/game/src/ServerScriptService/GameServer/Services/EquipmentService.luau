--!nonstrict
local Players=game:GetService("Players")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Motion=require(game.ReplicatedStorage.Game.Shared.Utilities.HeldItemMotion)
local Service={};Service.__index=Service
function Service.new() return setmetatable({Name="EquipmentService",Dependencies={"GameRunService"},_players={},_restrictions={}},Service) end
function Service:Init(deps)
	self._runs=deps.GameRunService;self._scope=Scope.new()
end
function Service:_Allowed(player)
	local context=player:GetAttribute("EHContext")
	if player:GetAttribute("EHLifeState")~="Alive" or (context~="ActiveFloor" and context~="Transit") then return false end
	-- (the surface yard is at night now: the torch works up there too)
	local view=self._runs:GetViewFor(player.UserId);if not view then return false end
	for _,scope in self._restrictions do if scope==view.floorInstanceId then return false end end
	return true
end
function Service:_Update(player)
	local r=self._players[player];if not r then return end
	local allowed=self:_Allowed(player)
	-- Sprinting automatically stows the light (off + put away); stopping brings it back out
	-- and on again. The player's own on/off choice (desired) is never changed by sprinting.
	local stowed=player:GetAttribute("EHSprinting")==true
	local lit=Motion.ResolveLight(r,allowed,r.desired,stowed,os.clock())
	player:SetAttribute("EHFlashlightAllowed",allowed);player:SetAttribute("EHFlashlightWanted",allowed and r.desired)
	player:SetAttribute("EHFlashlightOn",lit);player:SetAttribute('EHFlashlightEquipped',lit)
end
function Service:SetAim(player,epoch,yaw,pitch)
    local r=self._players[player]
    if not r or player:GetAttribute("EHCharacterEpoch")~=epoch then return false,"StaleCharacter"end
    if not self:_Allowed(player) or not player:GetAttribute("EHFlashlightOn")then return false,"FlashlightUnavailable"end
    if os.clock()-(r.lastAim or -math.huge)<.12 then return false,"AimCooldown"end
    if type(yaw)~="number" or yaw~=yaw or math.abs(yaw)>math.pi or type(pitch)~="number" or pitch~=pitch or math.abs(pitch)>1.35 then return false,"InvalidAim"end
    r.lastAim=os.clock();player:SetAttribute("EHLightAim",Vector3.new(-math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)))
    return true,"OK"
end
function Service:Toggle(player,epoch,wanted)
	local r=self._players[player]
	if not r or player:GetAttribute("EHCharacterEpoch")~=epoch then return false,"StaleCharacter" end
	if not self:_Allowed(player) then return false,"FlashlightUnavailable" end
	-- the light is stowed while sprinting: the switch cannot be worked until you slow down
	if player:GetAttribute("EHSprinting")==true then return false,"Sprinting" end
	if (player:GetAttribute("EHKnockedUntil") or 0)>workspace:GetServerTimeNow() then return false,"Knocked" end
	if wanted~=nil and type(wanted)~='boolean'then return false,'InvalidLightState'end
	if wanted~=nil and wanted==r.desired then self:_Update(player);return true,'Unchanged'end
	if os.clock()-r.lastToggle<.25 then return false,"ToggleCooldown" end
	r.lastToggle=os.clock();if wanted==nil then r.desired=not r.desired else r.desired=wanted end;self:_Update(player)
	return true,"Toggled"
end
function Service:SetRestriction(key,floorInstanceId,blocked)
	assert(type(key)=="string" and #key<=64 and type(floorInstanceId)=="string","Invalid light restriction")
	self._restrictions[key]=blocked and floorInstanceId or nil
	for p in self._players do self:_Update(p) end
end
function Service:_Track(player)
	if self._players[player] then return end
	local r={scope=Scope.new(),desired=false,lastToggle=-math.huge};self._players[player]=r
	-- (Oct 25) the surface run starts with the torch already in your hand and on (EHSurfaceKit, set by the
	-- ElevatorService when the crew arrives)
	r.scope:Add(player:GetAttributeChangedSignal("EHSurfaceKit"):Connect(function()
		if player:GetAttribute("EHSurfaceKit")==true then r.desired=true;self:_Update(player) end
	end))
	for _,attr in {"EHContext","EHLifeState","EHCharacterEpoch","EHSprinting"} do r.scope:Add(player:GetAttributeChangedSignal(attr):Connect(function()
		if player:GetAttribute("EHLifeState")~="Alive" or player:GetAttribute("EHContext")=="Lobby" then r.desired=false end
		self:_Update(player)
	end)) end
	self:_Update(player)
end
function Service:Start()
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function()
		for p in self._players do self:_Update(p) end
	end))
	self._scope:Add(Players.PlayerAdded:Connect(function(p) self:_Track(p) end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p) if self._players[p] then self._players[p].scope:Destroy();self._players[p]=nil end end))
	self._scope:Add(self._runs:Subscribe(function()
		local token=self._runs:GetToken()
		for key,scope in self._restrictions do if not token or scope~=token.floorInstanceId then self._restrictions[key]=nil end end
		for p in self._players do self:_Update(p) end
	end))
	for _,p in Players:GetPlayers() do self:_Track(p) end
end
function Service:Destroy()
	if self._scope then self._scope:Destroy() end
	for p,r in self._players do r.scope:Destroy();p:SetAttribute("EHFlashlightOn",false);p:SetAttribute("EHFlashlightAllowed",false);p:SetAttribute('EHFlashlightEquipped',false);p:SetAttribute("EHFlashlightWanted",false) end
	table.clear(self._players);table.clear(self._restrictions)
end
return table.freeze(Service)