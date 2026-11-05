--!strict
-- Runtime darkness. The place is saved with bright, high-visibility Lighting so everything is easy to
-- see while editing. As soon as a playtest or a live server starts, this switches Lighting to the
-- game's dark horror settings (Config.RuntimeLighting). It runs on the server, so every client
-- receives the dark values before their character spawns. Light sources are never changed.
local RunService=game:GetService("RunService")
local Lighting=game:GetService("Lighting")
if not RunService:IsRunning() then return end
local Config=require(game.ReplicatedStorage:WaitForChild("Game"):WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RuntimeLighting"))
for key,value in Config.Lighting do
	local ok,err=pcall(function()(Lighting::any)[key]=value end)
	if not ok then warn("[ElevatorHorror] RuntimeLighting: "..key..": "..tostring(err)) end
end
for name,props in Config.Effects do
	local effect=Lighting:FindFirstChild(name)
	if effect then for key,value in props do pcall(function()(effect::any)[key]=value end) end end
end
Lighting:SetAttribute("RuntimeDark",true)
