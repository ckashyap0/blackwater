--!nonstrict
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio only")
	local root=script.Parent.Parent;local Shared=game.ReplicatedStorage.Game.Shared
	local Inventory=require(root.Data.ObjectiveInventory)
	local Interaction=require(root.Services.InteractionService)
	local InventoryService=require(root.Services.InventoryService)
	local Equipment=require(root.Services.EquipmentService)
	local Network=require(Shared.Contracts.NetworkContract);local Constants=require(Shared.Constants)
	local Places=require(Shared.Config.PlaceConfig)
	local results={}
	local function test(name,callback)
		local ok,err=xpcall(callback,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	local function inventory()
		local i=Inventory.new();i:RegisterItem("A","Core","FloorA");i:RegisterItem("B","Fuse","FloorA")
		i:RegisterSocket("CoreSocket","Core","FloorA");return i
	end
	test("Competing pickups commit exactly one owner",function()
		local i=inventory();assert(i:Pickup(101,"A"));assert(not i:Pickup(102,"A"));assert(i:Get("A").owner==101 and not i:Carried(102))
	end)
	test("Single item capacity excludes personal equipment",function()
		local i=inventory();assert(i:Pickup(101,"A"));assert(not i:Pickup(101,"B"));assert(not i:Pickup(102,"Flashlight"));assert(i:Get("B").state=="AtSpawn")
	end)
	test("Drop and teammate exchange preserve one item",function()
		local i=inventory();assert(i:Pickup(101,"A"));assert(i:Drop(101));assert(not i:Drop(101));assert(i:Pickup(102,"A"))
		assert(not i:Carried(101) and i:Carried(102)=="A" and i:Get("A").revision==4)
	end)
	test("Installation clears ownership and prevents retrieval",function()
		local i=inventory();assert(i:Pickup(101,"A"));assert(i:Install(101,"CoreSocket"));assert(i:Get("A").state=="Installed")
		assert(not i:Carried(101) and not i:Pickup(102,"A") and not i:Install(101,"CoreSocket"))
	end)
	test("Wrong socket kind or floor leaves item carried",function()
		local i=inventory();assert(i:Pickup(101,"B"));assert(not i:Install(101,"CoreSocket"));assert(i:Carried(101)=="B")
		i:RegisterSocket("OtherFloor","Fuse","FloorB");assert(not i:Install(101,"OtherFloor"));assert(i:Carried(101)=="B")
	end)
	test("Death and disconnect share an idempotent safe-drop transaction",function()
		local i=inventory();i:Pickup(101,"A");assert(i:Drop(101));assert(not i:Drop(101));assert(i:Get("A").state=="Dropped")
		assert(i:Pickup(102,"A"));assert(i:Drop(102));assert(not i:Drop(102));assert(i:Get("A").state=="Dropped")
	end)
	test("Floor retirement removes carrier ownership and permits bounded reuse",function()
		local i=inventory();i:Pickup(101,"A");i:RetireScope("FloorA");assert(not i:Carried(101));assert(i:Get("A").state=="Retired")
		assert(not i:Pickup(102,"A"));i:ForgetRetired("FloorA");i:RegisterItem("A","Core","FloorB");assert(i:Get("A").state=="AtSpawn")
	end)
	test("Inventory snapshots cannot mutate ownership",function()
		local i=inventory();local s=i:Get("A");assert(table.isfrozen(s));assert(not pcall(function() s.owner=101 end));assert(i:Get("A").owner==false)
	end)
	test("Duplicate IDs and invalid users are rejected",function()
		local i=inventory();assert(not pcall(function() i:RegisterItem("A","Core","FloorA") end));assert(not i:Pickup(0,"A"));assert(not i:Pickup(0/0,"A"))
	end)
	local function fixture(callback)
		local container=Instance.new("Folder");container.Name="IsolatedInteractionChecks";container.Parent=workspace
		local target=Instance.new("Part");target.Name="Target";target.Anchored=true;target.Size=Vector3.new(1,2,1);target.Position=Vector3.new(5000,53,5000);target.Parent=container
		local users={};local now=0;local phase="FloorActive";local runId="TestRun";local floorId="TestFloor"
		local service=Interaction.new({clock=function()return now end,players=users,holdBonus=0});service._active=true
		service._runs={GetViewFor=function()return {runId=runId,floorInstanceId=floorId,phase=phase} end}
		local function actor(id,x)
			local character=Instance.new("Model");character.Parent=container
			local rootPart=Instance.new("Part");rootPart.Name="HumanoidRootPart";rootPart.Anchored=true;rootPart.Position=Vector3.new(x,53,5004);rootPart.Parent=character
			local humanoid=Instance.new("Humanoid");humanoid.Parent=character
			local attrs={EHCharacterEpoch=1,EHLifeState="Alive"}
			return {UserId=id,Parent=users,Character=character,GetAttribute=function(_,key)return attrs[key] end,SetAttribute=function(_,key,value)attrs[key]=value end},rootPart,attrs
		end
		local a,ar,aa=actor(101,5000);local b,br,ba=actor(102,5003)
		local completed=0
		service:Register({interactionId="Target",target=target,runId=runId,floorInstanceId=floorId,allowedRunPhases={FloorActive=true},holdDuration=2,complete=function()completed+=1;return true end})
		local ok,err=xpcall(function() callback({s=service,a=a,b=b,ar=ar,br=br,aa=aa,ba=ba,target=target,container=container,
			advance=function(dt)now+=dt end,phase=function(v)phase=v end,floor=function(v)floorId=v end,count=function()return completed end}) end,debug.traceback)
		service:Destroy();container:Destroy();assert(ok,err)
	end
	test("Exclusive hold and one-hold-per-player enforced",function() fixture(function(f)
		assert(f.s:Begin(f.a,"Target",1));assert(not f.s:Begin(f.b,"Target",1));assert(not f.s:Begin(f.a,"Target",1))
		assert(f.s:Cancel(f.a,"Released"));assert(f.s:Begin(f.b,"Target",1))
	end) end)
	test("Hold timing is server measured and commits once",function() fixture(function(f)
		assert(f.s:Begin(f.a,"Target",1));f.advance(1);assert(f.s:Continue(f.a,"Target",1));f.s:_Step();assert(f.count()==0)
		f.advance(1);f.s:_Step();assert(f.count()==1);f.s:_Step();assert(f.count()==1)
	end) end)
	test("Every hold takes half a second longer than requested",function()
		assert(Interaction.HoldBonus==.5)
		local part=Instance.new("Part")
		local s=Interaction.new({clock=function()return 0 end,players={}})
		s:Register({interactionId="BonusCheck",target=part,runId="R",floorInstanceId="F",allowedRunPhases={FloorActive=true},holdDuration=1,complete=function()return true end})
		s:Register({interactionId="BonusDefault",target=Instance.new("Part"),runId="R",floorInstanceId="F",allowedRunPhases={FloorActive=true},complete=function()return true end})
		local ok=math.abs(s._defs.BonusCheck.holdDuration-1.5)<1e-6 and math.abs(part:GetAttribute("EHHoldDuration")-1.5)<1e-6 and math.abs(s._defs.BonusDefault.holdDuration-1)<1e-6
		s:Destroy();part:Destroy();assert(ok,"hold bonus not applied")
	end)
	test("Expired hold cannot be resurrected by keepalive",function() fixture(function(f)
		f.s:Begin(f.a,"Target",1);f.advance(1.6);assert(not f.s:Continue(f.a,"Target",1));f.s:_Step();assert(f.count()==0)
	end) end)
	test("Range and line of sight reject inaccessible targets",function() fixture(function(f)
		f.ar.Position=Vector3.new(5000,53,5010);assert(not f.s:Begin(f.a,"Target",1));f.ar.Position=Vector3.new(5000,53,5004)
		local wall=Instance.new("Part");wall.Anchored=true;wall.Size=Vector3.new(5,5,.5);wall.Position=Vector3.new(5000,53,5002);wall.Parent=f.container
		assert(not f.s:Begin(f.a,"Target",1))
	end) end)
	test("Range loss cancels an existing hold",function() fixture(function(f)
		assert(f.s:Begin(f.a,"Target",1));f.ar.Position+=Vector3.new(20,0,0);f.s:_Step();assert(not f.s._holds[f.a]);assert(f.count()==0)
	end) end)
	test("Death downing and stale epoch cancel holds",function() fixture(function(f)
		for _,life in {"Downed","Dead"} do f.aa.EHLifeState="Alive";assert(f.s:Begin(f.a,"Target",1));f.aa.EHLifeState=life;f.s:_Step();assert(not f.s._holds[f.a]) end
		f.aa.EHLifeState="Alive";assert(f.s:Begin(f.a,"Target",1));f.aa.EHCharacterEpoch=2;f.s:_Step();assert(not f.s._holds[f.a])
	end) end)
	test("Phase floor target and disconnect changes cancel holds",function() fixture(function(f)
		assert(f.s:Begin(f.a,"Target",1));f.phase("Transit");f.s:_Step();assert(not f.s._holds[f.a]);f.phase("FloorActive")
		assert(f.s:Begin(f.a,"Target",1));f.floor("Other");f.s:_Step();assert(not f.s._holds[f.a]);f.floor("TestFloor")
		assert(f.s:Begin(f.a,"Target",1));f.a.Parent=nil;f.s:_Step();assert(not f.s._holds[f.a])
	end) end)
	test("Disabling or removing a target frees its exclusive lock",function() fixture(function(f)
		assert(f.s:Begin(f.a,"Target",1));f.s:SetEnabled("Target",false);assert(not f.s._locks.Target)
		f.s:SetEnabled("Target",true);assert(f.s:Begin(f.b,"Target",1));f.target.Parent=nil;f.s:_Step();assert(not f.s._locks.Target);f.target:Destroy()
	end) end)
	test("Client payloads cannot supply timing positions ownership or light state",function()
		for _,action in {"BeginInteraction","ContinueInteraction","EndInteraction"} do
			local packet={schemaVersion=Constants.SchemaVersion,requestId=1,action=action,payload={characterEpoch=1,interactionId="Target"}}
			assert(Network.ValidateAction(packet));packet.payload.duration=0;assert(not Network.ValidateAction(packet))
		end
		for _,action in {"ToggleFlashlight","DropObjectiveItem"} do
			local packet={schemaVersion=Constants.SchemaVersion,requestId=1,action=action,payload={characterEpoch=1}}
			assert(Network.ValidateAction(packet));packet.payload.owner=102;assert(not Network.ValidateAction(packet))
		end
	end)
	test("Missing recovery anchor has an emergency fallback",function()
		local s=InventoryService.new();s:RegisterFloor("F","R",Vector3.new(20,20,20),nil,CFrame.new(0,50,0))
		assert(s:_Recovery("F")==CFrame.new(0,50,0));assert(s:_InBounds("F",Vector3.new(0,50,0)))
		assert(not s:_InBounds("F",Vector3.new(100,50,0)))
	end)
	test("Flashlight restrictions are scoped to their floor",function()
		-- (independent of whether a live crew happens to be boarding at the surface right now)
		local G=game.ReplicatedStorage.Game;local boarding=G:GetAttribute("SurfaceBoarding");G:SetAttribute("SurfaceBoarding",nil)
		local ok,err=pcall(function()
		local s=Equipment.new();local floor="F";s._runs={GetViewFor=function()return {floorInstanceId=floor} end}
		local attrs={EHContext="ActiveFloor",EHLifeState="Alive"};local p={GetAttribute=function(_,key)return attrs[key] end}
		assert(s:_Allowed(p));s:SetRestriction("Darkness","F",true);assert(not s:_Allowed(p));floor="G";assert(s:_Allowed(p))
		s:SetRestriction("Darkness","F",false);floor="F";assert(s:_Allowed(p));attrs.EHLifeState="Dead";assert(not s:_Allowed(p))
		end)
		G:SetAttribute("SurfaceBoarding",boarding);assert(ok,err)
	end)
	test("Lobby and Game build roles remain separate",function()
		assert(Places.Resolve(0,true,"Lobby")=="Lobby");assert(Places.Resolve(0,true,"Game")=="Game")
		assert(Places.Resolve(Places.LobbyPlaceId,false)=="Lobby");assert(not pcall(Places.Resolve,0,false))
		assert(not pcall(Places.Resolve,0,true,"Both"));assert(Places.GamePlaceId==0 or Places.GamePlaceId~=Places.LobbyPlaceId)
	end)
	local passed=0;for _,r in results do if r.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
