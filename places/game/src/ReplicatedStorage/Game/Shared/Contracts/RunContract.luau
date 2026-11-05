--!nonstrict
local Shared=script.Parent.Parent
local V=require(Shared.Utilities.Validation)
local Freeze=require(Shared.Utilities.TableUtil).DeepFreeze
local Constants=require(Shared.Constants)
local Contract={}
local phases={}
for _,phase in Constants.RunPhases do phases[phase]=true end
Contract.Actions=Freeze({
	Queue={Initializing=true},BeginIntro={WaitingForRoster=true},
	PrepareFloor={Intro=true,Transit=true},ActivateFloor={PreparingFloor=true},
	CompleteObjective={FloorActive=true},BeginDeparture={FloorActive=true},
	CleanupResult={Departing=true},Escape={FinaleActive=true},
	Wipe={Intro=true,PreparingFloor=true,FloorActive=true,FinaleActive=true,Departing=true,Transit=true},
	TechnicalFailure={Initializing=true,WaitingForRoster=true,Intro=true,PreparingFloor=true,
		FloorActive=true,Departing=true,Transit=true,FinaleActive=true},
	Resolve={Resolving=true},Close={Completed=true,Failed=true},
})
Contract.FailureReasons=Freeze({LoadFailed=true,CleanupFailed=true,InternalError=true,RosterUnavailable=true})
function Contract.ValidateToken(token)
	return V.HasExactKeys(token,{runId=true,revision=true,expectedPhase=true,floorInstanceId=true},4)
		and V.IsIdentifier(token.runId,64) and V.IsInteger(token.revision,1,2147483647)
		and type(token.expectedPhase)=="string" and phases[token.expectedPhase]==true
		and (token.floorInstanceId==false or V.IsIdentifier(token.floorInstanceId,96))
end
function Contract.ValidateCommand(command)
	if not V.HasExactKeys(command,{token=true,action=true,payload=true},3)
		or not Contract.ValidateToken(command.token) or type(command.action)~="string"
		or not Contract.Actions[command.action] then return false end
	local allowed={}
	local maximum=0
	if command.action=="CleanupResult" then allowed={succeeded=true};maximum=1
	elseif command.action=="Escape" then allowed={escapedUserIds=true};maximum=1
	elseif command.action=="TechnicalFailure" then allowed={reason=true};maximum=1 end
	if not V.HasExactKeys(command.payload,allowed,maximum) then return false end
	if command.action=="CleanupResult" then return type(command.payload.succeeded)=="boolean" end
	if command.action=="TechnicalFailure" then
		return type(command.payload.reason)=="string" and Contract.FailureReasons[command.payload.reason]==true
	end
	if command.action=="Escape" then
		local ids=command.payload.escapedUserIds
		if type(ids)~="table" or getmetatable(ids)~=nil then return false end
		local count=0;local seen={}
		for key,id in ids do
			count+=1
			if count>4 or not V.IsInteger(key,1,4) or not V.IsInteger(id,-2147483648,9007199254740991)
				or id==0 or seen[id] then return false end
			seen[id]=true
		end
		if count==0 then return false end
		for i=1,count do if ids[i]==nil then return false end end
	end
	return true
end
function Contract.ValidateView(view)
	if view==false then return true end
	local keys={runId=true,revision=true,phase=true,floorNumber=true,floorInstanceId=true,
		objectiveComplete=true,completedFloors=true,result=true}
	if not V.HasExactKeys(view,keys,8) then return false end
	if not Contract.ValidateToken({runId=view.runId,revision=view.revision,expectedPhase=view.phase,
		floorInstanceId=view.floorInstanceId}) then return false end
	if not V.IsInteger(view.floorNumber,1,5) or type(view.objectiveComplete)~="boolean" then return false end
	if type(view.completedFloors)~="table" or getmetatable(view.completedFloors)~=nil then return false end
	local count=0
	for index,floor in view.completedFloors do
		count+=1
		if count>5 or not V.IsInteger(index,1,5) or floor~=6-index then return false end
	end
	for i=1,count do if view.completedFloors[i]==nil then return false end end
	if view.result~=false then
		if not V.HasExactKeys(view.result,{outcome=true,reason=true,resolvedAt=true,escapedUserIds=true},4) then return false end
		if view.result.outcome~="Completed" and view.result.outcome~="Failed" then return false end
		if not V.IsIdentifier(view.result.reason,64) or not V.IsInteger(view.result.resolvedAt,0,9007199254740991) then return false end
		local ids=view.result.escapedUserIds
		if type(ids)~="table" or getmetatable(ids)~=nil then return false end
		local n=0;local seen={}
		for key,id in ids do
			n+=1
			if n>4 or not V.IsInteger(key,1,4) or not V.IsInteger(id,-2147483648,9007199254740991)
				or id==0 or seen[id] then return false end
			seen[id]=true
		end
		for i=1,n do if ids[i]==nil then return false end end
	end
	return true
end
return Freeze(Contract)
