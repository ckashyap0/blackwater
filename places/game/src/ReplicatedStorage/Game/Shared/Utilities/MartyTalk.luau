--!nonstrict
-- R34 (Nov 9), R35: talking to Marty just inside the works gate (GatePlaza spot, his first appearance). Same look and timing as the check-in
-- talk with Hale (Utilities.CheckInTalk): the authored StarterGui.MartyTalk panel is a copy of CheckInTalk, with the
-- speaker's portrait on the left (your Roblox headshot / a still view of Marty's face in Portrait.NpcView), the
-- name over the line and the line typing out.
-- Unlike Hale's talk this one is per player: whoever holds TALK on Marty gets the conversation on their own screen.
-- The server (ElevatorService:_OnMartyTalk) sets two attributes on that player (R36: per spot):
--   EHMartyTalkAt  = server time the talk starts
--   EHMartyTalkSet = spot + 1 for the first talk there, spot + 2 after that (Gate1, Gate2, L51, L52)
-- MartyNPC reads M.State() to turn Marty towards that player while they talk.
-- R34 scope: Marty is in his normal form. He is friendly and he does not catch or chase anyone.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}
-- (R36) one set per spot and talk: <TalkSets attribute on the Marty model><1 first talk | 2 any later talk>.
-- (R37) The yard Marty moves ahead of the crew unseen: Gate (inside the works gate) -> Shaft (outside the shaft
-- hall doors) -> Lift (beside the lift doors). L5 = beside the service panel on Level 5 (he got there first).
-- Warm and helpful, in the same easy voice as Hale; only small things are off.
M.Sets = {
	Gate1 = {
		{who = 'him', text = "There you are! You must be the new hire. Martin Voss, maintenance. Everyone calls me Marty."},
		{who = 'you', text = "Hi, I'm {name}. Nice to meet you."},
		{who = 'him', text = "Good to have you, {name}. Follow the road up to the shaft hall. The lift's inside."},
		{who = 'him', text = "Go on ahead. I'll catch up with you."},
	},
	Gate2 = {
		{who = 'him', text = "Don't mind the smell. After a while you stop noticing it."},
	},
	Shaft1 = {
		{who = 'him', text = "Oh, there you are. Mind your step in there, the floor's always slick."},
		{who = 'you', text = "How did you get here so fast?"},
		{who = 'him', text = "Shortcut round the back. You learn them all after a while."},
	},
	Shaft2 = {
		{who = 'him', text = "Lift's at the far end. Go on."},
	},
	Lift1 = {
		{who = 'him', text = "Here she is. Old, but she still runs."},
		{who = 'him', text = "Take her down. I'll meet you on Level Five."},
	},
	Lift2 = {
		{who = 'him', text = "Level Five. I'll be there."},
	},
	L51 = {
		{who = 'him', text = "Oh, hello there! Made it down alright?"},
		{who = 'you', text = "Yeah. That lift is something."},
		{who = 'him', text = "Isn't it? She groans, but she's never dropped anyone. Not yet, anyway."},
		{who = 'him', text = "Everything okay? You look a little pale."},
		{who = 'you', text = "I'm fine. What do we do first?"},
		{who = 'him', text = "Start with the leaking pipe down the hall. Close the valve before the pressure climbs."},
	},
	L52 = {
		{who = 'him', text = "Everything alright? Holler if you need me."},
	},
}
M.Speakers = {him = 'Marty', you = '{name}'}
M.CharsPerSecond = 32
M.NameChars = 10
M.Hold = 1.1
M.PerChar = .025
M.Lead = .3
M.FadeIn, M.FadeOut = .25, .5
M.Gap = .2

-- line timings per set (seconds after EHMartyTalkAt): {shown, start, typed, finish}
M.Timelines, M.Durations = {}, {}
for set, lines in M.Sets do
	local timeline, t = {}, M.Lead
	for i, l in lines do
		local n = #(string.gsub(l.text, '{name}', string.rep('x', M.NameChars)))
		local typing = n / M.CharsPerSecond
		local start = t + M.FadeIn * .6
		local finish = start + typing + M.Hold + n * M.PerChar + M.FadeOut
		timeline[i] = {shown = t, start = start, typed = start + typing, finish = finish}
		t = finish + M.Gap
	end
	M.Timelines[set], M.Durations[set] = timeline, t
end

function M.Duration(set) return M.Durations[set] or 0 end

function M.LineAt(set, t)
	local lines, timeline = M.Sets[set], M.Timelines[set]
	if not lines then return end
	for i, tl in timeline do
		if t >= tl.shown and t < tl.finish then
			return i, lines[i], tl, math.clamp((t - tl.start) / (tl.typed - tl.start), 0, 1)
		end
	end
end

-- the local player's talk right now, or nil
function M.State()
	local player = Players.LocalPlayer
	if not player then return nil end
	local at, set = player:GetAttribute('EHMartyTalkAt'), player:GetAttribute('EHMartyTalkSet')
	if type(at) ~= 'number' or not M.Sets[set] then return nil end
	local t = workspace:GetServerTimeNow() - at
	if t < 0 or t > M.Durations[set] + .4 then return nil end
	local _, line, tl = M.LineAt(set, t)
	return {t = t, set = set, speaking = line ~= nil and line.who == 'him' and t < tl.typed + .25}
end

