--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local V=require(Shared.Utilities.Validation)
local Util=require(Shared.Utilities.TableUtil)
local Economy=require(Shared.Config.EconomyConfig)
local Schema=require(script.Parent.ProfileSchema)
local Repository={}
Repository.__index=Repository
local amounts={Floor05=Economy.FloorRewards[5],Floor04=Economy.FloorRewards[4],
	Floor03=Economy.FloorRewards[3],Floor02=Economy.FloorRewards[2],Floor01=Economy.FloorRewards[1],
	Escape=Economy.EscapeBonus,Completion=0}
local function result(ok,value,code)
	if not ok then return {ok=false,code=tostring(value)} end
	return {ok=true,code=code or "OK",profile=Util.DeepFreeze(Util.DeepClone(value))}
end
function Repository.new(adapter,clock)
	assert(type(adapter.Read)=="function" and type(adapter.Update)=="function","Invalid storage adapter")
	return setmetatable({_store=adapter,_clock=clock or os.time},Repository)
end
function Repository:Load(userId)
	if not Schema.ValidUserId(userId) then return {ok=false,code="InvalidUserId"} end
	local key=Schema.UserKey(userId)
	local ok,current=self._store:Read(key)
	if not ok then return result(false,current) end
	if current~=nil then
		local valid,reason=Schema.Validate(current,userId)
		if not valid then return result(false,reason) end
		return result(true,current,"Loaded")
	end
	local updated,value,code=self._store:Update(key,function(latest)
		if latest~=nil then Schema.AssertValid(latest,userId);return latest,"Loaded" end
		return Schema.New(),"Created"
	end)
	return result(updated,value,code)
end
function Repository:_Update(userId,transform)
	if not Schema.ValidUserId(userId) then return {ok=false,code="InvalidUserId"} end
	local ok,value,code=self._store:Update(Schema.UserKey(userId),function(current)
		if current==nil then error("ProfileNotLoaded",0) end
		Schema.AssertValid(current,userId)
		local nextProfile,status=transform(current)
		if nextProfile~=nil then Schema.AssertValid(nextProfile,userId) end
		return nextProfile,status
	end)
	return result(ok,value,code)
end
function Repository:SavePreferences(userId,patch)
	if not V.HasExactKeys(patch,Schema.PreferenceKeys,3) then return {ok=false,code="InvalidPreferences"} end
	for _,value in patch do if type(value)~="boolean" then return {ok=false,code="InvalidPreferences"} end end
	local safe=Util.DeepClone(patch)
	return self:_Update(userId,function(profile)
		for key,value in safe do profile.accessibilityPreferences[key]=value end
		return profile,"PreferencesSaved"
	end)
end
function Repository:GrantCosmetic(userId,id)
	if not V.IsIdentifier(id,64) then return {ok=false,code="InvalidCosmeticId"} end
	return self:_Update(userId,function(profile)
		profile.ownedCosmeticIds[id]=true
		return profile,"CosmeticGranted"
	end)
end
function Repository:EquipCosmetic(userId,slot,id)
	if type(slot)~="string" or not Schema.CosmeticSlots[slot] or not V.IsIdentifier(id,64) then
		return {ok=false,code="InvalidEquipment"}
	end
	return self:_Update(userId,function(profile)
		if profile.ownedCosmeticIds[id]~=true then error("UnownedEquipment",0) end
		profile.equippedCosmeticIds[slot]=id
		return profile,"CosmeticEquipped"
	end)
end
function Repository:RecordDiscovery(userId,id)
	if not V.IsIdentifier(id,64) then return {ok=false,code="InvalidLoreId"} end
	return self:_Update(userId,function(profile)
		profile.discoveredLoreIds[id]=true
		return profile,"DiscoveryRecorded"
	end)
end
function Repository:ApplyAward(userId,request)
	local keys={runId=true,milestoneId=true,occurredAt=true}
	if not Schema.ValidUserId(userId) or not V.HasExactKeys(request,keys,3)
		or not V.IsIdentifier(request.runId,64) or type(request.milestoneId)~="string"
		or amounts[request.milestoneId]==nil or not V.IsInteger(request.occurredAt,0,9007199254740991) then
		return {ok=false,code="InvalidAward"}
	end
	local now=self._clock()
	if request.occurredAt>now then return {ok=false,code="FutureReceipt"} end
	if request.occurredAt<now-Schema.ReceiptRetentionSeconds then return {ok=false,code="ReceiptExpired"} end
	-- occurredAt belongs to the server's immutable milestone; retries must preserve it.
	local receipt={runId=request.runId,userId=userId,milestoneId=request.milestoneId,
		occurredAt=request.occurredAt,amount=amounts[request.milestoneId]}
	local id=Schema.ReceiptId(receipt)
	return self:_Update(userId,function(profile)
		local previous=profile.processedRewardReceipts[id]
		if previous then
			if previous.amount~=receipt.amount or previous.occurredAt~=receipt.occurredAt then
				error("ReceiptConflict",0)
			end
			return nil,"AlreadyApplied"
		end
		local count=0
		for key,saved in profile.processedRewardReceipts do
			if saved.occurredAt<now-Schema.ReceiptRetentionSeconds then
				profile.processedRewardReceipts[key]=nil
			else count+=1 end
		end
		-- Never evict an unexpired receipt to make space; that would allow duplicate awards.
		if count>=Schema.ReceiptLimit then error("ReceiptCapacityReached",0) end
		profile.currencyBalance+=receipt.amount
		if receipt.milestoneId=="Completion" then
			profile.standardCompletionCount+=1
			profile.hardModeUnlocked=true
		end
		profile.processedRewardReceipts[id]=receipt
		return profile,"AwardApplied"
	end)
end
function Repository:RecordCompletion(userId,runId,occurredAt)
	return self:ApplyAward(userId,{runId=runId,milestoneId="Completion",occurredAt=occurredAt})
end
return table.freeze(Repository)
