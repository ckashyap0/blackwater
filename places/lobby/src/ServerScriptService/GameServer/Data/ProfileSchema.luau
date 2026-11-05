--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local V=require(Shared.Utilities.Validation)
local Freeze=require(Shared.Utilities.TableUtil).DeepFreeze
local Schema={}
Schema.Version=1
Schema.MaxCurrency=2147483647
Schema.ReceiptLimit=2048
Schema.ReceiptRetentionSeconds=30*24*60*60
Schema.PreferenceKeys=table.freeze({reducedFlashing=true,reducedCameraMotion=true,captionsEnabled=true})
Schema.CosmeticSlots=table.freeze({Flashlight=true,ElevatorDecoration=true})
local profileKeys={schemaVersion=true,currencyBalance=true,ownedCosmeticIds=true,equippedCosmeticIds=true,
	discoveredLoreIds=true,standardCompletionCount=true,hardModeUnlocked=true,
	accessibilityPreferences=true,processedRewardReceipts=true}
local receiptKeys={runId=true,userId=true,milestoneId=true,occurredAt=true,amount=true}
local milestones={Floor05=true,Floor04=true,Floor03=true,Floor02=true,Floor01=true,Escape=true,Completion=true}
function Schema.ValidUserId(userId)
	return V.IsInteger(userId,-2147483648,9007199254740991) and userId~=0
end
function Schema.UserKey(userId)
	assert(Schema.ValidUserId(userId),"InvalidUserId")
	return "Player_"..tostring(userId)
end
function Schema.New()
	return {schemaVersion=Schema.Version,currencyBalance=0,ownedCosmeticIds={},equippedCosmeticIds={},
		discoveredLoreIds={},standardCompletionCount=0,hardModeUnlocked=false,
		accessibilityPreferences={reducedFlashing=false,reducedCameraMotion=false,captionsEnabled=true},
		processedRewardReceipts={}}
end
local function validSet(value,maximum)
	if type(value)~="table" or getmetatable(value)~=nil then return false end
	local count=0
	for key,flag in value do
		count+=1
		if count>maximum or not V.IsIdentifier(key,64) or flag~=true then return false end
	end
	return true
end
function Schema.ValidateReceipt(receipt)
	return V.HasExactKeys(receipt,receiptKeys,6)
		and V.IsIdentifier(receipt.runId,64) and Schema.ValidUserId(receipt.userId)
		and type(receipt.milestoneId)=="string" and milestones[receipt.milestoneId]==true
		and V.IsInteger(receipt.occurredAt,0,9007199254740991)
		and V.IsInteger(receipt.amount,0,Schema.MaxCurrency)
end
function Schema.ReceiptId(receipt)
	return receipt.runId..":"..tostring(receipt.userId)..":"..receipt.milestoneId
end
function Schema.Validate(profile,userId)
	if not V.HasExactKeys(profile,profileKeys,9) then return false,"InvalidProfileShape" end
	if profile.schemaVersion~=Schema.Version then return false,"UnsupportedSchemaVersion" end
	if not V.IsInteger(profile.currencyBalance,0,Schema.MaxCurrency)
		or not V.IsInteger(profile.standardCompletionCount,0,2147483647)
		or type(profile.hardModeUnlocked)~="boolean" then return false,"InvalidProfileValues" end
	if not validSet(profile.ownedCosmeticIds,1024) or not validSet(profile.discoveredLoreIds,2048) then
		return false,"InvalidCollection"
	end
	if not V.HasExactKeys(profile.equippedCosmeticIds,Schema.CosmeticSlots,2) then return false,"InvalidEquipment" end
	for _,id in profile.equippedCosmeticIds do
		if not V.IsIdentifier(id,64) or profile.ownedCosmeticIds[id]~=true then return false,"UnownedEquipment" end
	end
	if not V.HasExactKeys(profile.accessibilityPreferences,Schema.PreferenceKeys,3) then return false,"InvalidPreferences" end
	for key in Schema.PreferenceKeys do
		if type(profile.accessibilityPreferences[key])~="boolean" then return false,"InvalidPreferences" end
	end
	if type(profile.processedRewardReceipts)~="table" or getmetatable(profile.processedRewardReceipts)~=nil then
		return false,"InvalidReceipts"
	end
	local count=0
	for id,receipt in profile.processedRewardReceipts do
		count+=1
		if count>Schema.ReceiptLimit or not Schema.ValidateReceipt(receipt) or id~=Schema.ReceiptId(receipt)
			or (userId~=nil and receipt.userId~=userId) then
			return false,"InvalidReceipts"
		end
	end
	return true,"OK"
end
function Schema.AssertValid(profile,userId)
	local ok,reason=Schema.Validate(profile,userId)
	assert(ok,reason)
	return profile
end
return Freeze(Schema)
