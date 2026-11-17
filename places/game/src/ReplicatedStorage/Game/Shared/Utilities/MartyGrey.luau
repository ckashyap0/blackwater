--!nonstrict
-- R41: the grey face (Level 3). Seen by ONE player: the crew member at the bypass wheel, through the
-- wired glass of the sealed attendant's booth, 8 studs away. Nothing here is replicated.
--
-- The server publishes GreyFaceAt on the floor (a server time, 2.7 s after the last wheel turn). From it:
--    0.0   the booth's bulb ticks on. Marty is at the glass, grey all over, wet at the mouth. He has been
--          standing there in the dark. He does not move for four seconds. One drip falls at 1.6 s.
--    3.0   his one line comes from the intercom behind the player (server). His mouth stays shut.
--    4.0   the bulb goes out.
--    4.3   it comes back for 1.2 s: the booth is empty, a patch of clear water on the floor.
--    5.5   dark for good. A slow heartbeat, six beats, fading.
-- He appears and goes only while the bulb is off. No stinger, no lunge, no camera lock: the player keeps
-- control the whole time. The rest of the crew see it on the header console monitor (FiltrationController).
--
-- Rig: ReplicatedStorage.MartyStages.GreyRig (M4 standing, GreyLooks SurfaceAppearances swapped in for good).
-- Marker: Level3.MartyMarkers.MartyMarker_L3Booth.MartyStand (his feet, LookVector = the way he faces).
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local SoundService = game:GetService('SoundService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Config = require(ReplicatedStorage.Game.Shared.Config.Level3)
local Refs = require(script.Parent.FloorRefs)

local M = {}
M.Active = false -- true while the sequence runs on this screen (other effects duck their sound)
local G = Config.Grey
local started = false
local played = setmetatable({}, {__mode = 'k'})

local function oneShot(id, vol, speed, parent, life)
	if not id or id == '' then return end
	local s = Instance.new('Sound')
	s.SoundId = id; s.Volume = vol; s.PlaybackSpeed = speed or 1
	if parent then s.RollOffMinDistance = 6; s.RollOffMaxDistance = 40 end
	s.Parent = parent or SoundService; s:Play()
	task.delay(life or 5, function() s:Destroy() end)
	return s
end

local function build(floor)
	local stages = ReplicatedStorage:FindFirstChild('MartyStages')
	local tpl = stages and stages:FindFirstChild('GreyRig')
	local markers = floor:FindFirstChild('MartyMarkers')
	local mk = markers and markers:FindFirstChild(Config.Stands.C)
	local stand = mk and mk:FindFirstChild('MartyStand')
	if not (tpl and tpl.PrimaryPart and stand) then return nil end
	local m = tpl:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA('BasePart') then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
		elseif d:IsA('LuaSourceContainer') or d:IsA('Sound') then d:Destroy() end
	end
	-- grey for good (one SurfaceAppearance per part)
	local gl = m:FindFirstChild('GreyLooks')
	if gl then
		for _, g in gl:GetChildren() do
			local part = m:FindFirstChild(g.Name)
			if part then
				local sa = part:FindFirstChildOfClass('SurfaceAppearance'); if sa then sa:Destroy() end
				g.Parent = part
			end
		end
		gl:Destroy()
	end
	local clip = m:FindFirstChild('Clipboard'); if clip then clip:Destroy() end
	local look = stand.CFrame.LookVector * Vector3.new(1, 0, 1)
	local feet = Vector3.new(stand.Position.X, stand.Position.Y - stand.Size.Y / 2, stand.Position.Z)
	-- stand him on the floor: his lowest point on the stand's base
	local f = CFrame.lookAt(feet, feet + look.Unit)
	m:PivotTo(f * m.PrimaryPart.CFrame:ToObjectSpace(m:GetPivot()))
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(0, feet.Y - (cf.Position.Y - size.Y / 2), 0))
	return m
end

local function run(floor, at)
	M.Active = true
	local bulb = Refs.Find(floor, 'BoothBulb')
	local light = bulb and bulb:FindFirstChildWhichIsA('Light')
	local puddle = Refs.Find(floor, 'BoothPuddle')
	local model = build(floor)
	local S = Config.Sounds
	local glassOff, glassOn = bulb and bulb.Color, Color3.fromRGB(255, 214, 150)
	local function lamp(on)
		if light then light.Enabled = on end
		if bulb then bulb.Material = on and Enum.Material.Neon or Enum.Material.Glass; bulb.Color = on and glassOn or glassOff end
		oneShot(S.click, .5, on and 1.5 or 1.2, bulb, 2)
	end
	local function waitUntil(t)
		local d = at + t - workspace:GetServerTimeNow()
		if d > 0 then task.wait(d) end
		return floor.Parent ~= nil
	end
	local buzz
	local ok, err = pcall(function()
		if model then model.Parent = workspace.CurrentCamera end
		if not waitUntil(0) then return end
		lamp(true)
		buzz = oneShot(S.bulb ~= '' and S.bulb or S.motor, .05, 2.4, bulb, G.End + 2)
		if buzz then buzz.Looped = true end
		if not waitUntil(1.6) then return end
		oneShot(S.drip, .7, .9, bulb, 3)
		local chin = model and model:FindFirstChild('ChinDrip', true)
		if chin and chin:IsA('ParticleEmitter') then chin:Emit(1) end
		if not waitUntil(G.Hold) then return end
		lamp(false)
		if buzz then buzz.Volume = 0 end
		task.wait(.06)
		if model then model:Destroy(); model = nil end
		if puddle then puddle.Transparency = .35 end
		if not waitUntil(G.Hold + G.Dark) then return end
		lamp(true)
		if buzz then buzz.Volume = .05 end
		if not waitUntil(G.Hold + G.Dark + G.Empty) then return end
		lamp(false)
		if buzz then buzz:Destroy(); buzz = nil end
		-- slow heartbeat, fading (the Floor 5 peek uses it fast)
		for i = 1, 6 do
			task.delay((i - 1) * 1.05, function() oneShot(S.heart, .9 * (1 - (i - 1) / 6.5), .86, nil, 2) end)
		end
		waitUntil(G.End)
	end)
	if not ok then warn('[ElevatorHorror] grey face: ' .. tostring(err)) end
	if model then model:Destroy() end
	if buzz then buzz:Destroy() end
	if light then light.Enabled = false end
	M.Active = false
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	task.spawn(function()
		while true do
			task.wait(.2)
			local runtime = workspace:FindFirstChild('Runtime')
			local env = runtime and runtime:FindFirstChild('DescentEnvironment')
			if env then
				for _, floor in env:GetChildren() do
					local at = floor:GetAttribute('EncounterId') == 'Level3' and floor:GetAttribute('GreyFaceAt')
					if type(at) == 'number' and played[floor] ~= at then
						played[floor] = at
						-- only the crew member in the chamber sees him, and only if they are there in time
						if player:GetAttribute('EHL3InChamber') and workspace:GetServerTimeNow() - at < G.Hold - .5 then
							task.spawn(run, floor, at)
						end
					end
				end
			end
		end
	end)
end

return M
