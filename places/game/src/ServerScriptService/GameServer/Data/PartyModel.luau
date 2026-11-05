--!nonstrict
-- Non-yielding party transactions. Friendship is checked by PartyService before Join.
local Util=require(game.ReplicatedStorage.Game.Shared.Utilities.TableUtil)
local V=require(game.ReplicatedStorage.Game.Shared.Utilities.Validation)
local Model={};Model.__index=Model
function Model.new()return setmetatable({_bays={},_membership={},_serial=0},Model)end
function Model:Get(bay)local p=self._bays[bay];return p and Util.DeepFreeze(Util.DeepClone(p))end
function Model:ForUser(id)return self._membership[id]end
function Model:_Changed(p) p.revision+=1;p.ready={};p.state="Open" end
function Model:Join(id,bay,friend,expectedRevision,expectedPartyId)
	if not V.IsInteger(id,-2147483648,9007199254740991) or id==0 or not V.IsInteger(bay,1,4) then return false,"InvalidParty" end
	if self._membership[id] then return false,"AlreadyInParty" end
	local p=self._bays[bay]
	if expectedPartyId and (not p or p.partyId~=expectedPartyId)then return false,"PartyChanged"end
	if p then
		if p.state~="Open" or #p.members>=p.capacity then return false,"PartyUnavailable" end
		if expectedRevision and p.revision~=expectedRevision then return false,"PartyChanged" end
		if p.accessMode=="FriendsOfHost" and not friend then return false,"FriendsOnly" end
		table.insert(p.members,id);self:_Changed(p)
	else
		self._serial+=1;p={partyId="Party_"..self._serial,bayId=bay,hostUserId=id,capacity=4,accessMode="Public",members={id},ready={},state="Open",revision=1}
		self._bays[bay]=p
	end
	self._membership[id]=bay;return true,"Joined"
end
function Model:Leave(id,forced)
	local bay=self._membership[id];local p=bay and self._bays[bay];if not p then return false,"NoParty" end
	if p.state=="Launching" and not forced then return false,"Launching" end
	self._membership[id]=nil;table.remove(p.members,table.find(p.members,id));p.ready[tostring(id)]=nil
	if #p.members==0 then self._bays[bay]=nil
	elseif p.state~="Launching" then p.hostUserId=p.members[1];self:_Changed(p) end
	return true,"Left"
end
function Model:Configure(id,capacity,access)
	local p=self._bays[self._membership[id]]
	if not p or p.hostUserId~=id or p.state~="Open" then return false,"HostOnly" end
	if not V.IsInteger(capacity,1,4) or capacity<#p.members or (access~="Public" and access~="FriendsOfHost") then return false,"InvalidSettings" end
	p.capacity=capacity;p.accessMode=access;self:_Changed(p);return true,"Configured"
end
function Model:Ready(id,value)
	local p=self._bays[self._membership[id]];if not p or p.state~="Open" or type(value)~="boolean" then return false,"PartyUnavailable" end
	p.ready[tostring(id)]=value;p.revision+=1;return true,"ReadyChanged"
end
function Model:Launch(id)
	local p=self._bays[self._membership[id]];if not p or p.hostUserId~=id or p.state~="Open" then return false,"HostOnly" end
	for _,member in p.members do if p.ready[tostring(member)]~=true then return false,"NotEveryoneReady" end end
	p.state="Launching";p.revision+=1
	return true,Util.DeepFreeze(Util.DeepClone(p))
end
function Model:Recover(bay,partyId)
	local p=self._bays[bay];if not p or p.partyId~=partyId or p.state~="Launching" then return false end
	p.hostUserId=p.members[1];self:_Changed(p);return true
end
function Model:Finish(bay,partyId)
	local p=self._bays[bay];if not p or p.partyId~=partyId then return end
	for _,id in p.members do self._membership[id]=nil end;self._bays[bay]=nil
end
return table.freeze(Model)
