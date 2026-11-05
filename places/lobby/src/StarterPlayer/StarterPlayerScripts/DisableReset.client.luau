--!nonstrict
-- Turns off "Reset Character" in the Roblox menu, so players can't kill themselves to respawn.
-- (SetCore can fail for a moment while the core scripts load, so it retries.)
local StarterGui=game:GetService("StarterGui")
for _=1,40 do
	if pcall(StarterGui.SetCore,StarterGui,"ResetButtonCallback",false) then break end
	task.wait(.25)
end
