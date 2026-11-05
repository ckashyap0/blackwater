--!nonstrict
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio-only checks")
	local root=script.Parent.Parent
	local Shared=game:GetService("ReplicatedStorage").Game.Shared
	local Machine=require(root.Data.RunStateMachine)
	local Service=require(root.Services.GameRunService)
	local Driver=require(root.Development.RunDriver)
	local Contract=require(Shared.Contracts.RunContract)
	local Constants=require(Shared.Constants)
	local JSON=game:GetService("HttpService")
	local results={}
	local function test(name,fn)
		local ok,err=xpcall(fn,debug.traceback)
		table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	local function new(roster) return Machine.new("TestRun",roster or {101},"Standard",42,function() return 2000000000 end) end
	local function apply(machine,action,payload,token)
		return machine:Dispatch({action=action,payload=payload or {},token=token or machine:GetToken()})
	end
	local function take(machine,action,payload)
		local r=apply(machine,action,payload);assert(r.ok,action..": "..r.code);return r
	end
	local function activate(machine)
		take(machine,"Queue");take(machine,"BeginIntro");take(machine,"PrepareFloor");take(machine,"ActivateFloor")
	end
	local function nextFloor(machine)
		take(machine,"CompleteObjective");take(machine,"BeginDeparture");take(machine,"CleanupResult",{succeeded=true})
		take(machine,"PrepareFloor");take(machine,"ActivateFloor")
	end
	local function at(phase)
		local m=new()
		if phase=="Initializing" then return m end
		take(m,"Queue");if phase=="WaitingForRoster" then return m end
		take(m,"BeginIntro");if phase=="Intro" then return m end
		take(m,"PrepareFloor");if phase=="PreparingFloor" then return m end
		take(m,"ActivateFloor");if phase=="FloorActive" then return m end
		if phase=="Resolving" or phase=="Failed" or phase=="Closing" then
			take(m,"Wipe");if phase=="Resolving" then return m end
			take(m,"Resolve");if phase=="Failed" then return m end
			take(m,"Close");return m
		end
		if phase=="Departing" or phase=="Transit" then
			take(m,"CompleteObjective");take(m,"BeginDeparture")
			if phase=="Transit" then take(m,"CleanupResult",{succeeded=true}) end
			return m
		end
		while m:GetSnapshot().currentFloorNumber>1 do nextFloor(m) end
		if phase=="FinaleActive" then return m end
		take(m,"Escape",{escapedUserIds={101}});take(m,"Resolve")
		assert(phase=="Completed")
		return m
	end
	test("Successful descent visits and clears exactly 5,4,3,2,1",function()
		local m=new();activate(m);local visited={5}
		while m:GetSnapshot().currentFloorNumber>1 do nextFloor(m);table.insert(visited,m:GetSnapshot().currentFloorNumber) end
		assert(m:GetSnapshot().phase=="FinaleActive")
		assert(table.concat(visited,",")=="5,4,3,2,1")
		assert(table.concat(m:GetSnapshot().completedFloorNumbers,",")=="5,4,3,2")
		take(m,"Escape",{escapedUserIds={101}})
		assert(m:GetSnapshot().result==nil and m:GetSnapshot().phase=="Resolving")
		take(m,"Resolve")
		local snap=m:GetSnapshot()
		assert(snap.result.outcome=="Completed" and snap.participants["101"].escaped)
		assert(table.concat(snap.completedFloorNumbers,",")=="5,4,3,2,1")
		assert(#snap.pendingRewardReceipts==0,"Chunk 3 must not issue rewards")
		take(m,"Close");assert(m:GetSnapshot().phase=="Closing")
	end)
	test("All forbidden phase/action pairs leave state unchanged",function()
		local checked=0
		for _,phase in Constants.RunPhases do
			for action,allowed in Contract.Actions do
				if not allowed[phase] then
					local m=at(phase)
					local payload={}
					if action=="CleanupResult" then payload={succeeded=true}
					elseif action=="Escape" then payload={escapedUserIds={101}}
					elseif action=="TechnicalFailure" then payload={reason="InternalError"} end
					local before=JSON:JSONEncode(m:GetSnapshot())
					local r=apply(m,action,payload)
					assert(not r.ok and r.code=="IllegalTransition",phase.."/"..action)
					assert(JSON:JSONEncode(m:GetSnapshot())==before,"Rejected command mutated state")
					checked+=1
				end
			end
		end
		assert(checked>100)
	end)
	test("Departure requires completed objective; completion fires once",function()
		local m=at("FloorActive")
		assert(apply(m,"BeginDeparture").code=="ObjectiveIncomplete")
		take(m,"CompleteObjective")
		local revision=m:GetToken().revision
		assert(apply(m,"CompleteObjective").code=="ObjectiveAlreadyComplete")
		assert(m:GetToken().revision==revision)
		take(m,"BeginDeparture")
	end)
	test("Run, floor, phase and revision guards reject stale callbacks",function()
		local m=at("FloorActive")
		local original=m:GetToken()
		for key,value in {runId="AnotherRun",floorInstanceId="OtherFloor",expectedPhase="Intro",revision=1} do
			local token=table.clone(original);token[key]=value
			assert(not apply(m,"CompleteObjective",{},token).ok)
		end
		take(m,"CompleteObjective")
		assert(apply(m,"CompleteObjective",{},original).code=="StaleRevision")
		local oldFloor=m:GetToken()
		take(m,"BeginDeparture");take(m,"CleanupResult",{succeeded=true});take(m,"PrepareFloor");take(m,"ActivateFloor")
		assert(apply(m,"CompleteObjective",{},oldFloor).code=="StaleFloor")
	end)
	test("Malformed commands and forged payloads are rejected",function()
		local m=at("FloorActive")
		assert(not m:Dispatch(nil).ok)
		assert(not m:Dispatch({token=m:GetToken(),action="SetPhase",payload={phase="Completed"}}).ok)
		assert(not apply(m,"CompleteObjective",{currency=10000}).ok)
		local token=table.clone(m:GetToken());token.revision=0/0
		assert(not apply(m,"CompleteObjective",{},token).ok)
		assert(m:GetSnapshot().phase=="FloorActive")
	end)
	test("Failed cleanup cannot clear a floor or advance",function()
		local m=at("Departing")
		take(m,"CleanupResult",{succeeded=false})
		assert(m:GetSnapshot().phase=="Resolving" and #m:GetSnapshot().completedFloorNumbers==0)
		assert(not apply(m,"PrepareFloor").ok)
		take(m,"Resolve")
		assert(m:GetSnapshot().result.reason=="CleanupFailed" and m:GetSnapshot().phase=="Failed")
	end)
	test("A wipe resolves once and cannot be changed to victory",function()
		local m=at("FloorActive")
		take(m,"Wipe")
		assert(not apply(m,"Resolve",{outcome="Completed"}).ok)
		local resolvingToken=m:GetToken()
		take(m,"Resolve")
		local before=JSON:JSONEncode(m:GetSnapshot().result)
		assert(not apply(m,"Resolve",{},resolvingToken).ok)
		assert(not apply(m,"Escape",{escapedUserIds={101}}).ok)
		assert(JSON:JSONEncode(m:GetSnapshot().result)==before)
	end)
	test("Initialization cannot accidentally become a gameplay wipe",function()
		for _,phase in {"Initializing","WaitingForRoster"} do
			assert(apply(at(phase),"Wipe").code=="IllegalTransition")
		end
	end)
	test("Technical failure is handled in every unfinished phase",function()
		for phase in Contract.Actions.TechnicalFailure do
			local m=at(phase);take(m,"TechnicalFailure",{reason="LoadFailed"});take(m,"Resolve")
			assert(m:GetSnapshot().phase=="Failed" and m:GetSnapshot().result.reason=="LoadFailed")
		end
	end)
	test("Escape requires a nonempty unique subset of the roster",function()
		local m=at("FinaleActive")
		for _,ids in {{},{999},{101,101},{[2]=101}} do assert(not apply(m,"Escape",{escapedUserIds=ids}).ok) end
		assert(m:GetSnapshot().phase=="FinaleActive")
		take(m,"Escape",{escapedUserIds={101}});take(m,"Resolve")
		assert(Contract.ValidateView(m:GetView()))
	end)
	test("Solo, duo and four-player runs support a single escape survivor",function()
		for _,roster in {{101},{101,102},{101,102,103,104}} do
			local m=new(roster);activate(m)
			while m:GetSnapshot().currentFloorNumber>1 do nextFloor(m) end
			take(m,"Escape",{escapedUserIds={101}});take(m,"Resolve")
			assert(m:GetSnapshot().participants["101"].escaped)
			if #roster>1 then assert(not m:GetSnapshot().participants["102"].escaped) end
		end
	end)
	test("Snapshots and tokens cannot mutate authoritative state",function()
		local m=at("FloorActive")
		assert(not pcall(function() m:GetSnapshot().participants["101"].lifeState="Dead" end))
		assert(not pcall(function() m:GetToken().revision=0 end))
		assert(not pcall(function() m:GetView().completedFloors[1]=1 end))
		assert(m:GetSnapshot().participants["101"].lifeState=="Alive")
	end)
	local function service(ready)
		local players={}
		local people={}
		for _,id in {101,102,103,104} do people[id]={UserId=id} end
		function players:GetPlayerByUserId(id) return people[id] end
		local svc=Service.new({players=players,clock=function() return 2000000000 end,idFactory=function() return "ServiceRun" end})
		svc:Init({ProfileService={IsReady=function(_,player) return ready~=false and player~=nil end}})
		svc:Start()
		return svc
	end
	local function dispatch(svc,action,payload)
		local response=svc:Dispatch({token=svc:GetToken(),action=action,payload=payload or {}})
		assert(response.ok,response.code);return response
	end
	test("Service rejects absent or unloaded participants and concurrent runs",function()
		local blocked=service(false)
		assert(blocked:CreateRun({101},0).code=="ProfileNotReady");blocked:Destroy()
		local svc=service()
		assert(svc:CreateRun({999},0).code=="ParticipantUnavailable")
		assert(svc:CreateRun({},0).code=="InvalidRunParameters")
		assert(svc:CreateRun({101},0).ok)
		assert(svc:CreateRun({102},0).code=="RunAlreadyActive")
		assert(svc:GetViewFor(999)==false)
		assert(svc:GetViewFor(101).phase=="Initializing")
		svc:Destroy()
	end)
	test("Cleanup confirmation gates release and next-run identity",function()
		local svc=service();assert(svc:CreateRun({101},0).ok)
		local first=svc:GetToken()
		assert(svc:ReleaseRun(first,true).code=="NotClosing")
		dispatch(svc,"TechnicalFailure",{reason="InternalError"});dispatch(svc,"Resolve");dispatch(svc,"Close")
		local closing=svc:GetToken()
		assert(svc:ReleaseRun(closing,false).code=="CleanupFailed")
		assert(svc:CreateRun({101},0).code=="RunAlreadyActive")
		assert(svc:ReleaseRun(closing,true).ok)
		assert(svc:GetSnapshot()==nil)
		assert(svc:CreateRun({101},0).ok)
		assert(svc:GetToken().runId~=first.runId)
		assert(svc:Dispatch({token=first,action="Queue",payload={}}).code=="WrongRun")
		svc:Destroy()
	end)
	test("Service revisions increase across runs but not rejected commands",function()
		local svc=service();local initial=svc:GetRevision()
		svc:CreateRun({101},0);assert(svc:GetRevision()>initial)
		local before=svc:GetRevision()
		assert(not svc:Dispatch({token=svc:GetToken(),action="Escape",payload={escapedUserIds={101}}}).ok)
		assert(svc:GetRevision()==before)
		dispatch(svc,"Queue");assert(svc:GetRevision()>before)
		svc:Destroy();svc:Destroy()
		assert(svc:CreateRun({101},0).code=="NotRunning")
	end)
	test("Studio driver rejects stale steps and cleans up its endpoint",function()
		local svc=service();local folder=Instance.new("Folder")
		local driver=Driver.new(folder);driver:Init({GameRunService=svc});driver:Start()
		assert(folder:FindFirstChild("RunCommand"))
		local started=driver:Handle("Start",{roster={101},seed=0});assert(started.ok)
		assert(driver:Handle("Step",{token=started.token}).ok)
		assert(driver:Handle("Step",{token=started.token}).code=="StaleRevision")
		driver:Destroy()
		assert(not folder:FindFirstChild("RunCommand"))
		assert(driver:Handle("Start",{roster={101}}).code=="DriverDisabled")
		svc:Destroy();folder:Destroy()
	end)
	test("Disabled development driver creates no endpoint",function()
		local svc=service();local folder=Instance.new("Folder")
		local driver=Driver.new(folder,{enabled=false});driver:Init({GameRunService=svc});driver:Start()
		assert(not folder:FindFirstChild("RunCommand"))
		assert(driver:Handle("Start",{roster={101}}).code=="DriverDisabled")
		driver:Destroy();svc:Destroy();folder:Destroy()
	end)
	test("Client views reject malformed run data",function()
		local view=at("FloorActive"):GetView()
		assert(Contract.ValidateView(view) and Contract.ValidateView(false))
		local invalid=table.clone(view);invalid.floorNumber=0/0;assert(not Contract.ValidateView(invalid))
		invalid=table.clone(view);invalid.completedFloors={5,3};assert(not Contract.ValidateView(invalid))
		invalid=table.clone(view);invalid.result={outcome="Completed"};assert(not Contract.ValidateView(invalid))
	end)
	local passed=0
	for _,result in results do if result.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
