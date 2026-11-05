--!nonstrict
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio only")
	local root=script.Parent.Parent;local Shared=game.ReplicatedStorage.Game.Shared
	local Party=require(root.Data.PartyModel);local Policy=require(root.Data.SessionPolicy);local Directory=require(root.Data.SessionDirectory)
	local Util=require(Shared.Utilities.TableUtil);local Network=require(Shared.Contracts.NetworkContract);local Constants=require(Shared.Constants)
	local Runs=require(root.Services.GameRunService);local Session=require(root.Services.SessionService);local Character=require(root.Services.CharacterService)
	local results={};local function test(name,fn)local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err)or nil})end
	local function party(n)local p=Party.new();for id=101,100+n do assert(p:Join(id,1,true))end;return p end
	test("Solo capacity launches with one ready member",function()
		local p=party(1);assert(p:Configure(101,1,"Public"));assert(p:Ready(101,true))
		local ok,s=p:Launch(101);assert(ok and #s.members==1 and s.capacity==1)
	end)
	test("Selected capacity must be filled and every member ready",function()
		local partial=party(1);assert(partial:Ready(101,true))
		local ok,reason=partial:Launch(101);assert(not ok and reason=="PartyNotFull")
		for _,count in {1,2,3,4} do
			local p=party(count);assert(p:Configure(101,count,"Public"));assert(not p:Launch(101))
			for id=101,100+count do assert(p:Ready(id,true)) end
			local launched,s=p:Launch(101);assert(launched and #s.members==count and s.capacity==count)
		end
	end)
	test("Capacity fill does not automatically launch",function()local p=party(4);assert(p:Get(1).state=="Open");assert(not p:Join(105,1,true))end)
	test("Player cannot join two crews",function()local p=party(1);assert(not p:Join(101,2,true));assert(p:ForUser(101)==1)end)
	test("Membership and settings clear readiness",function()
		local p=party(1);p:Ready(101,true);p:Join(102,1,true);assert(next(p:Get(1).ready)==nil)
		p:Ready(101,true);assert(p:Configure(101,3,"FriendsOfHost"));assert(next(p:Get(1).ready)==nil)
	end)
	test("Host-only settings cannot shrink below occupancy",function()
		local p=party(2);assert(not p:Configure(102,4,"Public"));assert(not p:Configure(101,1,"Public"));assert(not p:Configure(101,5,"Public"));assert(not p:Launch(102))
	end)
	test("Host transfers to longest-present member",function()
		local p=party(3);p:Configure(101,4,"FriendsOfHost");assert(p:Leave(101));assert(p:Get(1).hostUserId==102 and #p:Get(1).members==2)
		assert(not p:Join(104,1,false));assert(p:Join(104,1,true,p:Get(1).revision))
	end)
	test("Async friendship result cannot admit against changed settings",function()
		local p=party(1);local revision=p:Get(1).revision;p:Configure(101,4,"FriendsOfHost");assert(not p:Join(102,1,true,revision))
	end)
	test("Launch locks membership and duplicate starts",function()
		local p=party(4);for id=101,104 do p:Ready(id,true) end;local ok,s=p:Launch(101);assert(ok)
		assert(not p:Launch(101) and not p:Join(103,1,true) and not p:Leave(102) and not p:Configure(101,3,"Public"))
		assert(table.isfrozen(s.members));p:Leave(101,true);assert(#s.members==4)
	end)
	test("Failed allocation recovers correct party and clears ready",function()
		local p=party(4);for id=101,104 do p:Ready(id,true) end;local _,s=p:Launch(101);assert(not p:Recover(1,"Wrong"));assert(p:Recover(1,s.partyId));assert(p:Get(1).state=="Open" and next(p:Get(1).ready)==nil)
	end)
	test("Finished launch frees surviving lobby members and bay",function()
		local p=party(4);local id=p:Get(1).partyId;p:Finish(1,id);assert(not p:Get(1) and not p:ForUser(101));assert(p:Join(105,1,true))
	end)
	local function directory()
		local data={};local now=100;local map={}
		function map:GetAsync(k)return data[k] and Util.DeepClone(data[k])end
		function map:SetAsync(k,v) data[k]=Util.DeepClone(v)end
		function map:UpdateAsync(k,fn)
			-- Exercise retryable transforms: the first attempted result is discarded.
			fn(self:GetAsync(k));local value=fn(self:GetAsync(k))
			if value==nil then return nil end
			data[k]=Util.DeepClone(value);return Util.DeepClone(value)
		end
		return Directory.new(map,function()return now end),function(dt)now+=dt end,data,map
	end
	test("Allocation records immutable roster and server-only access code",function()
		local d=directory();local t=d:Create("RunA",{101,102},"SecretCode","PrivateA")
		assert(t.status=="Waiting" and #t.roster==2 and t.members["101"].deadline==265)
		assert(d:ForUser(101).id=="RunA")
	end)
	test("Concurrent session allocation cannot steal a user reservation",function()
		local d=directory();d:Create("RunA",{101},"CodeA","PrivateA")
		assert(not pcall(function()d:Create("RunB",{102,101},"CodeB","PrivateB")end))
		assert(d:ForUser(101).id=="RunA" and d:ForUser(102)==nil and d:Get("RunB").status=="Ended")
	end)
	test("A pointer left over from a run already under way never blocks a new launch",function()
		local d=directory();d:Create("RunA",{101},"CodeA","PrivateA");assert(d:Claim("RunA",101,"PrivateA","JobA"))
		assert(d:Publish("RunA","JobA",{["101"]={state="Disconnected",deadline=400}},false))
		local t=d:Create("RunB",{101},"CodeB","PrivateB");assert(t and t.status=="Waiting" and d:ForUser(101).id=="RunB")
	end)
	test("Only original roster reaches the matching reserved process",function()
		local d=directory();d:Create("RunA",{101,102},"Code","PrivateA")
		assert(not d:Claim("RunA",999,"PrivateA","JobA"));assert(not d:Claim("RunA",101,"Public","JobA"))
		assert(d:Claim("RunA",101,"PrivateA","JobA"));assert(not d:Claim("RunA",102,"PrivateA","JobB"))
		assert(d:Claim("RunA",102,"PrivateA","JobA"));assert(d:Get("RunA").arrivals==2)
	end)
	test("Duplicate arrival claim and connected replay rejected",function()
		local d=directory();d:Create("RunA",{101},"Code","PrivateA");assert(d:Claim("RunA",101,"PrivateA","JobA"));assert(not d:Claim("RunA",101,"PrivateA","JobA"))
		d:Publish("RunA","JobA",{["101"]={state="Connected",deadline=0}},false);assert(not d:Claim("RunA",101,"PrivateA","JobA"))
	end)
	test("Same-account disconnected reservation reconnects before deadline",function()
		local d,advance=directory();d:Create("RunA",{101},"Code","PrivateA");d:Claim("RunA",101,"PrivateA","JobA")
		d:Publish("RunA","JobA",{["101"]={state="Disconnected",deadline=220}},false);advance(20)
		assert(Policy.CanReconnect(d:ForUser(101),101,120));assert(d:Claim("RunA",101,"PrivateA","JobA"))
	end)
	test("Expired abandoned finished and stale-server sessions deny access",function()
		local d,advance=directory();d:Create("RunA",{101},"Code","PrivateA");d:Claim("RunA",101,"PrivateA","JobA")
		d:Publish("RunA","JobA",{["101"]={state="Disconnected",deadline=110}},false);advance(10)
		assert(not d:Claim("RunA",101,"PrivateA","JobA"))
		d:Publish("RunA","JobA",{["101"]={state="Abandoned",deadline=0}},false);assert(d:ForUser(101)==nil)
		d:End("RunA");assert(not d:Claim("RunA",101,"PrivateA","JobA"))
		local t={status="Active",heartbeat=0,members={["101"]={state="Disconnected",deadline=999}},privateId="PrivateA"}
		assert(not Policy.CanJoin(t,101,"PrivateA","JobA",61))
	end)
	test("No-arrival cancellation cannot cancel a claimed destination",function()
		local d=directory();d:Create("RunA",{101},"Code","PrivateA");d:Claim("RunA",101,"PrivateA","JobA");assert(not d:End("RunA",true));assert(d:Get("RunA").status~="Ended")
	end)
	test("Ended older session cannot erase a newer user index",function()
		local d=directory();d:Create("RunA",{101},"CodeA","PrivateA");d:End("RunA");d:Create("RunB",{101},"CodeB","PrivateB");d:End("RunA");assert(d:ForUser(101).id=="RunB")
	end)
	test("Party network messages reject injected host roster and access code",function()
		local function packet(action,payload)return {schemaVersion=Constants.SchemaVersion,requestId=1,action=action,payload=payload}end
		assert(Network.ValidateAction(packet("PartyConfigure",{capacity=1,accessMode="Public"})))
		assert(not Network.ValidateAction(packet("PartyConfigure",{capacity=5,accessMode="Public"})))
		assert(not Network.ValidateAction(packet("PartyReady",{ready="true"})))
		for _,action in {"PartyLaunch","ReconnectRun","ReturnLobby","PartyLeave"} do
			assert(Network.ValidateAction(packet(action,{})));assert(not Network.ValidateAction(packet(action,{accessCode="X",hostUserId=101,roster={101}})))
		end
	end)
	test("Session run retains absent original members but rejects zero arrivals",function()
		local players={GetPlayerByUserId=function(_,id)return id==101 and {UserId=101}end}
		local r=Runs.new({players=players,clock=function()return 100 end});r:Init({ProfileService={IsReady=function()return true end}});r:Start()
		assert(not r:CreateSessionRun("TestRun",{101,102},{},220).ok)
		assert(r:CreateSessionRun("TestRun",{101,102},{[101]=true},220).ok)
		local s=r:GetSnapshot();assert(#s.originalRoster==2 and s.participants["102"].connectionState=="Disconnected" and s.participants["102"].reconnectDeadline==220)
		assert(not r:SetConnection(999,"Connected"));assert(r:SetConnection(102,"Abandoned"));assert(not r:SetConnection(102,"Connected"));r:Destroy()
	end)
	test("Admission gate prevents premature character spawn",function()
		local c=Character.new();c._active=true;c:SetAdmissionRequired(true)
		local p={};c._records[p]={life="Alive",admitted=false}
		local ok,code=c:Spawn(p);assert(not ok and code=="NotAdmitted")
	end)
	test("Rejected reconnect cannot extend existing deadline",function()
		local s=Session.new();s._runs={GetSnapshot=function()return {phase="FloorActive",participants={["101"]={connectionState="Disconnected"}}}end,SetConnection=function()error("Must not reset deadline")end}
		s._Publish=function()end;s:_Leave({UserId=101});assert(s._removed[101])
	end)
	local function sessionFixture(roster,fn)
		local d,tick=directory();d:Create("SessionFixture",roster,"HiddenCode","PrivateA")
		local now=100;local people={};local players={}
		function players:GetPlayers()local list={} for _,p in people do if p.Parent==self then table.insert(list,p)end end return list end
		function players:GetPlayerByUserId(id)local p=people[id];return p and p.Parent==self and p or nil end
		local profiles={IsReady=function()return true end}
		local runs=Runs.new({players=players,clock=function()return now end});runs:Init({ProfileService=profiles});runs:Start()
		local chars={RetargetAdmission=function(_,p,life,frame)p.admittedLife=life;p.retargetedFrame=frame;p:SetAttribute("EHLifeState",life)end,SetAdmissionRequired=function()end,SetSuspended=function()end,SetAdmissionReady=function(_,p,v)p.ready=v end,
			RestoreAdmissionStamina=function(_,p,v)p.restoredStamina=v end,IsCharacterReady=function()return true end,
			Admit=function(_,p,life,frame,stamina)p.admittedLife=life;p:SetAttribute("EHLifeState",life)end}
		local survival={SetConnectionManaged=function()end,RefreshPlayer=function()end,RecalculateContinuation=function()end,
			RestoreReconnect=function(_,p,advanced)if advanced then runs:SetParticipantSurvival("SessionFixture",p.UserId,{lifeState="Alive",revivesUsedThisFloor=0,downedDeadline=0,protectionUntil=0})end end}
		local s=Session.new({players=players,clock=function()return now end,monotonic=function()return now end,required=true,directory=d,
			server={universe=123,privateId="PrivateA",ownerId=0,jobId="JobA"}})
		s:Init({EnvironmentService={Role="Game"},ProfileService=profiles,GameRunService=runs,CharacterService=chars,SurvivalService=survival,
			InventoryService={_InBounds=function()return false end,Drop=function(_,p)p.drops=(p.drops or 0)+1 end},InteractionService={Cancel=function(_,p)p.canceled=true end}})
		s._active=true
		local function person(id,source)
			local attrs={EHStamina=37};local p={UserId=id,Parent=players}
			function p:GetAttribute(k)return attrs[k]end;function p:SetAttribute(k,v)attrs[k]=v end
			function p:GetJoinData()return {SourceGameId=source or 123,SourcePlaceId=require(Shared.Config.PlaceConfig).LobbyPlaceId,TeleportData={sessionId="SessionFixture"}}end
			function p:Kick(reason)self.kicked=reason;self.Parent=nil end
			people[id]=p;return p
		end
		local f={s=s,r=runs,d=d,person=person,advance=function(dt)now+=dt;tick(dt)end,
			dispatch=function(action,payload)local r=runs:Dispatch({token=runs:GetToken(),action=action,payload=payload or {}});assert(r.ok,r.code)end}
		local ok,err=xpcall(function()fn(f)end,debug.traceback)
		s:Destroy();runs:Destroy();assert(ok,err)
	end
	test("Actual session service waits for client readiness before run creation",function()sessionFixture({101},function(f)
		local p=f.person(101);f.s:_Join(p);f.s:_Step();assert(not f.r:GetSnapshot() and not f.s:IsReady(p))
		f.s:ClientReady(p);f.s:_Step();assert(f.s:IsReady(p) and f.r:GetSnapshot().phase=="Intro")
		f.advance(3);f.s:_Step();assert(f.r:GetSnapshot().phase=="FloorActive")
	end)end)
	test("Partial arrival starts after 45 seconds with original missing reservation",function()sessionFixture({101,102},function(f)
		local p=f.person(101);f.s:_Join(p);f.s:ClientReady(p);f.s:_Step();assert(not f.r:GetSnapshot())
		f.advance(45);f.s:_Step();local r=f.r:GetSnapshot();assert(r.phase=="Intro" and r.participants["102"].connectionState=="Disconnected")
		assert(r.participants["102"].reconnectDeadline==265)
	end)end)
	test("Actual admission rejects outsiders and forged teleport source",function()sessionFixture({101},function(f)
		local outsider=f.person(999);f.s:_Join(outsider);assert(outsider.kicked)
		local forged=f.person(101,999);f.s:_Join(forged);assert(forged.kicked and not forged.admittedLife)
	end)end)
	test("Reconnect preserves death and requires new readiness",function()sessionFixture({101},function(f)
		local p=f.person(101);f.s:_Join(p);f.s:ClientReady(p);f.s:_Step();f.advance(3);f.s:_Step()
		f.r:SetParticipantSurvival("SessionFixture",101,{lifeState="Dead",revivesUsedThisFloor=1,downedDeadline=0,protectionUntil=0})
		f.s:_Leave(p);p.Parent=nil;assert(f.r:GetSnapshot().participants["101"].connectionState=="Disconnected")
		local returned=f.person(101);f.s:_Join(returned);assert(returned.admittedLife=="Dead" and not f.s:IsReady(returned))
		f.s:ClientReady(returned);f.s:_Step();local r=f.r:GetSnapshot().participants["101"]
		assert(r.lifeState=="Dead" and r.revivesUsedThisFloor==1 and r.connectionState=="Connected")
	end)end)
	test("Disconnect drops objective and preserves stamina for ready-time restore",function()sessionFixture({101},function(f)
		local p=f.person(101);f.s:_Join(p);f.s:ClientReady(p);f.s:_Step();f.advance(3);f.s:_Step()
		f.s:_Leave(p);p.Parent=nil;assert(p.drops==1 and p.canceled)
		local returned=f.person(101);f.s:_Join(returned);f.s:ClientReady(returned);f.s:_Step();assert(returned.restoredStamina==37)
	end)end)
	test("Reconnect after floor advancement uses normal life restoration",function()sessionFixture({101,102},function(f)
		local a,b=f.person(101),f.person(102)
		for _,p in {a,b} do f.s:_Join(p);f.s:ClientReady(p)end;f.s:_Step();f.advance(3);f.s:_Step()
		f.r:SetParticipantSurvival("SessionFixture",101,{lifeState="Dead",revivesUsedThisFloor=1,downedDeadline=0,protectionUntil=0})
		f.s:_Leave(a);a.Parent=nil;f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true});f.dispatch("PrepareFloor");f.dispatch("ActivateFloor")
		local returned=f.person(101);f.s:_Join(returned);assert(returned.admittedLife=="Alive")
		f.s:ClientReady(returned);f.s:_Step();local r=f.r:GetSnapshot().participants["101"];assert(r.lifeState=="Alive" and r.revivesUsedThisFloor==0)
	end)end)
	local function startPair(f)
		local a,b=f.person(101),f.person(102)
		for _,p in {a,b}do f.s:_Join(p);f.s:ClientReady(p)end
		f.s:_Step();f.advance(3);f.s:_Step();return a,b
	end
	test("Returning during transit receives the committed departure restoration",function()sessionFixture({101,102},function(f)
		local a=startPair(f)
		f.r:SetParticipantSurvival("SessionFixture",101,{lifeState="Dead",revivesUsedThisFloor=1,downedDeadline=0,protectionUntil=0})
		f.s:_Leave(a);a.Parent=nil
		f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true})
		local p=f.person(101);f.s:_Join(p);assert(p.admittedLife=="Alive","Transit has the old floor ID but a new completed milestone")
		f.s:ClientReady(p);f.s:_Step();assert(f.r:GetSnapshot().participants["101"].lifeState=="Alive")
	end)end)
	test("Floor departure while reconnect is loading retargets to the cabin",function()sessionFixture({101,102},function(f)
		local a=startPair(f);f.s:_Leave(a);a.Parent=nil
		local p=f.person(101);f.s:_Join(p);assert(not f.s:IsReady(p))
		f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true});f.dispatch("PrepareFloor");f.dispatch("ActivateFloor")
		f.s:ClientReady(p);f.s:_Step();assert(f.s:IsReady(p) and f.s._admitted[p]);assert(p.restoredStamina==nil,"Old-floor stamina must not override restoration")
	end)end)
	test("A downed timeout during loading restores death instead of stale downing",function()sessionFixture({101,102},function(f)
		local a=startPair(f)
		f.r:SetParticipantSurvival("SessionFixture",101,{lifeState="Downed",revivesUsedThisFloor=0,downedDeadline=125,protectionUntil=0})
		f.s:_Leave(a);a.Parent=nil;local p=f.person(101);f.s:_Join(p);assert(p.admittedLife=="Downed")
		f.r:SetParticipantSurvival("SessionFixture",101,{lifeState="Dead",revivesUsedThisFloor=0,downedDeadline=0,protectionUntil=0})
		f.s:ClientReady(p);f.s:_Step();assert(p.admittedLife=="Dead" and f.s:IsReady(p))
	end)end)
	test("Abandonment while loading rejects admission even before timeout",function()sessionFixture({101,102},function(f)
		local a=startPair(f);f.s:_Leave(a);a.Parent=nil;local p=f.person(101);f.s:_Join(p)
		assert(f.r:SetConnection(101,"Abandoned"));f.s:ClientReady(p);f.s:_Step();assert(p.kicked and not f.s:IsReady(p))
	end)end)
	test("Loading timeout cannot extend an original reconnect reservation",function()sessionFixture({101,102},function(f)
		local a=startPair(f);f.s:_Leave(a);a.Parent=nil;local deadline=f.r:GetSnapshot().participants["101"].reconnectDeadline
		local p=f.person(101);f.s:_Join(p);f.advance(20);f.s:_Step();assert(p.kicked)
		f.s:_Leave(p);assert(f.r:GetSnapshot().participants["101"].reconnectDeadline==deadline)
	end)end)
	test("Directory changes during an in-flight heartbeat flush immediately afterward",function()sessionFixture({101},function(f)
		local p=f.person(101);f.s:_Join(p)
		local original=f.d.Publish;local entered,release,finished=false,false,false;local writes=0
		function f.d:Publish(...)
			writes+=1
			if writes==1 then entered=true;while not release do task.wait()end end
			local result=original(self,...);if writes>=2 then finished=true end;return result
		end
		f.s:_Publish();local limit=os.clock()+3;while not entered and os.clock()<limit do task.wait()end;assert(entered)
		f.s._removed[101]=true;f.s:_Publish();release=true
		while not finished and os.clock()<limit do task.wait()end
		assert(finished and writes==2);assert(f.d:Get("SessionFixture").members["101"].state=="Disconnected")
	end)end)

 test("Empty transit rejects advancement and resumes with an admitted member",function()sessionFixture({101,102},function(f)
  local a,b=startPair(f)
  f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true})
  f.s:_Leave(a);f.s:_Leave(b)
  local result=f.r:Dispatch({token=f.r:GetToken(),action="PrepareFloor",payload={}})
  assert(not result.ok and result.code=="AwaitingReconnect" and f.r:GetSnapshot().phase=="Transit")
  assert(f.r:SetConnection(101,"Connected"));f.dispatch("PrepareFloor");f.dispatch("ActivateFloor")
 end)end)
 test("Expired empty transit can resolve a wipe",function()sessionFixture({101,102},function(f)
  local a,b=startPair(f)
  f.dispatch("CompleteObjective");f.dispatch("BeginDeparture");f.dispatch("CleanupResult",{succeeded=true})
  f.s:_Leave(a);f.s:_Leave(b);f.r:SetConnection(101,"Abandoned");f.r:SetConnection(102,"Abandoned")
  f.dispatch("Wipe");f.dispatch("Resolve");assert(f.r:GetSnapshot().result.reason=="TeamWipe")
 end)end)
 test("Empty intro retains its pending start until a member returns",function()sessionFixture({101},function(f)
  local p=f.person(101);f.s:_Join(p);f.s:ClientReady(p);f.s:_Step();f.s:_Leave(p);p.Parent=nil
  f.advance(3);f.s:_Step();assert(f.r:GetSnapshot().phase=="Intro" and f.s._introUntil)
  local q=f.person(101);f.s:_Join(q);f.s:ClientReady(q);f.s:_Step();assert(f.r:GetSnapshot().phase=="FloorActive")
 end)end)
 local passed=0;for _,r in results do if r.passed then passed+=1 end end
	return {passed=passed,total=#results,results=results}
end
return table.freeze(Checks)
