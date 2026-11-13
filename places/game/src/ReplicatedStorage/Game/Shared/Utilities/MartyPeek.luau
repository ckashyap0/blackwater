--!nonstrict
-- R37 (Nov 13): Marty peeking round a corner, seen by ONE player at a time. Markers are parts tagged "MartyPeek"
-- inside a floor (Level5.MartyMarkers.MartyPeek_GateCorner, Level4.MartyMarkers.MartyPeek_CoreDrum). Each holds
-- his feet position and facing, plus attributes:
--   Condition   "GateReleased" (a floor attribute that must be set) or "Stage=Reboot" (attribute = value)
--   TriggerDist how close (studs) this player must be before he is put there
--   LeanDeg     how far he leans out sideways (degrees, sign = side)
--   Glitch      true: his face corrupts while you look (Floor 4)
-- On this screen only: when the condition holds and you are near, a local copy of Marty is placed while the spot
-- is out of your view. When you look straight at him with a clear line of sight he holds for a moment, then
-- ducks back out of sight with a sharp sting and a heartbeat (hard first beat, fading), and he is gone. Once per
-- marker per player. If you walk right up to the spot without looking, he is simply gone. Nobody else sees or
-- hears it. He never touches anyone.
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}
local started = false
local STING = 'rbxassetid://130018094603454' -- "Horror Stinger" (Daily Sounds, free)
local BEAT = 'rbxassetid://176554627' -- "Slow Heartbeat" (free)
local SEE_COS = math.cos(math.rad(20))
local AWAY_COS = math.cos(math.rad(55))

local done = {}
local active = nil

local function floorOf(inst)
	local a = inst.Parent
	while a and a ~= workspace and a:GetAttribute('EncounterId') == nil do a = a.Parent end
	return (a ~= workspace) and a or nil
end

local function conditionMet(marker)
	local floor = floorOf(marker)
	if not floor then return false end
	local c = marker:GetAttribute('Condition') or ''
	local k, v = string.match(c, '^(%w+)=(%w+)$')
	if k then return tostring(floor:GetAttribute(k)) == v end
	return c ~= '' and floor:GetAttribute(c) and true or false
end

local function sound(id, vol, speed)
	local s = Instance.new('Sound')
	s.SoundId = id; s.Volume = vol; s.PlaybackSpeed = speed or 1
	s.Parent = game:GetService('SoundService'); s:Play()
	task.delay(6, function() s:Destroy() end)
end

local function heartbeat()
	-- a heavy first beat, then three more fading away
	for i, v in {1, .55, .3, .14} do
		task.delay((i - 1) * .95, function() sound(BEAT, v, 1) end)
	end
end

local function template()
	local f = game.ReplicatedStorage:FindFirstChild('MartyStages')
	return f and f:FindFirstChild('PeekTemplate')
end

local function place(marker)
	local tpl = template()
	if not tpl or not tpl.PrimaryPart then return nil end
	local m = tpl:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA('BasePart') then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	local base = marker.CFrame * CFrame.Angles(0, 0, math.rad(marker:GetAttribute('LeanDeg') or 0))
	m:PivotTo(base * m.PrimaryPart.CFrame:ToObjectSpace(m:GetPivot()))
	m.Parent = workspace.CurrentCamera -- (local only, never replicated)
	return m
end

local function headOf(m)
	local h = m.PrimaryPart and m.PrimaryPart:FindFirstChild('Head', true)
	return h and h.TransformedWorldCFrame.Position or m:GetPivot().Position + Vector3.new(0, 6.6, 0)
end

local function visibleFrom(cam, point, ignore)
	local dir = point - cam.CFrame.Position
	if dir.Magnitude < .1 then return true, 1 end
	local dot = cam.CFrame.LookVector:Dot(dir.Unit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(cam.CFrame.Position, dir, params)
	return (not hit) or (hit.Position - point).Magnitude < .8, dot
end

local function glitch(m, on)
	local stages = game.ReplicatedStorage:FindFirstChild('MartyStages')
	local skin = m:FindFirstChild('Skin')
	if not (stages and skin) then return end
	local want = on and stages:FindFirstChild('Skin_Stage3') or stages:FindFirstChild('Skin_Stage1')
	if not want then return end
	local old = skin:FindFirstChildOfClass('SurfaceAppearance')
	local new = want:Clone(); new.Name = 'SurfaceAppearance'; new.Parent = skin
	if old then old:Destroy() end
end

function M.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local player = Players.LocalPlayer
	local nextScan = 0
	RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		local root = player.Character and player.Character:FindFirstChild('HumanoidRootPart')
		if not (cam and root) then return end
		local now = os.clock()
		-- one peek at a time
		if active then
			local a = active
			if not a.marker.Parent or not a.model.Parent then if a.model.Parent then a.model:Destroy() end; active = nil; return end
			local head = headOf(a.model)
			local vis, dot = visibleFrom(cam, head, {a.model, player.Character})
			if a.phase == 'wait' then
				if vis and dot > SEE_COS then
					a.seenFor += dt
					if a.marker:GetAttribute('Glitch') and not a.glitched then a.glitched = true; glitch(a.model, true) end
					if a.glitched then
						-- the face corrupts: the head twitches and the eyes flicker while you look
						local h = a.model.PrimaryPart:FindFirstChild('Head', true)
						if h then h.Transform = CFrame.Angles(math.rad(math.random(-6, 6)), math.rad(math.random(-8, 8)), math.rad(math.random(-5, 5))) end
						local eyes = a.model:FindFirstChild('Eyes'); if eyes then eyes.Transparency = (math.random() < .3) and 1 or 0 end
					end
					if a.seenFor > .35 then
						a.phase = 'duck'; a.t0 = now; a.from = a.model:GetPivot()
						sound(STING, .7); heartbeat()
					end
				else
					a.seenFor = math.max(0, a.seenFor - dt)
					if (root.Position - a.marker.Position).Magnitude < 5 then a.model:Destroy(); active = nil end
				end
			elseif a.phase == 'duck' then
				-- straight back out of sight, fast, then gone
				local u = math.clamp((now - a.t0) / .18, 0, 1); u = 1 - (1 - u) ^ 3
				local side = (a.marker:GetAttribute('LeanDeg') or 0) >= 0 and 1 or -1
				local away = a.marker.CFrame.RightVector * (-1.9 * side) - a.marker.CFrame.LookVector * .6
				a.model:PivotTo(a.from + away * u)
				if u >= 1 then a.model:Destroy(); active = nil end
			end
			return
		end
		if now < nextScan then return end
		nextScan = now + .15
		local runtime = workspace:FindFirstChild('Runtime')
		if not runtime then return end
		for _, marker in CS:GetTagged('MartyPeek') do
			if marker:IsDescendantOf(runtime) and not done[marker] and conditionMet(marker) then
				if (root.Position - marker.Position).Magnitude < (marker:GetAttribute('TriggerDist') or 16) then
					-- only put him there while that spot is out of view
					local _, dot = visibleFrom(cam, marker.Position + Vector3.new(0, 6, 0), {player.Character})
					if dot < AWAY_COS then
						local m = place(marker)
						if m then done[marker] = true; active = {marker = marker, model = m, phase = 'wait', seenFor = 0}; break end
					end
				end
			end
		end
	end)
end

return M
