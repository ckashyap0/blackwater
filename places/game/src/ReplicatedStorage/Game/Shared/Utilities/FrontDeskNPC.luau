--!nonstrict
-- FrontDeskNPC v7 (Nov 3): the gatehouse attendant ("FrontDeskNPC" tag). See the vault note "NPC - Front Desk Guy".
-- Rig (BW_FrontDeskGuy2.fbx): Root / Chest / Neck / Head and, on each side, upperarm_ lowerarm_ hand_ and
-- <finger>_01_ / <finger>_02_ for index, middle, ring, pinky, thumb (bones keep Blender's local axes: X = curl).
-- His rest pose has the fingertips resting on the keys and his head looking at the CRT screen.
--
--  TYPING (v7): word by word - 2-8 letters at uneven 0.09-0.2 s intervals, hands mostly alternating, the right
--    thumb on the space bar between words, a stop every few words, the odd backspace. Each keystroke is struck at the
--    base knuckle with the end joints easing straight (~4 mm of key travel), neighbouring fingers move along a
--    little and the hand dips slightly on each strike; the click plays when the key bottoms out
--    (model attribute KeySoundIds = "id,id,...").
--  READING: every 8-13 s he looks down at the visitor log lying on the desk to his right ("Prop_DocPaper") for
--    1-2 s while he keeps typing more slowly, then looks back at the screen ("Prop_CRT_Screen", wherever it sits).
--  ATTEND: while any player holds CHECK IN (their EHActiveInteraction == "StallCheckIn"), or for 2.5 s after it
--    ends, he stops typing (fingers stay on the keys), looks straight at that player and nods once.
--  TALK (v6): during the check-in conversation (Utilities.CheckInTalk) he looks at whoever is watching - on each
--    screen he looks at THAT player - and his head moves gently while his lines type out.
--  HANDS (v6): while typing, both hands slide across the keyboard a key or two at a time (the whole arm turns about
--    the shoulder around the vertical axis, so the fingertips stay at key height).
--  Players walking past do NOT distract him.
-- Aiming is done in world space: the rotation that turns his rest gaze (head -> CRT screen) onto the target is split
-- 40% neck / 60% head and converted into each bone's local Transform, so he looks exactly at you whatever the bone
-- axes are. Every channel runs through a critically damped spring, so nothing ever snaps.
local RunService = game:GetService('RunService')
local CS = game:GetService('CollectionService')
local Players = game:GetService('Players')

local M = {}
local started = false
local LIMIT_YAW, PDOWN, PUP = math.rad(80), math.rad(40), math.rad(35)
local CURL = 1
local TAP = .24
local KEY_YAW = math.rad(2.6)
local okTalk, Talk = pcall(require, script.Parent:WaitForChild('CheckInTalk', 5))
if not okTalk then Talk = nil end
local state = {}
CS:GetInstanceRemovedSignal('FrontDeskNPC'):Connect(function(m) state[m] = nil end)

local function spring(x, v, target, w, dt)
	local d = x - target
	local e = math.exp(-w * dt)
	return target + (d + (v + w * d) * dt) * e, (v - (v + w * d) * w * dt) * e
end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function yawOf(v) return math.atan2(-v.X, -v.Z) end
local function elevOf(v) return math.atan2(v.Y, math.sqrt(v.X * v.X + v.Z * v.Z)) end
-- One keystroke (v7, from keystroke kinematics studies): the strike is made at the base knuckle (MCP) while the
-- end joints straighten a little under load; the key travels ~4 mm; contact is short. Profile over TAP seconds:
--   0 - .18  a small lift off the key        .18 - .40  the strike (fast, eases in)
--   .40 - .60 bottomed out (the click)       .60 - 1    back up to resting on the key (eases out)
local LIFT, PRESS = math.rad(6), math.rad(3.5)   -- (Nov 5: bigger lift so the fingers visibly rise and fall, like the reference clips)
local function ease(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
local function keystroke(e)
	local a
	if e < .18 then a = -LIFT * ease(e / .18)
	elseif e < .40 then local u = (e - .18) / .22; a = -LIFT + (LIFT + PRESS) * u * u
	elseif e < .60 then a = PRESS
	else a = PRESS * (1 - ease((e - .60) / .40)) end
	return a, (a > 0) and -.35 * a or .5 * a
end
local HAND = {
	l = {{'index', .38}, {'middle', .30}, {'ring', .20}, {'pinky', .12}},
	r = {{'index', .38}, {'middle', .30}, {'ring', .20}, {'pinky', .12}},
}
local NEIGHBOURS = {index = {'middle'}, middle = {'index', 'ring'}, ring = {'middle', 'pinky'}, pinky = {'ring'}, thumb = {}}
local COUPLE = .3

-- RESTING HANDS (Nov 5, from the reference image): fingers close together and gently curved down onto the keys,
-- knuckles the highest point. Worked out once at startup on top of the baked pose: the wrist lifts HAND_X, each
-- finger's end joint curls CURL2 degrees, its base joint is aimed FAN degrees off the hand's forward line (toward the
-- thumb is +), and its down angle is solved so the fingertip rests TIP_CLEAR studs above the key under it.
-- (Nov 5 b) straighter: a big curl and fully re-aimed base joints crushed and twisted the knuckles, so the end joints
-- curl only a little and the base joints turn only YAW_BLEND of the way toward the FAN line (less twist).
-- (R43b, Hale v6) the end joint now bends in WORLD space, about the horizontal axis across the finger, so CURL2 is
-- the real knuckle angle. The v6 rig's bone X axes are skewed, so a local X curl of 40 gave only 6-20 degrees and a
-- twist. With the world bend the fingers arch (knuckles highest, tips down on the keys) like the owner's reference.
local POSE = {
	HAND_X = 10,
	FAN = {index = 3, middle = 0, ring = -2, pinky = -4},
	YAW_BLEND = .8,
	CURL2 = {index = 38, middle = 40, ring = 38, pinky = 32},
	TIP_CLEAR = .045,     -- (Nov 5 e) more room so a keystroke never pushes a fingertip into the keyboard
	TIP_LEN = 1.6,        -- (Nov 5 c) end segment + fingertip, as a multiple of the base segment (1.15 put the tips in the keys)
	THUMB_LEN = 1.3,      -- (Nov 5 d) the thumb's base (metacarpal) is left alone; only its knuckle bends, bringing the
	THUMB_OUT = 38,       -- (Nov 5 f) how far out to the side the thumb rests
	THUMB_FWD = .9,       --   thumb out from under the palm toward the space bar (THUMB_FWD of the way to the hand's
	THUMB_DROP = 14,      --   forward line) and down until its tip rests on the keys. One plain rotation, no roll.
	THUMB_MAXDOWN = 30,   -- the base knuckle tips down THUMB_DROP deg so the thumb can lie flatter (at most MAXDOWN deg)
}
M.Pose = POSE

-- base local Transform for every posed bone: {boneName = CFrame}. Call with every bone's Transform at identity.
function M.SolvePose(m, scope)
	local B = {}
	for _, b in m:GetDescendants() do if b:IsA('Bone') then B[b.Name] = b end end
	local base = {}
	local kb = scope and scope:FindFirstChild('Prop_KB_Keys', true)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = {kb and kb.Parent or scope}
	for _, side in {'l', 'r'} do
		local hand = B['hand_' .. side]; local i1 = B['index_01_' .. side]; local p1 = B['pinky_01_' .. side]
		if not (hand and i1 and p1) then continue end
		base[hand.Name] = CFrame.Angles(math.rad(POSE.HAND_X), 0, 0); hand.Transform = base[hand.Name]
		local fallbackY = i1.WorldPosition.Y - .13
		local fwd = hand.WorldCFrame.UpVector; fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
		local ts = i1.WorldPosition - p1.WorldPosition; ts = ts - fwd * ts:Dot(fwd); ts = Vector3.new(ts.X, 0, ts.Z).Unit
		-- thumb: one bend at the knuckle (its own curl axis), solved so the tip rests on the keyboard
		local t1 = B['thumb_01_' .. side]; local t2 = B['thumb_02_' .. side]
		if t1 and t2 then
			t1.Transform = CFrame.identity; t2.Transform = CFrame.identity
			local L = (t2.WorldPosition - t1.WorldPosition).Magnitude * POSE.THUMB_LEN
			do -- base knuckle: tip it straight down (about the horizontal axis across it - no roll)
				local R = t1.WorldCFrame.Rotation; local d = R.UpVector
				local across = d:Cross(Vector3.yAxis)
				if across.Magnitude > 1e-4 then
					local Dw = CFrame.fromAxisAngle(across.Unit, -math.rad(POSE.THUMB_DROP))
					if (Dw * d).Y > d.Y then Dw = Dw:Inverse() end
					t1.Transform = R:Inverse() * Dw * R
				end
			end
			local own = t2.WorldCFrame.UpVector; own = Vector3.new(own.X, 0, own.Z).Unit
			-- (Nov 5 f) out from under the palm: forward and THUMB_OUT degrees out to the thumb side (toward the middle of
			-- the keyboard), lying fairly flat on the keys
			local out = (fwd * math.cos(math.rad(POSE.THUMB_OUT)) + ts * math.sin(math.rad(POSE.THUMB_OUT))).Unit
			local dirH = own:Lerp(out, POSE.THUMB_FWD).Unit
			local function tipAt(p)
				local d = dirH * math.cos(p) - Vector3.yAxis * math.sin(p)
				t2.Transform = CFrame.identity
				local R = t2.WorldCFrame.Rotation; local cur = R.UpVector
				local ax = cur:Cross(d); local ang = math.asin(math.clamp(ax.Magnitude, 0, 1)); if cur:Dot(d) < 0 then ang = math.pi - ang end
				t2.Transform = ax.Magnitude > 1e-6 and (R:Inverse() * CFrame.fromAxisAngle(ax.Unit, ang) * R) or CFrame.identity
				local w = t2.TransformedWorldCFrame   -- (WorldCFrame leaves out the bone's own Transform)
				return w.Position + w.UpVector * L
			end
			local lo, hi = math.rad(-10), math.rad(POSE.THUMB_MAXDOWN)
			for _ = 1, 22 do
				local mid = (lo + hi) / 2; local tip = tipAt(mid)
				local hit = workspace:Raycast(tip + Vector3.new(0, 1, 0), Vector3.new(0, -2, 0), rp)
				if tip.Y > (hit and hit.Position.Y or fallbackY) + POSE.TIP_CLEAR then lo = mid else hi = mid end
			end
			tipAt((lo + hi) / 2)
			base[t1.Name] = t1.Transform; base[t2.Name] = t2.Transform
		end
		for f, fan in POSE.FAN do
			local b1 = B[f .. '_01_' .. side]; local b2 = B[f .. '_02_' .. side]
			if not (b1 and b2) then continue end
			b1.Transform = CFrame.identity; b2.Transform = CFrame.identity
			local L2 = (b2.TransformedWorldCFrame.Position - b1.TransformedWorldCFrame.Position).Magnitude * POSE.TIP_LEN
			local own = b1.TransformedWorldCFrame.UpVector; own = Vector3.new(own.X, 0, own.Z).Unit   -- where it points now
			local fanDir = (fwd * math.cos(math.rad(fan)) + ts * math.sin(math.rad(fan))).Unit
			local dirH = own:Lerp(fanDir, POSE.YAW_BLEND).Unit
			local curl = math.rad(POSE.CURL2[f])
			-- turn a bone (with everything above it already posed) so its long axis points along world direction d
			local function rotTo(bone, d)
				bone.Transform = CFrame.identity
				local R = bone.TransformedWorldCFrame.Rotation; local cur = R.UpVector
				local ax = cur:Cross(d); local ang = math.asin(math.clamp(ax.Magnitude, 0, 1)); if cur:Dot(d) < 0 then ang = math.pi - ang end
				bone.Transform = ax.Magnitude > 1e-6 and (R:Inverse() * CFrame.fromAxisAngle(ax.Unit, ang) * R) or CFrame.identity
			end
			local function apply(p)
				rotTo(b1, dirH * math.cos(p) - Vector3.yAxis * math.sin(p))
				local q = p + curl
				rotTo(b2, dirH * math.cos(q) - Vector3.yAxis * math.sin(q))
				local w = b2.TransformedWorldCFrame
				return w.Position + w.UpVector * L2
			end
			local lo, hi = math.rad(-30), math.rad(55)
			for _ = 1, 22 do
				local mid = (lo + hi) / 2; local tip = apply(mid)
				local hit = workspace:Raycast(tip + Vector3.new(0, 1, 0), Vector3.new(0, -2, 0), rp)
				if tip.Y > (hit and hit.Position.Y or fallbackY) + POSE.TIP_CLEAR then lo = mid else hi = mid end
			end
			apply((lo + hi) / 2)
			base[b1.Name] = b1.Transform; base[b2.Name] = b2.Transform
		end
	end
	return base
end
local function pickFinger(side)
	local r, acc = math.random(), 0
	for _, e in HAND[side] do acc += e[2]; if r <= acc then return e[1] end end
	return 'index'
end

local function find(root, name) return root and root:FindFirstChild(name, true) end
local function partPos(p) if p and p:IsA('BasePart') then return p.Position end end

local function setup(m, t)
	local head = find(m, 'Head'); local neck = find(m, 'Neck'); local chest = find(m, 'Chest')
	if not (head and neck and chest) then return nil end
	local s = {chest = chest, neck = neck, head = head, bones = {},
		yaw = 0, yv = 0, pitch = 0, pv = 0, nod = 0, nv = 0, rate = 1, ratev = 0,
		inBurst = true, nextPress = t + .5, presses = {}, busy = {}, word = 0, words = 0, lastSide = 'l', dip = {l = 0, r = 0},
		nextGlance = t + 6 + math.random() * 5, glanceEnd = 0, phase = math.random() * 10,
		slide = {l = 0, r = 0, lv = 0, rv = 0, lt = 0, rt = 0, next = t + 1.5}, talkAmp = 0, talkAmpV = 0}
	for _, b in m:GetDescendants() do if b:IsA('Bone') then s.bones[b.Name] = b; b.Transform = CFrame.identity end end
	s.Rc0 = chest.WorldCFrame.Rotation; s.Rn0 = neck.WorldCFrame.Rotation; s.Rh0 = head.WorldCFrame.Rotation
	s.headPos = head.WorldPosition
	s.base = M.SolvePose(m, m.Parent or m)
	-- (Nov 5 d) the thumb presses the space bar by bending straight down at its knuckle (its own X axis swings it sideways)
	s.thumbAx = {}
	for _, side in {'l', 'r'} do
		local t2 = s.bones['thumb_02_' .. side]
		if t2 then
			local w = t2.TransformedWorldCFrame; local d = w.UpVector
			local ax = Vector3.yAxis:Cross(d)
			if ax.Magnitude > 1e-4 then s.thumbAx[side] = w.Rotation:VectorToObjectSpace(ax.Unit) end
		end
	end
	s.arms = {}
	for _, side in {'l', 'r'} do
		local u = s.bones['upperarm_' .. side]
		if u then table.insert(s.arms, {bone = u, side = side, R0 = u.WorldCFrame.Rotation}) end
	end
	local scope = m.Parent or m
	local screen = partPos(find(scope, 'Prop_CRT_Screen'))
	local g0 = screen and (screen - s.headPos) or (head.WorldCFrame.LookVector - Vector3.new(0, .3, 0))
	s.g0 = g0.Unit
	local g0h = Vector3.new(s.g0.X, 0, s.g0.Z).Unit
	s.pitchAxis = g0h:Cross(Vector3.yAxis).Unit
	s.paper = find(scope, 'Prop_DocPaper')
	local kb = find(scope, 'Prop_KB_Keys')
	local ids = string.split(m:GetAttribute('KeySoundIds') or '', ',')
	s.sounds = {}
	if kb then
		for i, id in ids do
			if id ~= '' then
				local snd = Instance.new('Sound'); snd.Name = 'KeyClick' .. i; snd.SoundId = 'rbxassetid://' .. string.gsub(id, '%D', '')
				snd.Volume = .55; snd.RollOffMode = Enum.RollOffMode.InverseTapered; snd.RollOffMinDistance = 4; snd.RollOffMaxDistance = 40
				snd.Parent = kb; table.insert(s.sounds, snd)
			end
		end
	end
	return s
end

local function click(s)
	local n = #s.sounds; if n == 0 then return end
	local snd = s.sounds[math.random(1, n)]
	snd.PlaybackSpeed = .9 + math.random() * .25
	snd.TimePosition = 0; snd:Play()
end

local function attendTarget()
	for _, p in Players:GetPlayers() do
		if p:GetAttribute('EHActiveInteraction') == 'StallCheckIn' then
			local h = p.Character and p.Character:FindFirstChild('Head')
			if h then return p, h.Position end
		end
	end
end

local function toLocal(R, D) return R:Inverse() * D * R end

local function step(dt)
	dt = math.min(dt, 1 / 20)
	local cam = workspace.CurrentCamera; if not cam then return end
	local cp = cam.CFrame.Position; local t = os.clock()
	for _, m in CS:GetTagged('FrontDeskNPC') do
		if not m:IsDescendantOf(workspace) then state[m] = nil continue end
		local s = state[m] or setup(m, t); state[m] = s
		if not s then continue end
		if (s.headPos - cp).Magnitude > 160 then continue end
		local tt = t + s.phase

		local who, target = attendTarget()
		if who then
			if s.attendFor ~= who then s.attendFor = who; s.attendStart = t end
			if who == Players.LocalPlayer then target = cp end
			s.lastAttend = t
		elseif s.attendFor and s.lastAttend and t - s.lastAttend < 2.5 and s.attendFor.Character and s.attendFor.Character:FindFirstChild('Head') then
			target = (s.attendFor == Players.LocalPlayer) and cp or s.attendFor.Character.Head.Position
		else
			s.attendFor = nil
		end
		local talk = Talk and Talk.State(m)
		local busyTyping = talk and talk.typing   -- (Nov 4) "let me add you to our system": back to the screen, typing fast
		if busyTyping then
			target = nil; s.attendFor = nil; s.lastAttend = nil
		elseif talk then
			target = cp
			if s.talkStart == nil then s.talkStart = t - talk.t; s.attendStart = s.talkStart end
		else
			s.talkStart = nil
		end
		local attending = target ~= nil
		local glancing = false
		if not attending then
			if t >= s.nextGlance and s.paper and not busyTyping then
				s.glanceEnd = t + 1.1 + math.random() * .9
				s.nextGlance = s.glanceEnd + 7 + math.random() * 5
			end
			if t < s.glanceEnd and s.paper then glancing = true; target = s.paper.Position end
		else
			s.glanceEnd = 0
		end

		local ty, tp = 0, 0
		if target then
			local g1 = (target - s.headPos)
			ty = math.clamp(wrap(yawOf(g1) - yawOf(s.g0)), -LIMIT_YAW, LIMIT_YAW)
			tp = math.clamp(elevOf(g1) - elevOf(s.g0), -PDOWN, PUP)
			if glancing then ty, tp = ty * .85, math.max(tp - math.rad(14), -PDOWN) end
		else
			ty = math.rad(1.5) * math.noise(tt * .08, 1.7); tp = math.rad(1) * math.noise(tt * .1, 4.1)
		end
		local w = attending and 2.6 or (glancing and 4.2 or 3.0)
		s.yaw, s.yv = spring(s.yaw, s.yv, ty, w, dt)
		s.pitch, s.pv = spring(s.pitch, s.pv, tp, w, dt)
		local nodT = 0
		if attending and s.attendStart then
			local e = (t - s.attendStart - .7) / 1.1
			if e > 0 and e < 1 then nodT = math.sin(e * math.pi) end
		end
		s.nod, s.nv = spring(s.nod, s.nv, math.rad(9) * nodT, 10, dt)
		s.talkAmp, s.talkAmpV = spring(s.talkAmp, s.talkAmpV, (talk and talk.speaking) and 1 or 0, 6, dt)
		local talkPitch = s.talkAmp * (math.rad(1.6) * math.sin(tt * 7.1) * (.6 + .4 * math.noise(tt * 1.3, 2.2)))
		local talkYaw = s.talkAmp * math.rad(1.2) * math.noise(tt * 1.7, 5.5)

		local br = math.sin(tt * 2 * math.pi / 4.8)
		local Tc = CFrame.Angles(math.rad(.3) * br, 0, 0)
		s.chest.Transform = Tc
		local Cw = s.Rc0 * Tc * s.Rc0:Inverse()
		local sl = s.slide
		if not attending and s.inBurst and t >= sl.next then
			local side = math.random() < .5 and 'l' or 'r'
			sl[side .. 't'] = math.clamp(sl[side .. 't'] + (math.random(0, 1) * 2 - 1) * KEY_YAW, -KEY_YAW, KEY_YAW)
			sl.next = t + 1.1 + math.random() * 1.9
		end
		for _, side in {'l', 'r'} do
			sl[side], sl[side .. 'v'] = spring(sl[side], sl[side .. 'v'], attending and 0 or sl[side .. 't'], 5.5, dt)
		end
		for _, a in s.arms do
			local Y = CFrame.fromAxisAngle(Vector3.yAxis, sl[a.side])
			a.bone.Transform = toLocal(a.R0, Y * Cw:Inverse())
		end

		local up = Vector3.yAxis
		local D = CFrame.fromAxisAngle(up, s.yaw) * CFrame.fromAxisAngle(s.pitchAxis, s.pitch)
		local Dn = CFrame.fromAxisAngle(up, s.yaw * .4) * CFrame.fromAxisAngle(s.pitchAxis, s.pitch * .4)
		local Dfull = CFrame.fromAxisAngle(up, s.yaw + talkYaw) * CFrame.fromAxisAngle(s.pitchAxis, s.pitch - s.nod + talkPitch)
		local roll = CFrame.fromAxisAngle(D * s.g0, math.rad(1) * math.noise(tt * .06, 7.3))
		local Rn = Cw * s.Rn0
		s.neck.Transform = toLocal(Rn, Dn)
		local Dh = roll * Dfull * Dn:Inverse()
		s.head.Transform = toLocal(Dn * Cw * s.Rh0, Dh)

		s.rate, s.ratev = spring(s.rate, s.ratev, attending and 0 or (busyTyping and 1.7 or (glancing and .45 or 1)), 5, dt)
		if not attending and t >= s.nextPress and s.rate > .2 then
			local f, side, gap
			if s.word > 0 then
				side = (math.random() < .58) and (s.lastSide == 'l' and 'r' or 'l') or s.lastSide
				f = pickFinger(side); s.word -= 1
				gap = .09 + math.random() * .11
			elseif s.word == 0 then
				f, side = 'thumb', 'r'
				s.words += 1; s.word = -1
				gap = .18 + math.random() * .17
			else
				s.word = math.random(2, 8)
				if s.words >= (s.stopAfter or 4) then
					s.words = 0; s.stopAfter = 3 + math.random(0, 3); s.inBurst = false
					s.nextPress = t + .6 + math.random() * 1.1
				elseif math.random() < .08 then
					f, side = 'pinky', 'r'; gap = .3 + math.random() * .2
				else
					s.nextPress = t
				end
			end
			if f then
				s.inBurst = true
				local bone = f .. '_01_' .. side
				if not s.busy[bone] then
					s.busy[bone] = true; s.lastSide = side
					table.insert(s.presses, {bone = bone, f = f, side = side, start = t, clicked = false})
				end
				s.nextPress = t + gap / math.max(s.rate, .2)
			end
		end
		local mcp, pip, dip = {}, {}, {l = 0, r = 0}
		for i = #s.presses, 1, -1 do
			local p = s.presses[i]; local e = (t - p.start) / TAP
			if e >= .40 and not p.clicked then p.clicked = true; click(s) end
			if e >= 1 then table.remove(s.presses, i); s.busy[p.bone] = nil
			else
				local a, b = keystroke(e)
				local k = (p.f == 'thumb') and .7 or 1
				local key = p.f .. '_' .. p.side
				mcp[key] = (mcp[key] or 0) + a * k; pip[key] = (pip[key] or 0) + b * k
				for _, n in NEIGHBOURS[p.f] do local nk = n .. '_' .. p.side; mcp[nk] = (mcp[nk] or 0) + a * COUPLE; pip[nk] = (pip[nk] or 0) + b * COUPLE end
				if a > 0 then dip[p.side] = math.max(dip[p.side], a / PRESS) end
			end
		end
		for _, side in {'l', 'r'} do
			s.dip[side .. 'v'] = s.dip[side .. 'v'] or 0
			s.dip[side], s.dip[side .. 'v'] = spring(s.dip[side], s.dip[side .. 'v'], dip[side], 22, dt)
			local hand = s.bones['hand_' .. side]; local fore = s.bones['lowerarm_' .. side]
			if fore then fore.Transform = CFrame.identity end
			local sn = side == 'l' and 1 or 2
			if hand then
				-- resting pose, a slow drift of the wrist (Nov 5: so the hands never look frozen) and the dip on each strike
				local drift = math.rad(1.1) * math.noise(tt * .45, sn) + CURL * math.rad(1) * s.dip[side]
				local sway = math.rad(.9) * math.noise(tt * .35, sn + 10)
				hand.Transform = (s.base[hand.Name] or CFrame.identity) * CFrame.Angles(drift, 0, sway)
			end
			for fi, f in {'index', 'middle', 'ring', 'pinky', 'thumb'} do
				local b1 = s.bones[f .. '_01_' .. side]; local b2 = s.bones[f .. '_02_' .. side]
				local key = f .. '_' .. side
				local idle = math.rad(1.2) * math.noise(tt * .6, fi * 3.1, sn)   -- small resting finger movement
				if f == 'thumb' and s.thumbAx[side] then
					if b1 then b1.Transform = s.base[b1.Name] or CFrame.identity end
					if b2 then b2.Transform = (s.base[b2.Name] or CFrame.identity) * CFrame.fromAxisAngle(s.thumbAx[side], (mcp[key] or 0) + idle * .5) end
				else
					if b1 then b1.Transform = (s.base[b1.Name] or CFrame.identity) * CFrame.Angles(CURL * ((mcp[key] or 0) + idle), 0, 0) end
					if b2 then b2.Transform = (s.base[b2.Name] or CFrame.identity) * CFrame.Angles(CURL * ((pip[key] or 0) + idle * .6), 0, 0) end
				end
			end
		end
	end
end

function M.Start()
	if started then return end
	started = true
	RunService:BindToRenderStep('FrontDeskNPC', Enum.RenderPriority.Camera.Value + 2, step)
end
return M
