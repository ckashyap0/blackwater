--!nonstrict
-- R37 (Nov 13): lighter Floor 4 on phones and tablets. When the Floor 4 copy is built in
-- Runtime.DescentEnvironment on a touch-first device (no keyboard), this screen only:
--  * minor lights (range 18 studs or less) stop casting shadows; the big practical lights keep theirs
--  * particle emitters run at half rate
-- Nothing changes on computers or consoles, and nothing changes on the server.
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')

local M = {}
local started = false
local done = setmetatable({}, {__mode = 'k'})

local function phone()
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

local function lighten(floor)
	if done[floor] then return end
	done[floor] = true
	local n = 0
	for _, d in floor:GetDescendants() do
		if d:IsA('Light') and d.Shadows and d.Range <= 18 then
			d.Shadows = false
		elseif d:IsA('ParticleEmitter') then
			d.Rate = d.Rate * .5
		end
		n += 1
		if n % 2000 == 0 then task.wait() end
	end
end

function M.Start()
	if started or not RunService:IsClient() or not phone() then return end
	started = true
	task.spawn(function()
		while true do
			local runtime = workspace:FindFirstChild('Runtime')
			local env = runtime and runtime:FindFirstChild('DescentEnvironment')
			if env then
				for _, m in env:GetChildren() do
					local e = m:GetAttribute('EncounterId')
					if e == 'Level4' or e == 'Level3' then task.spawn(lighten, m) end
				end
			end
			task.wait(2)
		end
	end)
end

return M
