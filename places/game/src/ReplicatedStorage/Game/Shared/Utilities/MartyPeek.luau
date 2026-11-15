--!nonstrict
-- Marty peeking round a corner, seen by ONE player at a time (each screen runs its own copy; nothing is
-- replicated). Markers are parts tagged "MartyPeek" inside a floor.
--
-- R40: the only Marty scare in the game (Floor 5). One model, ReplicatedStorage.MartyStages.PeekRig (M4 rig with
-- the smirk baked into the face), posed bone by bone from Config.MartyPeekPoses (four poses built in Blender:
-- A peek, B face turning in, C deep retract, D gone behind the wall).
--
-- The marker part stands at his FEET, LookVector = the way he faces (into the wall that hides him), so the wall
-- edge he peeks past is on his right: WallEdge in MartyPeekPoses (0.42 m right, 0.30 m ahead, about 1.5 and 1.08
-- studs at his 7.5-stud height). Attributes:
--   Condition  "GateReleased" (a floor attribute that must be set) or "Stage=Reboot" (attribute = value)
--   ViewMin, ViewMax  distance band (studs) from which the peek plays (default 15..42)
--   SeeDeg     how straight you must look at him (default 22)
--   HideShift  studs he stands further left while hidden (default 1.2)
--
-- What you see: you look down the hall at the corner and his head, shoulder and both hands lean out past the
-- edge and hold (he smirks). While he is out he flickers grey a few times, each flick with an electric crackle
-- over a low static bed. Then he turns his face in and pulls back fast, hands last. One second after the last
-- of him is gone, the model is removed. A heartbeat starts on the first sound and runs fast, then fades out
-- slowing down. The copy only ever appears or disappears while it is hidden behind the wall from YOUR camera.
-- Once per marker per player. He never touches or chases anyone.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')
local ContentProvider = game:GetService('ContentProvider')
local SoundService = game:GetService('SoundService')

local Poses = require(game:GetService('ReplicatedStorage').Game.Shared.Config.MartyPeekPoses)

local M = {}
local started = false
local STING = 'rbxassetid://130018094603454' -- "Horror Stinger" (Daily Sounds, free)
local BEAT = 'rbxassetid://176554627' -- "Slow Heartbeat" (free; one 1 s beat)
local STATIC = 'rbxassetid://9117060042' -- "Nasa Static Burst 2" (ProSoundEffects), already used by the control room
local CRACKLE = 'rbxassetid://87751901232664' -- the lift's ElectricalFault crackle

-- timings (seconds)
local OUT_T, HOLD_T = .55, 1.25
local RETRACT = {{'A', 'B', .16}, {'B', 'C', .16}, {'C', 'D', .24}}
local GONE_T = 1.0
local FLICKS = {.22, .62, .98} -- grey flicks during the hold (from the end of the lean out)
local FLICK_LEN = .085
-- heartbeat: gaps between beats and their volume; fast and loud first, then fading out and slowing down
local BEAT_GAPS = {.62, .52, .46, .42, .43, .48, .56, .66, .78, .92}
local BEAT_VOL = {.95, 1, 1, .92, .78, .6, .44, .3, .18, .08}

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

local function newSound(id, vol, speed, looped)
	local s = Instance.new('Sound')
	s.SoundId = id; s.Volume = vol; s.PlaybackSpeed = speed or 1; s.Looped = looped or false
	s.Parent = SoundService
	return s
end

local function oneShot(id, vol, speed, life)
	local s = newSound(id, vol, speed); s:Play()
	task.delay(life or 6, function() s:Destroy() end)
	return s
end

local function heartbeat()
	local t = 0
	for i, gap in BEAT_GAPS do
		local v = BEAT_VOL[i]
		local speed = 1 + .07 * math.clamp(1 - math.abs(i - 4) / 3, 0, 1) -- a touch quicker at the fast part
		task.delay(t, function() oneShot(BEAT, v, speed, 2) end)
		t += gap
	end
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

-- Blender armature space -> the marker's local space (Roblox: X = his right, Y = up, -Z = the way he faces)
local BLEND = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
local function bvec(t) return BLEND:VectorToWorldSpace(Vector3.new(t[1], t[2], t[3])) end

