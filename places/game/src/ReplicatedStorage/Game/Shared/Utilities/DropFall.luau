--!nonstrict
-- R36 (Nov 9): a flat item that someone drops (DropFlat, e.g. the site keycard) falls smoothly on every
-- screen, not only on the dropper's. The server puts the item at its resting spot and sets three
-- attributes on it (InventoryService:Drop): EHFallFrom (the CFrame it left the hand at), EHFallBy (the
-- dropper's UserId) and EHFallAt (server time). Here every other client draws the fall locally: straight
-- down with gravity, turning flat on the way, the same curve as the dropper's own ghost. The dropper's
-- screen is skipped: EquipmentController already shows that fall.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}
local started = false
local falling = {}

local function ease(x) x = math.clamp(x, 0, 1) return x * x end -- gravity: slow at the top, fast at the end

local function watch(part)
	if not part:IsA('BasePart') then return end
	part:GetAttributeChangedSignal('EHFallAt'):Connect(function()
		local at, from, by = part:GetAttribute('EHFallAt'), part:GetAttribute('EHFallFrom'), part:GetAttribute('EHFallBy')
		if type(at) ~= 'number' or typeof(from) ~= 'CFrame' then return end
		local me = Players.LocalPlayer
		if me and by == me.UserId then return end
		if workspace:GetServerTimeNow() - at > 1.5 then return end -- (joined late: it has long landed)
		-- the resting spot (EHFallTo; the server also sets it as the part's CFrame)
		local to = part:GetAttribute('EHFallTo')
		if typeof(to) ~= 'CFrame' then to = part.CFrame end
		local h = math.max(.05, from.Position.Y - to.Position.Y)
		local dur = math.clamp(math.sqrt(2 * h / workspace.Gravity) * 1.25, .22, .6)
		falling[part] = {from = from, to = to, at = at, dur = dur}
		part.CFrame = from
	end)
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	for _, p in CS:GetTagged('EHInteractable') do watch(p) end
	CS:GetInstanceAddedSignal('EHInteractable'):Connect(watch)
	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for part, f in falling do
			local st = part:GetAttribute('EHItemState')
			if not part.Parent or st ~= 'Dropped' then falling[part] = nil; continue end
			local u = (now - f.at) / f.dur
			if u >= 1 then
				part.CFrame = f.to; falling[part] = nil
			else
				local pos = f.from.Position:Lerp(f.to.Position, ease(u))
				local rot = f.from.Rotation:Lerp(f.to.Rotation, math.clamp(u * 1.3, 0, 1))
				part.CFrame = CFrame.new(pos) * rot
			end
		end
	end)
end

return M