local function findMarty()
	-- (R36) the nearest Marty in the world (the gate one and the Level 5 one never share a scene, but be sure)
	local me = Players.LocalPlayer
	local root = me and me.Character and me.Character:FindFirstChild('HumanoidRootPart')
	local best, bd = nil, math.huge
	for _, m in CS:GetTagged('MartyNPC') do
		if m:IsDescendantOf(workspace) and m.PrimaryPart then
			local d = root and (m.PrimaryPart.Position - root.Position).Magnitude or 0
			if d < bd then best, bd = m, d end
		end
	end
	return best
end
M.FindMarty = findMarty

local started = false
function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	local AuthoredGui = require(script.Parent.AuthoredGui)
	local gui = AuthoredGui.Get(player:WaitForChild('PlayerGui'), 'MartyTalk')
	gui.Enabled = false
	local box = gui:WaitForChild('Root'):WaitForChild('Box')
	local text = box:WaitForChild('Text')
	local line = text:WaitForChild('Line')
	local speaker = text:WaitForChild('Speaker')
	local portrait = box:WaitForChild('Portrait')
	local face, npcView = portrait:WaitForChild('Face'), portrait:WaitForChild('NpcView')
	local baseT, baseS, baseSp = line.TextTransparency, line.TextStrokeTransparency, speaker.TextTransparency
	local basePos, boxPos = line.Position, box.Position
	-- (R37) phones: a line too long for the box grows the box upward (up to 96 px more), then shrinks the text a
	-- step at a time (never below 18), so a line is never cut off
	local baseH, baseTS = box.Size.Y.Offset, line.TextSize
	local fitting = false
	local function fitStep()
		if not fitting then return end
		if line.TextFits then fitting = false return end
		if box.Size.Y.Offset < baseH + 96 then
			box.Size = UDim2.new(box.Size.X.Scale, box.Size.X.Offset, 0, box.Size.Y.Offset + 24)
		elseif line.TextSize > 18 then
			line.TextSize -= 2
		else
			fitting = false
		end
	end
	task.spawn(function()
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
		if ok then face.Image = img end
	end)
	-- Marty's portrait: a still copy of him in the viewport, framed on his face from the front
	local builtFor = nil
	local function buildMarty()
		local npc = findMarty()
		if not npc or builtFor == npc then return end
		local mesh = npc.PrimaryPart or npc:FindFirstChildWhichIsA('MeshPart')
		local head = mesh and mesh:FindFirstChild('Head', true)
		if not head then return end
		builtFor = npc
		npcView:ClearAllChildren()
		local wm = Instance.new('WorldModel'); wm.Parent = npcView
		local copy = npc:Clone()
		for _, d in copy:GetDescendants() do if d:IsA('LuaSourceContainer') or d:IsA('Sound') or d:IsA('KeyframeSequence') then d:Destroy() end end
		copy.Parent = wm
		local fwd = mesh.CFrame.LookVector
		local at = head.WorldPosition + Vector3.new(0, .35, 0) + fwd * .2
		local cam = Instance.new('Camera'); cam.FieldOfView = 20; cam.Parent = npcView; npcView.CurrentCamera = cam
		cam.CFrame = CFrame.lookAt(at + (fwd + Vector3.new(0, .12, 0)).Unit * 3.8, at)
	end
	local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
	local lastKey = nil
	RunService.RenderStepped:Connect(function()
		local at, set = player:GetAttribute('EHMartyTalkAt'), player:GetAttribute('EHMartyTalkSet')
		local timeline = M.Timelines[set]
		local t = (type(at) == 'number' and timeline) and (workspace:GetServerTimeNow() - at) or -1
		if not timeline or t < 0 or t > M.Durations[set] then
			if gui.Enabled then gui.Enabled = false end
			lastKey = nil
			return
		end
		local first, last = timeline[1], timeline[#timeline]
		local i, l, tl, k = M.LineAt(set, t)
		if not l then
			if t >= first.shown and t < last.finish then
				line.TextTransparency, line.TextStrokeTransparency, speaker.TextTransparency = 1, 1, 1
				return
			end
			if gui.Enabled then gui.Enabled = false end
			lastKey = nil
			return
		end
		if not gui.Enabled then gui.Enabled = true end
		local key = tostring(at) .. ':' .. i
		if key ~= lastKey then
			lastKey = key
			box.Size = UDim2.new(box.Size.X.Scale, box.Size.X.Offset, 0, baseH); line.TextSize = baseTS; fitting = true
			line.RichText = false
			line.Text = (string.gsub(l.text, '{name}', player.Name))
			speaker.Text = (string.gsub(M.Speakers[l.who] or '', '{name}', player.Name))
			if l.who == 'him' then buildMarty() end
			face.Visible = l.who == 'you'; npcView.Visible = l.who == 'him'
		end
		local n = utf8.len(line.ContentText) or #line.Text
		fitStep()
		line.MaxVisibleGraphemes = (k >= 1) and -1 or math.floor(n * k + .5)
		local b = smooth((t - first.shown) / .3) * smooth((last.finish - t) / .8) -- (R36) a slower, clearly visible fade out once the talk is done
		box.GroupTransparency = 1 - b
		box.Position = boxPos -- fades in place, as Hale's does (Nov 8)
		local a = smooth((t - tl.shown) / M.FadeIn) * smooth((tl.finish - t) / M.FadeOut)
		line.TextTransparency = 1 - (1 - baseT) * a
		line.TextStrokeTransparency = 1 - (1 - baseS) * a
		speaker.TextTransparency = 1 - (1 - baseSp) * a
		line.Position = basePos
		-- the portrait fades with the words, line by line
		face.ImageTransparency = 1 - a; npcView.ImageTransparency = 1 - a
	end)
end

return M
