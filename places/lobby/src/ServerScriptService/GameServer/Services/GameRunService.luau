--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Util=require(Shared.Utilities.TableUtil)
local V=require(Shared.Utilities.Validation)
local Scope=require(Shared.Utilities.CleanupScope)
local Machine=require(script.Parent.Parent.Data.RunStateMachine)
local Service={}
Service.__index=Service
function Service.new(options)
	options=options or {}
	return setmetatable({Name="GameRunService",Dependencies={"ProfileService"},
		_players=options.players or game:GetService("Players"),_clock=options.clock or os.time,
		_idFactory=options.idFactory or function() return game:GetService("HttpService"):GenerateGUID(false) end,
		_diagnostics=options.diagnostics,_generation=0,_serial=1,_machine=nil,_active=false},Service)
end
function Service:Init(dependencies)
	self._profiles=dependencies.ProfileService
	self._scope=Scope.new()
	self._changed=self._scope:Add(Instance.new("BindableEvent"))
end
function Service:Start() self._active=true end
function Service:Subscribe(callback) return self._changed.Event:Connect(callback) end
function Service:_Changed()
	self._serial+=1
	if self._diagnostics then
		local view=self._machine and self._machine:GetView() or nil
		self._diagnostics:SetAttribute("RunSnapshotRevision",self._serial)
		self._diagnostics:SetAttribute("ActiveRunPhase",view and view.phase or nil)
		self._diagnostics:SetAttribute("ActiveFloorNumber",view and view.floorNumber or nil)
	end
	self._changed:Fire(self._serial)
end
function Service:GetRevision() return self._serial end
function Service:GetToken() return self._machine and self._machine:GetToken() or nil end
function Service:GetSnapshot() return self._machine and self._machine:GetSnapshot() or nil end
function Service:GetViewFor(userId)
	if not self._machine or not self._machine:IsParticipant(userId) then return false end
	return self._machine:GetView()
end
function Service:CreateRun(roster,seed)
	if not self._active then return {ok=false,code="NotRunning"} end
	if self._machine then return {ok=false,code="RunAlreadyActive"} end
	-- Validate the roster using the same constructor as actual run creation.
	local ok,candidate=pcall(Machine.new,"Validation",roster,"Standard",seed or 0,self._clock)
	if not ok then return {ok=false,code="InvalidRunParameters"} end
	for _,userId in candidate:GetSnapshot().originalRoster do
		local player=self._players:GetPlayerByUserId(userId)
		if not player then return {ok=false,code="ParticipantUnavailable"} end
		if not self._profiles:IsReady(player) then return {ok=false,code="ProfileNotReady"} end
	end
	self._generation+=1
	local generatedOk,generated=pcall(self._idFactory)
	if not generatedOk or not V.IsIdentifier(generated,48) then return {ok=false,code="InvalidRunId"} end
	local runId=generated.."-"..self._generation
	local created,machine=pcall(Machine.new,runId,roster,"Standard",seed or 0,self._clock)
	if not created then return {ok=false,code="RunCreationFailed"} end
	self._machine=machine
	self:_Changed()
	return {ok=true,code="Created",token=self._machine:GetToken(),view=self._machine:GetView()}
end
-- Called only after MemoryStore roster admission; absent original members retain reservations.
function Service:CreateSessionRun(runId,roster,present,deadline)
	if not self._active or self._machine then return {ok=false,code="RunAlreadyActive"} end
	local ok,machine=pcall(Machine.new,runId,roster,"Standard",0,self._clock)
	if not ok then return {ok=false,code="InvalidRunParameters"} end
	local count=0
	for _,id in roster do
		if present[id] then
			local p=self._players:GetPlayerByUserId(id)
			if not p or not self._profiles:IsReady(p) then return {ok=false,code="ProfileNotReady"} end
			count+=1
		else machine:SetConnection(id,"Disconnected",deadline) end
	end
	if count==0 then return {ok=false,code="NobodyArrived"} end
	self._machine=machine;self:_Changed();return {ok=true,code="Created"}
end
function Service:SetConnection(userId,state,deadline)
	if not self._machine then return false end
	local ok=self._machine:SetConnection(userId,state,deadline);if ok then self:_Changed()end;return ok
end
local progression={PrepareFloor=true,ActivateFloor=true,CompleteObjective=true,BeginDeparture=true,CleanupResult=true,Escape=true}
function Service:HasConnectedParticipant()
 local snapshot=self:GetSnapshot();if not snapshot then return false end
 for _,p in snapshot.participants do if p.connectionState=="Connected" then return true end end
 return false
end
function Service:Dispatch(command)
	if not self._active or not self._machine then return {ok=false,code="NoActiveRun"} end
	if type(command)=="table" and progression[command.action] and not self:HasConnectedParticipant() then
  return {ok=false,code="AwaitingReconnect"}
 end
 local response=self._machine:Dispatch(command)
	if response.ok then self:_Changed() end
	return response
end
function Service:SetParticipantSurvival(runId,userId,state)
	if not self._active or not self._machine then return false end
	local ok,changed=self._machine:SetParticipantSurvival(runId,userId,state)
	if changed then self:_Changed() end
	return ok
end
function Service:ReleaseRun(token,cleanupSucceeded)
	if not self._active or not self._machine then return {ok=false,code="NoActiveRun"} end
	local matches,reason=self._machine:Matches(token)
	if not matches then return {ok=false,code=reason} end
	if token.expectedPhase~="Closing" then return {ok=false,code="NotClosing"} end
	if cleanupSucceeded~=true then return {ok=false,code="CleanupFailed"} end
	self._machine:Destroy();self._machine=nil
	self:_Changed()
	return {ok=true,code="Released"}
end
function Service:Destroy()
	self._active=false
	if self._machine then self._machine:Destroy();self._machine=nil end
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Service)
