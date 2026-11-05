--!nonstrict
-- Pure server authority: no remotes, waits, geometry, rewards, or player-data writes.
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Util=require(Shared.Utilities.TableUtil)
local Contract=require(Shared.Contracts.RunContract)
local RunRecord=require(script.Parent.RunRecord)
local Machine={}
Machine.__index=Machine
function Machine.new(runId,roster,difficulty,seed,clock)
	clock=clock or os.time
	return setmetatable({_record=RunRecord.New(runId,roster,difficulty,seed,clock()),
		_revision=1,_clock=clock,_destroyed=false},Machine)
end
function Machine:GetToken()
	local record=self._record
	return Util.DeepFreeze({runId=record.runId,revision=self._revision,expectedPhase=record.phase,
		floorInstanceId=record.currentFloorInstanceId or false})
end
function Machine:GetSnapshot()
	local copy=Util.DeepClone(self._record)
	copy.revision=self._revision
	return Util.DeepFreeze(copy)
end
function Machine:GetView()
	local r=self._record
	return Util.DeepFreeze({runId=r.runId,revision=self._revision,phase=r.phase,floorNumber=r.currentFloorNumber,
		floorInstanceId=r.currentFloorInstanceId or false,
		objectiveComplete=r.objectiveSnapshot.status=="Completed",
		completedFloors=Util.DeepClone(r.completedFloorNumbers),result=Util.DeepClone(r.result) or false})
end
function Machine:IsParticipant(userId)
	return self._record.participants[tostring(userId)]~=nil
end
function Machine:Matches(token)
	if not Contract.ValidateToken(token) then return false,"InvalidToken" end
	local current=self:GetToken()
	if token.runId~=current.runId then return false,"WrongRun" end
	if token.floorInstanceId~=current.floorInstanceId then return false,"StaleFloor" end
	if token.revision~=current.revision then return false,"StaleRevision" end
	if token.expectedPhase~=current.expectedPhase then return false,"UnexpectedPhase" end
	return true,"OK"
end
function Machine:Dispatch(command)
	if self._destroyed then return {ok=false,code="Destroyed"} end
	if not Contract.ValidateCommand(command) then return {ok=false,code="InvalidCommand"} end
	local matches,reason=self:Matches(command.token)
	if not matches then return {ok=false,code=reason} end
	local action,payload=command.action,command.payload
	if not Contract.Actions[action][self._record.phase] then return {ok=false,code="IllegalTransition"} end
	local draft=Util.DeepClone(self._record)
	local function fail(reasonCode)
		draft.phase="Resolving"
		draft.pendingResult={outcome="Failed",reason=reasonCode,escapedUserIds={}}
	end
	local ok,code=pcall(function()
		if action=="Queue" then draft.phase="WaitingForRoster"
		elseif action=="BeginIntro" then draft.phase="Intro"
		elseif action=="PrepareFloor" then
			if draft.phase=="Transit" then
				if draft.currentFloorNumber<=1 then return "NoNextFloor" end
				draft.currentFloorNumber-=1
			end
			draft.currentFloorInstanceId=draft.runId.."-F"..draft.currentFloorNumber
			draft.objectiveSnapshot={status="Active"}
			draft.phase="PreparingFloor"
		elseif action=="ActivateFloor" then
			draft.phase=draft.currentFloorNumber==1 and "FinaleActive" or "FloorActive"
		elseif action=="CompleteObjective" then
			if draft.objectiveSnapshot.status=="Completed" then return "ObjectiveAlreadyComplete" end
			draft.objectiveSnapshot.status="Completed"
		elseif action=="BeginDeparture" then
			if draft.objectiveSnapshot.status~="Completed" then return "ObjectiveIncomplete" end
			draft.phase="Departing"
		elseif action=="CleanupResult" then
			if not payload.succeeded then fail("CleanupFailed")
			else
				table.insert(draft.completedFloorNumbers,draft.currentFloorNumber)
				draft.phase="Transit"
			end
		elseif action=="Escape" then
			for _,userId in payload.escapedUserIds do
				local participant=draft.participants[tostring(userId)]
				if not participant or participant.lifeState~="Alive" or participant.connectionState~="Connected" then
					return "InvalidEscapeParticipant"
				end
			end
			draft.phase="Resolving"
			draft.pendingResult={outcome="Completed",reason="Escaped",
				escapedUserIds=Util.DeepClone(payload.escapedUserIds)}
		elseif action=="Wipe" then fail("TeamWipe")
		elseif action=="TechnicalFailure" then fail(payload.reason)
		elseif action=="Resolve" then
			if draft.result~=nil then return "AlreadyResolved" end
			local pending=draft.pendingResult
			if not pending then return "MissingOutcome" end
			draft.result=Util.DeepClone(pending)
			draft.result.resolvedAt=self._clock()
			draft.pendingResult=nil
			draft.phase=draft.result.outcome
			if draft.phase=="Completed" then
				draft.objectiveSnapshot.status="Completed"
				table.insert(draft.completedFloorNumbers,1)
				for _,userId in draft.result.escapedUserIds do
					local participant=draft.participants[tostring(userId)]
					participant.escaped=true;participant.lifeState="Escaped"
				end
			end
		elseif action=="Close" then draft.phase="Closing"
		end
		return "OK"
	end)
	if not ok then return {ok=false,code="TransitionError",detail=tostring(code)} end
	if code~="OK" then return {ok=false,code=code} end
	Util.DeepFreeze(draft.originalRoster)
	self._record=draft
	self._revision+=1
	return {ok=true,code="OK",token=self:GetToken(),view=self:GetView()}