-- the rig copy: placed so its rest skeleton sits on the marker exactly as the Blender rig sits on its origin,
-- and every pose turned into bone Transforms once (so blending is a Lerp per bone)
local function build(marker)
	local stages = game:GetService('ReplicatedStorage'):FindFirstChild('MartyStages')
	local tpl = stages and stages:FindFirstChild('PeekRig')
	if not tpl or not tpl.PrimaryPart then return nil end
	local m = tpl:Clone()
	local bones, parts = {}, {}
	for _, d in m:GetDescendants() do
		if d:IsA('Bone') then bones[d.Name] = d
		elseif d:IsA('BasePart') then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; table.insert(parts, d) end
	end
	for _, n in Poses.Order do if not bones[n] then m:Destroy() return nil end end
	-- fit: a frame on hips/head/legs in both spaces gives the turn, the head-hips length gives the scale
	local function frame(lt, head, ll, rl)
		local up = (head - lt).Unit
		local r = rl - ll; r = (r - up * r:Dot(up)).Unit
		return CFrame.fromMatrix(lt, r, up)
	end
	local P = function(n) return bones[n].WorldPosition end
	local Q = function(n) return bvec(Poses.Rest[n]) end
	local s = (P('Head') - P('LowerTorso')).Magnitude / (Q('Head') - Q('LowerTorso')).Magnitude
	local Gp = frame(P('LowerTorso'), P('Head'), P('LeftUpperLeg'), P('RightUpperLeg'))
	local Gq = frame(Q('LowerTorso') * s, Q('Head') * s, Q('LeftUpperLeg') * s, Q('RightUpperLeg') * s)
	local feet = marker.CFrame
	m:PivotTo(feet * Gq * Gp:Inverse() * m:GetPivot())
	local root = m.PrimaryPart
	local rest = {}
	for _, n in Poses.Order do rest[n] = bones[n].WorldCFrame end
	local inv = feet:Inverse()
	local tf = {}
	for name, pose in Poses.Poses do
		local want, t = {}, {}
		for _, n in Poses.Order do
			local d = pose[n]
			local rot = BLEND * CFrame.new(0, 0, 0, d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9]) * BLEND:Inverse()
			local change = feet * (CFrame.new(bvec({d[10], d[11], d[12]}) * s) * rot) * inv
			want[n] = change * rest[n]
			local par = Poses.Parents[n]
			local pw = par and want[par] or root.CFrame
			t[n] = (pw * bones[n].CFrame):Inverse() * want[n]
		end
		tf[name] = t
	end
	-- the grey looks (one SurfaceAppearance per part, swapped in for a few frames)
	local greys, normals = {}, {}
	local gl = m:FindFirstChild('GreyLooks')
	if gl then
		for _, g in gl:GetChildren() do
			local part = m:FindFirstChild(g.Name)
			local sa = part and part:FindFirstChildOfClass('SurfaceAppearance')
			if sa then greys[part] = g; normals[part] = sa end
		end
		gl.Parent = nil
		task.spawn(function() pcall(function() ContentProvider:PreloadAsync(gl:GetChildren()) end) end)
	end
	local clip = m:FindFirstChild('Clipboard'); if clip then clip:Destroy() end
	return {model = m, bones = bones, tf = tf, base = m:GetPivot(), feet = feet, greys = greys, normals = normals, scale = s}
end

local function pose(a, from, to, u)
	local A, B = a.tf[from], a.tf[to]
	for _, n in Poses.Order do a.bones[n].Transform = A[n]:Lerp(B[n], u) end
end

local function place(a, hide) -- hide 0..1: how far he stands back to his left
	local shift = a.feet.RightVector * -(a.hideShift * hide)
	a.model:PivotTo(a.base + shift)
end

local function grey(a, on)
	if a.isGrey == on then return end
	a.isGrey = on
	for part, g in a.greys do
		local n = a.normals[part]
		if on then n.Parent = nil; g.Parent = part else g.Parent = nil; n.Parent = part end
	end
end

local function pointAt(a, which, bone, lift)
	-- a bone's position in a pose, from the pose data (no need to move the model to read it)
	local d = Poses.Poses[which][bone]
	local r = Poses.Rest[bone]
	local rot = Vector3.new(d[1] * r[1] + d[2] * r[2] + d[3] * r[3], d[4] * r[1] + d[5] * r[2] + d[6] * r[3], d[7] * r[1] + d[8] * r[2] + d[9] * r[3])
	local p = rot + Vector3.new(d[10], d[11], d[12]) + Vector3.new(0, 0, lift or 0)
	return a.feet:PointToWorldSpace(bvec({p.X, p.Y, p.Z}) * a.scale)
end

local function stopAudio(a)
	if a.static then
		local s = a.static; a.static = nil
		task.spawn(function()
			local v0 = s.Volume
			for i = 1, 12 do s.Volume = v0 * (1 - i / 12); task.wait(.03) end
			s:Destroy()
		end)
	end
end

local function finish(a)
	grey(a, false)
	stopAudio(a)
	if a.model.Parent then a.model:Destroy() end
	active = nil
end

