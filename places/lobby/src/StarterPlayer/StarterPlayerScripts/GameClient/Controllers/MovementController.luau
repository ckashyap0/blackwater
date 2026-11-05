--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.MovementConfig)
local Responsive=require(Shared.Utilities.ResponsiveScale)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="MovementController",Dependencies={"StateController","InputController"},_player=player,_gui=gui,_held=false},Controller)
end
function Controller:Init(dependencies)
	self._state=dependencies.StateController;self._input=dependencies.InputController;self._scope=Scope.new()
	-- authored in StarterGui.Stamina (Meter > Fill); Fill's TiredColor attribute is the exhausted colour
	local gui=AuthoredGui.Get(self._gui,"Stamina");Responsive.Watch(gui)
	local bar=gui:WaitForChild("Meter");local fill=bar:WaitForChild("Fill")
	self._restColor=fill.BackgroundColor3;self._tiredColor=fill:GetAttribute("TiredColor") or Color3.fromRGB(190,105,78)
	self._bar=bar;self._fill=fill
end
function Controller:_Send(enabled)
	local epoch=self._player:GetAttribute("EHCharacterEpoch")
	if self._state:GetSnapshot() and type(epoch)=="number" and epoch>0 then
		self._state:SendAction(enabled and "BeginSprint" or "EndSprint",{characterEpoch=epoch})
	end
end
function Controller:Start()
	self._scope:Add(self._input:Register("Sprint",function(state)
		self._held=state=="Begin";self:_Send(self._held);self._elapsed=0
	end))
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function(dt)
		self._elapsed=(self._elapsed or 0)+dt
		if self._held and self._elapsed>=.5 then self._elapsed=0;self:_Send(true) end
		local stamina=self._player:GetAttribute("EHStamina") or Config.MaxStamina
		local context=self._player:GetAttribute("EHContext")
		self._bar.Visible=(context=="ActiveFloor" or context=="Transit") and stamina<Config.MaxStamina-.1
		self._fill.Size=UDim2.fromScale(math.clamp(stamina/Config.MaxStamina,0,1),1)
		self._fill.BackgroundColor3=self._player:GetAttribute("EHExhausted") and self._tiredColor or self._restColor
	end))
end
function Controller:Destroy()
	if self._held then self:_Send(false) end;self._held=false
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