end
-- Server-only survival mirror. No client action exposes this method.
function Machine:SetParticipantSurvival(runId,userId,state)
	if self._destroyed or runId~=self._record.runId then return false end
	local p=self._record.participants[tostring(userId)];if not p then return false end
	if state.lifeState~="Alive" and state.lifeState~="Downed" and state.lifeState~="Dead" then return false end
	local V=require(Shared.Utilities.Validation)
	if not V.IsInteger(state.revivesUsedThisFloor,0,1) then return false end
	for _,key in {"downedDeadline","protectionUntil"} do
		local n=state[key];if type(n)~="number" or n~=n or n<0 or n==math.huge then return false end
	end
	local changed=false
	for _,key in {"lifeState","revivesUsedThisFloor","downedDeadline","protectionUntil"} do
		if p[key]~=state[key] then changed=true end
	end
	if not changed then return true,false end
	for _,key in {"lifeState","revivesUsedThisFloor","downedDeadline","protectionUntil"} do p[key]=state[key] end
	self._revision+=1;return true,true
end
function Machine:SetConnection(userId,state,deadline)
	local p=self._record.participants[tostring(userId)]
	if not p or (state~="Connected" and state~="Disconnected" and state~="Abandoned") then return false end
	if p.connectionState=="Abandoned" and state~="Abandoned" then return false end
	if state=="Disconnected" and (type(deadline)~="number" or deadline~=deadline or deadline<=0 or deadline==math.huge) then return false end
	p.connectionState=state;p.reconnectDeadline=state=="Disconnected" and deadline or nil;self._revision+=1;return true
end
-- Server-only (admin floor transfer): the next PrepareFloor lands on floor n. From Transit,
-- PrepareFloor counts down one, so the record is set one above the target.
function Machine:SetNextFloor(n)
	if self._destroyed or type(n)~="number" or n~=math.floor(n) or n<1 or n>5 then return false end
	local phase=self._record.phase
	if phase=="Transit" then self._record.currentFloorNumber=n+1
	elseif phase=="Intro" then self._record.currentFloorNumber=n
	else return false end
	self._revision+=1;return true
end
function Machine:Destroy()
	self._destroyed=true
end
return table.freeze(Machine)
