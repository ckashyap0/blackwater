--!nonstrict
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio only")
	local root=script.Parent.Parent;local Shared=game.ReplicatedStorage.Game.Shared
	local Model=require(root.Data.SurvivalModel);local Survival=require(root.Services.SurvivalService)
	local Interaction=require(root.Services.InteractionService);local Machine=require(root.Data.RunStateMachine)
	local Spectator=require(Shared.Utilities.SpectatorPolicy)
	local results={};local function test(name,fn)
		local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	local function damage(id,kind,bypass)return {targetUserId=id or 101,sourceId="TestThreat",damageType=kind or "Attack",lethal=true,bypassDowned=bypass==true}end
	test("First lethal attack downs for 25 seconds",function()
		local s=assert(Model.Damage(Model.New(),damage(),100));assert(s.lifeState=="Downed" and s.downedDeadline==125)
	end)
	test("Rescue gives one revival and three-second protection",function()
		local s=Model.Damage(Model.New(),damage(),100);s=assert(Model.Revive(s,Model.New(),104))
		assert(s.lifeState=="Alive" and s.revivesUsedThisFloor==1 and s.protectionUntil==107)
		assert(not Model.Damage(s,damage(),106.999));local dead=assert(Model.Damage(s,damage(),107));assert(dead.lifeState=="Dead")
	end)
	test("Deadline tie denies rescue regardless of heartbeat ordering",function()
		local s=Model.Damage(Model.New(),damage(),100)
		assert(Model.Revive(s,Model.New(),124.999));assert(not Model.Revive(s,Model.New(),125));assert(Model.Expire(s,125).lifeState=="Dead")
	end)
	test("Abyss and consumption bypass downing",function()
		for _,kind in {"Abyss","Consumption"} do assert(Model.Damage(Model.New(),damage(101,kind),100).lifeState=="Dead") end
		assert(Model.Damage(Model.New(),damage(101,"Attack",true),100).lifeState=="Dead")
	end)
	test("Invalid damage and nonlethal calls cannot change life",function()
		for _,d in {{},damage(0),damage(101,"Bogus")} do assert(not Model.ValidDamage(d)) end
		local d=damage();d.extra=true;assert(not Model.ValidDamage(d))
		d=damage();d.lethal=false;assert(not Model.Damage(Model.New(),d,100))
	end)
	test("Downed and protected players cannot rescue",function()
		local s=Model.Damage(Model.New(),damage(),100);assert(not Model.Revive(s,s,101))
		local r=Model.New();r.protectionUntil=104;assert(not Model.Revive(s,r,103));assert(Model.Revive(s,r,104))
	end)
	test("Expiration is idempotent and final death cannot revive",function()
		local s=Model.Damage(Model.New(),damage(),100);assert(not Model.Expire(s,124))
		s=Model.Expire(s,125);assert(not Model.Expire(s,126));assert(not Model.Revive(s,Model.New(),126));assert(not Model.Damage(s,damage(),126))
	end)
	test("Continuation requires capable connected teammate",function()
		local p={a={userId=101,lifeState="Downed",connectionState="Connected"},b={userId=102,lifeState="Alive",connectionState="Connected"}}
		assert(Model.Continuation(p,{[101]=true,[102]=true},100)=="Continue")
		p.b.lifeState="Downed";assert(Model.Continuation(p,{[101]=true,[102]=true},100)=="Wipe")
	end)
	test("Only living unexpired reconnect reservations delay wipe",function()
		local p={a={userId=101,lifeState="Alive",connectionState="Disconnected",reconnectDeadline=120}}
		assert(Model.Continuation(p,{},119)=="AwaitingReconnect");assert(Model.Continuation(p,{},120)=="Wipe")
		p.a.lifeState="Downed";assert(Model.Continuation(p,{},110)=="Wipe")
	end)
	test("Spectators exclude self outsiders dead and unloaded characters",function()
		assert(Spectator.Eligible(101,"R",102,"R","Alive",true,true))
		assert(not Spectator.Eligible(101,"R",101,"R","Alive",true,true))
		assert(not Spectator.Eligible(101,"R",102,"Other","Alive",true,true))
		assert(not Spectator.Eligible(101,"R",102,"R","Downed",true,true))
		assert(not Spectator.Eligible(101,"R",102,"R","Alive",false,true))
		assert(not Spectator.Eligible(101,"R",102,"R","Alive",true,false))
	end)
	test("Spectator switching wraps and recovers from target departure",function()
		assert(Spectator.Select({102,103},102,1)==103);assert(Spectator.Select({102,103},102,-1)==103)
		assert(Spectator.Select({103},102,0)==103);assert(Spectator.Select({},103,1)==nil)
	end)
	local function fixture(count,fn)
		local folder=Instance.new("Folder");folder.Name="IsolatedSurvivalChecks";folder.Parent=workspace
		local users={};local all={};local roster={};local now=100;local restores={};local drops={}
		function users:GetPlayers() local list={} for _,p in all do if p.Parent==self then table.insert(list,p) end end return list end
		function users:GetPlayerByUserId(id)for _,p in self:GetPlayers() do if p.UserId==id then return p end end end
		for i=1,count do
			local c=Instance.new("Model");c.Parent=folder
			local part=Instance.new("Part");part.Name="HumanoidRootPart";part.Anchored=true;part.Size=Vector3.new(2,2,1)
			part.Position=Vector3.new(10000+(i-1)*3,50,10000);part.Parent=c
			local h=Instance.new("Humanoid");h.Parent=c
			local attrs={EHLifeState="Alive",EHCharacterEpoch=1}
			local p={UserId=100+i,DisplayName="Test"..i,Parent=users,Character=c}
			function p:GetAttribute(k)return attrs[k]end;function p:SetAttribute(k,v)attrs[k]=v end
			table.insert(all,p);table.insert(roster,p.UserId)
		end
		local machine=Machine.new("SurvivalTest",roster,"Standard",0,function()return 100 end)
		local runs={}
		function runs:GetSnapshot()return machine:GetSnapshot()end
		function runs:GetToken()return machine:GetToken()end
		function runs:GetViewFor(id)return machine:IsParticipant(id) and machine:GetView()end
		function runs:Dispatch(command)return machine:Dispatch(command)end
		function runs:SetParticipantSurvival(runId,id,s)return machine:SetParticipantSurvival(runId,id,s)end
		local function dispatch(action,payload)local r=runs:Dispatch({action=action,payload=payload or {},token=runs:GetToken()});assert(r.ok,r.code)end
		for _,action in {"Queue","BeginIntro","PrepareFloor","ActivateFloor"} do dispatch(action) end
		local chars={}
		function chars:SetLifeState(p,life)p:SetAttribute("EHLifeState",life);return true end
		function chars:SetSuspended(p,v)p:SetAttribute("EHAwaitingReconnect",v)end
		function chars:RestoreForFloor(p,frame)restores[p.UserId]=(restores[p.UserId] or 0)+1;p:SetAttribute("EHLifeState","Alive");return true end
		local interactions=Interaction.new({players=users,clock=function()return now end});interactions._runs=runs;interactions._active=true
		local inventory={Drop=function(_,p)drops[p.UserId]=(drops[p.UserId] or 0)+1 end}
		local service=Survival.new({players=users,clock=function()return now end})
		service:Init({GameRunService=runs,CharacterService=chars,InteractionService=interactions,InventoryService=inventory,EnvironmentService={}})
		service:_Sync()
		local f={s=service,i=interactions,all=all,machine=machine,runs=runs,restores=restores,drops=drops,dispatch=dispatch,
			advance=function(dt)now+=dt end}
		local ok,err=xpcall(function()fn(f)end,debug.traceback)
		service:Destroy();interactions:Destroy();folder:Destroy();assert(ok,err)
	end
	test("Solo lethal defeat resolves failure without self revival",function() fixture(1,function(f)
		assert(f.s:Damage(damage(101)));assert(f.runs:GetSnapshot().phase=="Failed");assert(not f.s:Revive(101,101))
	end) end)
	test("Duo rescue uses exclusive timed interaction",function() fixture(3,function(f)
		assert(f.s:Damage(damage(101)));local a,b,c=unpack(f.all)
		assert(f.i:Begin(b,"Revive_101",1));assert(not f.i:Begin(c,"Revive_101",1))
		for _=1,4 do f.advance(1);assert(f.i:Continue(b,"Revive_101",1));f.i:_Step() end
		assert(f.s._states[101].lifeState=="Alive" and f.s._states[101].revivesUsedThisFloor==1)
		assert(f.runs:GetSnapshot().participants["101"].lifeState=="Alive")
	end) end)
	test("Canceled rescue loses progress and a different rescuer starts fresh",function() fixture(3,function(f)
		f.s:Damage(damage(101));local b,c=f.all[2],f.all[3]
		assert(f.i:Begin(b,"Revive_101",1));f.advance(1);f.i:Continue(b,"Revive_101",1);f.i:_Step();f.i:Cancel(b,"Released")
		-- Place the third player beside the target, with clear line of sight.
		c.Character.HumanoidRootPart.Position=Vector3.new(10000,50,10003)
		assert(f.i:Begin(c,"Revive_101",1));for _=1,3 do f.advance(1);f.i:Continue(c,"Revive_101",1);f.i:_Step() end
		assert(f.s._states[101].lifeState=="Downed");f.advance(1);f.i:Continue(c,"Revive_101",1);f.i:_Step()
		assert(f.s._states[101].lifeState=="Alive")
	end) end)
	test("Downing the rescuer cancels rescue and full wipe resolves",function() fixture(2,function(f)
		f.s:Damage(damage(101));assert(f.i:Begin(f.all[2],"Revive_101",1));f.s:Damage(damage(102));f.i:_Step()
		assert(not f.i._holds[f.all[2]] and f.runs:GetSnapshot().phase=="Failed")
	end) end)
	test("Rescue completion at deadline is rejected by service",function() fixture(2,function(f)
		f.s:Damage(damage(101));f.advance(25);assert(not f.s:Revive(102,101));f.s:_Step();assert(f.s._states[101].lifeState=="Dead")
	end) end)
	test("Departure restores dead teammates once and new floor resets allowance",function() fixture(2,function(f)
		f.s:Damage(damage(101,"Abyss"));assert(f.s._states[101].lifeState=="Dead")
		f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true});f.s:_Sync()
		assert(f.s._states[101].lifeState=="Alive" and f.restores[101]==1);f.s:_Sync();assert(f.restores[101]==1)
		f.dispatch("PrepareFloor");f.s:_Sync();assert(f.s._states[101].revivesUsedThisFloor==0)
	end) end)
	test("Absent dead participant is not respawned by departure",function() fixture(2,function(f)
		f.s:Damage(damage(101,"Abyss"));f.all[1].Parent=nil
		f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true});f.s:_Sync()
		assert(f.s._states[101].lifeState=="Dead" and not f.restores[101])
	end) end)
	test("Disconnecting target invalidates active rescue",function() fixture(2,function(f)
		f.s:Damage(damage(101));assert(f.i:Begin(f.all[2],"Revive_101",1));f.all[1].Parent=nil;f.i:_Step()
		assert(not f.i._holds[f.all[2]] and f.s._states[101].lifeState=="Downed")
	end) end)
	test("Server survival state prevents dead player escape",function() fixture(2,function(f)
		f.s:Damage(damage(101,"Abyss"));assert(f.runs:GetSnapshot().participants["101"].lifeState=="Dead")
		assert(not f.machine:SetParticipantSurvival("WrongRun",101,Model.New()))
		local malformed=Model.New();malformed.protectionUntil=0/0;assert(not f.machine:SetParticipantSurvival("SurvivalTest",101,malformed))
	end) end)
	test("Revival protection blocks generic objective holds",function() fixture(2,function(f)
		local b=f.all[2];f.s:Damage(damage(101));b:SetAttribute("EHProtectionUntil",workspace:GetServerTimeNow()+3)
		assert(not f.i:Begin(b,"Revive_101",1))
	end) end)
	test("Fast next-floor transition still restores once",function() fixture(2,function(f)
		f.s:Damage(damage(101,"Abyss"));f.dispatch("CompleteObjective");f.dispatch("BeginDeparture")
		f.dispatch("CleanupResult",{succeeded=true});f.dispatch("PrepareFloor");f.s:_Sync()
		assert(f.s._states[101].lifeState=="Alive" and f.restores[101]==1)
		f.s:_Sync();assert(f.restores[101]==1)
	end) end)
	test("Broken target Humanoid cannot complete rescue",function() fixture(2,function(f)
		f.s:Damage(damage(101));assert(f.i:Begin(f.all[2],"Revive_101",1))
		f.all[1].Character.Humanoid.Health=0;f.i:_Step();assert(not f.i._holds[f.all[2]])
	end) end)
	test("Reserved teammate suspends encounters and expiry fails run",function() fixture(2,function(f)
		local p=f.machine._record.participants["102"];p.connectionState="Disconnected";p.reconnectDeadline=105;f.all[2].Parent=nil
		f.s:Damage(damage(101));assert(f.s:IsEncounterSuspended());assert(f.runs:GetSnapshot().phase=="FloorActive")
		assert(not f.s:Damage(damage(101)));f.advance(5);f.s:_Step();assert(f.runs:GetSnapshot().phase=="Failed")
	end) end)
	test("Returning capable reservation resumes encounter",function() fixture(2,function(f)
		local p=f.machine._record.participants["102"];local parent=f.all[2].Parent
		p.connectionState="Disconnected";p.reconnectDeadline=105;f.all[2].Parent=nil
		f.s:Damage(damage(101));assert(f.s:IsEncounterSuspended())
		p.connectionState="Connected";f.all[2].Parent=parent;f.s:_Step();assert(not f.s:IsEncounterSuspended())
		assert(f.runs:GetSnapshot().phase=="FloorActive")
	end) end)
	test("Dead Humanoid restoration explicitly reloads and resets stamina",function()
		local Character=require(root.Services.CharacterService);local Scope=require(Shared.Utilities.CleanupScope)
		local Sprint=require(Shared.Utilities.SprintModel)
		local service=Character.new();service:Init({GameRunService={GetViewFor=function()return {runId="ReturnTest",phase="Transit"}end}})
		service._active=true
		local attrs={};local spawned=0;local models={}
		local p={UserId=201,Parent=game.Players,GetAttribute=function(_,k)return attrs[k]end,SetAttribute=function(_,k,v)attrs[k]=v end}
		local r={epoch=3,life="Dead",context="Dead",runId="ReturnTest",sprint=Sprint.New(),modifiers={Water=.5},scope=Scope.new()}
		r.sprint.stamina=1;r.humanoid={Health=0};service._records[p]=r
		function p:LoadCharacterAsync()
			spawned+=1;local c=Instance.new("Model");c.Parent=workspace;table.insert(models,c)
			local part=Instance.new("Part");part.Name="HumanoidRootPart";part.Anchored=true;part.Parent=c;c.PrimaryPart=part
			local h=Instance.new("Humanoid");h.RequiresNeck=false;h.Parent=c
			self.Character=c;service:_Attach(self,r,c)
		end
		local ok,err=xpcall(function()
			assert(service:RestoreForFloor(p,CFrame.new(12000,50,12000)));task.wait(.1)
			assert(spawned==1 and attrs.EHLifeState=="Alive" and attrs.EHContext=="Transit")
			assert(r.sprint.stamina==Sprint.New().stamina and next(r.modifiers)==nil and r.epoch>3)
			assert((p.Character.HumanoidRootPart.Position-Vector3.new(12000,50,12000)).Magnitude<.1)
			assert(attrs.EHReturnSerial==1)
		end,debug.traceback)
		service:Destroy();for _,m in models do m:Destroy() end;assert(ok,err)
	end)
	test("Unchanged survival publication does not reset character controls",function()
		local life="Alive";local intent=true
		local p={GetAttribute=function(_,k)if k=="EHLifeState" then return life end end,SetAttribute=function()end}
		local service=Survival.new({players={GetPlayerByUserId=function()return p end}})
		service._characters={SetLifeState=function(_,_,value)life=value;intent=false end}
		service:_Publish(101,Model.New());service:_Publish(101,Model.New());assert(intent)
		local down=Model.New();down.lifeState="Downed";service:_Publish(101,down);assert(not intent and life=="Downed")
	end)
	local passed=0;for _,r in results do if r.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
