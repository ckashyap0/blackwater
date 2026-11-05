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
function Gateway.Return(player)return Teleport:TeleportAsync(Places.LobbyPlaceId,{player})end
return table.freeze(Gateway)
