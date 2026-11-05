--!nonstrict
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio-only checks")
	local Shared=game.ReplicatedStorage.Game.Shared
	local Sprint=require(Shared.Utilities.SprintModel)
	local Policy=require(Shared.Contracts.CharacterContract)
	local Network=require(Shared.Contracts.NetworkContract)
	local C=require(Shared.Constants)
	local Service=require(script.Parent.Parent.Services.CharacterService)
	local results={}
	local function test(name,fn)
		local ok,err=xpcall(fn,debug.traceback)
		table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	local function close(a,b) assert(math.abs(a-b)<.0001,tostring(a).." != "..tostring(b)) end
	test("Sprint lasts five moving seconds and exhausts",function()
		local s=Sprint.New();local speed
		for _=1,50 do s,speed=Sprint.Step(s,.1,true,true,true,1) end
		close(s.stamina,0);assert(s.exhausted and speed==12)
	end)
	test("Holding sprint stationary never drains",function()
		local s,speed=Sprint.Step(Sprint.New(),20,true,false,true,1)
		assert(s.stamina==100 and not s.sprinting and speed==12)
	end)
	test("Regeneration splits frames across delay correctly",function()
		local s=Sprint.Step(Sprint.New(),2,true,true,true,1)
		s=Sprint.Step(s,1,false,false,true,1);close(s.stamina,60)
		s=Sprint.Step(s,1,false,false,true,1);close(s.stamina,66.25)
		s=Sprint.Step(s,100,false,false,true,1);assert(s.stamina==100)
	end)
	test("Exhaustion blocks until twenty stamina",function()
		local s=Sprint.Step(Sprint.New(),5,true,true,true,1)
		s=Sprint.Step(s,3,true,true,true,1);close(s.stamina,18.75);assert(not s.sprinting)
		s=Sprint.Step(s,.1,true,true,true,1);close(s.stamina,20)
		s=Sprint.Step(s,.1,true,true,true,1);assert(s.sprinting);close(s.stamina,18)
	end)
	test("Environmental modifier applies once without altering drain",function()
		local original=Sprint.New();local s,speed=Sprint.Step(original,1,true,true,true,.5)
		assert(speed==9 and s.stamina==80 and original.stamina==100)
	end)
	test("Invalid timing and modifier values rejected",function()
		for _,dt in {-1,0/0,math.huge} do assert(not pcall(Sprint.Step,Sprint.New(),dt,true,true,true,1)) end
		assert(not pcall(Sprint.Step,Sprint.New(),1,true,true,true,0/0))
	end)
	test("All run phases resolve to intended character contexts",function()
		local expected={Initializing="Lobby",WaitingForRoster="Lobby",Intro="Intro",PreparingFloor="Intro",
			FloorActive="ActiveFloor",FinaleActive="ActiveFloor",Departing="Transit",Transit="Transit",
			Resolving="Results",Completed="Results",Failed="Results",Closing="Results"}
		for phase,context in expected do assert(Policy.ContextFor({phase=phase},"Alive")==context) end
		assert(Policy.ContextFor(false,"Alive")=="Lobby")
		assert(Policy.ContextFor({phase="FloorActive"},"Downed")=="Downed")
		assert(Policy.ContextFor({phase="Transit"},"Dead")=="Dead")
		assert(Policy.ContextFor({phase="Failed"},"Dead")=="Results")
	end)
	test("Restricted contexts cannot move or sprint",function()
		for _,context in {"Intro","Downed","Dead","Results"} do assert(not Policy.Contexts[context].movement and not Policy.Contexts[context].sprint) end
		assert(Policy.Contexts.Transit.movement and not Policy.Contexts.Transit.sprint)
	end)
	test("Sprint packets accept only a bounded character epoch",function()
		for _,action in {"BeginSprint","EndSprint"} do
			local packet={schemaVersion=C.SchemaVersion,requestId=1,action=action,payload={characterEpoch=2}}
			assert(Network.ValidateAction(packet))
			for _,payload in {{},{characterEpoch=0},{characterEpoch=0/0},{characterEpoch=1,speed=99},{characterEpoch="2"}} do
				packet.payload=payload;assert(not Network.ValidateAction(packet))
			end
		end
	end)
	test("Stale or locked sprint requests cannot mutate intent",function()
		local service=Service.new();local player={}
		local r={epoch=5,context="ActiveFloor",life="Alive",intent=false,humanoid={Health=100}}
		service._records[player]=r
		assert(not service:SetSprint(player,4,true));assert(not r.intent)
		assert(service:SetSprint(player,5,true));assert(r.intent)
		r.context="Downed";r.intent=false
		assert(not service:SetSprint(player,5,true));assert(not r.intent)
		assert(service:SetSprint(player,5,false));assert(r.expires==0)
	end)
	test("Modifiers replace by key and reject nonfinite values",function()
		local service=Service.new();local player={};local r={modifiers={}};service._records[player]=r
		assert(service:SetSpeedModifier(player,"Water",.7));assert(service:SetSpeedModifier(player,"Water",.5))
		assert(r.modifiers.Water==.5);assert(not service:SetSpeedModifier(player,"Water",0/0))
		assert(service:SetSpeedModifier(player,"Water",nil));assert(next(r.modifiers)==nil)
	end)
	test("Server movement locks anchor and restore the character",function()
		local service=Service.new();local player=Instance.new("Folder");local root=Instance.new("Part");root.Anchored=false;root.Parent=workspace
		local ok,err=pcall(function()
			local h={Health=100};local r={epoch=1,life="Alive",context="Intro",intent=false,expires=0,sprint=Sprint.New(),modifiers={},humanoid=h,root=root,jumpPower=50,jumpHeight=7.2}
			service._records[player]=r;service:_Step(.1)
			assert(root.Anchored and h.WalkSpeed==0 and h.JumpPower==0)
			r.context="ActiveFloor";service:_Step(.1)
			assert(not root.Anchored and h.WalkSpeed==12 and h.JumpPower==50)
		end)
		root:Destroy();player:Destroy();assert(ok,err)
	end)
	local passed=0;for _,r in results do if r.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
