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
	-- The label is authored in StarterGui.DevelopmentStatus (edit it there). StarterGui cloning waits for
	-- the first character, so wait off-thread instead of holding up the other controllers.
	local label
	local function render(snapshot)
		if not label then return end
		if snapshot.run then
			label.Text="  F"..snapshot.run.floorNumber.." | "..snapshot.run.phase.." | rev "..snapshot.revision
		else label.Text="  Foundation ready | no active run" end
	end
	self._scope:Add(self._state:Subscribe(render))
	task.spawn(function()
		local gui=AuthoredGui.Get(self._playerGui,"DevelopmentStatus")
		label=gui:WaitForChild("FoundationStatus")
		gui.Enabled=true
		local snapshot=self._state:GetSnapshot()
		if snapshot then render(snapshot) end
	end)
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
