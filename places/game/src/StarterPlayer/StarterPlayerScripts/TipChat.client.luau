--!nonstrict
-- Tips from any lobby, announced in chat in green (Oct 18).
local TextChatService=game:GetService("TextChatService")
local Config=require(game.ReplicatedStorage.Game.Shared.Config.DonationConfig)
local tip=game.ReplicatedStorage:WaitForChild("Game"):WaitForChild("Network"):WaitForChild("Tip",120)
if not tip then return end
local function commas(n)local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse();return (out:gsub("^,",""))end
tip.OnClientEvent:Connect(function(name,robux)
	local channels=TextChatService:FindFirstChild("TextChannels");local general=channels and channels:FindFirstChild("RBXGeneral")
	if general and type(name)=="string" and type(robux)=="number" then
		general:DisplaySystemMessage(string.format('<font color="%s"><b>%s</b> has tipped %s Robux! Thank you!</font>',Config.TipColor,(name:gsub("[<>&]","")),commas(robux)))
	end
end)
