--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Config=require(Shared.Config.GameConfig)
local CleanupScope=require(Shared.Utilities.CleanupScope)
local Controller={}
Controller.__index=Controller
function Controller.new(playerGui)
	return setmetatable({Name="InterfaceController",Dependencies={"StateController"},_playerGui=playerGui},Controller)
end
function Controller:Init(dependencies)
	self._state=dependencies.StateController
	self._scope=CleanupScope.new()
end
function Controller:Start()
	-- Development-only status. No gameplay HUD, currency or objective banner is added.
	if not RunService:IsStudio() or not Config.DevelopmentStatusInStudio then return end
	-- authored in StarterGui.DevelopmentStatus (edit it there)
	local gui=AuthoredGui.Get(self._playerGui,"DevelopmentStatus");gui.Enabled=true
	local label=gui:WaitForChild("FoundationStatus")
	local function render(snapshot)
		if snapshot.run then
			label.Text="  F"..snapshot.run.floorNumber.." | "..snapshot.run.phase.." | rev "..snapshot.revision
		else label.Text="  Foundation ready | no active run" end
	end
	self._scope:Add(self._state:Subscribe(render))
	local snapshot=self._state:GetSnapshot()
	if snapshot then render(snapshot) end
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
