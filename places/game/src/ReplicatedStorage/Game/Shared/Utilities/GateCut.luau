--!nonstrict
-- Level 5's shaft gate opening, shown to the whole crew. When someone pulls OPEN GATE in the control room, the
-- server sets ReturnGateOpenedAt on the floor (Level5Floor) and every client lifts the gate leaf from that time
-- (MechanismController, 2.4 s). On every screen:
--   fade to black -> a camera pointed straight at the gate as it grinds open -> fade to black -> your own view.
-- R39: the fades make the move into and out of the shot smooth; the gate area is streamed in for this player
-- before the shot (StreamingEnabled: players far away in the control room had nothing there to look at); the
-- shot is timed from the server stamp, so everyone sees the same lift. No skip (it is short).
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')

local M = {}
local started = false
local FADE = .35
local SHOT_END = 3.3
local REGROUP_HOLD = 4.15 -- seconds after the stamp the black lifts (the regroup happens at 3.75 on the server) -- seconds after the stamp when the fade back to your view starts (the lift takes 2.4)
local MOTOR = 'rbxassetid://9119630180' -- the barrier motor already used in the yard, slowed down

local function blackScreen(player)
	local gui = Instance.new('ScreenGui')
	gui.Name = 'GateCutFade'; gui.IgnoreGuiInset = true; gui.DisplayOrder = 50; gui.ResetOnSpawn = false
	local f = Instance.new('Frame')
	f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.new(0, 0, 0); f.BackgroundTransparency = 1; f.BorderSizePixel = 0
	f.Parent = gui
	gui.Parent = player:WaitForChild('PlayerGui')
	return gui, f
end

local function fade(f, to)
	local tw = TweenService:Create(f, TweenInfo.new(FADE, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), {BackgroundTransparency = to and 0 or 1})
	tw:Play(); tw.Completed:Wait()
end

local function play(floor, at)
	local player = Players.LocalPlayer
	local cam = workspace.CurrentCamera
	if not cam or player:GetAttribute('EHCinematic') then return end
	local gate
	for _, d in floor:GetDescendants() do if d:IsA('BasePart') and (d:GetAttribute('Ref') == 'ReturnGate' or d.Name == 'ReturnGate') then gate = d break end end
	if not gate then return end
	player:SetAttribute('EHCinematic', true)
	local gui, black = blackScreen(player)
	fade(black, true)
	-- make sure the gate and the hall around it are loaded on this screen
	pcall(function() player:RequestStreamAroundAsync(gate.Position, 3) end)
	-- the camera stands on the side of the gate the crew is on (away from the lift), a little above eye level
	local side = gate.CFrame.RightVector
	local root = player.Character and player.Character:FindFirstChild('HumanoidRootPart')
	if root and side:Dot(root.Position - gate.Position) < 0 then side = -side end
	local aim = gate.Position + Vector3.new(0, -1.5, 0)
	local pos0 = aim + side * 13 + Vector3.new(0, 2.2, 0)
	local pos1 = aim + side * 10 + Vector3.new(0, 1.6, 0)
	local type0, fov0 = cam.CameraType, cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 55
	local s = Instance.new('Sound'); s.SoundId = MOTOR; s.Volume = .55; s.PlaybackSpeed = .55
	s.Parent = game:GetService('SoundService'); s:Play()
	local conn = RunService.RenderStepped:Connect(function()
		local u = math.clamp((workspace:GetServerTimeNow() - at) / SHOT_END, 0, 1)
		-- a slow push in towards the gate while it rises
		cam.CFrame = CFrame.lookAt(pos0:Lerp(pos1, u * u * (3 - 2 * u)), aim)
	end)
	fade(black, false)
	local left = SHOT_END - (workspace:GetServerTimeNow() - at)
	if left > 0 then task.wait(left) end
	fade(black, true)
	conn:Disconnect()
	cam.CameraType = type0 == Enum.CameraType.Scriptable and Enum.CameraType.Custom or type0
	cam.FieldOfView = fov0
	player:SetAttribute('EHCinematic', nil)
	-- (Nov 17) stay black until the server has brought the crew together beside whoever opened the gate
	-- (Level5Floor REGROUP_AT = 3.75 s), so the move is never seen
	local hold = (at + REGROUP_HOLD) - workspace:GetServerTimeNow()
	task.wait(math.max(.1, hold))
	fade(black, false)
	gui:Destroy()
	task.delay(1.5, function() s:Destroy() end)
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local seen = setmetatable({}, {__mode = 'k'})
	task.spawn(function()
		while true do
			local runtime = workspace:FindFirstChild('Runtime')
			local env = runtime and runtime:FindFirstChild('DescentEnvironment')
			if env then
				for _, m in env:GetChildren() do
					if m:GetAttribute('EncounterId') == 'Level5' and not seen[m] then
						seen[m] = true
						local function check()
							local at = m:GetAttribute('ReturnGateOpenedAt')
							if type(at) == 'number' and workspace:GetServerTimeNow() - at < 2 then task.spawn(play, m, at) end
						end
						m:GetAttributeChangedSignal('ReturnGateOpenedAt'):Connect(check)
						check() -- (the gate may have opened just before this floor was found)
					end
				end
			end
			task.wait(1)
		end
	end)
end

return M
