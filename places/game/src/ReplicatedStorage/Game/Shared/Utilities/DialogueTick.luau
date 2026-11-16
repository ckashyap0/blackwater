--!nonstrict
-- DialogueTick (Nov 13): the soft tick under dialogue as it types out (Hale, Marty, your own lines).
-- One shared helper: a talk calls M.Step(key, shown, text) every frame with how many letters are showing.
-- It reuses the intro typewriter's strokes, cut to a few hundredths of a second, pitched up and kept quiet,
-- so it reads as a light text tick and not as a typewriter. The sounds are loaded once and replayed, so
-- every tick lands with its letter.
local IDS = {9120299319, 9120299407, 9120299595, 9120299736}
local VOLUME, CLIP, SPEED, EVERY = .11, .05, 1.7, 2 -- one tick per EVERY letters (spaces are silent)
local M = {}
local pool, last
local rng = Random.new()
local function sounds()
	if pool then return pool end
	pool = {}
	for _, id in IDS do
		local s = Instance.new('Sound'); s.Name = 'DialogueTick'; s.SoundId = 'rbxassetid://' .. id
		s.PlaybackRegionsEnabled = true; s.PlaybackRegion = NumberRange.new(0, CLIP)
		s.Parent = game:GetService('SoundService')
		table.insert(pool, s)
	end
	task.spawn(function() pcall(function() game:GetService('ContentProvider'):PreloadAsync(pool) end) end)
	return pool
end
M.Preload = sounds
local function tick()
	local p = sounds()
	local i = rng:NextInteger(1, #p); if i == last then i = i % #p + 1 end; last = i
	local s = p[i]
	s.Volume = VOLUME * (.85 + rng:NextNumber() * .3); s.PlaybackSpeed = SPEED * (.96 + rng:NextNumber() * .08)
	s.TimePosition = 0; s:Play()
end
local curKey, curN = nil, 0
function M.Step(key, shown, text)
	if key ~= curKey then curKey, curN = key, 0 end
	if shown <= curN then return end
	local played = false
	for k = curN + 1, shown do
		local ch = string.sub(text, k, k)
		if not played and ch ~= ' ' and k % EVERY == 1 then tick(); played = true end
	end
	curN = shown
end
return M
