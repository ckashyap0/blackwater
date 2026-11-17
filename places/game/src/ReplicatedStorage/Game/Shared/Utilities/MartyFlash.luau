--!nonstrict
-- (Nov 16) The Level 5 -> Level 4 ride. The doors shut, the lift goes down smoothly and you can move about as normal.
-- A few seconds in, with no build-up, a sudden scare noise hits and Marty is THERE for half a second: standing in
-- his normal pose in the corner of the cabin to the right of where you are looking, eyes glowing, glitching in and
-- straight back out (Config.MartyGlitch, keyed in Blender). Then he is gone and nothing else happens: the ride
-- carries on to Level 4. Your camera and controls are never touched.
-- One copy of him, on your screen only (each screen runs its own; nothing is replicated).
-- AtmosphereController calls M.Step() every frame; it plays once per ride whose cabin has TravelFromFloor == 5
-- (set by ElevatorService:_Seal).
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local SoundService = game:GetService('SoundService')
local Rig = require(script.Parent.MartyRig)

local M = {}
M.FROM_FLOOR = 5
M.AT = 3.2          -- seconds into the ride
M.SHOW = .5         -- how long he is there (the glitch animation's length)
M.SCREEN_X = .42    -- where he stands across your view (0 = middle, 1 = right edge of the view)
local SOUNDS = {
	{'rbxassetid://130018094603454', 1.1, 1.05},  -- horror stinger
	{'rbxassetid://9125474229', 1.3, 1.15},       -- short creature screech
	{'rbxassetid://9120188288', .9, .7},          -- metal hit, low
}
local CRACKLE = 'rbxassetid://87751901232664'   -- electrical crackle under the glitch

local played = {}
local active = nil
local sets, order, fps

local function sound(id, vol, speed, life)
	local s = Instance.new('Sound'); s.SoundId = id; s.Volume = vol; s.PlaybackSpeed = speed or 1; s.Parent = SoundService; s:Play()
	task.delay(life or 5, function() s:Destroy() end)
	return s
end

local function cabinNow()
	local r = workspace:FindFirstChild('Runtime'); local e = r and r:FindFirstChild('DescentEnvironment')
	return e and e:FindFirstChild('Elevator')
end

-- his spot: the cabin corner nearest to the right-hand side of your view (so you catch him in the corner of your eye)
local function spot(cabin, cam, head)
	local floor = cabin:FindFirstChild('Floor', true)
	if not (floor and floor:IsA('BasePart')) then return nil end
	local top = floor.Position.Y + floor.Size.Y / 2
	local hx, hz = floor.Size.X / 2 - 1.7, floor.Size.Z / 2 - 1.6
	local best, bestScore
	for _, c in {{1, 1}, {1, -1}, {-1, 1}, {-1, -1}, {1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
		local p = floor.CFrame:PointToWorldSpace(Vector3.new(c[1] * hx, 0, c[2] * hz))
		p = Vector3.new(p.X, top, p.Z)
		local v = cam.CFrame:PointToObjectSpace(p + Vector3.new(0, 4, 0))
		local fwd = -v.Z
		local score
		if fwd > 2 then score = -math.abs(v.X / fwd - M.SCREEN_X) else score = -10 + fwd * .1 end
		if Vector3.new(p.X - head.X, 0, p.Z - head.Z).Magnitude < 3 then score -= 5 end -- never on top of you
		if not bestScore or score > bestScore then best, bestScore = p, score end
	end
	return best
end

local function finish(a)
	if a.conn then a.conn:Disconnect() end
	if a.model and a.model.Parent then a.model:Destroy() end
	active = nil
end

function M.Showing() return active ~= nil end

function M.Step()
	if active or not RunService:IsClient() then return end
	local cabin = cabinNow(); if not cabin then return end
	local started = cabin:GetAttribute('TravelStartedAt')
	if type(started) ~= 'number' or cabin:GetAttribute('TravelFromFloor') ~= M.FROM_FLOOR or played[started] then return end
	local e = workspace:GetServerTimeNow() - started
	if e < M.AT then return end
	played[started] = true
	if e > M.AT + .6 then return end -- joined late: never half way
	M.Play(cabin)
end

function M.Play(cabin)
	if active then return end
	local cam = workspace.CurrentCamera
	local char = Players.LocalPlayer.Character
	local head = char and char:FindFirstChild('Head')
	if not (cam and head) then return end
	local centre = cabin:FindFirstChild('CabinCentre', true)
	if centre and centre:IsA('BasePart') then
		local d = head.Position - centre.Position
		if Vector2.new(d.X, d.Z).Magnitude > 9 or math.abs(d.Y) > 9 then return end -- not in the cabin
	end
	local p = spot(cabin, cam, head.Position); if not p then return end
	local feet = CFrame.lookAt(p, Vector3.new(head.Position.X, p.Y, head.Position.Z))
	if not sets then sets, order, fps = Rig.GlitchSets() end
	local a = Rig.Build(feet, sets); if not a then return end
	Rig.Set(a, 'G' .. order[1])
	for _, d in a.model:GetDescendants() do if d:IsA('BasePart') then d.CastShadow = false end end
	a.model.Parent = cam -- (local only)
	a.t0 = os.clock()
	active = a
	Rig.Eyes(a, 1)
	for _, s in SOUNDS do sound(s[1], s[2], s[3]) end
	local c = sound(CRACKLE, .35, 1.1, 1.2); pcall(function() c.TimePosition = math.random() * 3 end)
	local parts = {}
	for _, d in a.model:GetDescendants() do if d:IsA('BasePart') and d.Name ~= 'RootPart' then table.insert(parts, d) end end
	local lastF = -1
	a.conn = RunService.RenderStepped:Connect(function()
		if active ~= a then return end
		local t = os.clock() - a.t0
		if t >= M.SHOW then finish(a); if c.Parent then c:Stop() end; return end
		local f = math.clamp(math.floor(t * fps), 0, #order - 1)
		if f ~= lastF then
			lastF = f
			Rig.Set(a, 'G' .. order[f + 1])
			-- the glitch stutters: in the snapping frames he blinks out for a frame here and there
			local blink = (f == 1 or f == 3 or f == 23 or f == 27)
			for _, part in parts do part.LocalTransparencyModifier = blink and 1 or 0 end
			Rig.Eyes(a, blink and 0 or (f >= 6 and f < 22) and 1 or .55 + .45 * (f % 2))
		end
	end)
end

return M
