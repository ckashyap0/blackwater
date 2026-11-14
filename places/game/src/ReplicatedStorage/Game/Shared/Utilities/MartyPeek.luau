--!nonstrict
-- Marty peeking round a corner, seen by ONE player at a time (each screen runs its own copy; nothing is
-- replicated). Markers are parts tagged "MartyPeek" inside a floor. Each holds his feet position and facing.
-- Attributes:
--   Condition   "GateReleased" (a floor attribute that must be set) or "Stage=Reboot" (attribute = value)
--   Template    model in ReplicatedStorage.MartyStages to use (default "PeekTemplate")
--   Mode        "Far" (R39) or nothing (R37 close peek)
--
-- R39 "Far" mode (Level 5, MartyPeek_FarCorner): you are at the other end of a long hallway and, far away
-- through the haze, his head leans out past a corner, holds, and slides back. He never appears in view:
--   * the local copy is put in place only while it is hidden behind the wall from THIS camera (a ray from your
--     camera to his hidden head must hit the wall first), and only on your screen;
--   * the peek is a slow lean out from behind the wall (HideShift studs sideways), so the move you see is only
--     his head and shoulder coming past the edge, never his body arriving;
--   * it plays when you are ViewMin..ViewMax studs away, can see the corner, and look down the hall at it;
--   * if you reach the corner first, he is removed while still hidden. Once per marker per player.
--   HideShift (studs, along his left), ViewMin, ViewMax, SeeDeg (how straight you must look at the corner).
-- Close mode (Floor 4 glitch at the core drum): placed out of view near you, ducks away once seen.
-- He never touches or chases anyone.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}
local started = false
local STING = 'rbxassetid://130018094603454' -- "Horror Stinger" (Daily Sounds, free)
local BEAT = 'rbxassetid://176554627' -- "Slow Heartbeat" (free)
local SEE_COS = math.cos(math.rad(20))
local AWAY_COS = math.cos(math.rad(55))

local done = {}
local active = nil

local function smoother(u) u = math.clamp(u, 0, 1) return u * u * u * (u * (u * 6 - 15) + 10) end

local function floorOf(inst)
	local a = inst.Parent
	while a and a ~= workspace and a:GetAttribute('EncounterId') == nil do a = a.Parent end
	return (a ~= workspace) and a or nil
end

local function conditionMet(marker)
	local floor = floorOf(marker)
	if not floor then return false end
	local c = marker:GetAttribute('Condition') or ''
	local k, v = string.match(c, '^(%w+)=(%w+)$')
	if k then return tostring(floor:GetAttribute(k)) == v end
	return c ~= '' and floor:GetAttribute(c) and true or false
end

local function sound(id, vol, speed)
	local s = Instance.new('Sound')
	s.SoundId = id; s.Volume = vol; s.PlaybackSpeed = speed or 1
	s.Parent = game:GetService('SoundService'); s:Play()
	task.delay(6, function() s:Destroy() end)
end

local function heartbeat(scale)
	-- a heavy first beat, then three more fading away
	for i, v in {1, .55, .3, .14} do
		task.delay((i - 1) * .95, function() sound(BEAT, v * (scale or 1), 1) end)
	end
end

local function template(marker)
	local f = game.ReplicatedStorage:FindFirstChild('MartyStages')
	return f and f:FindFirstChild(marker:GetAttribute('Template') or 'PeekTemplate')
end

-- a local copy; returns the model and its pivot relative to the root (so we can move it by the root frame)
local function spawnCopy(marker, rootCF)
	local tpl = template(marker)
	if not tpl or not tpl.PrimaryPart then return nil end
	local m = tpl:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA('BasePart') then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	local off = m.PrimaryPart.CFrame:ToObjectSpace(m:GetPivot())
	m:PivotTo(rootCF * off)
	m.Parent = workspace.CurrentCamera -- (local only, never replicated)
	return m, off
end

local function headOf(m)
	local h = m.PrimaryPart and m.PrimaryPart:FindFirstChild('Head', true)
	return h and h.TransformedWorldCFrame.Position or m:GetPivot().Position + Vector3.new(0, 6.6, 0)
