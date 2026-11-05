--!nonstrict
-- Explicit Studio-only checks. Never runs automatically in a published game.
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Development checks are Studio-only")
	local Shared=game:GetService("ReplicatedStorage").Game.Shared
	local Network=require(Shared.Contracts.NetworkContract)
	local Constants=require(Shared.Constants)
	local Guard=require(script.Parent.Parent.Services.RequestGuard)
	local Scope=require(Shared.Utilities.CleanupScope)
	local Lifecycle=require(Shared.Utilities.Lifecycle)
	local Floor=require(Shared.Contracts.FloorContract)
	local Freeze=require(Shared.Utilities.TableUtil).DeepFreeze
	local State=require(script.Parent.Parent.Services.FoundationStateService)
	local results={}
	local function test(name,fn)
		local ok,err=xpcall(fn,debug.traceback)
		table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	test("Reject malformed remote packets",function()
		for _,packet in {false,42,"hello",{}, {schemaVersion=Constants.SchemaVersion,requestId=0},
			{schemaVersion=Constants.SchemaVersion,requestId=0/0},{schemaVersion=Constants.SchemaVersion,requestId=math.huge},
			{schemaVersion=Constants.SchemaVersion,requestId=1,extra=true},{schemaVersion=Constants.SchemaVersion+1,requestId=1}} do
			assert(not Network.ValidateReady(packet))
		end
		assert(not Network.ValidateReady(nil))
		assert(Network.ValidateReady({schemaVersion=Constants.SchemaVersion,requestId=1}))
	end)
	test("Unimplemented gameplay requests remain disabled",function()
		assert(Network.ValidateAction({schemaVersion=Constants.SchemaVersion,requestId=1,action="RequestSnapshot",payload={}}))
		for _,action in {"GiveCurrency","ObjectiveComplete","RequestDeparture","Interact"} do
			assert(not Network.ValidateAction({schemaVersion=Constants.SchemaVersion,requestId=2,action=action,payload={}}))
		end
		assert(not Network.ValidateAction({schemaVersion=Constants.SchemaVersion,requestId=3,action="RequestSnapshot",payload={nested={}}}))
	end)
	test("Token bucket limits bursts and refills",function()
		local clock=0
		local guard=Guard.new(2,1,function() return clock end)
		assert(guard:Consume("A")); assert(guard:Consume("A"))
		assert(not guard:Consume("A"))
		assert(guard:Consume("B"))
		clock=0.5; assert(not guard:Consume("A"))
		clock=1; assert(guard:Consume("A")); assert(not guard:Consume("A"))
		guard:Destroy()
	end)
	test("Request IDs reject replay; removal clears state",function()
		local guard=Guard.new(12,3)
		assert(guard:Consume("A"))
		assert(guard:AcceptId("A",1))
		assert(not guard:AcceptId("A",1))
		assert(guard:AcceptId("A",100))
		assert(not guard:AcceptId("A",2))
		assert(not guard:IsReady("A"))
		guard:SetReady("A"); assert(guard:IsReady("A"))
		guard:Forget("A"); assert(not guard:IsReady("A"))
		assert(guard:Consume("A")); assert(guard:AcceptId("A",1))
		guard:Destroy()
	end)
	test("Cleanup is reverse-order and idempotent",function()
		local scope=Scope.new(); local order={}
		scope:Add(function() table.insert(order,"first") end)
		scope:Add(function() table.insert(order,"second") end)
		local event=Instance.new("BindableEvent")
		local connection=scope:Add(event.Event:Connect(function() end))
		scope:Destroy(); scope:Destroy()
		assert(not connection.Connected)
		assert(table.concat(order,",")=="second,first")
		local disposed=false
		scope:Add(function() disposed=true end)
		assert(disposed)
		event:Destroy()
	end)
	local function service(name,deps,order,failStart)
		return {Name=name,Dependencies=deps,
			Init=function(self,resolved)
				for _,dependency in deps do assert(resolved[dependency]) end
				table.insert(order,"Init"..name)
			end,
			Start=function()
				table.insert(order,"Start"..name)
				if failStart then error("Intentional startup failure") end
			end,
			Destroy=function() table.insert(order,"Destroy"..name) end}
	end
	test("Lifecycle ordering and duplicate start guard",function()
		local order={}
		local runner=Lifecycle.new({service("A",{},order),service("B",{"A"},order)})
		runner:Start()
		assert(runner.State=="Running")
		assert(not pcall(function() runner:Start() end))
		runner:Destroy(); runner:Destroy()
		assert(table.concat(order,",")=="InitA,InitB,StartA,StartB,DestroyB,DestroyA")
	end)
	test("Lifecycle rejects duplicate, missing and cyclic dependencies",function()
		assert(not pcall(function() Lifecycle.new({service("A",{},{}),service("A",{},{})}) end))
		assert(not pcall(function() Lifecycle.new({service("B",{"A"},{})}) end))
		assert(not pcall(function() Lifecycle.new({service("A",{"B"},{}),service("B",{"A"},{})}) end))
	end)
	test("Failed startup rolls back initialized services",function()
		local order={}
		local runner=Lifecycle.new({service("A",{},order),service("B",{"A"},order,true)})
		assert(not pcall(function() runner:Start() end))
		assert(runner.State=="Failed")
		assert(table.concat(order,",")=="InitA,InitB,StartA,StartB,DestroyB,DestroyA")
	end)
	test("Snapshot is recipient-specific and immutable",function()
		local state=State.new()
		state:Init({GameRunService={
			GetRevision=function() return 1 end,
			GetViewFor=function() return false end,
		}})
		state:Start()
		local snapshot=state:GetSnapshot({UserId=123})
		assert(Network.ValidateSnapshot(snapshot,123))
		assert(not Network.ValidateSnapshot(snapshot,124))
		assert(table.isfrozen(snapshot) and table.isfrozen(snapshot.availableActions))
		assert(not pcall(function() snapshot.revision=8 end))
		local invalid=table.clone(snapshot); invalid.revision=0/0
		assert(not Network.ValidateSnapshot(invalid,123))
		state:Destroy()
		assert(not pcall(function() state:GetSnapshot({UserId=123}) end))
	end)
	test("Floor templates require anchored recovery and dock anchors",function()
		local template=Instance.new("Model")
		assert(not pcall(function() Floor.ValidateTemplate(template) end))
		for _,name in Floor.RequiredAnchors do
			local part=Instance.new("Part"); part.Name=name; part.Anchored=true; part.Parent=template
		end
		Floor.ValidateTemplate(template)
		template.ElevatorDock.Anchored=false
		assert(not pcall(function() Floor.ValidateTemplate(template) end))
		template:Destroy()
	end)
	test("Configuration is deeply immutable and descends 5 to 1",function()
		local config=require(Shared.Config.GameConfig)
		assert(table.isfrozen(config) and table.isfrozen(config.FloorOrder))
		assert(table.concat(config.FloorOrder,",")=="5,4,3,2,1")
		assert(config.MinPlayers==1 and config.MaxRunPlayers==4)
		local sample=Freeze({nested={value=1}})
		assert(not pcall(function() sample.nested.value=2 end))
	end)
	local passed=0
	for _,result in results do if result.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
