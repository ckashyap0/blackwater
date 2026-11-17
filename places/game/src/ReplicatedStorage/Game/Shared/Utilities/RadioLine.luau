--!nonstrict
-- R41: one intercom line on this player's screen (Level 3). The server sets, on the player:
--   EHRadioLine (text), EHRadioWho (name shown), EHRadioFace (user id for a headshot, 0 = no picture),
--   EHRadioKind ('Marty' | 'Crew' | 'Old'), EHRadioSeconds (how long it stays), EHRadioAt (server time)
-- Authored in StarterGui.RadioLine (edit the look there):
--   Root > Box (CanvasGroup) > Lamp, Tag, Portrait (Face, NoVideo, Scan), Speaker, Line, Meter (Bar1..BarN)
-- It reads as the works' wall intercom: a call lamp, a level meter that moves while the voice speaks and a
-- grainy picture of whoever the channel says is calling. A crew line shows that player's headshot and name,
-- which is the whole point: the name on the box is not always the person speaking.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local SoundService = game:GetService('SoundService')
local Config = require(game:GetService('ReplicatedStorage').Game.Shared.Config.Level3)

local M = {}
M.CharsPerSecond = 30
M.FadeIn, M.FadeOut, M.Lead = .25, .5, .3
M.Volume = 1 -- (MartyGrey turns the squelch down during the booth sequence)

local started = false
local faces = {}

local function headshot(userId, label)
	if faces[userId] then label.Image = faces[userId] return end
	label.Image = ''
	task.spawn(function()
		local ok, img = pcall(function() return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
		if ok then faces[userId] = img; label.Image = img end
	end)
end

local function sound(id, volume, speed, looped)
	local s = Instance.new('Sound')
	s.Name = 'IntercomFx'; s.SoundId = id; s.Volume = volume; s.PlaybackSpeed = speed or 1; s.Looped = looped or false
	s.Parent = SoundService
	return s
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	local AuthoredGui = require(script.Parent.AuthoredGui)
	local Tick = require(script.Parent.DialogueTick)
	local Fit = require(script.Parent.DialogueFit)
	local gui = AuthoredGui.Get(player:WaitForChild('PlayerGui'), 'RadioLine')
	gui.Enabled = false
	local box = gui:WaitForChild('Root'):WaitForChild('Box')
	local line, speaker = box:WaitForChild('Line'), box:WaitForChild('Speaker')
	local lamp, meter = box:WaitForChild('Lamp'), box:WaitForChild('Meter')
	local portrait = box:WaitForChild('Portrait')
	local face, noVideo = portrait:WaitForChild('Face'), portrait:WaitForChild('NoVideo')
	local bars = {}
	for _, b in meter:GetChildren() do if b:IsA('Frame') then table.insert(bars, b) end end
	table.sort(bars, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	local baseH, baseTS = box.Size.Y.Offset, line.TextSize
	local outline = box:FindFirstChild('Outline')
	local outlineBase = outline and outline.Transparency or 0
	local lampOn, lampOff = lamp.BackgroundColor3, lamp.BackgroundColor3:Lerp(Color3.new(0, 0, 0), .75)
	local static = sound(Config.Sounds.static, 0, 1, true)
	local shownAt = nil
	local function smooth(x) x = math.clamp(x, 0, 1) return x * x * (3 - 2 * x) end
	RunService.RenderStepped:Connect(function()
		local at = player:GetAttribute('EHRadioAt')
		local text = player:GetAttribute('EHRadioLine')
		local total = player:GetAttribute('EHRadioSeconds') or 4
		local t = (type(at) == 'number' and type(text) == 'string') and (workspace:GetServerTimeNow() - at) or -1
		if t < 0 or t > total then
			if gui.Enabled then gui.Enabled = false; static:Stop() end
			shownAt = nil
			return
		end
		if shownAt ~= at then
			shownAt = at
			local kind = player:GetAttribute('EHRadioKind') or 'Marty'
			local who = player:GetAttribute('EHRadioWho') or 'Marty'
			local id = player:GetAttribute('EHRadioFace') or 0
			speaker.Text = string.upper(who)
			line.Text = text; line.MaxVisibleGraphemes = 0
			local crew = kind == 'Crew' and id > 0
			face.Visible = crew; noVideo.Visible = not crew
			if crew then headshot(id, face) end
			gui.Enabled = true
			task.spawn(Fit.Fit, box, line, text, baseH, baseTS, -line.Size.Y.Offset) -- (the line fills the box under the header rows)
			local sq = sound(Config.Sounds.squelch, .22 * M.Volume, kind == 'Old' and .8 or 1)
			sq:Play(); task.delay(3, function() sq:Destroy() end)
			static.PlaybackSpeed = kind == 'Old' and .85 or 1
			static.Volume = 0; static:Play()
		end
		local n = utf8.len(line.ContentText) or #text
		local typing = n / M.CharsPerSecond
		local k = math.clamp((t - M.Lead) / typing, 0, 1)
		local shown = math.floor(n * k + .5)
		line.MaxVisibleGraphemes = k >= 1 and -1 or shown
		Tick.Step(tostring(at), shown, text)
		local a = smooth(t / M.FadeIn) * smooth((total - t) / M.FadeOut)
		box.GroupTransparency = 1 - a
		if outline then outline.Transparency = 1 - (1 - outlineBase) * a end -- (a UIStroke does not follow GroupTransparency)
		-- the call lamp and the level meter move while the voice is speaking
		local speaking = k > 0 and k < 1
		local now = os.clock()
		lamp.BackgroundColor3 = (speaking and (now * 6) % 1 < .6 or (not speaking and k >= 1)) and lampOn or lampOff
		for i, b in bars do
			local level = speaking and (.25 + .75 * math.abs(math.noise(now * 9, i * 1.7))) or .12
			b.Size = UDim2.new(b.Size.X.Scale, b.Size.X.Offset, level, 0)
		end
		static.Volume = (speaking and .05 or .025) * a * M.Volume
	end)
end

return M
