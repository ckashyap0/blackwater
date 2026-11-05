--!nonstrict
-- Lobby and descent are different Roblox Places in the same experience.
local C={LobbyPlaceId=97536935253958,GamePlaceId=96605018559143,DefaultStudioRole="Lobby",EnablePlaytestRoom=true}
function C.Resolve(placeId,isStudio,override)
	if isStudio and override then
  assert(override=="Lobby" or override=="Game","Invalid Studio place role");return override
 end
 if placeId==C.LobbyPlaceId then return "Lobby"end
 if C.GamePlaceId>0 and placeId==C.GamePlaceId then return "Game"end
 if isStudio then
		local role=override or C.DefaultStudioRole
		assert(role=="Lobby" or role=="Game","Invalid Studio place role")
		return role
	end
	assert(C.GamePlaceId==0 or C.GamePlaceId~=C.LobbyPlaceId,"Lobby and Game Place IDs must differ")
	if placeId==C.LobbyPlaceId then return "Lobby" end
	if C.GamePlaceId>0 and placeId==C.GamePlaceId then return "Game" end
	error("Unconfigured Place ID; set PlaceConfig before publishing")
end
return table.freeze(C)
