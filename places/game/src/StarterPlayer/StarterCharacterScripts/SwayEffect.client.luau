--!nonstrict
-- Mouse-look roll from the supplied SwayEffect, scoped to floor play.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local Turn = 0
local BIND_NAME = "BlackwaterCameraSway"

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function reducedMotion()
	if Player:GetAttribute("EHReduceMotion") == true then
		return true
	end
	local ok, enabled = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and enabled == true
end

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 3, function(deltaTime)
	local camera = workspace.CurrentCamera
	local context = Player:GetAttribute("EHContext")
	local active = camera
		and camera.CameraType == Enum.CameraType.Custom
		and (context == "ActiveFloor" or context == "Transit")
		and UserInputService.PreferredInput == Enum.PreferredInput.KeyboardAndMouse
		and Player:GetAttribute("EHInVent") == nil -- (no look-roll while lying in a duct)
		and not reducedMotion()
	local dt = math.clamp(deltaTime, 0, 0.1)
	local blend = 1 - math.exp(-11 * dt)
	if not active then
		Turn = lerp(Turn, 0, blend)
		return
	end

	local mouseDelta = UserInputService:GetMouseDelta()
	local targetTurn = math.clamp(mouseDelta.X, -7.5, 7.5) * 0.14
	Turn = lerp(Turn, targetTurn, blend)
	camera.CFrame = camera.CFrame * CFrame.Angles(0, 0, math.rad(Turn))
end)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep(BIND_NAME)
end)