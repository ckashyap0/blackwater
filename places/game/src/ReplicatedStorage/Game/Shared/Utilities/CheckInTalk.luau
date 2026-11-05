--!nonstrict
-- Check-in conversation at the gatehouse window (Nov 2, restyled Nov 3). One timing definition shared by the server and every client.
-- The server starts it: when someone holds CHECK IN, ElevatorService sets the yard attribute CheckInTalkAt (server
-- time). Every client then plays the same lines on the same clock in StarterGui.CheckInTalk.Root.Line
-- (look edited there - every frame is authored in StarterGui, nothing is built here). Nov 4: simple white dialogue -
-- a dark see-through panel, the speaker's portrait on the left (your Roblox headshot / a live view of Hale's face),
-- the name in bold italic and the line in plain white, typing out cleanly. The box fades in with the first line
-- and out after the last; between lines it stays up. "{name}" is filled in on each
-- screen with THAT player's own Roblox username (Tom sees "Tom.", Bobby sees "Bobby."). Timing never depends on the
-- name, so everyone stays in sync and the server knows exactly when the talk ends.
-- FrontDeskNPC reads M.State() to look at whoever is watching and move his head while he speaks.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

local M = {}
-- (Nov 4, Ryan's script: a sleepy Hale on the early shift)
--  kind = 'typing': no words - "typing..." in italics while Hale turns back to his screen and types for `dur` s
--  card = true: he hands the keycard over during this line
M.Lines = {
	{who = 'him', text = "*yawn* Oh. Hey there. What can I do for you?"},
	{who = 'you', text = "Hi! It's my first day working here."},
	{who = 'him', text = "Right, the new hire. Martin mentioned you. What's your name?"},
	{who = 'you', text = "It's {name}."},
	{who = 'him', text = "Okay, give me a second. I'll get you into the system."},
	{who = 'him', kind = 'typing', text = 'typing...', dur = 4},
	{who = 'him', text = "There we go. Here's your keycard, it gets you into the facility. Anything else?", card = true},
	{who = 'you', text = "Nope, that's everything. Thanks, have a good one!"},
}
M.Speakers = {him = 'Hale', you = '{name}'}  -- (Nov 4: plain names over the line; {name} = this screen's username)
M.CharsPerSecond = 28      -- typing speed (a little slower: it's early)
M.NameChars = 10           -- length {name} is timed as, whatever the real name is
M.Hold = 1.2               -- after a line finishes typing
M.PerChar = .025           -- extra reading time per character
M.Lead = .4                -- before the first line
M.FadeIn, M.FadeOut = .25, .5   -- each line fades in, and out before the next
M.Gap = .2                 -- dark between two lines

-- line timings (seconds after CheckInTalkAt): {shown, start, typed, finish}
local timeline, total = {}, 0
do
	local t = M.Lead
	for i, l in M.Lines do
		if l.dur then          -- a fixed-length beat (the typing pause)
			timeline[i] = {shown = t, start = t, typed = t + .01, finish = t + l.dur}
			t = t + l.dur + M.Gap
		else
			local n = #(string.gsub(l.text, '{name}', string.rep('x', M.NameChars)))
			local typing = n / M.CharsPerSecond
			local start = t + M.FadeIn * .6
			local finish = start + typing + M.Hold + n * M.PerChar + M.FadeOut
			timeline[i] = {shown = t, start = start, typed = start + typing, finish = finish}
			t = finish + M.Gap
		end
	end
	total = t
end
M.Timeline = timeline
M.Duration = total
M.KeycardAt = timeline[#timeline].start + .8
for i, l in M.Lines do if l.card then M.KeycardAt = timeline[i].start + .8 end end

function M.LineAt(t)
	for i, tl in timeline do
		if t >= tl.shown and t < tl.finish then
			return i, M.Lines[i], tl, math.clamp((t - tl.start) / (tl.typed - tl.start), 0, 1)
		end
	end
end

local function findYard(from)
	local o = from
	while o and o ~= workspace do
		if o:GetAttribute('CheckInTalkAt') ~= nil then return o end
		o = o.Parent
	end
end
M.FindYard = findYard

function M.State(fromInstance)
	local yard = findYard(fromInstance)
	local at = yard and yard:GetAttribute('CheckInTalkAt')
	if type(at) ~= 'number' then return nil end
	local t = workspace:GetServerTimeNow() - at
	-- once you have said goodbye he goes back to his screen and his work
	if t < 0 or t > timeline[#timeline].typed + .6 then return nil end
	local i, line, tl, k = M.LineAt(t)
	-- typing = the pause where he turns back to the computer and types you into the system
	return {t = t, index = i, typing = line ~= nil and line.kind == 'typing',
		speaking = line ~= nil and line.who == 'him' and line.kind == nil and t < tl.typed + .25}
end

local started = false
function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	local AuthoredGui = require(script.Parent.AuthoredGui)
	-- (Nov 3) after the talk: "Get back in the car" in the task bar, with the car outlined, until the crew is in
	local okS, Sources = pcall(require, script.Parent:WaitForChild('ObjectiveSources', 5))
	if okS and Sources then
		Sources.Register('CarGetIn', function(p)
			if p ~= player or p:GetAttribute('EHInCar') or p:GetAttribute('EHCinematic') then return nil end
			local runtime = workspace:FindFirstChild('Runtime')
			local w = runtime and runtime:FindFirstChild('ServiceWindow', true)
			local yard = w and findYard(w)
			if not yard or not yard:GetAttribute('CarGetInReady') or yard:GetAttribute('GateDriveAt') then return nil end
			local car = yard:FindFirstChild('ArrivalCar', true)
			return car and {key = yard, text = 'Get back in the car', targets = {car}} or nil
		end)
	end
	local gui = AuthoredGui.Get(player:WaitForChild('PlayerGui'), 'CheckInTalk')
	gui.Enabled = false
	local box = gui:WaitForChild('Root'):WaitForChild('Box')       -- CanvasGroup: fades as one piece
	local text = box:WaitForChild('Text')
	local line = text:WaitForChild('Line')
	local speaker = text:WaitForChild('Speaker')
	local portrait = box:WaitForChild('Portrait')
	local face, haleView = portrait:WaitForChild('Face'), portrait:WaitForChild('HaleView')
	local baseT, baseS, baseSp = line.TextTransparency, line.TextStrokeTransparency, speaker.TextTransparency
	local basePos, boxPos = line.Position, box.Position
	-- your portrait: your own Roblox headshot
	task.spawn(function()
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
		if ok then face.Image = img end
	end)
	-- Hale's portrait: a still copy of him in the viewport, framed on his face
	local haleReady = false
	local function buildHale()
		if haleReady then return end
		local npc = game:GetService('CollectionService'):GetTagged('FrontDeskNPC')[1]
		if not (npc and npc:IsDescendantOf(workspace)) then return end
		local head = npc:FindFirstChild('Head', true); if not head then return end
		haleReady = true
		local wm = Instance.new('WorldModel'); wm.Parent = haleView
		local copy = npc:Clone(); for _, d in copy:GetDescendants() do if d:IsA('LuaSourceContainer') or d:IsA('Sound') then d:Destroy() end end
		copy.Parent = wm
		local hp = head.WorldPosition
		local scr = npc.Parent and npc.Parent:FindFirstChild('Prop_CRT_Screen', true)
		-- (he looks down at his screen in this still pose: the camera sits along his gaze, a little below
		-- his eyes, so the portrait is his face straight on)
		local dir = (scr and (scr.Position - hp) or head.WorldCFrame.LookVector).Unit
		local cam = Instance.new('Camera'); cam.FieldOfView = 20; cam.Parent = haleView; haleView.CurrentCamera = cam
		local at = hp + Vector3.new(0, .3, 0) + dir * .15
		cam.CFrame = CFrame.lookAt(at + (dir + Vector3.new(0, .25, 0)).Unit * 3.6, at)
	end
	local first, last = timeline[1], timeline[#timeline]
	local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
	local sw, nextLook, lastIndex = nil, 0, nil
	RunService.RenderStepped:Connect(function()
		if not (sw and sw:IsDescendantOf(workspace)) then
			sw = nil
			if gui.Enabled then gui.Enabled = false end
			if os.clock() < nextLook then return end
			nextLook = os.clock() + 1
			local runtime = workspace:FindFirstChild('Runtime')
			sw = runtime and runtime:FindFirstChild('ServiceWindow', true)
			if not sw then return end
		end
		local yard = findYard(sw)
		local at = yard and yard:GetAttribute('CheckInTalkAt')
		local t = type(at) == 'number' and (workspace:GetServerTimeNow() - at) or -1
		local i, l, tl, k = nil, nil, nil, 0
		if t >= 0 and t <= total then i, l, tl, k = M.LineAt(t) end
		if not l then
			-- between two lines the box stays up, empty for a moment
			if t >= first.shown and t < last.finish then
				line.TextTransparency, line.TextStrokeTransparency, speaker.TextTransparency = 1, 1, 1
				return
			end
			if gui.Enabled then gui.Enabled = false end
			lastIndex = nil
			return
		end
		if not gui.Enabled then gui.Enabled = true end
		if l.kind == 'typing' then
			-- "typing..." in italics, the dots counting up while he types
			local dots = string.rep('.', 1 + math.floor((t - tl.shown) * 2.5) % 3)
			local want = '<i>typing' .. dots .. '</i>'
			if line.Text ~= want then line.Text = want end
		end
		if i ~= lastIndex then
			lastIndex = i
			line.RichText = l.kind == 'typing'
			if l.kind ~= 'typing' then line.Text = (string.gsub(l.text, '{name}', player.Name)) end
			speaker.Text = (string.gsub(M.Speakers[l.who] or '', '{name}', player.Name))
			if l.who == 'him' then buildHale() end
			face.Visible = l.who == 'you'; haleView.Visible = l.who == 'him'
		end
		local n = utf8.len(line.ContentText) or #line.Text
		line.MaxVisibleGraphemes = (k >= 1) and -1 or math.floor(n * k + .5)
		-- the box: in with the first line (rising a few pixels), out after the last
		local b = smooth((t - first.shown) / .3) * smooth((last.finish - t) / .4)
		box.GroupTransparency = 1 - b
		box.Position = boxPos + UDim2.fromOffset(0, math.floor(8 * (1 - b) + .5))
		-- the words (and who is speaking) fade in and out line by line inside it
		local a = smooth((t - tl.shown) / M.FadeIn) * smooth((tl.finish - t) / M.FadeOut)
		line.TextTransparency = 1 - (1 - baseT) * a
		line.TextStrokeTransparency = 1 - (1 - baseS) * a
		speaker.TextTransparency = 1 - (1 - baseSp) * a
		-- (Nov 4) the words drift down a few pixels as they fade out (clean, eased)
		local outK = 1 - smooth((tl.finish - t) / M.FadeOut)
		line.Position = basePos + UDim2.fromOffset(0, math.floor(6 * outK + .5))

	end)
end

return M
