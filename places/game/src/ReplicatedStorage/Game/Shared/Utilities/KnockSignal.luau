--!nonstrict
-- The knock signal (R41): three knocks, a pause, three more. The presence's signature sound.
-- KnockSignal.Play(target) plays it at a part (3D) or, with no target, straight in the ear.
-- KnockSignal.At(target, serverTime) plays it in step with a time the server published, so every
-- client hears the same knocks together (late arrivals join part-way or skip it).
local Config = require(game:GetService('ReplicatedStorage').Game.Shared.Config.Level3)
local M = {}
local K = Config.Knock
M.Length = K.Gap * 4 + K.Pause

local function one(target, volume)
	local s = Instance.new('Sound')
	s.Name = 'KnockSignal'; s.SoundId = K.Sound; s.Volume = volume or K.Volume
	s.PlaybackSpeed = K.Speed * (.97 + math.random() * .06)
	s.RollOffMinDistance = 8; s.RollOffMaxDistance = 90; s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = target or game:GetService('SoundService')
	s:Play()
	task.delay(3, function() s:Destroy() end)
end

function M.Times()
	local t, out = 0, {}
	for i = 1, 6 do
		table.insert(out, t)
		t += (i == 3) and K.Pause or K.Gap
	end
	return out
end

function M.Play(target, volume, skip)
	for _, t in M.Times() do
		local wait = t - (skip or 0)
		if wait >= -.05 then task.delay(math.max(0, wait), function() if not target or target.Parent then one(target, volume) end end) end
	end
end

function M.At(target, serverTime, volume)
	local late = workspace:GetServerTimeNow() - serverTime
	if late > M.Length then return end
	if late < 0 then task.delay(-late, function() M.Play(target, volume) end) else M.Play(target, volume, late) end
end

return M
