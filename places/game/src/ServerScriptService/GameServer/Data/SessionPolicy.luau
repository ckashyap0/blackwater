--!nonstrict
local Policy={}
function Policy.CanJoin(ticket,userId,privateId,jobId,now)
	if type(ticket)~="table" or ticket.status=="Ended" or ticket.status=="Allocating" then return false,"SessionClosed" end
	if ticket.privateId~=privateId or privateId=="" then return false,"WrongServer" end
	if ticket.ownerJob and ticket.ownerJob~=jobId then return false,"WrongServerProcess" end
	if now>ticket.heartbeat+60 then return false,"SessionUnavailable" end
	local member=ticket.members[tostring(userId)]
	if not member or (member.state~="Pending" and member.state~="Disconnected") then return false,"NotReserved" end
	if now>=member.deadline then return false,"ReservationExpired" end
	return true,"OK"
end
function Policy.CanReconnect(ticket,userId,now)
	if not ticket or ticket.status=="Ended" or ticket.status=="Allocating" or now>ticket.heartbeat+60 then return false end
	local m=ticket.members[tostring(userId)]
	return m and (m.state=="Pending" or m.state=="Disconnected") and now<m.deadline
end
-- What the lobby offers this player: "Rejoin" while their crew's server is still running the
-- run and holding their place, otherwise nothing.
function Policy.ConnectionExpired(participant,now)
	return participant.connectionState=="Disconnected" and type(participant.reconnectDeadline)=="number" and now>=participant.reconnectDeadline
end
return table.freeze(Policy)
