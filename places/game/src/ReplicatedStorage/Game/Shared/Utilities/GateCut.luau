--!nonstrict
-- R37 (Nov 13): Level 5's shaft gate opening, shown to the whole crew. When someone pulls OPEN GATE in the
-- control room, the server sets ReturnGateOpenedAt on the floor (Level5Floor) and the gate leaf rises. On every
-- screen: a hard cut to a camera pointed straight at the gate, the gate grinds open with a heavy mechanical
-- sound, and after about three seconds a hard cut back to your own view. No skip (it is short).
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

local M = {}
local started = false
local SHOT = 3.1
local MOTOR = 'rbxassetid://9119630180' -- the barrier motor already used in the yard, slowed down

local function play(floor)
	local player = Players.LocalPlayer
	local cam = workspace.CurrentCamera
	if not cam or player:GetAttribute('EHCinematic') then return end
	local gate
	for _, d in floor:GetDescendants() do if d:IsA('BasePart') and (d:GetAttribute('Ref') == 'ReturnGate' or d.Name == 'ReturnGate') then gate = d break end end
	if not gate then return end
	-- the camera stands on the side of the gate the crew is on (away from the lift), a little above eye level
	local side = gate.CFrame.RightVector
	local root = player.Character and player.Character:FindFirstChild('HumanoidRootPart')
	if root and side:Dot(root.Position - gate.Position) < 0 then side = -side end
	local at = gate.Position + Vector3.new(0, -1.5, 0)
	local pos = at + side * 13 + Vector3.new(0, 2.2, 0)
	local type0, fov0 = cam.CameraType, cam.FieldOfView
	player:SetAttribute('EHCinematic', true)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 55
	local s = Instance.new('Sound'); s.SoundId = MOTOR; s.Volume = .55; s.PlaybackSpeed = .55
	s.Parent = game:GetService('SoundService'); s:Play()
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = os.clock() - t0
		-- a slow push in towards the gate while it rises
		cam.CFrame = CFrame.lookAt(pos:Lerp(at + side * 10 + Vector3.new(0, 1.6, 0), math.clamp(u / SHOT, 0, 1)), at)
		if u >= SHOT then
			conn:Disconnect()
			cam.CameraType = type0 == Enum.CameraType.Scriptable and Enum.CameraType.Custom or type0
			cam.FieldOfView = fov0
			player:SetAttribute('EHCinematic', nil)
			task.delay(1.5, function() s:Destroy() end)
		end
	end)
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
							if type(at) == 'number' and workspace:GetServerTimeNow() - at < 2 then play(m) end
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
