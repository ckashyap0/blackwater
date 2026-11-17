--!nonstrict
-- R43: checks for the shared set-piece systems (interaction modes, rising water, beats, camera cuts).
-- Studio only; run with Workspace.RunDevChecks = true. Nothing here touches a live run.
local Checks={}
function Checks.Run()
	assert(game:GetService("RunService"):IsStudio(),"Studio only")
	local root=script.Parent.Parent;local Shared=game.ReplicatedStorage.Game.Shared
	local Interaction=require(root.Services.InteractionService)
	local Water=require(root.Floors.RisingWater)
	local Beats=require(root.Floors.BeatRunner)
	local Network=require(Shared.Contracts.NetworkContract);local Constants=require(Shared.Constants)
	local results={}
	local function test(name,fn)
		local ok,err=xpcall(fn,debug.traceback);table.insert(results,{name=name,passed=ok,error=not ok and tostring(err) or nil})
	end
	-- an isolated InteractionService with two fake players standing at a target
	local function fixture(defs,fn)
		local container=Instance.new("Folder");container.Name="IsolatedSetPieceChecks";container.Parent=workspace
		local users={};local now=0
		local s=Interaction.new({clock=function()return now end,players=users,holdBonus=0});s._active=true
		s._runs={GetViewFor=function()return {runId="R",floorInstanceId="F",phase="FloorActive"} end}
		local function actor(id,x)
			local c=Instance.new("Model");c.Parent=container
			local r=Instance.new("Part");r.Name="HumanoidRootPart";r.Anchored=true;r.Position=Vector3.new(x,53,6004);r.Parent=c
			Instance.new("Humanoid").Parent=c
			local attrs={EHCharacterEpoch=1,EHLifeState="Alive"}
			return {UserId=id,Parent=users,Character=c,GetAttribute=function(_,k)return attrs[k] end,SetAttribute=function(_,k,v)attrs[k]=v end}
		end
		local a,b=actor(201,6000),actor(202,6002)
		local done={}
		for i,d in defs do
			local t=Instance.new("Part");t.Name="T"..i;t.Anchored=true;t.Size=Vector3.new(1,2,1);t.Position=Vector3.new(5999+i,53,6000);t.Parent=container
			d.target=t;d.runId="R";d.floorInstanceId="F";d.allowedRunPhases={FloorActive=true}
			local id=d.interactionId;d.complete=function()done[id]=(done[id] or 0)+1;return true end
			s:Register(d)
		end
		local ok,err=xpcall(function()fn({s=s,a=a,b=b,advance=function(dt)now+=dt end,done=done})end,debug.traceback)
		s:Destroy();container:Destroy();assert(ok,err)
	end
	test("A crank is credited no faster than its max rate and completes at its work",function()
		fixture({{interactionId="Wheel",mode="Crank",work=2,maxRate=1}},function(f)
			assert(f.s:Begin(f.a,"Wheel",1))
			f.advance(.25);f.s:Continue(f.a,"Wheel",1,5) -- claims 5 turns in a quarter second
			local p=f.s:GetProgress("Wheel");assert(p<.5,"credited "..p)
			for _=1,12 do f.advance(.25);f.s:Continue(f.a,"Wheel",1,.25) end
			assert(f.done.Wheel==1,"did not complete")
			assert(not f.s:Begin(f.a,"Wheel",1),"a finished crank starts again")
		end)
	end)
	test("A crank stalls while its rate is zero and keeps its progress between holds",function()
		local stall=true
		fixture({{interactionId="Wheel",mode="Crank",work=3,rate=function()return stall and 0 or 1 end}},function(f)
			assert(f.s:Begin(f.a,"Wheel",1));f.advance(.25);f.s:Continue(f.a,"Wheel",1,.25)
			assert(f.s:GetProgress("Wheel")==0,"moved while stalled")
			stall=false;f.advance(.25);f.s:Continue(f.a,"Wheel",1,.25);local p=f.s:GetProgress("Wheel");assert(p>0)
			f.s:Cancel(f.a,"Released");assert(f.s:GetProgress("Wheel")==p,"progress lost on release")
			assert(f.s:Begin(f.b,"Wheel",1),"a teammate can carry on")
		end)
	end)
	test("A lever that does not persist resets when let go",function()
		fixture({{interactionId="Lever",mode="Lever",work=1,persist=false}},function(f)
			assert(f.s:Begin(f.a,"Lever",1));f.advance(.25);f.s:Continue(f.a,"Lever",1,.3);assert(f.s:GetProgress("Lever")>0)
			f.s:Cancel(f.a,"Released");assert(f.s:GetProgress("Lever")==0)
		end)
	end)
	test("Pump strokes closer than the minimum gap do not count, and a sustained pump drains when the beat stops",function()
		fixture({{interactionId="Pump",mode="Pump",work=10,sustain=true,decay=2,pumpGap={min=.25,max=1}}},function(f)
			assert(f.s:Begin(f.a,"Pump",1))
			f.s:Continue(f.a,"Pump",1,1);f.advance(.05);f.s:Continue(f.a,"Pump",1,1)
			assert(f.s:GetProgress("Pump")==1,"double tap counted")
			for _=1,12 do f.advance(.4);f.s:Continue(f.a,"Pump",1,1) end
			assert(f.s:GetProgress("Pump")==10 and not f.done.Pump,"sustain completed or did not fill")
			f.s:_Step();f.advance(1.2);f.s:Continue(f.a,"Pump",1);f.s:_Step();f.advance(.4);f.s:_Step()
			assert(f.s:GetProgress("Pump")<10,"did not drain")
		end)
	end)
	test("A sync hold waits for the crew and completes everyone together",function()
		fixture({{interactionId="SyncA",mode="Sync",syncGroup="G",holdDuration=1},{interactionId="SyncB",mode="Sync",syncGroup="G",holdDuration=1}},function(f)
			assert(f.s:Begin(f.a,"SyncA",1));f.advance(1.1);f.s:Continue(f.a,"SyncA",1);f.s:_Step()
			assert(not f.done.SyncA and f.s._holds[f.a] and f.s._holds[f.a].ready,"completed alone")
			assert(f.s:Begin(f.b,"SyncB",1));f.advance(1.1);f.s:Continue(f.a,"SyncA",1);f.s:Continue(f.b,"SyncB",1);f.s:_Step()
			assert(f.done.SyncA==1 and f.done.SyncB==1,"not completed together")
		end)
	end)
	test("The network contract accepts reported effort and refuses bad numbers",function()
		local function packet(work)return {schemaVersion=Constants.SchemaVersion,requestId=1,action="ContinueInteraction",payload={characterEpoch=1,interactionId="Wheel",work=work}} end
		assert(Network.ValidateAction(packet(.5)))
		assert(not Network.ValidateAction(packet(-1)) and not Network.ValidateAction(packet(0/0)) and not Network.ValidateAction(packet(99)))
		assert(Network.ValidateAction({schemaVersion=Constants.SchemaVersion,requestId=1,action="ContinueInteraction",payload={characterEpoch=1,interactionId="Wheel"}}))
	end)
	test("Rising water follows its stages and runs its failure once",function()
		local folder=Instance.new("Folder");folder.Name="WaterCheck";folder:SetAttribute("Stages","0;2;5");folder:SetAttribute("FailRise",4.5)
		local surf=Instance.new("Part");surf.Name="Surface";surf.Anchored=true;surf.Position=Vector3.new(0,-500,0);surf.Parent=folder
		local now=0;local fails=0
		local w=Water.new(folder,{now=function()return now end,onFail=function()fails+=1 end})
		local ok,err=pcall(function()
			assert(w.Base==-500 and w:Rise()==0)
			w:ToStage(2,4);now=2;assert(math.abs(w:Rise()-1)<1e-6);now=4;assert(w:Rise()==2)
			w:ToStage(3,2);now=6;w:Step(.1);w:Step(.1);task.wait()
			assert(fails==1,"fail ran "..fails.." times")
			w:ToStage(1,1);now=7;assert(w:Rise()==0)
		end)
		folder:Destroy();assert(ok,err)
	end)
	test("Beats fire once on their conditions and can be reset",function()
		local m=Instance.new("Model");local now=0;local runs=0
		local r=Beats.new(m,{
			A={when={stage="Two"},run=function()runs+=1 end},
			B={when={after="A",delay=2}},
			C={when={attr="Count",atLeast=3}},
			D={when={manual=true}},
		},{now=function()return now end})
		r:Step();assert(not r:Fired("A"))
		m:SetAttribute("Stage","Two");r:Step();r:Step();assert(r:Fired("A") and runs==1 and m:GetAttribute("Beat_A")==0)
		now=1;r:Step();assert(not r:Fired("B"));now=2;r:Step();assert(r:Fired("B"))
		m:SetAttribute("Count",3);r:Step();assert(r:Fired("C"));r:Step();assert(not r:Fired("D"));assert(r:Fire("D"))
		r:Reset({"A"});assert(not r:Fired("A") and m:GetAttribute("Beat_A")==nil)
		m:Destroy()
	end)
	test("Every camera cut points at markers that exist in its floor",function()
		local cuts=require(Shared.Config.Cinematics)
		local Refs=require(Shared.Utilities.FloorRefs)
		local templates=game.ServerStorage:FindFirstChild("GameAssets") and game.ServerStorage.GameAssets:FindFirstChild("FloorTemplates")
		for floor,list in cuts do
			local t=templates and templates:FindFirstChild(floor)
			if t then
				for id,cut in list do
					for i,shot in cut.shots do
						for _,k in {"from","to","lookAt"} do
							if shot[k] then assert(Refs.Find(t,shot[k]),floor.."."..id.." shot "..i.." is missing marker "..shot[k]) end
						end
					end
				end
			end
		end
	end)
	return {results=results}
end
return Checks
