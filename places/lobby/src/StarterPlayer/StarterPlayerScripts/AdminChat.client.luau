--!nonstrict
-- Shows the replies to admin chat commands (ServerScriptService...AdminService) in chat, to you only.
local TextChatService=game:GetService("TextChatService")
local remote=game.ReplicatedStorage:WaitForChild("Game"):WaitForChild("Network"):WaitForChild("AdminChat",30)
if not remote then return end
local function escape(s)
	return (string.gsub(string.gsub(string.gsub(s,"&","&amp;"),"<","&lt;"),">","&gt;"))
end
remote.OnClientEvent:Connect(function(text,color)
	local channels=TextChatService:FindFirstChild("TextChannels")
	local ch=channels and (channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral"))
	if not ch then return end
	pcall(function()
		ch:DisplaySystemMessage('<font color="'..tostring(color or "#B9B6AE")..'">'..escape(tostring(text))..'</font>')
	end)
end)
