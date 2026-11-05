--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Cosmetics=require(game.ReplicatedStorage.Game.Shared.Config.CosmeticsConfig)
-- beam colour (player attribute EHFlashlightColor, set by CosmeticService from the LOCKER's COLORS tab)
local BEAMS={}
for _,e in Cosmetics.Beam do BEAMS[e.Id]=Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3]) end
local function beamColor(player)
	local id=player:GetAttribute("EHFlashlightColor")
	return BEAMS[(type(id)=="string" and id~="") and id or "Default"] or BEAMS.Default
end
local Controller={};Controller.__index=Controller
function Controller.new(player)
	return setmetatable({Name="EquipmentController",Dependencies={"StateController","InputController"},_player=player,_beams={}},Controller)
end
function Controller:Init(deps) self._state=deps.StateController;self._input=deps.InputController;self._scope=Scope.new() end
function Controller:_Add(player)
	if self._beams[player] then return end
	local part=Instance.new("Part");part.Name="LocalFlashlightBeam";part.Size=Vector3.new(.1,.1,.1)
	part.Transparency=1;part.Anchored=true;part.CanQuery=false;part.CanTouch=false;part.CanCollide=false;part.Parent=workspace
	local light=Instance.new("SpotLight");light.Name="Flashlight";light.Angle=55;light.Range=45;light.Brightness=2.7
	light.Face=Enum.NormalId.Front;light.Color=Color3.fromRGB(237,231,196);light.Shadows=true;light.Enabled=false;light.Parent=part
	self._beams[player]={part=part,light=light}
end
function Controller:Start()
	self._scope:Add(self._input:Register("Flashlight",function(state)
		if state=="Begin" then
			local epoch=self._player:GetAttribute("EHCharacterEpoch")
			if type(epoch)=="number" and epoch>0 then self._state:SendAction("ToggleFlashlight",{characterEpoch=epoch}) end
		end
	end))
	local function available() self._input:SetAvailable("Flashlight",self._player:GetAttribute("EHFlashlightAllowed")==true) end
	self._scope:Add(self._player:GetAttributeChangedSignal("EHFlashlightAllowed"):Connect(available));available()
	for _,p in Players:GetPlayers() do self:_Add(p) end
	self._scope:Add(Players.PlayerAdded:Connect(function(p) self:_Add(p) end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p) local b=self._beams[p];if b then b.part:Destroy();self._beams[p]=nil end end))
	self._scope:Add(RunService.RenderStepped:Connect(function()
		for player,b in self._beams do
			local head=player.Character and player.Character:FindFirstChild("Head")
			local camera=workspace.CurrentCamera
			b.light.Enabled=head~=nil and player:GetAttribute("EHFlashlightOn")==true
			if b.light.Enabled then
				local c=beamColor(player)
				if b.light.Color~=c then b.light.Color=c end
			end
			if b.light.Enabled then b.part.CFrame=player==self._player and camera and camera.CFrame or head.CFrame end
		end
	end))
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy() end
	for _,b in self._beams do b.part:Destroy() end;table.clear(self._beams)
end
return table.freeze(Controller)
