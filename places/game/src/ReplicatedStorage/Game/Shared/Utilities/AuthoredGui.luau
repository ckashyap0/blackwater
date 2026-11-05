--!nonstrict
-- Every on-screen UI in this place is authored in StarterGui (edit it there in Studio; nothing about
-- how it looks is set in code). Controllers call AuthoredGui.Get(playerGui,"Name") to get their copy.
-- Roblox only copies StarterGui into PlayerGui once the first character spawns, which is later than some
-- screens are needed (the black arrival cover is up the instant you join), so the copy is made here
-- straight away and the extra copy Roblox makes on spawn is removed.
local StarterGui=game:GetService("StarterGui")
local M={}
local managed={}
local watching=setmetatable({},{__mode="k"})
local function watch(playerGui)
	if watching[playerGui] then return end
	watching[playerGui]=true
	playerGui.ChildAdded:Connect(function(child)
		if managed[child.Name] and not child:GetAttribute("EHAuthored") then
			task.defer(function()child:Destroy()end)
		end
	end)
end
function M.Get(playerGui,name)
	watch(playerGui)
	local live=managed[name]
	if live and live.Parent==playerGui then return live end
	local g=playerGui:FindFirstChild(name)
	if not g then
		local source=StarterGui:WaitForChild(name,10)
		assert(source,"StarterGui."..name.." is missing")
		g=source:Clone()
		g.Parent=playerGui
	end
	g:SetAttribute("EHAuthored",true)
	managed[name]=g
	return g
end
-- a fresh copy of an authored ScreenGui that the caller owns (for one-off effects that are destroyed after use)
function M.Fresh(playerGui,name)
	local source=StarterGui:WaitForChild(name,10)
	assert(source,"StarterGui."..name.." is missing")
	watch(playerGui)
	-- (drop a copy Roblox already made on spawn)
	for _,c in playerGui:GetChildren() do if c.Name==name and not c:GetAttribute("EHAuthored") then c:Destroy() end end
	local g=source:Clone();g:SetAttribute("EHAuthored",true)
	managed[name]=managed[name] or g
	g.Parent=playerGui
	return g
end
return table.freeze(M)