end

local function sight(cam, point, ignore)
	local dir = point - cam.CFrame.Position
	if dir.Magnitude < .1 then return true, 1, 0 end
	local dot = cam.CFrame.LookVector:Dot(dir.Unit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true -- (haze volumes and light shells do not block the view)
	local hit = workspace:Raycast(cam.CFrame.Position, dir, params)
	return (not hit) or (hit.Position - point).Magnitude < .8, dot, dir.Magnitude
end

local function glitch(m, on)
	local stages = game.ReplicatedStorage:FindFirstChild('MartyStages')
	local skin = m:FindFirstChild('Skin')
	if not (stages and skin) then return end
	local want = on and stages:FindFirstChild('Skin_Stage3') or stages:FindFirstChild('Skin_Stage1')
	if not want then return end
	local old = skin:FindFirstChildOfClass('SurfaceAppearance')
	local new = want:Clone(); new.Name = 'SurfaceAppearance'; new.Parent = skin
	if old then old:Destroy() end
end

-- R39 far peek ------------------------------------------------------------------------------------------
local OUT_T, HOLD_T, BACK_T = .9, 1.25, .65

-- his head and chest relative to his feet, read from the template once (the pose leans his head to his right)
local offsets = {}
local function bodyOffsets(marker)
	local tpl = template(marker)
	if not tpl then return Vector3.new(0, 6.6, 0), Vector3.new(0, 4.6, 0) end
	if not offsets[tpl] then
		local root = tpl.PrimaryPart
		local function at(name, fallback)
			local b = root and root:FindFirstChild(name, true)
			return b and root.CFrame:PointToObjectSpace(b.WorldPosition) or fallback
		end
		offsets[tpl] = {at('Head', Vector3.new(0, 6.4, 0)) + Vector3.new(0, .35, 0), at('UpperTorso', Vector3.new(0, 4.7, 0))}
	end
	return offsets[tpl][1], offsets[tpl][2]
end

local function farFrames(marker)
	local shift = marker:GetAttribute('HideShift') or 1.4
	return marker.CFrame * CFrame.new(-shift, 0, 0), marker.CFrame
end

local function farTryPlace(marker, cam, root, char)
	local maxD = marker:GetAttribute('ViewMax') or 110
	local minD = marker:GetAttribute('ViewMin') or 28
	local d = (root.Position - marker.Position).Magnitude
	if d > maxD + 25 or d < minD then return end
	local hidden = farFrames(marker)
	-- only put him there if his hidden head (and chest) are behind something solid from this camera
	local headOff, chestOff = bodyOffsets(marker)
	for _, o in {headOff, chestOff} do
		local vis = sight(cam, hidden:PointToWorldSpace(o), {char})
		if vis then return end
	end
	local m, off = spawnCopy(marker, hidden)
	if not m then return end
	done[marker] = true
	active = {marker = marker, model = m, off = off, mode = 'far', phase = 'hidden', seenFor = 0}
end

local function farStep(a, cam, root, char, dt, now)
	local marker = a.marker
	local hidden, out = farFrames(marker)
	local d = (root.Position - marker.Position).Magnitude
	if a.phase == 'hidden' then
		local minD = marker:GetAttribute('ViewMin') or 28
		local maxD = marker:GetAttribute('ViewMax') or 110
		if d < minD then a.model:Destroy(); active = nil; return end -- you got there first: he was never seen
		local seeCos = math.cos(math.rad(marker:GetAttribute('SeeDeg') or 12))
		local peekHead = out:PointToWorldSpace((bodyOffsets(marker)))
		local vis, dot = sight(cam, peekHead, {char, a.model})
		if d <= maxD and vis and dot > seeCos then a.seenFor += dt else a.seenFor = math.max(0, a.seenFor - dt) end
		if a.seenFor > .3 then a.phase = 'out'; a.t0 = now; sound(STING, .38, .92) end
	elseif a.phase == 'out' then
		local u = smoother((now - a.t0) / OUT_T)
		a.model:PivotTo(hidden:Lerp(out, u) * a.off)
		if u >= 1 then a.phase = 'hold'; a.t0 = now end
	elseif a.phase == 'hold' then
		if now - a.t0 >= HOLD_T then a.phase = 'back'; a.t0 = now; heartbeat(.8) end
	elseif a.phase == 'back' then
		local u = smoother((now - a.t0) / BACK_T)
		a.model:PivotTo(out:Lerp(hidden, u) * a.off)
		if u >= 1 then a.model:Destroy(); active = nil end
	end
end

-- R37 close peek (Floor 4) -------------------------------------------------------------------------------
local function closeStep(a, cam, root, char, dt, now)
	local head = headOf(a.model)
	local vis, dot = sight(cam, head, {a.model, char})
	if a.phase == 'wait' then
		if vis and dot > SEE_COS then
			a.seenFor += dt
			if a.marker:GetAttribute('Glitch') and not a.glitched then a.glitched = true; glitch(a.model, true) end
			if a.glitched then
				-- the face corrupts: the head twitches and the eyes flicker while you look
				local h = a.model.PrimaryPart:FindFirstChild('Head', true)
				if h then h.Transform = CFrame.Angles(math.rad(math.random(-6, 6)), math.rad(math.random(-8, 8)), math.rad(math.random(-5, 5))) end
				local eyes = a.model:FindFirstChild('Eyes'); if eyes then eyes.Transparency = (math.random() < .3) and 1 or 0 end
			end
			if a.seenFor > .35 then
				a.phase = 'duck'; a.t0 = now; a.from = a.model:GetPivot()
				sound(STING, .7); heartbeat()
			end
		else
			a.seenFor = math.max(0, a.seenFor - dt)
			if (root.Position - a.marker.Position).Magnitude < 5 then a.model:Destroy(); active = nil end
		end
	elseif a.phase == 'duck' then
		-- back out of sight, then gone
		local u = smoother((now - a.t0) / .45)
		local side = (a.marker:GetAttribute('LeanDeg') or 0) >= 0 and 1 or -1
		local away = a.marker.CFrame.RightVector * (-1.9 * side) - a.marker.CFrame.LookVector * .6
		a.model:PivotTo(a.from + away * u)
		if u >= 1 then a.model:Destroy(); active = nil end
	end
end

local function closeTryPlace(marker, cam, root, char)
	if (root.Position - marker.Position).Magnitude >= (marker:GetAttribute('TriggerDist') or 16) then return end
	local _, dot = sight(cam, marker.Position + Vector3.new(0, 6, 0), {char})
	if dot >= AWAY_COS then return end -- only while that spot is out of view
	local base = marker.CFrame * CFrame.Angles(0, 0, math.rad(marker:GetAttribute('LeanDeg') or 0))
	local m, off = spawnCopy(marker, base)
	if m then done[marker] = true; active = {marker = marker, model = m, off = off, mode = 'close', phase = 'wait', seenFor = 0} end
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	local nextScan = 0
	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local cam = workspace.CurrentCamera
		local char = player.Character
		local root = char and char:FindFirstChild('HumanoidRootPart')
		if not (cam and root) then return end
		local now = os.clock()
		if active then
			local a = active
			if not a.marker.Parent or not a.model.Parent then if a.model.Parent then a.model:Destroy() end; active = nil; return end
			if a.mode == 'far' then farStep(a, cam, root, char, dt, now) else closeStep(a, cam, root, char, dt, now) end
			return
		end
		if player:GetAttribute('EHCinematic') or now < nextScan then return end
		nextScan = now + .15
		local runtime = workspace:FindFirstChild('Runtime')
		if not runtime then return end
		for _, marker in CS:GetTagged('MartyPeek') do
			if marker:IsDescendantOf(runtime) and not done[marker] and conditionMet(marker) then
				if marker:GetAttribute('Mode') == 'Far' then farTryPlace(marker, cam, root, char) else closeTryPlace(marker, cam, root, char) end
				if active then break end
			end
		end
	end)
end

return M
