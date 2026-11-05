--!nonstrict
-- Transient server state only. Never stored as a player profile or a saved checkpoint.
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local V=require(Shared.Utilities.Validation)
local Movement=require(Shared.Config.MovementConfig)
local Schema=require(script.Parent.ProfileSchema)
local Util=require(Shared.Utilities.TableUtil)
local Record={}
Record.Version=1
function Record.New(runId,roster,difficulty,seed,startedAt)
	assert(V.IsIdentifier(runId,64),"InvalidRunId")
	assert(difficulty=="Standard","Only standard difficulty is implemented")
	assert(V.IsInteger(seed,0,2147483647),"InvalidSeed")
	assert(V.IsInteger(startedAt,0,9007199254740991),"InvalidStartTime")
	assert(type(roster)=="table" and getmetatable(roster)==nil,"InvalidRoster")
	local count=0
	for key in roster do
		count+=1
		assert(V.IsInteger(key,1,4),"InvalidRosterIndex")
	end
	assert(count>=1 and count<=4,"InvalidRosterSize")
	local originalRoster={}
	local participants={}
	for index=1,count do
		local userId=roster[index]
		assert(Schema.ValidUserId(userId),"InvalidRosterUser")
		local key=tostring(userId)
		assert(not participants[key],"DuplicateRosterUser")
		originalRoster[index]=userId
		participants[key]={
			userId=userId,connectionState="Connected",lifeState="Alive",lastSafeTransform=nil,
			stamina=Movement.MaxStamina,revivesUsedThisFloor=0,downedDeadline=nil,carriedObjectiveItemId=nil,
			completedMilestones={},reconnectDeadline=nil,escaped=false,
		}
	end
	return {runId=runId,schemaVersion=Record.Version,phase="Initializing",difficulty=difficulty,seed=seed,
		originalRoster=Util.DeepFreeze(originalRoster),currentFloorNumber=5,currentFloorInstanceId=nil,
		participants=participants,completedFloorNumbers={},objectiveSnapshot={},pendingRewardReceipts={},
		startedAt=startedAt,result=nil,suspensionReason=nil}
end
return table.freeze(Record)