local function tryPlace(marker, cam, root, char)
	local maxD = marker:GetAttribute('ViewMax') or 42
	local minD = marker:GetAttribute('ViewMin') or 15
	local d = (root.Position - marker.Position).Magnitude
	if d > maxD + 25 or d < minD then return end
	local a = build(marker)
	if not a then return end
	a.hideShift = marker:GetAttribute('HideShift') or 1.2
	pose(a, 'D', 'D', 0); place(a, 1)
	-- only if his hidden head and chest are behind something solid from this camera
	local hHead = a.bones.Head.TransformedWorldCFrame.Position
	local hChest = a.bones.UpperTorso.TransformedWorldCFrame.Position
	for _, p in {hHead, hChest} do
		if sight(cam, p, {char}) then a.model:Destroy() return end
	end
	a.model.Parent = workspace.CurrentCamera -- (local only, never replicated)
	a.marker = marker; a.phase = 'hidden'; a.seenFor = 0; a.peekHead = pointAt(a, 'A', 'Head', .12)
	-- when he leans out, only his head, shoulder and hands may show: his hips and knees must stay behind the wall
	a.mustHide = {pointAt(a, 'A', 'LowerTorso', .05), pointAt(a, 'A', 'RightLowerLeg'), pointAt(a, 'A', 'LeftLowerLeg')}
	done[marker] = true
	active = a
end

local function step(a, cam, root, char, dt, now)
	local marker = a.marker
	local d = (root.Position - marker.Position).Magnitude
	if a.phase == 'hidden' then
		local minD = marker:GetAttribute('ViewMin') or 15
		local maxD = marker:GetAttribute('ViewMax') or 42
		if d < minD * .5 then finish(a) return end -- you got right up to the corner first: he was never seen
		local seeCos = math.cos(math.rad(marker:GetAttribute('SeeDeg') or 22))
		local vis, dot = sight(cam, a.peekHead, {char, a.model})
		local bodyHidden = true
		if vis and dot > seeCos then
			for _, p in a.mustHide do if sight(cam, p, {char, a.model}) then bodyHidden = false break end end
		end
		if d >= minD and d <= maxD and vis and dot > seeCos and bodyHidden then a.seenFor += dt else a.seenFor = math.max(0, a.seenFor - dt) end
		if a.seenFor > .25 then
			a.phase = 'out'; a.t0 = now
			oneShot(STING, .5, .95, 6)
			heartbeat() -- (right on the first sound)
			a.static = newSound(STATIC, 0, 1, true); a.static:Play()
			a.crackle = nil
		end
	elseif a.phase == 'out' then
		local u = smoother((now - a.t0) / OUT_T)
		pose(a, 'D', 'A', u); place(a, 1 - u)
		if a.static then a.static.Volume = .09 * u end
		if u >= 1 then a.phase = 'hold'; a.t0 = now; a.flick = 1 end
	elseif a.phase == 'hold' then
		local t = now - a.t0
		local f = FLICKS[a.flick]
		local on = false
		for _, ft in FLICKS do if t >= ft and t < ft + FLICK_LEN then on = true end end
		if f and t >= f then
			a.flick += 1
			local c = oneShot(CRACKLE, .32, .9 + math.random() * .25, .5)
			pcall(function() c.TimePosition = math.random() * 3.5 end)
			task.delay(.14, function() if c.Parent then for i = 1, 5 do c.Volume *= .55; task.wait(.02) end; c:Stop() end end)
		end
		grey(a, on)
		-- the static swells with each flick and settles back, and wanders a little in pitch (never cut)
		if a.static then
			local want = on and .34 or .09
			a.static.Volume += (want - a.static.Volume) * (1 - math.exp(-dt * (on and 40 or 9)))
			a.static.PlaybackSpeed = .92 + .1 * math.noise(now * 3, 1.7)
		end
		-- while he is out a little twitch in the head on each flick
		if on then a.bones.Head.Transform = a.tf.A.Head * CFrame.Angles(math.rad(math.random(-3, 3)), math.rad(math.random(-4, 4)), 0)
		else a.bones.Head.Transform = a.tf.A.Head end
		if t >= HOLD_T then grey(a, false); a.phase = 'retract'; a.t0 = now; a.seg = 1 end
	elseif a.phase == 'retract' then
		local seg = RETRACT[a.seg]
		local u = math.clamp((now - a.t0) / seg[3], 0, 1)
		local e = seg[2] == 'D' and smoother(u) or u * u * (3 - 2 * u)
		pose(a, seg[1], seg[2], e)
		if seg[2] == 'D' then place(a, e) end
		if a.static then a.static.Volume = .09 * (1 - (a.seg - 1 + u) / #RETRACT) end
		if u >= 1 then
			if a.seg < #RETRACT then a.seg += 1; a.t0 = now
			else a.phase = 'gone'; a.t0 = now; stopAudio(a) end
		end
	elseif a.phase == 'gone' then
		if now - a.t0 >= GONE_T then finish(a) end
	end
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
			if not a.marker.Parent or not a.model.Parent then finish(a) return end
			step(a, cam, root, char, dt, now)
			return
		end
		if player:GetAttribute('EHCinematic') or now < nextScan then return end
		nextScan = now + .15
		local runtime = workspace:FindFirstChild('Runtime')
		if not runtime then return end
		for _, marker in CS:GetTagged('MartyPeek') do
			if marker:IsDescendantOf(runtime) and not done[marker] and conditionMet(marker) then
				tryPlace(marker, cam, root, char)
				if active then break end
			end
		end
	end)
end

return M
