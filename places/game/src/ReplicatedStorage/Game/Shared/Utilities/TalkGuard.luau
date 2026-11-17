--!nonstrict
-- (Nov 16, Ryan: 'the text box can still be running' through a floor change) A talk box (CheckInTalk, MartyTalk)
-- is never shown while the screen is changing scene: during the lift ride, any black fade or arrival cover, a
-- floor transfer, or any context other than walking about on a floor. Both talks call Blocked() every frame.
local Players = game:GetService('Players')
local M = {}
local COVERS = {'DescentFade', 'ArrivalCover', 'WakeLids', 'ArrivalText', 'IntroHud', 'IntroEyes'}
function M.Blocked()
	local player = Players.LocalPlayer
	if not player then return false end
	local ctx = player:GetAttribute('EHContext')
	if ctx ~= nil and ctx ~= 'ActiveFloor' then return true end
	local r = workspace:FindFirstChild('Runtime'); local e = r and r:FindFirstChild('DescentEnvironment')
	local cabin = e and e:FindFirstChild('Elevator')
	-- (only the floor-to-floor ride: the surface descent's DescendAt stays set for the whole run, which blocked
	-- Marty's Level 5 talk; that descent's black fade is caught by the cover check below)
	if cabin and cabin:GetAttribute('TravelStartedAt') ~= nil then return true end
	local pg = player:FindFirstChild('PlayerGui')
	if pg then for _, n in COVERS do local c = pg:FindFirstChild(n); if c and c:IsA('ScreenGui') and c.Enabled then return true end end end
	return false
end
return M
