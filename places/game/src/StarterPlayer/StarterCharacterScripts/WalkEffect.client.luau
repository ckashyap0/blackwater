--!nonstrict
-- Character-local first-person head motion (rebinds on every respawn).
--  * One shared stride clock (Shared.Utilities.StrideState): this script drives the camera
--    and publishes the stride; the held items read the same clock, so camera and hands
--    move on exactly the same footfalls.
--  * Uneven, organic cadence: left/right steps alternate in length and weight, each step's
--    strength varies slightly, and the rise after a footfall is quicker than the settle, so
--    it never reads as a clean mechanical sine wave.
--  * Sprinting strongly amplifies bob, sway, roll and nod, plus a light tremor for panic;
--    everything stays smoothed and clamped so it never becomes jittery.
--  * The motion added each frame is removed again just before the camera module runs, so
--    it can never accumulate into the player's aim.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")
local Shared = game.ReplicatedStorage:WaitForChild("Game"):WaitForChild("Shared")
local Immersion = require(Shared:WaitForChild("Config"):WaitForChild("ImmersionConfig"))
local Stride = require(Shared:WaitForChild("Utilities"):WaitForChild("StrideState"))

local STEP = Immersion.StepDistance or 5.8
local WALK_SPEED = 12
-- { walk, sprint } - positions in studs, angles in degrees.
local TUNE = {
	bob = { 0.066, 0.14 },   -- vertical travel per footfall (walk nudged up slightly; sprint unchanged)
	sway = { 0.052, 0.13 },  -- lateral travel per stride
	roll = { 0.36, 1.1 },     -- side-to-side roll per stride
	nod = { 0.2, 0 },     -- downward nod on each footfall (a faint one while walking only)
	tremor = { 0, 0 },    -- irregular high-frequency shake (sprint only)
	strafeRoll = 0.012,       -- lean into sideways movement (radians per walk speed)
	breath = 0.006,          -- idle breathing (studs)
}
local GAIT = {
	limp = 0.05,       -- left steps 5% longer / right 5% shorter in time
	weight = 0.08,     -- left steps land 8% heavier than right
	variation = 0.12,  -- per-step random strength variation
	peak = 0.4,        -- the head reaches its top 40% of the way through each step (quick rise, slow settle)
}
local PEAK_GAMMA = math.log(0.5) / math.log(GAIT.peak)

