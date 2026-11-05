--!nonstrict
local Teleport=game:GetService("TeleportService")
local Places=require(game.ReplicatedStorage.Game.Shared.Config.PlaceConfig)
local Gateway={}
function Gateway.Reserve()
	if game:GetService("RunService"):IsStudio() then error("PublishedClientRequired") end
	assert(Places.GamePlaceId>0 and Places.GamePlaceId~=Places.LobbyPlaceId,"GamePlaceNotConfigured")
	return Teleport:ReserveServerAsync(Places.GamePlaceId)
end
function Gateway.Send(players,ticket)
	local options=Instance.new("TeleportOptions");options.ReservedServerAccessCode=ticket.accessCode
	options:SetTeleportData({sessionId=ticket.id})
	return Teleport:TeleportAsync(Places.GamePlaceId,players,options)
end
-- notice: optional short message the lobby shows on arrival (why you were sent back)
function Gateway.Return(player,notice)
	local options
	if type(notice)=="string" then options=Instance.new("TeleportOptions");options:SetTeleportData({notice=notice})end
	return Teleport:TeleportAsync(Places.LobbyPlaceId,{player},options)
end
return table.freeze(Gateway)
