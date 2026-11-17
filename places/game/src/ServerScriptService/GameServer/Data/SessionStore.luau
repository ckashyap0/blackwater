--!nonstrict
-- (Nov 16, Ryan: 'connection problem for everyone in the lobby') The session directory (who is launching into
-- which game server) lived only in Roblox MemoryStoreService. Tested from a real Roblox server (Open Cloud Luau
-- execution, Nov 16): MemoryStore reads were failing for this experience with "InternalError: Unknown Error"
-- - Roblox's side, not the game's - and every launch failed with "Connection problem".
-- This store has the same calls as a MemoryStore hash map (GetAsync / SetAsync / UpdateAsync / RemoveAsync) but
-- keeps a copy of every entry in a DataStore too:
--  * reads try MemoryStore first; if it errors or has nothing, the DataStore copy is used;
--  * writes go to both (it only fails if BOTH are down);
--  * UpdateAsync reads, transforms and writes back under a per-key lock on this server.
-- The tickets carry their own expiry times / heartbeats, so an old DataStore copy is never mistaken for a live one.
local MemoryStoreService = game:GetService('MemoryStoreService')
local DataStoreService = game:GetService('DataStoreService')
local Store = {}; Store.__index = Store

function Store.new(name)
	local ms, ds
	pcall(function() ms = MemoryStoreService:GetHashMap(name) end)
	pcall(function() ds = DataStoreService:GetDataStore(name .. '_Backup') end)
	return setmetatable({_ms = ms, _ds = ds, _locks = {}, _name = name}, Store)
end

local function note(self, what, err)
	local now = os.clock()
	if now - (self._warned or 0) > 30 then
		self._warned = now
		warn('[ElevatorHorror] ' .. self._name .. ' ' .. what .. ' fell back to the DataStore copy: ' .. tostring(err))
	end
end

function Store:GetAsync(key)
	local ok, v = false, nil
	if self._ms then ok, v = pcall(function() return self._ms:GetAsync(key) end) end
	if ok and v ~= nil then return v end
	if not ok and self._ms then note(self, 'read', v) end
	if self._ds then
		local ok2, v2 = pcall(function() return self._ds:GetAsync(key) end)
		if ok2 then return v2 end
		if not ok then error(tostring(v) .. ' / ' .. tostring(v2)) end
		return nil -- (MemoryStore answered: there is no entry)
	end
	if not ok then error(v) end
	return nil
end

function Store:SetAsync(key, value, ttl)
	local okM = self._ms and pcall(function() self._ms:SetAsync(key, value, ttl or 3600) end)
	local okD = self._ds and pcall(function() self._ds:SetAsync(key, value) end)
	if not okM and not okD then error('SessionStoreUnavailable') end
	if not okM then note(self, 'write', 'MemoryStore write failed') end
	return true
end

function Store:UpdateAsync(key, transform, ttl)
	while self._locks[key] do task.wait() end
	self._locks[key] = true
	local ok, result = pcall(function()
		local current = self:GetAsync(key)
		local new = transform(current)
		if new == nil then return nil end
		self:SetAsync(key, new, ttl)
		return new
	end)
	self._locks[key] = nil
	if not ok then error(result) end
	return result
end

function Store:RemoveAsync(key)
	if self._ms then pcall(function() self._ms:RemoveAsync(key) end) end
	if self._ds then pcall(function() self._ds:RemoveAsync(key) end) end
end

return Store
