--!nonstrict
-- Shows the server's answer to the admin "/floor transfer <n>" command as a quiet system line in
-- chat (only the admin who typed it ever gets one; see ElevatorService:_AdminCommand).
local Players=game:GetService('Players')
local TCS=game:GetService('TextChatService')
local p=Players.LocalPlayer
p:GetAttributeChangedSignal('EHAdminReplySerial'):Connect(function()
	local text=p:GetAttribute('EHAdminReply');if type(text)~='string' or text=='' then return end
	local channels=TCS:FindFirstChild('TextChannels');local sys=channels and (channels:FindFirstChild('RBXSystem') or channels:FindFirstChild('RBXGeneral'))
	if sys then pcall(function()sys:DisplaySystemMessage('[Floor] '..text:gsub('^! ',''))end) end
end)
