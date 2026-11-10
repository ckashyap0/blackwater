--!nonstrict
-- UiScaleController (Nov 5): one size for every authored HUD panel on every device.
-- A panel opts in by holding a UIScale named "AutoScale" (authored in StarterGui - edit it there). Optional
-- attributes on that UIScale tune it: RefX / RefY (the design size the panel was laid out for, default 1280 x 720 -
-- the Studio window these panels were built and checked in, so a normal PC window shows them exactly as authored),
-- Min / Max (clamp, default .6 / 1.25). Every AutoScale in the PlayerGui - including copies other scripts clone
-- from the templates - is kept on HudScale.Factor for the current screen size and input device (phones and
-- tablets get a readable boost, consoles a couch-distance boost), so offset-sized panels look the same on PC,
-- phone, tablet and console. Panels that already scale themselves (objective line, interaction prompt and card,
-- control room HUD and task window, records reader) keep their own UIScales and are not touched.
local HudScale = require(game.ReplicatedStorage.Game.Shared.Utilities.HudScale)
local Scope = require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local UIS = game:GetService('UserInputService')
local NAME = 'AutoScale'

local Controller = {}; Controller.__index = Controller
function Controller.new(playerGui)
	return setmetatable({Name = 'UiScaleController', Dependencies = {}, _gui = playerGui, _scales = {}}, Controller)
end
function Controller:Init() self._scope = Scope.new() end

local function optionsFor(s)
	return {
		referenceSize = Vector2.new(s:GetAttribute('RefX') or 1280, s:GetAttribute('RefY') or 720),
		min = s:GetAttribute('Min') or .6,
		max = s:GetAttribute('Max') or 1.25,
	}
end

function Controller:_Apply(s)
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	if not v or v.X < 2 or v.Y < 2 then return end
	s.Scale = HudScale.Factor(v, optionsFor(s), HudScale.IsTenFoot())
end
function Controller:_Track(s)
	if not (s:IsA('UIScale') and s.Name == NAME) or self._scales[s] then return end
	self._scales[s] = true
	self:_Apply(s)
end
function Controller:_RefreshAll()
	for s in self._scales do
		if s.Parent and s:IsDescendantOf(self._gui) then self:_Apply(s) else self._scales[s] = nil end
	end
end

function Controller:Start()
	for _, d in self._gui:GetDescendants() do self:_Track(d) end
	self._scope:Add(self._gui.DescendantAdded:Connect(function(d) self:_Track(d) end))
	local camConn
	local function watchCamera()
		if camConn then camConn:Disconnect() end
		local cam = workspace.CurrentCamera
		if cam then camConn = cam:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:_RefreshAll() end) end
		self:_RefreshAll()
	end
	watchCamera()
	self._scope:Add(workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(watchCamera))
	self._scope:Add(UIS:GetPropertyChangedSignal('PreferredInput'):Connect(function() self:_RefreshAll() end))
	self._scope:Add(function() if camConn then camConn:Disconnect() end end)
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
