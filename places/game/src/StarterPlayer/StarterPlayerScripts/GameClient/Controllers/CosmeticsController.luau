--!nonstrict
-- Game-place side of the unlockable cosmetics (the Lobby copy also handles the secret-room pickups):
--  * chat: an equipped title shows in front of the sender's name, e.g. [Secret] in purple
-- Flashlight skins are applied by EquipmentController (beam colour + held model).
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.CosmeticsConfig)
local Controller={};Controller.__index=Controller
local function entry(slot,id)
	for _,e in Config[slot] or {} do if e.Id==id then return e end end
end
function Controller.new(player)
	return setmetatable({Name="CosmeticsController",Dependencies={},_player=player},Controller)
end
function Controller:Init()self._scope=Scope.new()end
function Controller:Start()
	TextChatService.OnIncomingMessage=function(message)
		local source=message.TextSource
		local sender=source and Players:GetPlayerByUserId(source.UserId)
		local id=sender and sender:GetAttribute("EHTitle")
		local e=type(id)=="string" and id~="" and entry("Title",id)
		if not e or not e.Color then return nil end
		local label=e.Label
		if e.Leaderboard then
			-- leaderboard titles carry the live rank; dropped off the board = no tag
			local r=sender:GetAttribute(e.Leaderboard=="Donor" and "EHDonorRank" or "EHCoinRank")
			if type(r)~="number" then return nil end
			label=(r<=10 and ("#"..r) or "TOP 100").." "..(e.Leaderboard=="Donor" and "DONOR" or "COINS")
		end
		local props=Instance.new("TextChatMessageProperties")
		props.PrefixText=string.format('<font color="%s">[%s]</font> %s',e.Color,label,message.PrefixText)
		return props
	end
	self._scope:Add(function()TextChatService.OnIncomingMessage=nil end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
