--!nonstrict
-- Development adapter. This is an ordinary server-memory table, NOT Roblox MemoryStoreService.
-- Contract: Read(key) -> ok,value/error; Update(key,nonYieldingTransform) -> ok,value/error,metadata.
local Clone=require(game:GetService("ReplicatedStorage").Game.Shared.Utilities.TableUtil).DeepClone
local Store={}
Store.__index=Store
function Store.new(initial)
	return setmetatable({_records=Clone(initial or {}),_locks={},_faults={}},Store)
end
function Store:FailNext(operation,count)
	assert(operation=="Read" or operation=="Update","Unknown operation")
	assert(type(count)=="number" and count>=1 and count%1==0,"Invalid failure count")
	self._faults[operation]=count
end
function Store:_Fail(operation)
	local remaining=self._faults[operation] or 0
	if remaining<=0 then return false end
	self._faults[operation]=remaining-1
	return true
end
function Store:Read(key)
	if self:_Fail("Read") then return false,"StorageUnavailable" end
	return true,Clone(self._records[key])
end
function Store:Update(key,transform)
	if self:_Fail("Update") then return false,"StorageUnavailable" end
	if self._locks[key] then return false,"UpdateBusy" end
	self._locks[key]=true
	local worker=coroutine.create(function() return transform(Clone(self._records[key])) end)
	local ok,nextValue,metadata=coroutine.resume(worker)
	if coroutine.status(worker)~="dead" then
		coroutine.close(worker); self._locks[key]=nil
		return false,"TransformYielded"
	end
	if not ok then self._locks[key]=nil; return false,tostring(nextValue) end
	if nextValue==nil then
		self._locks[key]=nil
		return true,Clone(self._records[key]),metadata or "Cancelled"
	end
	if type(nextValue)~="table" then self._locks[key]=nil;return false,"InvalidStoredValue" end
	self._records[key]=Clone(nextValue)
	self._locks[key]=nil
	return true,Clone(self._records[key]),metadata
end
return table.freeze(Store)
