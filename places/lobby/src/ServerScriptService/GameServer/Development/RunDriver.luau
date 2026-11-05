--!nonstrict
-- Server-only Studio driver. No client RemoteEvent or chat command exposes these controls.
local Scope=require(game:GetService("ReplicatedStorage").Game.Shared.Utilities.CleanupScope)
local Driver={}
Driver.__index=Driver
function Driver.new(root,options)
	options=options or {}
	return setmetatable({Name="RunDriver",Dependencies={"GameRunService","SurvivalService"},_root=root,
		_enabled=options.enabled~=false,_active=false},Driver)
end
function Driver:Init(dependencies)
	self._run=dependencies.GameRunService;self._survival=dependencies.SurvivalService;self._scope=Scope.new()
end
function Driver:Handle(name,args)
	if not self._active then return {ok=false,code="DriverDisabled"} end
	args=args or {}
	if type(name)~="string" or type(args)~="table" then return {ok=false,code="InvalidDriverCommand"} end
	if name=="Damage" then
		local ok,code=self._survival:Damage(args);return {ok=ok,code=code}
	end
	if name=="Snapshot" then return {ok=true,token=self._run:GetToken() or false,snapshot=self._run:GetSnapshot() or false} end
	if name=="Start" then
		local roster=args.roster
		if roster==nil then
			roster={}
			for _,player in game:GetService("Players"):GetPlayers() do table.insert(roster,player.UserId) end
			table.sort(roster)
			while #roster>4 do table.remove(roster) end
		end
		return self._run:CreateRun(roster,args.seed or 0)
	end
	if name=="Release" then return self._run:ReleaseRun(args.token,args.cleanupSucceeded) end
	if name=="Dispatch" then return self._run:Dispatch(args) end
	local action,payload
	if name=="Step" then
		local snapshot=self._run:GetSnapshot()
		if not snapshot then return {ok=false,code="NoActiveRun"} end
		local phase=snapshot.phase
		local nextAction={Initializing="Queue",WaitingForRoster="BeginIntro",Intro="PrepareFloor",
			PreparingFloor="ActivateFloor",Departing="CleanupResult",Transit="PrepareFloor",
			Resolving="Resolve",Completed="Close",Failed="Close"}
		action=nextAction[phase]
		if phase=="FloorActive" then
			action=snapshot.objectiveSnapshot.status=="Completed" and "BeginDeparture" or "CompleteObjective"
		end
		if not action then return {ok=false,code=phase=="FinaleActive" and "UseEscapeOrWipe" or "UseRelease"} end
		payload=action=="CleanupResult" and {succeeded=true} or {}
	elseif name=="Escape" then action="Escape";payload={escapedUserIds=args.escapedUserIds}
	elseif name=="Wipe" then action="Wipe";payload={}
	elseif name=="Fail" then action="TechnicalFailure";payload={reason=args.reason}
	else return {ok=false,code="UnknownDriverCommand"} end
	return self._run:Dispatch({token=args.token,action=action,payload=payload})
end
function Driver:Start()
	if not self._enabled or not game:GetService("RunService"):IsStudio() then return end
	assert(not self._root:FindFirstChild("RunCommand"),"RunCommand already exists")
	local command=Instance.new("BindableFunction");command.Name="RunCommand"
	self._scope:Add(command)
	self._active=true
	command.OnInvoke=function(name,args) return self:Handle(name,args) end
	command.Parent=self._root
end
function Driver:Destroy()
	self._active=false
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Driver)
