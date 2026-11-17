--!nonstrict
-- (Nov 16) Marty's one rig, shared by every Marty effect (MartyPeek at the Level 5 gate, MartyFlash in the lift).
-- The model is ReplicatedStorage.MartyStages.PeekRig (skinned M4 rig, normal colours, glowing-eye overlay EyeGlow).
-- Poses come from Blender in armature space (Config.MartyPeekPoses format: 9 rotation numbers + 3 for the move, or
-- the compact form {qx,qy,qz,qw, x,y,z}); Build turns every pose into bone Transforms once, so playing them back is
-- a Lerp per bone. Only ever ONE copy of him is built at a time by each effect (never a second Marty).
local RS = game:GetService('ReplicatedStorage')
local Poses = require(RS.Game.Shared.Config.MartyPeekPoses)

local M = {}

-- Blender armature space -> the feet frame (Roblox: X = his right, Y = up, -Z = the way he faces)
local BLEND = CFrame.fromMatrix(Vector3.zero, Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
local function bvec(t) return BLEND:VectorToWorldSpace(Vector3.new(t[1], t[2], t[3])) end
M.BLEND, M.bvec = BLEND, bvec

-- {qx,qy,qz,qw,x,y,z} -> the 12-number form
local function expand(d)
	if #d == 12 then return d end
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = CFrame.new(0, 0, 0, d[1], d[2], d[3], d[4]):GetComponents()
	return {r00, r01, r02, r10, r11, r12, r20, r21, r22, d[5], d[6], d[7]}
end
M.Expand = expand

-- the Blender glitch (Config.MartyGlitch) as pose sets G1..Gn, plus its frame order
function M.GlitchSets()
	local G = require(RS.Game.Shared.Config.MartyGlitch)
	local sets = {}
	for i, p in G.Poses do
		local s = {}
		for _, n in Poses.Order do s[n] = expand(p[n] or {0, 0, 0, 1, 0, 0, 0}) end
		sets['G' .. i] = s
	end
	return sets, G.Order, G.Fps
end

-- builds the rig standing on `feet` (a CFrame at his feet, LookVector = the way he faces), with the given pose sets
function M.Build(feet, sets)
	local stages = RS:FindFirstChild('MartyStages')
	local tpl = stages and stages:FindFirstChild('PeekRig')
	if not tpl or not tpl.PrimaryPart then return nil end
	local m = tpl:Clone()
	local bones = {}
	for _, d in m:GetDescendants() do
		if d:IsA('Bone') then bones[d.Name] = d
		elseif d:IsA('BasePart') then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
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
	m:PivotTo(feet * Gq * Gp:Inverse() * m:GetPivot())
	local root = m.PrimaryPart
	local rest = {}
	for _, n in Poses.Order do rest[n] = bones[n].WorldCFrame end
	local inv = feet:Inverse()
	local tf = {}
	for name, pose in sets or {} do
		local want, t = {}, {}
		for _, n in Poses.Order do
			local d = expand(pose[n] or {0, 0, 0, 1, 0, 0, 0})
			local rot = BLEND * CFrame.new(0, 0, 0, d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8], d[9]) * BLEND:Inverse()
			local change = feet * (CFrame.new(bvec({d[10], d[11], d[12]}) * s) * rot) * inv
			want[n] = change * rest[n]
			local par = Poses.Parents[n]
			local pw = par and want[par] or root.CFrame
			t[n] = (pw * bones[n].CFrame):Inverse() * want[n]
		end
		tf[name] = t
	end
	-- (Nov 16) no grey looks any more: he always keeps his own colours
	local gl = m:FindFirstChild('GreyLooks'); if gl then gl:Destroy() end
	local clip = m:FindFirstChild('Clipboard'); if clip then clip:Destroy() end
	local eyes = m:FindFirstChild('EyeGlow')
	return {model = m, bones = bones, tf = tf, base = m:GetPivot(), feet = feet, scale = s, eyes = eyes}
end

function M.Pose(a, from, to, u)
	local A, B = a.tf[from], a.tf[to]
	for _, n in Poses.Order do a.bones[n].Transform = A[n]:Lerp(B[n], u) end
end

function M.Set(a, name)
	local A = a.tf[name]
	for _, n in Poses.Order do a.bones[n].Transform = A[n] end
end

-- glowing eyes: k = 0 (off) .. 1 (full)
function M.Eyes(a, k)
	local e = a.eyes; if not e then return end
	local t = 1 - math.clamp(k, 0, 1)
	if e.Transparency ~= t then e.Transparency = t end
	local light = e:FindFirstChild('Glow')
	if light then light.Enabled = k > .05; light.Brightness = 1.4 * k end
end

return M
