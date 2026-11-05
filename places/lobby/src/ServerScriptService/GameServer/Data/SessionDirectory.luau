--!nonstrict
-- Only server code may access this map. Access codes never leave this module's callers.
local Util=require(game.ReplicatedStorage.Game.Shared.Utilities.TableUtil)
local Policy=require(script.Parent.SessionPolicy)
local Directory={};Directory.__index=Directory
function Directory.new(map,clock)
	return setmetatable({_map=map or game:GetService("MemoryStoreService"):GetHashMap("EH_Sessions_v1"),_clock=clock or os.time},Directory)
end
function Directory:Get(id)return self._map:GetAsync("s:"..id)end
function Directory:Create(id,roster,accessCode,privateId,meta)
	local now=self._clock();local ticket={id=id,roster=table.clone(roster),members={},accessCode=accessCode,privateId=privateId,
		status="Allocating",createdAt=now,arrivalDeadline=now+45,heartbeat=now,arrivals=0,resume=meta and meta.resume==true or nil}
	for _,uid in roster do ticket.members[tostring(uid)]={state="Pending",deadline=now+165} end
	self._map:SetAsync("s:"..id,ticket,7200)
	local ok,err=pcall(function()
		for _,uid in roster do
			-- A pointer left over from an earlier run (the player left it, dropped, or its server shut
			-- down) is replaced: someone standing in the lobby launching a new descent is not in that run
			-- any more. Only a launch that is still in flight (not yet arrived) keeps its reservation.
			-- Refusing every old pointer used to block all launches until the old pointer expired.
			local replaceable=true
			local index=self._map:GetAsync("u:"..uid)
			if index and index.id~=id and index.expires>now then
				local other=self._map:GetAsync("s:"..index.id)
				replaceable=not other or (other.status~="Allocating" and other.status~="Waiting")
			end
			local result=self._map:UpdateAsync("u:"..uid,function(old)
				if old and old.id~=id and old.expires>now and not replaceable then return nil end
				return {id=id,expires=now+165}
			end,7200)
			assert(result and result.id==id,"ExistingSession")
		end
		self._map:UpdateAsync("s:"..id,function(old) if not old or old.status~="Allocating" then return nil end old.status="Waiting";return old end,7200)
	end)
	if not ok then self:End(id);error(tostring(err)) end
	return self:Get(id)
end
function Directory:Claim(id,uid,privateId,jobId)
	local reason="Unavailable";local accepted=false;local now=self._clock()
	local result=self._map:UpdateAsync("s:"..id,function(old)
		accepted=false
		local valid,code=Policy.CanJoin(old,uid,privateId,jobId,now);reason=code
		if not valid then return nil end
		old.ownerJob=jobId;old.heartbeat=now;old.members[tostring(uid)].state="Joining";old.arrivals+=1;accepted=true;return old
	end,7200)
	if not accepted or not result then return nil,reason end
	return result,"Accepted"
end
function Directory:Publish(id,jobId,members,ended)
	local now=self._clock()
	local result=self._map:UpdateAsync("s:"..id,function(old)
		if not old or old.ownerJob~=jobId or old.status=="Ended" then return nil end
		old.heartbeat=now;old.status=ended and "Ended" or "Active"
		for uid,m in members do if old.members[uid] then old.members[uid]=Util.DeepClone(m) end end
		return old
	end,7200)
	if not result then return false end
	for _,uid in result.roster do
		self._map:UpdateAsync("u:"..uid,function(old)
			if not old or old.id~=id then return nil end
			local member=result.members[tostring(uid)]
			old.expires=(ended or (member and member.state=="Abandoned")) and 0 or now+165;return old
		end,7200)
	end
	return true
end
function Directory:ForUser(uid)
	local index=self._map:GetAsync("u:"..uid)
	if not index or index.expires<=self._clock() then return nil end
	return self:Get(index.id)
end
-- Clear one player's pointer to an old run (after they rejoin, resume or dismiss it).
function Directory:Forget(uid,id)
	self._map:UpdateAsync("u:"..uid,function(old)
		if not old or (id and old.id~=id) then return nil end
		old.expires=0;return old
	end,7200)
end
function Directory:End(id,onlyIfUnclaimed)
	local result=self._map:UpdateAsync("s:"..id,function(old)
		if not old or (onlyIfUnclaimed and old.ownerJob) then return nil end
		old.status="Ended";return old
	end,7200)
	if result and result.status=="Ended" then
		for _,uid in result.roster do self._map:UpdateAsync("u:"..uid,function(old)if not old or old.id~=id then return nil end old.expires=0;return old end,7200) end
	end
	return result and result.status=="Ended"
end
return table.freeze(Directory)
