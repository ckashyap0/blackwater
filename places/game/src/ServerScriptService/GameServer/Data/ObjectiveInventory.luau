--!nonstrict
-- Synchronous transactions: no yield between validation and changing ownership.
local Util=require(game.ReplicatedStorage.Game.Shared.Utilities.TableUtil)
local V=require(game.ReplicatedStorage.Game.Shared.Utilities.Validation)
local Inventory={};Inventory.__index=Inventory
function Inventory.new() return setmetatable({_items={},_carriers={},_sockets={}},Inventory) end
function Inventory:RegisterItem(id,kind,scope)
	assert(V.IsIdentifier(id,64) and V.IsIdentifier(kind,48) and V.IsIdentifier(scope,64),"Invalid item")
	assert(not self._items[id],"Duplicate item")
	local count=0;for _ in self._items do count+=1 end;assert(count<64,"Item limit")
	self._items[id]={id=id,kind=kind,scope=scope,state="AtSpawn",owner=false,socket=false,revision=1}
end
function Inventory:RegisterSocket(id,kind,scope)
	assert(V.IsIdentifier(id,64) and V.IsIdentifier(kind,48) and V.IsIdentifier(scope,64),"Invalid socket")
	assert(not self._sockets[id],"Duplicate socket")
	local count=0;for _ in self._sockets do count+=1 end;assert(count<64,"Socket limit")
	self._sockets[id]={kind=kind,scope=scope,item=false}
end
function Inventory:Get(id) local item=self._items[id];return item and Util.DeepFreeze(Util.DeepClone(item)) or nil end
function Inventory:Carried(userId) return self._carriers[userId] end
function Inventory:Pickup(userId,id)
	if not V.IsInteger(userId,-2147483648,9007199254740991) or userId==0 then return false,"InvalidPlayer" end
	local item=self._items[id]
	if not item or (item.state~="AtSpawn" and item.state~="Dropped") then return false,"ItemUnavailable" end
	if self._carriers[userId] then return false,"AlreadyCarrying" end
	item.state="Carried";item.owner=userId;item.revision+=1;self._carriers[userId]=id
	return true,"PickedUp"
end
function Inventory:Drop(userId)
	local id=self._carriers[userId];if not id then return false,"NothingCarried" end
	local item=self._items[id];assert(item and item.state=="Carried" and item.owner==userId,"Ownership invariant")
	self._carriers[userId]=nil;item.owner=false;item.state="Dropped";item.revision+=1
	return true,id
end
function Inventory:Install(userId,socketId)
	local socket=self._sockets[socketId];local item=self._items[self._carriers[userId]]
	if not socket then return false,"UnknownSocket" end
	if socket.item then return false,"SocketOccupied" end
	if not item then return false,"NothingCarried" end
	if item.kind~=socket.kind then return false,"WrongItemKind" end
	if item.scope~=socket.scope then return false,"WrongFloor" end
	self._carriers[userId]=nil;item.owner=false;item.state="Installed";item.socket=socketId;item.revision+=1;socket.item=item.id
	return true,item.id
end
function Inventory:RetireScope(scope)
	local retired={}
	for id,item in self._items do if item.scope==scope then
		if item.owner then self._carriers[item.owner]=nil end
		item.state="Retired";item.owner=false;item.revision+=1;table.insert(retired,id)
	end end
	for id,socket in self._sockets do if socket.scope==scope then self._sockets[id]=nil end end
	return retired
end
function Inventory:ForgetRetired(scope)
	for id,item in self._items do if item.scope==scope and item.state=="Retired" then self._items[id]=nil end end
end
return table.freeze(Inventory)
