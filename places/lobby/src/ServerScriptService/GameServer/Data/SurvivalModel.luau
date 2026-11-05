--!nonstrict
-- Pure life-rule transitions. Time is injected and uses server seconds.
local Config=require(game.ReplicatedStorage.Game.Shared.Config.SurvivalConfig)
local V=require(game.ReplicatedStorage.Game.Shared.Utilities.Validation)
local Model={}
function Model.New()
	return {lifeState="Alive",revivesUsedThisFloor=0,downedDeadline=0,protectionUntil=0}
end
function Model.ValidDamage(d)
	return V.HasExactKeys(d,{targetUserId=true,sourceId=true,damageType=true,lethal=true,bypassDowned=true},5)
		and V.IsInteger(d.targetUserId,-2147483648,9007199254740991) and d.targetUserId~=0
		and V.IsIdentifier(d.sourceId,64) and (d.damageType=="Attack" or d.damageType=="Abyss" or d.damageType=="Consumption")
		and type(d.lethal)=="boolean" and type(d.bypassDowned)=="boolean"
end
function Model.Damage(s,d,now)
	if not Model.ValidDamage(d) then return nil,"InvalidDamage" end
	if s.lifeState~="Alive" then return nil,"NotAlive" end
	if now<s.protectionUntil then return nil,"Protected" end
	if not d.lethal then return nil,"NonlethalIgnored" end
	local nextState=table.clone(s)
	local fatal=d.bypassDowned or d.damageType=="Abyss" or d.damageType=="Consumption" or s.revivesUsedThisFloor>=Config.RevivesPerFloor
	nextState.lifeState=fatal and "Dead" or "Downed"
	nextState.downedDeadline=fatal and 0 or now+Config.DownedSeconds
	nextState.protectionUntil=0
	return nextState,"OK"
end
function Model.Revive(target,rescuer,now)
	if rescuer.lifeState~="Alive" or now<rescuer.protectionUntil then return nil,"RescuerUnavailable" end
	if target.lifeState~="Downed" or now>=target.downedDeadline then return nil,"RescueExpired" end
	if target.revivesUsedThisFloor>=Config.RevivesPerFloor then return nil,"RevivalUsed" end
	local s=table.clone(target);s.lifeState="Alive";s.downedDeadline=0
	s.revivesUsedThisFloor+=1;s.protectionUntil=now+Config.ProtectionSeconds
	return s,"Revived"
end
function Model.Expire(s,now)
	if s.lifeState~="Downed" or now<s.downedDeadline then return nil end
	local result=table.clone(s);result.lifeState="Dead";result.downedDeadline=0;result.protectionUntil=0;return result
end
function Model.Continuation(participants,connected,now)
	local reserved=false
	for key,p in participants do
		if p.lifeState=="Alive" then
			if connected[p.userId] and p.connectionState=="Connected" then return "Continue" end
			if p.connectionState=="Disconnected" and type(p.reconnectDeadline)=="number" and now<p.reconnectDeadline then reserved=true end
		end
	end
	return reserved and "AwaitingReconnect" or "Wipe"
end
return table.freeze(Model)