local BIND_NAME = "BlackwaterWalkEffect"
local UNDO_NAME = "BlackwaterWalkEffectUndo"
local steps, clock = 0, 0 -- steps: continuous count of footfalls (integer = footfall)
local moving, sprint, strafe, idle = 0, 0, 0, 0
-- crawling through a duct (EHInVent): a smooth glide - no footfall bob, no nod and almost no sway
-- or roll (the crawl's own slow body roll already moves the eye a little)
local crawl = 0
local applied = CFrame.identity
local alive = true

local function reducedMotion()
	if Player:GetAttribute("EHReduceMotion") == true then
		return true
	end
	local ok, enabled = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and enabled == true
end

local function mix(pair)
	return pair[1] + (pair[2] - pair[1]) * sprint
end

-- Deterministic strength of footfall n: alternating foot weight plus smooth per-step variation.
local function stepStrength(n)
	local foot = (n % 2 == 0) and (1 + GAIT.weight) or (1 - GAIT.weight)
	return foot * (1 + math.noise(n * 0.61 + 0.17, 3.7) * GAIT.variation * 2)
end

local function unapply()
	local camera = workspace.CurrentCamera
	if camera and applied ~= CFrame.identity then
		camera.CFrame = camera.CFrame * applied:Inverse()
	end
	applied = CFrame.identity
end

local function stop()
	alive = false
	RunService:UnbindFromRenderStep(BIND_NAME)
	RunService:UnbindFromRenderStep(UNDO_NAME)
	unapply()
	Stride.moving, Stride.sprint, Stride.impact = 0, 0, 0
end

local function update(deltaTime)
	if not alive or not Character.Parent or Humanoid.Health <= 0 then
		stop()
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then return end
	local dt = math.clamp(deltaTime, 0, 0.1)
	clock += dt

	local context = Player:GetAttribute("EHContext")
	local active = (context == "ActiveFloor" or context == "Transit")
		and camera.CameraType == Enum.CameraType.Custom
		and not reducedMotion()

	local root = Character:FindFirstChild("HumanoidRootPart")
	local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local grounded = Humanoid.FloorMaterial ~= Enum.Material.Air
	local sprinting = Player:GetAttribute("EHSprinting") == true and speed > WALK_SPEED * 0.6
	crawl += ((Player:GetAttribute("EHInVent") ~= nil and 1 or 0) - crawl) * (1 - math.exp(-6 * dt))
	local pace = WALK_SPEED * (1 - 0.5 * crawl)

	moving += ((active and grounded and math.clamp(speed / pace, 0, 1) or 0) - moving) * (1 - math.exp(-8 * dt))
	sprint += ((active and sprinting and 1 or 0) - sprint) * (1 - math.exp(-5 * dt))
	idle += (((active and speed < 0.5) and 1 or 0) - idle) * (1 - math.exp(-3 * dt))

	-- Advance the stride. Alternate steps take slightly different time (uneven rhythm).
	local n = math.floor(steps)
	if grounded then
		local limp = (n % 2 == 0) and (1 - GAIT.limp) or (1 + GAIT.limp)
		steps += speed / (STEP * (1 - 0.45 * crawl)) * dt * limp
	end
	n = math.floor(steps)
	local u = steps - n
	local w = u ^ PEAK_GAMMA -- warped progress: quick rise off the footfall, slower settle
	local phase = math.pi * (n + w)
	local strength = stepStrength(n) + (stepStrength(n + 1) - stepStrength(n)) * (u * u * (3 - 2 * u))
	local lift = math.sin(math.pi * w) -- 0 at each footfall, 1 at the top of the step
	local impact = (1 - lift) ^ 3

	local amp = moving * strength
	local y = (lift - 0.5) * mix(TUNE.bob) * amp * (1 - crawl)
	local c = math.cos(phase)
	local x = c * mix(TUNE.sway) * moving * (1 - 0.95 * crawl)
	local roll = math.rad(c * mix(TUNE.roll)) * moving * (1 - 0.9 * crawl)
	local nod = -math.rad(impact * mix(TUNE.nod)) * amp * (1 - crawl)

	local tremor = math.rad(mix(TUNE.tremor)) * moving
	local tremorPitch = (math.sin(clock * 23.1) + math.sin(clock * 37.7 + 1.3) * 0.5) * tremor
	local tremorRoll = (math.sin(clock * 19.3 + 0.7) + math.sin(clock * 31.1) * 0.5) * tremor

	local lateral = root and camera.CFrame:VectorToObjectSpace(velocity).X / WALK_SPEED or 0
	strafe += (math.clamp(active and -lateral * TUNE.strafeRoll or 0, -0.1, 0.1) * (1 - crawl) - strafe) * (1 - math.exp(-10 * dt))

	-- (lying still in a duct the view is perfectly still: no breathing bob there)
	local breathY = math.sin(clock * 1.7) * TUNE.breath * idle * (1 - crawl)
	local breathPitch = 0 -- no motion-driven change to player aim

	-- Publish the stride so the held items lock to these exact footfalls.
	Stride.phase, Stride.impact, Stride.moving, Stride.sprint, Stride.step = phase, impact * strength, moving, sprint, n
	Stride.updated = os.clock()

	if camera.CameraType ~= Enum.CameraType.Custom then
		return -- cutscenes and scripted shots are left untouched
	end
	local offset = CFrame.new(x, y + breathY, 0)
		* CFrame.Angles(nod + tremorPitch + breathPitch, 0, roll + strafe + tremorRoll)
	camera.CFrame = camera.CFrame * offset
	applied = offset
end

RunService:BindToRenderStep(UNDO_NAME, Enum.RenderPriority.Camera.Value - 1, unapply)
RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 4, update)
Humanoid.Died:Connect(stop)
script.Destroying:Connect(stop)
print("WalkEffect script loaded. Will run with attributes attached")