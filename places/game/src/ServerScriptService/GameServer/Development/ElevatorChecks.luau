--!nonstrict
local Checks={}
function Checks.Run()
	local root=script.Parent.Parent
	local Policy=require(root.Data.ElevatorPolicy);local Templates=require(game.ServerStorage.TestFixtures.TemporaryFloors)
	local Elevator=require(root.Services.ElevatorService);local Runs=require(root.Services.GameRunService)
	local results={};local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})end
	local function fixture(fn,factory)
		local env=require(game.ServerStorage.TestFixtures.EnvironmentBuilder).Game(workspace,false)
		local c=Instance.new("Model");c.Parent=env;local hrp=Instance.new("Part");hrp.Name="HumanoidRootPart";hrp.Anchored=true;hrp.Position=Vector3.new(0,23,0);hrp.Parent=c;c.PrimaryPart=hrp
		local p={UserId=101,Character=c};local players={GetPlayers=function()return {p}end,GetPlayerByUserId=function()return p end}
		local runs=Runs.new({players=players,idFactory=function()return "ElevatorFixture"end});runs:Init({ProfileService={IsReady=function()return true end}});runs:Start();assert(runs:CreateRun({101}).ok)
		local interactions=require(root.Services.InteractionService).new();interactions:Init({GameRunService=runs,CharacterService={}})
		local inventory=require(root.Services.InventoryService).new();inventory:Init({GameRunService=runs,InteractionService=interactions})
		local survival={suspended=false,IsEncounterSuspended=function(self)return self.suspended end,SetCabinProtection=function(self,cb)self.protection=cb end}
		local e=Elevator.new({players=players,factory=factory or Templates.Build,introSeconds=3});e:Init({EnvironmentService={Role="Game",Model=env,Spawn=env.GameSpawn},GameRunService=runs,InteractionService=interactions,InventoryService=inventory,SurvivalService=survival,CharacterService={},SessionService={ReturnLobby=function()return true end}});e._active=true
		local function action(a,payload)local r=runs:Dispatch({token=runs:GetToken(),action=a,payload=payload or {}});assert(r.ok,r.code)end
		action("Queue");action("BeginIntro")
		local f={e=e,r=runs,i=interactions,inventory=inventory,s=survival,p=p,root=hrp,env=env,action=action,
			step=function(seconds)for _=1,math.ceil(seconds/.25)do e:_Step(.25)end end}
		local ok,err=xpcall(function()fn(f)end,debug.traceback)
		e:Destroy();inventory:Destroy();interactions:Destroy();runs:Destroy();env:Destroy();assert(ok,err)
	end
	test("Five temporary templates validate and reject missing recovery",function()
		for n=5,1,-1 do local m=Templates.Build(n);assert(Policy.ValidateMap(m));m.PlayerRecovery:Destroy();assert(not Policy.ValidateMap(m));m:Destroy()end
	end)
	test("Departure rejects outside and downed crew but permits absent reservations",function()
		local snapshot={phase="FloorActive",objectiveSnapshot={status="Completed"},participants={a={userId=101,lifeState="Alive",connectionState="Connected"},b={userId=102,lifeState="Alive",connectionState="Connected"}}}
		local positions={[101]=Vector3.new(0,23,0),[102]=Vector3.new(0,23,-20)}
		assert(not Policy.CanDepart(snapshot,positions,false));snapshot.participants.b.connectionState="Disconnected";assert(Policy.CanDepart(snapshot,positions,false))
		snapshot.participants.b.connectionState="Connected";snapshot.participants.b.lifeState="Downed";positions[102]=Vector3.new(0,23,0);assert(not Policy.CanDepart(snapshot,positions,false))
		assert(not Policy.CanDepart(snapshot,positions,true))
	end)
	test("Elevator loads all five floors and retires prior resources exactly once",function()fixture(function(f)
		f.step(6)
		for n=5,1,-1 do
			local snap=f.r:GetSnapshot();assert(snap.currentFloorNumber==n and f.e.State=="Open");assert(#snap.completedFloorNumbers==5-n)
			local old=f.e._floor.Model;local count=0;for _ in f.inventory._floors do count+=1 end;assert(count==1)
			f.root.Position=n==1 and old.ObjectivePanel.Position+Vector3.new(0,0,2)or Vector3.new(0,23,0)
			assert(f.i._defs.TemporaryObjective.complete(f.p))
			if n>1 then assert(f.e:RequestDeparture());assert(not f.e:RequestDeparture());f.step(2);assert(old.Parent==nil);f.step(13)
			else f.step(.25);assert(f.r:GetSnapshot().phase=="Completed" and #f.r:GetSnapshot().completedFloorNumbers==5);assert(old.Parent==nil)end
		end
		assert(next(f.inventory._floors)==nil and next(f.i._defs)==nil)
	end)end)
	test("Crossing the threshold reopens without awarding a floor",function()fixture(function(f)
		f.step(6);f.action("CompleteObjective");assert(f.e:RequestDeparture());f.step(.75);f.root.Position=Vector3.new(0,23,-8);f.step(2.5)
		assert(f.e.State=="Open" and f.r:GetSnapshot().phase=="FloorActive" and #f.r:GetSnapshot().completedFloorNumbers==0)
	end)end)
	test("Objective completion alone never starts departure",function()fixture(function(f)
		f.step(6);f.action("CompleteObjective");f.step(12);assert(f.e.State=="Open" and #f.r:GetSnapshot().completedFloorNumbers==0)
	end)end)
	test("Closed cabin protection and travel pause share authoritative state",function()fixture(function(f)
		f.step(6);assert(not f.s.protection(f.p));f.action("CompleteObjective");f.e:RequestDeparture();f.step(2)
		assert(f.s.protection(f.p));local travel=f.e._travel;f.s.suspended=true;f.step(15);assert(f.e._travel==travel and f.e.State=="Closed")
		f.s.suspended=false;f.step(13);assert(f.e.State=="Open" and not f.s.protection(f.p))
	end)end)
	test("Preparation retries once with no leaked instance or interaction",function()
		local attempts=0
		fixture(function(f)f.step(8);assert(attempts==2 and f.e.State=="Open");local count=0;for _ in f.i._defs do count+=1 end;assert(count==2)end,
			function(n)attempts+=1;local m=Templates.Build(n);if attempts==1 then m.PlayerRecovery:Destroy()end;return m end)
	end)
	test("Two preparation failures end safely with doors secured",function()
		local attempts=0
		fixture(function(f)f.step(8);local s=f.r:GetSnapshot();assert(attempts==2 and s.phase=="Failed" and s.result.reason=="LoadFailed");assert(f.e.State=="Disabled" and f.e._alpha==0 and next(f.i._defs)==nil)end,
			function(n)attempts+=1;local m=Templates.Build(n);m.ElevatorDock:Destroy();return m end)
	end)
	test("Preparation failure after departure preserves earned milestones",function()
		fixture(function(f)f.step(6);f.action("CompleteObjective");f.e:RequestDeparture();f.step(16);local s=f.r:GetSnapshot();assert(s.phase=="Failed" and #s.completedFloorNumbers==1 and s.completedFloorNumbers[1]==5)end,
			function(n)local m=Templates.Build(n);if n==4 then m.ObjectiveRecovery:Destroy()end;return m end)
	end)
	test("Missing walkable ground cannot open a landing",function()
		fixture(function(f)f.step(8);assert(f.r:GetSnapshot().phase=="Failed" and f.e._alpha==0)end,
			function(n)local m=Templates.Build(n);m.Floor:Destroy();return m end)
	end)
	test("Objective recovery uses its safe anchor independently of bounds center",function()fixture(function(f)
		f.step(6);local id=f.e._floorId;local map=f.e._floor.Model
		assert(f.inventory:_InBounds(id,Vector3.new(0,23,-39)))
		local expected=map.ObjectiveRecovery.CFrame;map.ObjectiveRecovery:Destroy();assert(f.inventory:_Recovery(id)==expected)
	end)end)
	return {results=results}
end
return table.freeze(Checks)

