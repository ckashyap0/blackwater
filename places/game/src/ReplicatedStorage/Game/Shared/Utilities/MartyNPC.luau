--!nonstrict
-- R34 (Nov 9), R35: Marty just inside the works gate ("MartyNPC" tag; R35 model is M1 from the vault,
-- Assets/Models/BW_Marty.fbx: six skinned parts on one R15 bone rig). Runs on each client, like FrontDeskNPC.
--  IDLE: plays the Idle clip that came with the model (Anim_Idle, a KeyframeSequence inside the model) by sampling
--    its poses straight onto the bones. No uploaded animation asset is needed, so it behaves the same in Studio
--    and in the live game.
--  TALK: while THIS player talks to him (Utilities.MartyTalk) he turns to face them, and his head moves a
--    little while his lines type out. Each screen turns him to its own player only. When the talk ends he turns
--    back to where he stood.
-- Normal form only (stage 1). He never moves off the square.
local RunService = game:GetService('RunService')
local CS = game:GetService('CollectionService')
local Players = game:GetService('Players')

local M = {}
local started = false
local okTalk, Talk = pcall(require, script.Parent:WaitForChild('MartyTalk', 5))
if not okTalk then Talk = nil end
local state = {}
CS:GetInstanceRemovedSignal('MartyNPC'):Connect(function(m) state[m] = nil end)

local function spring(x, v, target, w, dt)
	local d = x - target
	local e = math.exp(-w * dt)
	return target + (d + (v + w * d) * dt) * e, (v - (v + w * d) * w * dt) * e
end
local function wrap(a) return (a + math.pi) % (2 * math.pi) - math.pi end
local function yawOf(v) return math.atan2(-v.X, -v.Z) end

-- one clip as per-bone tracks: tracks[boneName] = {{time, cframe}, ...} in time order
local function readClip(ks)
	local tracks, length = {}, 0
	if not (ks and ks:IsA('KeyframeSequence')) then return tracks, 0 end
	for _, kf in ks:GetChildren() do
		if kf:IsA('Keyframe') then
			length = math.max(length, kf.Time)
			local function walk(pose)
				for _, p in pose:GetChildren() do
					if p:IsA('Pose') then
						local tr = tracks[p.Name]
						if not tr then tr = {}; tracks[p.Name] = tr end
						table.insert(tr, {kf.Time, p.CFrame})
						walk(p)
					end
				end
			end
			walk(kf)
		end
	end
	for _, tr in tracks do table.sort(tr, function(a, b) return a[1] < b[1] end) end
	-- (R35) a clip exported with its own rig stores poses against that rig's rest (M1's Idle: 90 degrees on
	-- the root, 180 on the limbs). Model attribute AnimRelativeToFirstFrame plays the motion relative to the
	-- clip's first frame instead, which is his standing rest pose.
	if ks.Parent and ks.Parent:GetAttribute('AnimRelativeToFirstFrame') then
		for _, tr in tracks do
			local inv = tr[1][2]:Inverse()
			for _, k in tr do k[2] = inv * k[2] end
		end
	end
	return tracks, length
end
local function sample(tr, t)
	local n = #tr
	if n == 0 then return CFrame.identity end
	if t <= tr[1][1] then return tr[1][2] end
	for i = 2, n do
		local b = tr[i]
		if t <= b[1] then
			local a = tr[i - 1]
			return a[2]:Lerp(b[2], (t - a[1]) / math.max(1e-4, b[1] - a[1]))
		end
	end
	return tr[n][2]
end

local function setup(model)
	local mesh = model.PrimaryPart or model:FindFirstChildWhichIsA('MeshPart')
	if not mesh then return nil end
	local bones = {}
	for _, d in mesh:GetDescendants() do if d:IsA('Bone') then bones[d.Name] = d end end
	local tracks, length = readClip(model:FindFirstChild('Anim_Idle'))
	-- (R35) M1 is several skinned parts on one rig: turn the whole model about its root, not one part
	local base = mesh.CFrame
	local yaw = yawOf(base.LookVector)
	local upright = CFrame.new(base.Position) * CFrame.Angles(0, yaw, 0)
	return {model = model, mesh = mesh, bones = bones, tracks = tracks, length = length, base = base,
		offset = upright:ToObjectSpace(model:GetPivot()), lastYaw = yaw,
		baseYaw = yaw, yaw = yaw, vyaw = 0, t0 = math.random() * 3, holdUntil = 0, nod = 0, vnod = 0}
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	RunService.RenderStepped:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local cam = workspace.CurrentCamera
		for _, model in CS:GetTagged('MartyNPC') do
			if not model:IsDescendantOf(workspace) then continue end
			local s = state[model]
			if s == nil then s = setup(model) or false; state[model] = s end
			if not s or not s.mesh.Parent then continue end
			if cam and (cam.CFrame.Position - s.mesh.Position).Magnitude > 160 then continue end
			local talk = Talk and Talk.State()
			local now = os.clock()
			-- face whoever on this screen is talking to him, then back to his place
			local targetYaw = s.baseYaw
			local root = player.Character and player.Character:FindFirstChild('HumanoidRootPart')
			if talk and root then s.holdUntil = now + 1.5 end
			if root and now < s.holdUntil then
				local d = root.Position - s.mesh.Position
				if Vector3.new(d.X, 0, d.Z).Magnitude > .5 then targetYaw = yawOf(Vector3.new(d.X, 0, d.Z)) end
			end
			s.yaw, s.vyaw = spring(s.yaw, s.vyaw, s.yaw + wrap(targetYaw - s.yaw), 5, dt)
			s.yaw = wrap(s.yaw)
			if math.abs(wrap(s.yaw - s.lastYaw)) > 1e-4 then
				s.lastYaw = s.yaw
				s.model:PivotTo(CFrame.new(s.base.Position) * CFrame.Angles(0, s.yaw, 0) * s.offset)
			end
			-- idle clip on the bones
			if s.length > 0 then
				local t = (now + s.t0) % s.length
				for name, tr in s.tracks do
					local b = s.bones[name]
					if b then b.Transform = sample(tr, t) end
				end
			end
			-- a small, slow head movement while he speaks
			s.nod, s.vnod = spring(s.nod, s.vnod, (talk and talk.speaking) and 1 or 0, 6, dt)
			local head = s.bones.Head
			if head and s.nod > .001 then
				local a = math.rad(2) * s.nod
				head.Transform = head.Transform * CFrame.Angles(a * math.sin(now * 3.1), a * .7 * math.sin(now * 1.7), 0)
			end
		end
	end)
end

return M
