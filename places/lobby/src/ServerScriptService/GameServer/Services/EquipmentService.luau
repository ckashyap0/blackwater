--!nonstrict
local Players=game:GetService("Players")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Service={};Service.__index=Service
function Service.new() return setmetatable({Name="EquipmentService",Dependencies={"GameRunService"},_players={},_restrictions={}},Service) end
function Service:Init(deps)
	self._runs=deps.GameRunService;self._scope=Scope.new();self._noise=self._scope:Add(Instance.new("BindableEvent"))
end
function Service:SubscribeNoise(callback) return self._noise.Event:Connect(callback) end
function Service:_Allowed(player)
	local context=player:GetAttribute("EHContext")
	if player:GetAttribute("EHLifeState")~="Alive" or (context~="ActiveFloor" and context~="Transit") then return false end
	local view=self._runs:GetViewFor(player.UserId);if not view then return false end
	for _,scope in self._restrictions do if scope==view.floorInstanceId then return false end end
	return true
end
function Service:_Update(player)
	local r=self._players[player];if not r then return end
	local allowed=self:_Allowed(player)
	player:SetAttribute("EHFlashlightAllowed",allowed);player:SetAttribute("EHFlashlightOn",allowed and r.desired)
end
function Service:Toggle(player,epoch)
	local r=self._players[player]
	if not r or player:GetAttribute("EHCharacterEpoch")~=epoch then return false,"StaleCharacter" end
	if not self:_Allowed(player) then return false,"FlashlightUnavailable" end
	if os.clock()-r.lastToggle<.25 then return false,"ToggleCooldown" end
	r.lastToggle=os.clock();r.desired=not r.desired;self:_Update(player)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then self._noise:Fire({kind="FlashlightToggle",userId=player.UserId,position=root.Position,runId=self._runs:GetViewFor(player.UserId).runId}) end
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
	for _,attr in {"EHContext","EHLifeState","EHCharacterEpoch"} do r.scope:Add(player:GetAttributeChangedSignal(attr):Connect(function()
		if player:GetAttribute("EHLifeState")~="Alive" or player:GetAttribute("EHContext")=="Lobby" then r.desired=false end
		self:_Update(player)
	end)) end
	self:_Update(player)
end
function Service:Start()
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
	for p,r in self._players do r.scope:Destroy();p:SetAttribute("EHFlashlightOn",false);p:SetAttribute("EHFlashlightAllowed",false) end
	table.clear(self._players);table.clear(self._restrictions)
end
return table.freeze(Service)
