--!nonstrict
-- Server-only, bounded memory: one bucket and one sequence number per player.
local RequestGuard={}
RequestGuard.__index=RequestGuard
function RequestGuard.new(capacity, refillPerSecond, clock)
	assert(capacity>0 and refillPerSecond>0,"Invalid rate settings")
	return setmetatable({_capacity=capacity,_refill=refillPerSecond,_clock=clock or os.clock,_records={}},RequestGuard)
end
function RequestGuard:Consume(key)
	local now=self._clock()
	local record=self._records[key]
	if not record then
		record={tokens=self._capacity,last=now,lastRequestId=0,ready=false}
		self._records[key]=record
	end
	record.tokens=math.min(self._capacity,record.tokens+math.max(0,now-record.last)*self._refill)
	record.last=now
	if record.tokens<1 then return false end
	record.tokens-=1
	return true
end
function RequestGuard:AcceptId(key,requestId)
	local record=self._records[key]
	if not record or requestId<=record.lastRequestId then return false end
	record.lastRequestId=requestId
	return true
end
function RequestGuard:SetReady(key)
	assert(self._records[key],"Missing request record")
	self._records[key].ready=true
end
function RequestGuard:IsReady(key)
	local record=self._records[key]
	return record~=nil and record.ready==true
end
function RequestGuard:Forget(key)
	self._records[key]=nil
end
function RequestGuard:Destroy()
	table.clear(self._records)
end
return table.freeze(RequestGuard)
