--!nonstrict
-- R37 (Nov 13): where Marty is, decided on the server. Started by ElevatorService.
--  YARD: one Marty moves ahead of the crew, GatePlaza -> ShaftHall -> LiftLanding (the MartyStand parts in
--    SurfaceYard.19_MartyMarkers). He only moves when the crew has moved on (they talked to him, or someone is
--    already near his next spot) and nobody can see either spot (line of sight from every player's head).
--    Nobody ever sees him walk. Each move sets TalkSets (Gate, Shaft, Lift: lines in Utilities.MartyTalk) and
--    bumps SpotSerial so every client's MartyNPC starts again from the new spot.
--  LEVEL 5: once the shaft gate opens (floor attribute GateReleased), the Marty waiting by the lift leaves as
--    soon as nobody can see him (the peek round the corner is a separate, per-player effect: MartyPeek).
-- He never catches or chases anyone.
local Players = game:GetService('Players')
local CS = game:GetService('CollectionService')

local M = {}

local ORDER = {
	{marker = 'MartyMarker_GatePlaza', sets = 'Gate'},
	{marker = 'MartyMarker_ShaftHall', sets = 'Shaft'},
	{marker = 'MartyMarker_LiftLanding', sets = 'Lift'},
}

local function heads()
	local out = {}
	for _, p in Players:GetPlayers() do
		local h = p.Character and p.Character:FindFirstChild('Head')
		local r = p.Character and p.Character:FindFirstChild('HumanoidRootPart')
		if h then table.insert(out, {player = p, pos = h.Position, look = r and r.CFrame.LookVector or Vector3.zAxis}) end
	end
	return out
end

-- can any player see this point? (within 160 studs, inside their view (65 degrees either side of where they
-- face) and with a clear line from their head)
local VIEW_COS = math.cos(math.rad(65))
local function seen(point, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {ignore}
	for _, p in Players:GetPlayers() do if p.Character then table.insert(list, p.Character) end end
	params.FilterDescendantsInstances = list
	params.RespectCanCollide = true
	for _, h in heads() do
		local d = point - h.pos
		local flat = Vector3.new(d.X, 0, d.Z)
		local inView = flat.Magnitude < 4 or Vector3.new(h.look.X, 0, h.look.Z).Unit:Dot(flat.Unit) > VIEW_COS
		if d.Magnitude < 160 and inView then
			local hit = workspace:Raycast(h.pos, d, params)
			if not hit or (hit.Position - point).Magnitude < 1 then return true end
		end
	end
	return false
end

local function nearAny(point, radius)
	for _, h in heads() do if (h.pos - point).Magnitude < radius then return true end end
	return false
end

local function talking(now)
	for _, p in Players:GetPlayers() do
		local at = p:GetAttribute('EHMartyTalkAt')
		if type(at) == 'number' and now - at < 30 then
			local okT, Talk = pcall(require, game.ReplicatedStorage.Game.Shared.Utilities.MartyTalk)
			if okT and now < at + Talk.Duration(p:GetAttribute('EHMartyTalkSet')) + .5 then return true end
		end
	end
	return false
end

local function talked(sets)
	for _, p in Players:GetPlayers() do if p:GetAttribute('EHMartyTalked' .. sets) then return true end end
	return false
end

-- where his feet go on a stand: on the ground under it, facing the way the stand faces
local function standFrame(stand, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {ignore, stand.Parent}
	local hit = workspace:Raycast(stand.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), params)
	local y = hit and hit.Position.Y or (stand.Position.Y - stand.Size.Y / 2)
	local look = stand.CFrame.LookVector * Vector3.new(1, 0, 1)
	local p = Vector3.new(stand.Position.X, y, stand.Position.Z)
	return CFrame.lookAt(p, p + look.Unit)
end

local function chest(marty) return marty.PrimaryPart.Position + Vector3.new(0, 5.2, 0) end

local function moveTo(marty, stand, sets)
	local f = standFrame(stand, marty)
	marty:PivotTo(f * marty.PrimaryPart.CFrame:ToObjectSpace(marty:GetPivot()))
	marty:SetAttribute('TalkSets', sets)
	marty:SetAttribute('SpotSerial', (marty:GetAttribute('SpotSerial') or 0) + 1)
end

function M.Start(service)
	task.spawn(function()
		local yardState = setmetatable({}, {__mode = 'k'}) -- yard model -> index in ORDER
		while true do
			task.wait(.5)
			local now = workspace:GetServerTimeNow()
			-- the yard
			local yard = service._yard
			if yard and yard.Parent then
				local folder = yard:FindFirstChild('19_MartyMarkers')
				local marty
				for _, m in CS:GetTagged('MartyNPC') do if m:IsDescendantOf(yard) then marty = m break end end
				if folder and marty and marty.PrimaryPart then
					local i = yardState[yard] or 1
					yardState[yard] = i
					local nextSpot = ORDER[i + 1]
					local nextMk = nextSpot and folder:FindFirstChild(nextSpot.marker)
					local stand = nextMk and nextMk:FindFirstChild('MartyStand')
					if stand then
						local here = ORDER[i]
						local onward = talked(here.sets) or nearAny(stand.Position, 30)
						-- (the crew is through the gate drive before the first move can happen)
						if yard:GetAttribute('ArrivalCar') and not yard:GetAttribute('GateDriveDone') then onward = false end
						-- (Nov 13) after his intro the gate shuts behind the crew (ElevatorService waits for the talk to end);
						-- every camera is on the closing gate, so he leaves his first spot then, seen or not (each player
						-- then says "he's already gone": Utilities.MartyTalk, set Gone)
						local closed = yard:GetAttribute('GateClosedAt')
						local duringGate = i == 1 and type(closed) == 'number' and now >= closed + .3
						-- (and he never slips away from the gate before it has shut)
						if i == 1 and type(closed) ~= 'number' then onward = false end
						if duringGate or (onward and not talking(now) and not seen(chest(marty), marty) and not seen(stand.Position + Vector3.new(0, 3, 0), marty)) then
							moveTo(marty, stand, nextSpot.sets)
							yardState[yard] = i + 1
						end
					end
				end
			end
			-- Level 5: he leaves the lift once the shaft gate is open and nobody is looking
			for _, m in CS:GetTagged('MartyNPC') do
				if m.PrimaryPart and m:GetAttribute('TalkSets') == 'L5' and m:IsDescendantOf(workspace) then
					local floor = m.Parent
					while floor and floor ~= workspace and floor:GetAttribute('EncounterId') == nil do floor = floor.Parent end
					if floor and floor:GetAttribute('GateReleased') and not talking(now) and not seen(chest(m), m) then
						m:Destroy()
					end
				end
			end
		end
	end)
end

return M
