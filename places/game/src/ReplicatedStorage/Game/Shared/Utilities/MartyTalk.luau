--!nonstrict
-- R34 (Nov 9): talking to Marty on the red square outside the works gate. Same look and timing as the check-in
-- talk with Hale (Utilities.CheckInTalk): the authored StarterGui.MartyTalk panel is a copy of CheckInTalk, with the
-- speaker's portrait on the left (your Roblox headshot / a still view of Marty's face in Portrait.NpcView), the
-- name over the line and the line typing out.
-- Unlike Hale's talk this one is per player: whoever holds TALK on Marty gets the conversation on their own screen.
-- The server (ElevatorService:_OnMartyTalk) sets two attributes on that player:
--   EHMartyTalkAt  = server time the talk starts
--   EHMartyTalkSet = 1 for the first talk, 2 for any talk after that
-- MartyNPC reads M.State() to turn Marty towards that player while they talk.
-- R34 scope: Marty is in his normal form. He is friendly and he does not catch or chase anyone.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}
M.Sets = {
	[1] = {
		{who = 'him', text = "There you are! You must be the new hire. Martin Voss, maintenance. Everyone calls me Marty."},
		{who = 'you', text = "Hi, I'm {name}. Nice to meet you."},
		{who = 'him', text = "Good to have you, {name}. The gate's right behind me. The keycard Hale gave you opens it."},
		{who = 'him', text = "Take the lift down when you're ready. I'll meet you on Level Five."},
	},
	[2] = {
		{who = 'him', text = "Don't mind the smell. After a while you stop noticing it."},
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
	for _, m in CS:GetTagged('MartyNPC') do
		if m:IsDescendantOf(workspace) then return m end
	end
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
			line.RichText = false
			line.Text = (string.gsub(l.text, '{name}', player.Name))
			speaker.Text = (string.gsub(M.Speakers[l.who] or '', '{name}', player.Name))
			if l.who == 'him' then buildMarty() end
			face.Visible = l.who == 'you'; npcView.Visible = l.who == 'him'
		end
		local n = utf8.len(line.ContentText) or #line.Text
		line.MaxVisibleGraphemes = (k >= 1) and -1 or math.floor(n * k + .5)
		local b = smooth((t - first.shown) / .3) * smooth((last.finish - t) / .4)
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
