--!nonstrict
local Players=game:GetService("Players")
local Heartbeat=game:GetService("RunService").Heartbeat
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Policy=require(script.Parent.Parent.Data.ElevatorPolicy)
local Templates=require(game.ServerStorage.GameAssets.FloorRegistry)
local TemporaryFloor=require(script.Parent.Parent.Floors.TemporaryFloor)
local Level5Floor=require(script.Parent.Parent.Floors.Level5Floor)
local Level4Floor=require(script.Parent.Parent.Floors.Level4Floor)
local Intro=require(game.ReplicatedStorage.Game.Shared.Utilities.IntroTimeline)
local Slots=require(game.ReplicatedStorage.Game.Shared.Utilities.CabinSlots)
local Level5Config=require(game.ReplicatedStorage.Game.Shared.Config.Level5)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local SoundFade=require(game.ReplicatedStorage.Game.Shared.Utilities.SoundFade)
local Service={};Service.__index=Service
-- Descent funnel telemetry (Creator Hub > Analytics > Funnels): one step when a floor opens and one
-- when its objective is done, for every crew member on the run. Floor 5 arrival is step 1, its
-- completion step 2, Floor 4 arrival step 3, and so on down. Logged after the fact; never blocks play.
local DESCENT_FUNNEL="Descent"
local function logDescent(floorNumber,done)
	local n=tonumber(floorNumber);if not n or n<1 or n>5 then return end
	local step=(5-n)*2+(done and 2 or 1)
	local name=(done and "Completed Floor " or "Reached Floor ")..n
	for _,p in game:GetService("Players"):GetPlayers()do
		pcall(function()game:GetService("AnalyticsService"):LogFunnelStepEvent(p,DESCENT_FUNNEL,game.JobId,step,name)end)
	end
end
-- A crew member's place in the cabin: the slot's spot on the floor, with the root at exactly the
-- height the Humanoid stands at by itself. The crew are held anchored through the intro, so a root
-- placed any lower or higher would settle (a visible drop/pop) the moment the doors release them.
function Service:_SlotFrame(p,roster)
	local frame=Slots.Frame(self._environment.Spawn.CFrame,p.UserId,roster)
	-- every crew member stands squarely facing the inside of the lift doors (level, no drift)
	if self._cabin then local out=self:_DoorOutward();frame=CFrame.lookAt(frame.Position,frame.Position+out) end
	local character=p.Character
	local h=character and character:FindFirstChildOfClass("Humanoid");local root=character and character:FindFirstChild("HumanoidRootPart")
	if not(h and root and self._cabin)then return frame end
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances={self._cabin};params.RespectCanCollide=true
	local hit=workspace:Raycast(frame.Position+Vector3.new(0,2,0),Vector3.new(0,-8,0),params)
	if not hit then return frame end
	return frame.Rotation+Vector3.new(frame.X,hit.Position.Y+h.HipHeight+root.Size.Y/2,frame.Z)
end
local finished={Resolving=true,Completed=true,Failed=true,Closing=true}
function Service.new(options)
	options=options or {}
	return setmetatable({Name="ElevatorService",Dependencies={"EnvironmentService","GameRunService","InteractionService","InventoryService","SurvivalService","CharacterService","SessionService"},
		_players=options.players or Players,_factory=options.factory or Templates.Build,_preloadEnabled=options.factory==nil,_introSeconds=options.introSeconds or Level5Config.IntroSeconds,_arrivalDoorSeconds=options.arrivalDoorSeconds or (options.introSeconds and 2 or Intro.DoorSeconds),_elapsed=0,_alpha=0},Service)
end
function Service:Init(deps)
	self._environment=deps.EnvironmentService;self._runs=deps.GameRunService;self._interactions=deps.InteractionService;self._inventory=deps.InventoryService
	self._survival=deps.SurvivalService;self._characters=deps.CharacterService;self._session=deps.SessionService;self._scope=Scope.new()
	if self._environment.Role~="Game" then return end
	self._runs.FloorsManaged=true
	self._cabin=self._environment.Model.Elevator
	self._doorFrames={}
	for _,name in {"LeftDoor","RightDoor"} do local door=Refs.Get(self._cabin,name);self._doorFrames[name]=door.CFrame;door:SetAttribute('ClosedFrame',door.CFrame) end
	self:_Doors(0);self:_State("Closed","WAITING FOR CREW")
	self._survival:SetCabinProtection(function(player)
		local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return self._sealed==true and root and Policy.InCabin(root.Position)
	end)
end
function Service:_State(state,message,doorSeconds)
	if self.State~=state then
        -- how long a full open/close takes (clients animate the leaves with the same timing)
        self._doorSeconds=doorSeconds or 2;self._cabin:SetAttribute('DoorSeconds',self._doorSeconds)
        self._cabin:SetAttribute('DoorFromAlpha',self._alpha or 0)
        self._cabin:SetAttribute('DoorStartedAt',workspace:GetServerTimeNow())
    end
    self.State=state;self._cabin:SetAttribute("DoorState",state)
	self._cabin:SetAttribute("Status",message or state)
	self._interactions:SetEnabled("ElevatorClose",state=="Open")
	local legend=Refs.Find(self._cabin,"ControlLegend");local label=legend and legend:FindFirstChildWhichIsA("TextLabel",true)
	if label then label.Text=message or string.upper(state)end
end
function Service:_Doors(alpha)
	self._alpha=math.clamp(alpha,0,1)
	for _,side in {-1,1}do
		local door=Refs.Get(self._cabin,side<0 and "LeftDoor" or "RightDoor")
		local base=self._doorFrames and self._doorFrames[door.Name] or CFrame.new(side*3.9,25.5,-8)
		door.CFrame=base*CFrame.new(side*(door:GetAttribute("TravelDistance") or 7.8)*(self._alpha*self._alpha*(3-2*self._alpha)),0,0)
		door.CanCollide=self._alpha<.98
	end
end
function Service:_CabinSupply(enabled)
	if not self._cabin then return end
	if self._supplyOn==enabled and self._supplyScanned then return end
	self._supplyOn=enabled
	if not self._supplyScanned then
		-- Scan once: main lights remember their authored state, emergency lights are a separate circuit.
		self._supplyScanned=true;self._cabinLights={};self._emergency={};self._diffusers={};self._lenses={}
		for _,d in self._cabin:GetDescendants()do
			if d:IsA("Light")then
				if d.Name=="EmergencySupply"then table.insert(self._emergency,d);if d.Parent:IsA("BasePart")then self._lenses[d.Parent]=d.Parent.Material end
				else self._cabinLights[d]=d.Enabled end
			elseif d:IsA("BasePart")and d.Material==Enum.Material.Neon and d:GetAttribute("EHFlicker")then self._diffusers[d]=d.Color end
		end
	end
	for light,authored in self._cabinLights do if light.Parent then light.Enabled=enabled and authored end end
	for _,light in self._emergency do if light.Parent then light.Enabled=not enabled end end
	for part,color in self._diffusers do if part.Parent then part.Color=enabled and color or Color3.fromRGB(46,44,40) end end
	for part,material in self._lenses do if part.Parent then part.Material=enabled and material or Enum.Material.Neon end end
end
-- SkipIntro is this player's skip vote during the descent cinematic (the surface start is
-- sensor-based, see _Board, so there is nothing to request while boarding).
function Service:SkipIntro(player,runId,epoch)
    local s=self._runs:GetSnapshot()
    if not self._active or not s or s.runId~=runId or s.phase~="Intro" then return false,"IntroUnavailable" end
    local p=s.participants[tostring(player.UserId)]
    if not p or p.connectionState~="Connected" or player:GetAttribute("EHCharacterEpoch")~=epoch then return false,"StaleCharacter" end
    if self._skipped or self._elapsed>=Intro.StrainAt-Intro.UiFadeSeconds then return false,"IntroUnavailable" end
    self._skipVotes=self._skipVotes or {}
    self._skipVotes[tostring(player.UserId)]=true
    player:SetAttribute("EHSkippedIntro",runId)

    -- (Oct 18) a vote cast while still boarding on the surface used to be refused - and the client,
    -- already showing VOTED, never sent it again, so a solo skip never happened. It is now kept and
    -- counted the moment the ride down starts (the step loop re-tallies every frame).
    if self._boarding then return true,"Queued" end    self:_SkipTally(s)
    return true,"OK"
end
-- Cooperative skip, recounted from scratch every server step (so players joining, leaving or
-- dropping can never leave it stuck). The live tally (SkipVotes/SkipCrew) drives the "1/2 VOTED"
-- readout on every client.
--  * everyone connected voted            -> skip now
--  * anything less                        -> the ride simply plays on; the panel shows the tally
-- When the skip goes through the SHARED intro jumps straight to the fault, which still happens
-- exactly once through the normal timeline.
local SKIP_GRACE=4
function Service:_SkipTally(s)
    local votes=self._skipVotes or {}
    local voted,total=Intro.SkipTally(s.participants,votes)
    if self._cabin:GetAttribute("SkipVotes")~=voted then self._cabin:SetAttribute("SkipVotes",voted) end
    if self._cabin:GetAttribute("SkipCrew")~=total then self._cabin:SetAttribute("SkipCrew",total) end
    if self._skipped then return end
    local now=workspace:GetServerTimeNow()
    local go=voted>0 and Intro.AllSkipped(s.participants,votes)
    -- (only when EVERYONE has voted: no countdown on a part vote - the panel just shows 1/2, 2/3...)
    if not go and self._skipDeadline then
        self._skipDeadline=nil;self._cabin:SetAttribute("SkipDeadline",nil)
    end
    if go then
        self._skipped=true;self._skipDeadline=nil;self._cabin:SetAttribute("SkipDeadline",nil)
        self._cabin:SetAttribute('IntroSkipAt',now)
        -- straight on into the lead-up to the jolt: the dialogue and skip panel fade out over the
        -- next 1.5 s and the shake starts (no cut, the descent simply carries on)
        local to=Intro.StrainAt-Intro.UiFadeSeconds
        if self._elapsed<to then self._elapsed=to;self._cabin:SetAttribute("IntroElapsed",math.floor(self._elapsed*10)/10)end
    end
end
-- Flat direction from the middle of the cabin out through the closed doors.
function Service:_DoorOutward()
	local mid=Vector3.zero;local n=0
	for _,name in {"LeftDoor","RightDoor"}do local door=Refs.Find(self._cabin,name);local f=door and door:GetAttribute("ClosedFrame");if f then mid+=f.Position;n+=1 end end
	local from=self._environment.Spawn and self._environment.Spawn.Position or Vector3.zero
	local d=n>0 and (mid/n-from) or Vector3.new(0,0,-1)
	d=Vector3.new(d.X,0,d.Z)
	return d.Magnitude>.1 and d.Unit or Vector3.new(0,0,-1)
end
function Service:_Positions()
	local positions={}
	for _,p in self._players:GetPlayers()do local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart");if r then positions[p.UserId]=r.Position end end
	return positions
end
function Service:CanDepart()
	return Policy.CanDepart(self._runs:GetSnapshot(),self:_Positions(),self._survival:IsEncounterSuspended())
end
function Service:RequestDeparture()
	if self.State~="Open" then return false,"DoorUnavailable" end
	local ok,reason=self:CanDepart();if not ok then return false,reason end
	self:_State("Closing","STAND CLEAR OF THE DOORS");return true,"Closing"
end
function Service:_Command(action,payload)
	return self._runs:Dispatch({token=self._runs:GetToken(),action=action,payload=payload or {}})
end
-- STREAMED FLOOR SWAPS (R26). A floor is ~10-17k parts. Dropping one into the world (or deleting
-- one) in a single frame froze every screen for a second mid-ride. Instead:
--  * the next floor is cloned on the server while the crew are still working the floor above
--    (an unparented copy: nothing replicates, so nobody notices), see _PreloadNext;
--  * during the ride it is moved into the world a few hundred parts per frame (_StageIn);
--  * the floor left behind is removed in one go just after the doors shut (see _DisposeFloor).
local PROFILE=false -- (dev: prints how long each step of a departure takes)
local function mark(label,t0)if PROFILE then print(string.format("[Lift] %s %.1fms",label,(os.clock()-t0)*1000)) end;return os.clock() end
local CHUNK_PARTS=90
local chunkCache=setmetatable({},{__mode="k"}) -- model -> its chunk list (reused when it leaves)
local function chunks(root)
	if chunkCache[root] then return chunkCache[root] end
	-- one pass: part counts for every node, then split wherever a branch is too big
	local counts={}
	local function count(node)
		local n=node:IsA("BasePart") and 1 or 0
		for _,c in node:GetChildren()do n+=count(c) end
		counts[node]=n;return n
	end
	count(root)
	local list={}
	local function walk(node)
		for _,c in node:GetChildren()do
			local n=counts[c]
			if n<=CHUNK_PARTS or #c:GetChildren()==0 then table.insert(list,{inst=c,parent=node,n=n}) else walk(c) end
		end
	end
	walk(root)
	chunkCache[root]=list
	return list
end
function Service:_StageIn(model,parent)
	local list=chunks(model)
	for _,e in list do e.inst.Parent=nil end
	model.Parent=parent -- (the bare skeleton: folders and a handful of parts)
	local budget=0
	for _,e in list do
		e.inst.Parent=e.parent
		budget+=math.max(1,e.n)
		if budget>=CHUNK_PARTS then budget=0;task.wait() end
	end
end
-- clone floor n quietly on the server a few seconds after the crew arrive on the floor above it
function Service:_PreloadNext(n)
	if not self._preloadEnabled or n<1 then return end
	local runId=self._runId
	task.delay(6,function()
		if not self._active or self._runId~=runId then return end
		if self._preloaded then return end
		local ok,model=pcall(self._factory,n)
		if ok and model then
			if self._preloaded or self._runId~=runId then model:Destroy();return end
			self._preloaded=model;self._preloadedNumber=n
			task.wait();pcall(chunks,model)
			pcall(Refs.Index,model,3000) -- (its setup then finds every part straight from the cache)
		end
	end)
end
-- deferModel (a normal departure only): the floor's logic stops now, but its model is renamed
-- DepartingFloor and kept a few seconds so every client can fade its sounds and light out while
-- the lift pulls away (nothing on it works any more; the doors are shut).
function Service:_DisposeFloor(deferModel)
	local ok=true
	local t=os.clock()
	local leaving=deferModel and self._floor and self._floor.Model and self._floor.Model.Parent and self._floor.Model
	if leaving then leaving:SetAttribute("DepartedAt",workspace:GetServerTimeNow()) end -- (before the scope goes: it must not delete it)
	if self._floor then ok=pcall(function()self._floor:Stop()end)end
	t=mark("  floor:Stop",t)
	if self._floorScope then self._floorScope:Destroy();self._floorScope=nil end
	t=mark("  floorScope:Destroy",t)
	if self._floor and leaving then
		local model=leaving
		model:SetAttribute("DepartedEncounter",model:GetAttribute("EncounterId"));model:SetAttribute("EncounterId",nil)
		model.Name="DepartingFloor"
		-- (removed in one go a moment after the doors shut - taking it apart bit by bit was measured
		-- to stutter for seconds, the engine re-lights the scene after every batch; clients hand its
		-- playing sounds over to local copies first so the audio still fades out smoothly)
		-- (timed with the brakes-release clunk and lurch every client plays at TravelStartedAt+0.3)
		task.delay(.3,function()if model.Parent then model:Destroy() end end)
		self._floor=nil
	elseif self._floor then local cleaned=pcall(function()self._floor:Destroy()end);ok=ok and cleaned;self._floor=nil end
	if self._closeUnregister then self._closeUnregister();self._closeUnregister=nil end
	self._floorId=nil;return ok
end
function Service:_Failure(reason)
	if self._failed then return end;self._failed=true
	self:_Doors(0);self._sealed=true;self:_State("Disabled","LIFT BROKEN")
	self:_DisposeFloor()
	local result=self:_Command("TechnicalFailure",{reason=reason or "LoadFailed"})
	if result.ok then self:_Command("Resolve")end
	local snapshot=self._runs:GetSnapshot();local id=snapshot and snapshot.runId
	for _,p in self._players:GetPlayers()do
		if snapshot and snapshot.participants[tostring(p.UserId)] and p.Character then p.Character:PivotTo(self:_SlotFrame(p,(self._runs:GetSnapshot() or {}).originalRoster))end
	end
	task.delay(5,function()
		local current=self._runs:GetSnapshot()
		if self._active and current and current.runId==id and current.phase=="Failed" then
			for _,p in self._players:GetPlayers()do self._session:ReturnLobby(p)end
		end
	end)
end
function Service:_Load(snapshot)
	self._attempts=(self._attempts or 0)+1
	local scope=Scope.new();local model,floor
	local ok,err=xpcall(function()
		if self._preloaded and self._preloadedNumber==snapshot.currentFloorNumber then
            model=self._preloaded;self._preloaded=nil
        else
            -- (an admin floor transfer can skip the floor that was preloaded during the ride:
            -- never leave that copy standing in the shaft on top of the real floor)
            if self._preloaded then self._preloaded:Destroy();self._preloaded=nil end
            model=self._factory(snapshot.currentFloorNumber)
        end
        -- (a floor that is leaving normally is taken apart gradually by _StageOut instead)
        scope:Add(function()if not model:GetAttribute("DepartedAt") then model:Destroy() end end)
		local valid,reason=Policy.ValidateMap(model);assert(valid,reason)
		if not model.Parent then
			-- streamed in during the ride; clients only treat it as a floor (EncounterId) once it is
			-- all there, so nothing indexes a half-built floor
			local enc=model:GetAttribute("EncounterId");model:SetAttribute("EncounterId",nil)
			self:_StageIn(model,self._environment.Model)
			model:SetAttribute("EncounterId",enc)
			local now=self._runs:GetSnapshot()
			if not self._active or not now or now.currentFloorInstanceId~=snapshot.currentFloorInstanceId then error("Superseded",0) end
		end
		local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={model};ray.RespectCanCollide=true
		for _,name in {"PlayerRecovery","ObjectiveRecovery"}do
			local hit=workspace:Raycast(Refs.Get(model,name).Position+Vector3.new(0,2,0),Vector3.new(0,-10,0),ray)
			assert(hit and hit.Instance.CanCollide and hit.Normal.Y>.5,"RecoveryHasNoGround:"..name)
		end
		local id=snapshot.currentFloorInstanceId
		local bounds,objectiveRecovery=Refs.Get(model,"FloorBounds"),Refs.Get(model,"ObjectiveRecovery")
		self._inventory:RegisterFloor(id,snapshot.runId,bounds.Size,objectiveRecovery,objectiveRecovery.CFrame,bounds.CFrame)
		scope:Add(function()self._inventory:RetireFloor(id)end)
		local function live()
			local s=self._runs:GetSnapshot();return self._active and self._floor==floor and s and s.currentFloorInstanceId==id and not finished[s.phase]
		end
		local noise=scope:Add(Instance.new("BindableEvent"))
		local context={RunId=snapshot.runId,FloorInstanceId=id,PlayerRecovery=Refs.Get(model,"PlayerRecovery"),ObjectiveRecovery=objectiveRecovery,Noise=noise.Event,
			SetInteractionEnabled=function(id,enabled)self._interactions:SetEnabled(id,enabled)end,
			SetInteractionHoldScale=function(id,scale)return self._interactions:SetHoldScale(id,scale)end,
			Cabin=self._cabin,GetPlayers=function()return self._players:GetPlayers()end,
			SetStatus=function(message)self:_State(self.State,message)end,
			RestoreCabinSupply=function()self:_CabinSupply(true)end,
			SetSpeedModifier=function(player,key,value)return self._characters:SetSpeedModifier(player,key,value)end,
			IsSuspended=function()return self._survival:IsEncounterSuspended()end,
			RegisterInteraction=function(def)
				def=table.clone(def);def.runId=snapshot.runId;def.floorInstanceId=id;scope:Add(self._interactions:Register(def))
			end,
			RegisterItem=function(itemId,kind,part,opts)return self._inventory:RegisterItem(itemId,kind,id,part,opts)end,
			RegisterSocket=function(itemId,kind,part)return self._inventory:RegisterSocket(itemId,kind,id,part)end,
			EmitNoise=function(event)if live() and not self._survival:IsEncounterSuspended()then noise:Fire(event)end end,
			Damage=function(damage)
				if not live() or self.State~="Open" then return false,"FloorInactive" end
				return self._survival:Damage(damage)
			end,
			CompleteObjective=function()
				if not live() or self.State~="Open" then return false,"FloorInactive" end
				local result=self:_Command("CompleteObjective")
				if result.ok then logDescent(snapshot.currentFloorNumber,true) end
				return result.ok,result.code
			end,
			Escape=function(player)
				if not live() or self.State~="Open" then return false,"FloorInactive" end
				local ids={}
				for _,p in self._players:GetPlayers()do
					local record=self._runs:GetSnapshot().participants[tostring(p.UserId)]
					local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					if record and record.connectionState=="Connected" and record.lifeState=="Alive" and root and (root.Position-Refs.Get(model,"ObjectivePanel").Position).Magnitude<=8 then table.insert(ids,p.UserId)end
				end
				local result=self:_Command("Escape",{escapedUserIds=ids});if result.ok then self:_Command("Resolve")end
				return result.ok,result.code
			end}
		local encounter=model:GetAttribute("EncounterId")
		local implementation=encounter=="Level5" and Level5Floor or encounter=="Level4" and Level4Floor or TemporaryFloor
		local tp=os.clock()
		 floor=implementation.new(model,snapshot.currentFloorNumber);floor:Prepare(context)
		mark("floor:Prepare ("..tostring(encounter)..")",tp)
		self._floor=floor;self._floorId=id;self._floorScope=scope
		self._closeUnregister=self._interactions:Register({interactionId="ElevatorClose",target=Refs.Find(self._cabin,"ControlPanel") or Refs.Get(self._cabin,"ControlLegend"),runId=snapshot.runId,floorInstanceId=id,
			interactionType="Elevator",label="GO DOWN",holdDuration=1,enabled=false,allowedRunPhases={FloorActive=true},
			canUse=function()if self.State~="Open" then return false,"DoorUnavailable" end;if floor.TestLift and floor._stage==6 then return floor:_Available(6)end;return self:CanDepart()end,
			complete=function()
				-- One hold finishes the floor and starts the descent (no separate "test the lift" step).
				if floor.TestLift and floor._stage==6 then local ok,code=floor:TestLift();if not ok then return false,code end end
				return self:RequestDeparture()
			end})
		local readoutPart=Refs.Find(self._cabin,"FloorReadout");local readout=readoutPart and readoutPart:FindFirstChildWhichIsA("TextLabel",true)
		if readout then readout.Text=string.format("%02d",snapshot.currentFloorNumber)end
	end,debug.traceback)
	if not ok and tostring(err)=="Superseded" then
		-- (the run moved on while the floor was streaming in: drop it quietly)
		scope:Destroy();self._attempts=math.max(0,self._attempts-1);return false
	end
	if not ok then
		warn("[ElevatorHorror] Floor preparation attempt "..self._attempts..": "..tostring(err))
		scope:Destroy();if floor then pcall(function()floor:Destroy()end)end
		self._floor=nil;self._floorScope=nil;self._floorId=nil
		if self._closeUnregister then self._closeUnregister();self._closeUnregister=nil end
		if self._attempts>=2 then self:_Failure("LoadFailed")else self._retry=1;self:_State("Closed","PLEASE WAIT")end
	end
	return ok
end
function Service:_Seal()
	local ok=self:CanDepart();if not ok then self:_State("Opening","DOORS BLOCKED");return end
	local t=os.clock()
	self:_Doors(0);self._sealed=true;self:_State("Closed","GOING DOWN")
	t=mark("state",t)
	if not self:_Command("BeginDeparture").ok then self:_Failure("InternalError");return end
	t=mark("BeginDeparture",t)
	if not self:_DisposeFloor(true)then self:_Failure("CleanupFailed");return end
	t=mark("DisposeFloor",t)
	if not self:_Command("CleanupResult",{succeeded=true}).ok then self:_Failure("CleanupFailed");return end
	t=mark("CleanupResult",t)
	-- A fixed five-second descent with the motor running; doors open on arrival with no eye-open fade.
	self._travel=5;self._attempts=0;self._retry=0
	self._cabin:SetAttribute("TravelStartedAt",workspace:GetServerTimeNow());self._cabin:SetAttribute("TravelSeconds",5)
	local motor=self._cabin:FindFirstChild("DescentMotor",true);if motor then motor.PlaybackSpeed=1;motor:Play()end
	self:_ApplyAdminTarget()
	if not self:_Command("PrepareFloor").ok then self:_Failure("LoadFailed")end
	mark("PrepareFloor",t)
end
function Service:_Step(dt)
	if not self._active then return end
	local s=self._runs:GetSnapshot();if not s then return end
	if s.runId~=self._runId then
		self:_DisposeFloor();if self._preloaded then self._preloaded:Destroy();self._preloaded=nil end;self._preloadTried=false;self._runId=s.runId;self._ended=false;self._failed=false;self._elapsed=0;self._travel=0;self._attempts=0;self._retry=0
		self:_Doors(0);self._sealed=true;self:_State("Closed","PLEASE WAIT")
		self:_CabinSupply(true)
        self._skipVotes={};self._skipped=false;self._skipDeadline=nil;self._cabin:SetAttribute('SkipDeadline',nil);self._faultPlayed=false;self._facedDoor=false;self._cabin:SetAttribute('IntroSkipAt',nil);self._cabin:SetAttribute('FaultAt',nil)
        for _,p in self._players:GetPlayers()do if typeof(p)=="Instance" then p:SetAttribute("EHCrashFacing",nil)end end
        self._cabin:SetAttribute('SkipVotes',0);self._cabin:SetAttribute('SkipCrew',0)
        self._cabin:SetAttribute("IntroRunId",s.runId);self._cabin:SetAttribute("IntroElapsed",0)
        self._cabin:SetAttribute("IntroPaused",true)
        self._slotted={};self._cabinSlotted={}
        self:_BeginBoarding()
	end
	if finished[s.phase]then
		if not self._ended then
			self._ended=true
			for _,p in self._players:GetPlayers()do if s.participants[tostring(p.UserId)] and p.Character then p.Character:PivotTo(self:_SlotFrame(p,(self._runs:GetSnapshot() or {}).originalRoster))end end
			self:_DisposeFloor();self:_Doors(0);self._sealed=true;self:_State("Disabled",s.phase=="Completed" and "SURFACE REACHED" or "OUT OF SERVICE")
		end
		return
	end
	local paused=not self._runs:HasConnectedParticipant() or self._survival:IsEncounterSuspended()
    self._cabin:SetAttribute("IntroPaused",paused or s.phase~="Intro")
    if paused then return end
	if s.phase=="Intro" and self._boarding then self:_Board(s,dt);return end
	-- the intro has handed over (doors open on the floor): the elevator lock comes off
	if s.phase~="Intro" and s.phase~="PreparingFloor" and not self._lockCleared then
		self._lockCleared=true
		for _,p in self._players:GetPlayers()do if typeof(p)=="Instance" and p:IsA("Player") then p:SetAttribute("EHElevatorLock",nil) end end
	elseif s.phase=="Intro" then self._lockCleared=false end
	if s.phase=="Intro" then
		-- Each crew member is placed in their own cabin slot exactly once per run (per character),
		-- while the opening cover is still down; later frames never move them again.
		self._cabinSlotted=self._cabinSlotted or {}
		for _,p in self._players:GetPlayers()do
			local character=p.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
			if root and s.participants[tostring(p.UserId)] and self._cabinSlotted[p.UserId]~=character then
				self._cabinSlotted[p.UserId]=character
				character:PivotTo(self:_SlotFrame(p,s.originalRoster))
				root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
			end
		end
		if self._preloadEnabled and not self._preloadTried then
            self._preloadTried=true
            local ok,model=pcall(self._factory,s.currentFloorNumber)
            if ok then self._preloaded=model;self._preloadedNumber=s.currentFloorNumber;model.Parent=self._environment.Model end
        end
        self:_SkipTally(s)
        -- (an admin floor transfer called during boarding runs the ride straight through)
        if self._adminTarget and not self._boarding then self._elapsed=math.max(self._elapsed,self._introSeconds-.5) end
        self._elapsed+=dt;self._cabin:SetAttribute("IntroStarted",true)
		self._cabin:SetAttribute("IntroElapsed",math.floor(self._elapsed*10)/10)
        local t=self._elapsed
        local motor=self._cabin:FindFirstChild("DescentMotor",true)
        if motor then
            -- the motor dies at the crash
            if t>=Intro.DescentStart and t<Intro.ImpactAt then
                motor.PlaybackSpeed=t<Intro.StrainAt and 1 or .76+.05*math.sin(t*5.3)
                if not motor.IsPlaying then motor:Play()end
            elseif motor.IsPlaying then motor:Stop()end
        end
        -- Exactly one fault event per run, whether the intro played out or was skipped.
        if t>=Intro.ImpactAt and not self._faultPlayed then
            self._faultPlayed=true;self._cabin:SetAttribute('FaultAt',workspace:GetServerTimeNow())
            -- (the electrical fault is only a short, faint burst now - no running crackle under the heartbeat)
            local fault=self._cabin:FindFirstChild("ElectricalFault",true);if fault then fault:Play();task.delay(.6,function()SoundFade.Out(fault,.45)end)end -- faded, never cut
            local impact=self._cabin:FindFirstChild("CabinImpact",true);if impact then impact:Play()end
            -- the crash throws every crew member onto their back: they lie on the cabin floor until
            -- GetUpAt, then get up (EHKnockStyle 'Crash' = the full get-up animation on every client)
            local now=workspace:GetServerTimeNow()
            for _,p in self._players:GetPlayers()do
                if s.participants[tostring(p.UserId)] and p.Character then
                    p:SetAttribute("EHKnockStyle","Crash");p:SetAttribute("EHKnockedAt",now)
                    p:SetAttribute("EHKnockedUntil",now+math.max(.5,Intro.GetUpAt-t))
                end
            end
        end
        -- While the screen is black after the crash, everyone is turned (where they lie) to face the
        -- lift doors, so they come round and get up looking at the way out. Clients turn their held
        -- view the same way (EHCrashFacing).
        if t>=Intro.ImpactAt+Intro.SlamSeconds+.08 and not self._facedDoor then
            self._facedDoor=true
            local out=self:_DoorOutward()
            for _,p in self._players:GetPlayers()do
                local character=p.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
                if root and s.participants[tostring(p.UserId)] then
                    local pos=root.Position
                    character:PivotTo(CFrame.lookAt(pos,pos+out))
                    if typeof(p)=="Instance" then p:SetAttribute("EHCrashFacing",out) end
                end
            end
        end
        self:_CabinSupply(Intro.CabinPowered(t))
        if self._elapsed>=self._introSeconds then
            self:_CabinSupply(false);local motor=self._cabin:FindFirstChild("DescentMotor",true);if motor then motor:Stop()end;self._travel=0;self._sealed=true;self:_ApplyAdminTarget();self:_Command("PrepareFloor")
        end
	elseif s.phase=="PreparingFloor" then
		self._travel=math.max(0,(self._travel or 0)-dt)
		if not self._floor then
			self._retry=math.max(0,(self._retry or 0)-dt)
			-- (loading yields while the floor streams in: one load at a time)
			if self._retry==0 and not self._loading then
				self._loading=true
				task.spawn(function()pcall(self._Load,self,s);self._loading=false end)
			end
		end
		if self._travel==0 and self._cabin:GetAttribute("TravelStartedAt") then
			local motor=self._cabin:FindFirstChild("DescentMotor",true);if motor then motor:Stop()end
			self._cabin:SetAttribute("TravelStartedAt",nil)
		end
		if self._floor and self._travel==0 and self.State=="Closed" then
			-- arriving on a floor: the doors part slowly and deliberately
			self:_State("Opening","ARRIVING",self._arrivalDoorSeconds);self._sealed=false
		elseif self._floor and self.State=="Opening" then
			self:_Doors(self._alpha+dt/(self._doorSeconds or 2))
			if self._alpha>=1 then
				local result=self:_Command("ActivateFloor")
				if result.ok then self:_State("Open","COME BACK HERE TO GO DOWN");self._floor:Activate();self:_PreloadNext(s.currentFloorNumber-1);logDescent(s.currentFloorNumber,false) else self:_Failure("InternalError")end
			end
		end
	elseif self.State=="Closing" then
		local allowed=self:CanDepart();local crossed=false
		for id,position in self:_Positions()do if s.participants[tostring(id)] and Policy.InThreshold(position)then crossed=true end end
		if not allowed or crossed then self:_State("Opening","DOORS BLOCKED")
		else self:_Doors(self._alpha-dt/2);if self._alpha<=0 then self:_Seal()end end
	elseif self.State=="Opening" then
		self:_Doors(self._alpha+dt/2);if self._alpha>=1 then self:_State("Open","COME BACK HERE TO GO DOWN")end
	end
	if self._floor then self._floor:OnParticipantStateChanged(s)end
end
-- SURFACE BOARDING (the overground works above the shaft, between the lobby and Level 5).
-- Each run starts at dusk at Blackwater Water Treatment Works: the crew spawn on the apron in
-- front of Shaft 2 and the lift doors stand open. The start is sensor-based: once every connected
-- crew member has been inside the cabin for a moment the descent commits by itself (no button or
-- prompt). DescendAt is published, every screen fades smoothly to black while the doors close, the
-- yard is removed, the crew are lined up, and the picture fades back up on the cabin as the
-- cinematic resumes eyes-open at Intro.OpenCoverEnd.
function Service:_BeginBoarding()
	local assets=game.ServerStorage.GameAssets
	local template=self._preloadEnabled and (assets:FindFirstChild("SurfaceYard"))
	if not template then return end
	if self._yard then self._yard:Destroy() end
	self._yard=template:Clone();self._yard.Parent=self._environment.Model
	self._boarding={started=os.clock(),ready=0,closing=false}
	-- the arrival drive (ArrivalDrive): the crew's car pulls into the gatehouse driveway first
	self._carVotes={}
	if self._yard:FindFirstChild("ArrivalCar",true) then self._yard:SetAttribute("ArrivalCar",true);self._cabin:SetAttribute("ArrivalCar",true) end
	pcall(function()self:_GateHandle(self._yard)end)
	pcall(function()self:_CheckpointHandles(self._yard)end)
	self:_YardRespawns()
	self._sealed=false;self:_Doors(1);self:_State("Open","BOARDING")
	self._elapsed=Intro.OpenCoverEnd;self._cabin:SetAttribute("IntroElapsed",Intro.OpenCoverEnd)
	self._cabin:SetAttribute("DescendAt",nil)
	self._cabin:SetAttribute("Boarding",true);if self._players==Players then game.ReplicatedStorage.Game:SetAttribute("SurfaceBoarding",true) end -- (test fixtures never touch the shared flag)
end
-- While the crew board, every crew member (re)spawns straight onto their own spot on the surface
-- apron - never inside the lift first.
function Service:_YardRespawns()
	local s=self._runs:GetSnapshot();if not self._yard then return end
	for _,p in self._players:GetPlayers()do
		if typeof(p)=="Instance" and p:IsA("Player") then
			local spot=self._yard:FindFirstChild("YardSpawnLocation"..Slots.Index(p.UserId,s and s.originalRoster),true)
			if spot and p.RespawnLocation~=spot then spot.Enabled=true;p.RespawnLocation=spot end
		end
	end
end
-- THE MAIN GATE. The crew start outside the security wall on the approach road. The gate is
-- closed and locked until someone stands in front of it (GateTrigger); then the yard publishes
-- GateOpenedAt and every client plays the same short cutscene (MechanismController): the locks
-- clunk, the beacon spins, both leaves swing inward. The leaves stay solid the whole time (every
-- client moves its own copy smoothly, and your own character collides with exactly what you see);
-- the server sets the final pose when the motion ends.
-- It only ever opens through the Hold-E GateRequest (no timed auto-open).
-- Once the whole crew is through and clear of the leaves, the gate closes behind them (GateClosedAt,
-- animated on every client by MechanismController) and locks for good: hasOpened / hasClosed are
-- one-way server flags, so it can never open again, automatically or by accident. Nobody is ever
-- moved by the gate: run back at it and you simply hit the closed leaves. (A character created after
-- it has shut - a late joiner or a respawn - starts just inside it instead of on the road.)
local GATE_DELAY=.6
-- (closing timing must match MechanismController: the slam lands as every camera starts back)
local GATE_CLOSE_DELAY,GATE_CLOSE_SECONDS,GATE_CLEAR_SECONDS=.4,3.6,1.5
local function gateLeaves(yard)
	local leaves={}
	for _,m in yard:GetDescendants()do if m:IsA("Model") and m:GetAttribute("YardGate") and m.PrimaryPart then table.insert(leaves,m) end end
	return leaves
end
-- where each connected crew member (1-4) is relative to the gate: "inside" means past the painted
-- interior checkpoint line (GateCheckpoint, its LookVector points into the works); nearLeaves means
-- standing where the leaves swing
function Service:_GateCensus(s,trigger)
	local inside,outside,nearLeaves=0,0,false
	local checkpoint=self._yard and self._yard:FindFirstChild("GateCheckpoint",true)
	local line=(trigger.CFrame:Inverse()*CFrame.new(trigger.Position+Vector3.new(0,0,8.3))).Position.Z
	for _,p in self._players:GetPlayers()do
		local rec=s.participants[tostring(p.UserId)]
		local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if rec and rec.connectionState=="Connected" and root then
			local l=trigger.CFrame:PointToObjectSpace(root.Position)
			local past=checkpoint and (root.Position-checkpoint.Position):Dot(checkpoint.CFrame.LookVector)>0 or (not checkpoint and l.Z>line+3)
			if past then inside+=1 else outside+=1 end
			if l.Z>line-3 and l.Z<line+18 and math.abs(l.X)<13 then nearLeaves=true end
		end
	end
	return inside,outside,nearLeaves
end
function Service:_SwingGate(yard,closing)
	local leaves=gateLeaves(yard)
	local solid={}
	-- (collision stays on during the swing: solid during and after closing)
	for _,m in leaves do for _,d in m:GetDescendants()do if d:IsA("BasePart") and (d.CanCollide or d:GetAttribute("GateSolid")) then d:SetAttribute("GateSolid",true);solid[d]=true;d.CanCollide=true end end end
	local longest=0;for _,m in leaves do longest=math.max(longest,m:GetAttribute("SwingSeconds") or 3.4) end
	local wait=closing and GATE_CLOSE_DELAY+GATE_CLOSE_SECONDS+.05 or GATE_DELAY+longest+.05
	local stamp=yard:GetAttribute(closing and "GateClosedAt" or "GateOpenedAt")
	task.delay(wait,function()
		if self._yard~=yard or not yard.Parent then return end
		if yard:GetAttribute(closing and "GateClosedAt" or "GateOpenedAt")~=stamp then return end -- superseded
		for _,m in leaves do
			local off=m:GetAttribute("ClosedOffset")
			if off and m.Parent then m:PivotTo(yard:GetPivot()*off*CFrame.Angles(0,closing and 0 or math.rad(m:GetAttribute("SwingDegrees") or 90),0)) end
		end
		for d in solid do if d.Parent then d.CanCollide=true end end
	end)
end
-- Puts a brand-new character on its spot and holds it still until that spot has streamed in to
-- its player, so it can never fall through ground that has not arrived yet (no damage, no
-- dropping through the apron or the lift floor at the start of a run).
-- the fixed way a spawned character faces (level); clients square body and camera up to it when
-- the spawn / cutscene control lock ends (Shared.Utilities.ControlLock)
local function setFacing(character,frame)
	local lv=frame.LookVector;local flat=Vector3.new(lv.X,0,lv.Z)
	if flat.Magnitude>.05 then character:SetAttribute("EHFacing",flat.Unit) end
end
function Service:_PlaceSafely(p,character,frame)
	local root=character:FindFirstChild("HumanoidRootPart");if not root then return end
	root.Anchored=true
	setFacing(character,frame)
	character:PivotTo(frame);root.AssemblyLinearVelocity=Vector3.zero
	task.spawn(function()
		if typeof(p)=="Instance" and p:IsA("Player") then pcall(function()p:RequestStreamAroundAsync(frame.Position,4)end) end
		task.wait(.15)
		if root.Parent and p.Character==character then
			root.AssemblyLinearVelocity=Vector3.zero;root.Anchored=false
			-- straight back to the player's own physics, so it never hangs while ownership settles
			if typeof(p)=="Instance" and p:IsA("Player") then pcall(function()root:SetNetworkOwner(p)end) end
		end
	end)
end
-- a spot just inside the gate (past the checkpoint), one per crew slot
function Service:_InsideGateFrame(p,s)
	local yard=self._yard;local cp=yard and yard:FindFirstChild("GateCheckpoint",true)
	if not cp then return nil end
	local i=Slots.Index(p.UserId,s and s.originalRoster) or 1
	local at=cp.Position+cp.CFrame.LookVector*9+cp.CFrame.RightVector*((i-2.5)*3)
	local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Include;ray.FilterDescendantsInstances={yard}
	local hit=workspace:Raycast(at+Vector3.new(0,12,0),Vector3.new(0,-30,0),ray)
	local y=(hit and hit.Position.Y or at.Y)+3
	return CFrame.lookAt(Vector3.new(at.X,y,at.Z),Vector3.new(at.X,y,at.Z)+cp.CFrame.LookVector)
end
function Service:_YardGate(s,b)
	local yard=self._yard;if not yard then return end
	local trigger=yard:FindFirstChild("GateTrigger",true);if not trigger then return end
	local now=workspace:GetServerTimeNow()
	local openedAt=yard:GetAttribute("GateOpenedAt")
	if b.hasClosed then
		-- locked for good: never reopens, and never moves anyone
		return
	end
	if openedAt then
		b.hasOpened=true
		local closedAt=yard:GetAttribute("GateClosedAt")
		local inside,outside,nearLeaves=self:_GateCensus(s,trigger)
		local tick=os.clock();local dt=math.clamp(tick-(b.gateTick or tick),0,.5);b.gateTick=tick
		if closedAt and closedAt>openedAt then
			b.hasClosed=true
		else
			-- open: close behind the crew once everyone has been through and clear of the leaves a moment
			local longest=0;for _,m in gateLeaves(yard)do longest=math.max(longest,m:GetAttribute("SwingSeconds") or 3.4) end
			local settled=now-openedAt>GATE_DELAY+longest+3
			b.gateClear=(settled and outside==0 and inside>0 and not nearLeaves) and (b.gateClear or 0)+dt or 0
			if b.gateClear>=GATE_CLEAR_SECONDS then
				b.gateClear=0;b.hasClosed=true;yard:SetAttribute("GateClosedAt",now);self:_SwingGate(yard,true)
			end
		end
		return
	end
	-- The gate only opens when a crew member HOLDS E on it (OPEN GATE, see _GateHandle and the
	-- GateRequest remote). (Test fixtures without real players keep the old stand-in-front start.)
	local open=b.openRequested==true
	if not open and self._players~=Players then
		for _,p in self._players:GetPlayers()do
			local rec=s.participants[tostring(p.UserId)]
			local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if rec and rec.connectionState=="Connected" and root then
				local l=trigger.CFrame:PointToObjectSpace(root.Position);local h=trigger.Size/2
				if math.abs(l.X)<=h.X and math.abs(l.Y)<=h.Y and math.abs(l.Z)<=h.Z then open=true;break end
			end
		end
	end
	if not open or b.hasOpened then return end
	b.hasOpened=true
	yard:SetAttribute("GateOpenedAt",now)
	local handle=yard:FindFirstChild("GateOpenTarget",true)
	if handle then handle:SetAttribute("EHInteractionEnabled",false);game:GetService("CollectionService"):RemoveTag(handle,"EHInteractable") end
	self:_SwingGate(yard,false)
end
-- The hold-E target on the closed gate: an invisible panel filling the opening on the road side,
-- shown with the game's own prompt ("[E] OPEN GATE" and the hold bar). The hold runs on the
-- player's screen; when it completes the client asks the server (GateRequest), which checks the
-- player is really standing at the gate before anything moves.
function Service:_GateHandle(yard)
	local trigger=yard:FindFirstChild("GateTrigger",true);if not trigger then return end
	local leaves=gateLeaves(yard);if #leaves==0 then return end
	local mid=Vector3.zero;for _,m in leaves do mid+=m.PrimaryPart.Position end;mid/=#leaves
	local p=Instance.new("Part");p.Name="GateOpenTarget";p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=true
	p.Transparency=1;p.CastShadow=false;p.Size=Vector3.new(15.6,12,.4)
	-- just on the road side of the leaves, facing the approach
	local out=(trigger.Position-mid);out=Vector3.new(out.X,0,out.Z);out=out.Magnitude>.1 and out.Unit or Vector3.new(0,0,-1)
	local ground=mid.Y-6.8
	p.CFrame=CFrame.lookAt(Vector3.new(mid.X,ground+6.2,mid.Z)+out*2.1,Vector3.new(mid.X,ground+6.2,mid.Z)+out*3.1)
	p:SetAttribute("EHInteractionId","YardGateOpen");p:SetAttribute("EHInteractionType","Panel")
	p:SetAttribute("EHInteractionLabel","OPEN GATE");p:SetAttribute("EHHoldDuration",1.5)
	p:SetAttribute("EHMaximumDistance",12);p:SetAttribute("EHInteractionEnabled",true);p:SetAttribute("EHLocalHold","GateRequest")
	-- (Oct 25) the gate opens from the card reader on the verge: swipe the keycard you were given at check-in
	local reader=yard:FindFirstChild("KeycardReader",true);local body=reader and reader:FindFirstChild("Reader_Body")
	if body then
		p.Size=Vector3.new(1.6,1.8,1.4);p.CFrame=body.CFrame
		p:SetAttribute("EHInteractionLabel","USE KEYCARD");p:SetAttribute("EHHoldDuration",1.35);p:SetAttribute("EHMaximumDistance",7)
		p:SetAttribute("EHKeycardReader",true);p:SetAttribute("EHLocalHold",nil);p:SetAttribute("EHInteractionEnabled",false);p.CanQuery=false -- (only a position marker: it must not catch the aim in front of the reader, which is the real target)
	end
	p.Parent=trigger.Parent
	if not p:GetAttribute("EHKeycardReader") then game:GetService("CollectionService"):AddTag(p,"EHInteractable") end
end
-- (Oct 25) THE SITE KEYCARD is a real objective item (InventoryService, exactly like the fuse and Level 4's
-- keycard): held in the left hand where everyone sees it, shown in your own view by the carried-item view,
-- dropped with the drop key as a tumbling object that can be taken back ("Take Keycard"), outlined while
-- it lies on the ground. The card reader on the works gate is its socket: holding E there puts the card in
-- the slot (it is used up - out of your hands, no drop button) and the gate opens.
-- Everything lives in a "Surface" inventory scope that only ends with the boarding.
function Service:_SurfaceKeycard()
	if self._surfaceCard and self._surfaceCard.Parent then return self._surfaceCard end
	local yard=self._yard;local snap=self._runs:GetSnapshot();if not yard or not snap then return nil end
	local reader=yard:FindFirstChild("KeycardReader",true);local body=reader and reader:FindFirstChild("Reader_Body",true)
	local ks=game.ReplicatedStorage:FindFirstChild("KeycardSwipe",true);local tpl=ks and ks:FindFirstChild("CardTemplate")
	local spot=yard:FindFirstChild("YardSpawnLocation1",true) or yard:FindFirstChild("ServiceWindow",true)
	if not body or not tpl or not spot then return nil end
	pcall(function()self._inventory:RetireFloor("Surface")end)
	local cf,size=yard:GetBoundingBox()
	self._inventory:RegisterFloor("Surface",snap.runId,size+Vector3.new(0,60,0),spot,spot.CFrame,cf,{manual=true,phases={Intro=true}})
	local card=tpl:Clone();card.Name="SiteKeycard";card.Size=Vector3.new(card.Size.X,card.Size.Y,.04)
	card.Anchored=true;card.CanCollide=false;card.CanTouch=false;card.CanQuery=true;card.CFrame=spot.CFrame;card:SetAttribute("DropFlat",true);card.Parent=yard -- (Nov 3: drops flat, face up)
	self._inventory:RegisterItem("SiteKeycard","Keycard","Surface",card,{hold=.3,hiddenAtSpawn=true,label="TAKE KEYCARD"})
	-- the slot you aim at is the whole reader (screen, keypad, body): an invisible box around it, like every
	-- other small machine (aiming at the screen used to find nothing)
	local slot=Instance.new("Part");slot.Name="KeycardSlotHit";slot.Anchored=true;slot.CanCollide=false;slot.CanTouch=false;slot.CanQuery=true
	slot.Transparency=1;slot.CastShadow=false;slot.Size=body.Size+Vector3.new(.3,.3,.3);slot.CFrame=body.CFrame;slot:SetAttribute("SeatDepth",0);slot:SetAttribute("EHNeedsKind","Keycard");slot.Parent=reader -- (Nov 3: USE KEYCARD only shows while you hold the card)
	self._inventory:RegisterSocket("SiteKeycardReader","Keycard","Surface",slot,{label="USE KEYCARD",hold=.85,lineOfSightModel=reader,canUse=function()
		local bb=self._boarding;if not bb or bb.hasOpened or bb.closing then return false,"Unavailable" end;return true end})
	self._scope:Add(slot:GetAttributeChangedSignal("EHInstalledItem"):Connect(function()
		local bb=self._boarding;body:SetAttribute("EHInstalledItem",slot:GetAttribute("EHInstalledItem"))
		if slot:GetAttribute("EHInstalledItem")=="SiteKeycard" and bb and not bb.hasOpened and not bb.closing then bb.openRequested=true end
	end))
	self._surfaceCard=card
	return card
end
function Service:_OnGateRequest(player)
	local b=self._boarding;local yard=self._yard
	if not b or b.hasOpened or b.closing or not yard then return end
	local handle=yard:FindFirstChild("GateOpenTarget",true)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not handle or not root or not h or h.Health<=0 then return end
	if (root.Position-handle.Position).Magnitude>16 then return end
	-- only the keycard holder can open it (unless nobody connected has the card any more)
	-- (Oct 25) the works gate opens from the card reader only: the site keycard has to be in its slot
	if handle:GetAttribute("EHKeycardReader") then local rdr=yard:FindFirstChild("KeycardReader",true);local bd=rdr and rdr:FindFirstChild("Reader_Body",true);if not (bd and bd:GetAttribute("EHInstalledItem")) then return end end
	b.openRequested=true
end
-- THE CHECKPOINT (Oct 23). The arrival drive stops the crew's car at the closed red-and-white barrier.
-- Someone checks in at the gatehouse window (hold E: StallCheckIn), then everyone gets back in the
-- car (hold E on the car: CarGetIn). Getting in is never shown: the character is hidden and held
-- (EHInCar) and that screen waits in black. Once the whole crew is in (or 25 s after the first got in)
-- the yard publishes GateDriveAt and every client plays ArrivalDrive.PlayGate: the barrier swings
-- up, the car drives through and parks in its bay. Behind the black at the end the car is parked
-- there for real, the barrier stays up, the spawns move to the car park and everyone is put beside
-- the car (LotSpawn1-4, facing up the yard towards the treatment pods) to wake up.
local CS=game:GetService("CollectionService")
local okAD,ArrivalTiming=pcall(require,game.ReplicatedStorage.Game.Shared.Utilities.ArrivalDrive)
local GATE_SWAP=(okAD and ArrivalTiming.GateBlackAt or 16.8)+.05
local function holdTarget(p,id,label,hold,dist,enabled,remote)
	p:SetAttribute("EHInteractionId",id);p:SetAttribute("EHInteractionType","Panel");p:SetAttribute("EHInteractionLabel",label)
	p:SetAttribute("EHHoldDuration",hold);p:SetAttribute("EHMaximumDistance",dist);p:SetAttribute("EHInteractionEnabled",enabled)
	p:SetAttribute("EHLocalHold",remote);CS:AddTag(p,"EHInteractable")
end
function Service:_CheckpointHandles(yard)
	local sw=yard:FindFirstChild("ServiceWindow",true)
	if sw then holdTarget(sw,"StallCheckIn","CHECK IN",1,10,true,"StallCheckIn") end
	-- (Nov 3) the GET IN target on the car comes back: it is switched on when the check-in talk ends, and
	-- whoever in the crew holds it first takes everyone back to the car (see _OnCarGetIn)
	local car=yard:FindFirstChild("ArrivalCar",true)
	if car and car.PrimaryPart then
		local t=Instance.new("Part");t.Name="CarGetIn";t.Anchored=true;t.CanCollide=false;t.CanTouch=false;t.CanQuery=true
		-- (Nov 3) the hit box is the whole car (its own bounding box), and any part of the car counts too
		-- (EHWholeModel, InteractionController): hold E on a door, the bonnet, a wheel, the roof
		local bcf,bsz=car:GetBoundingBox()
		t.Transparency=1;t.CastShadow=false;t.Size=bsz+Vector3.new(.3,.3,.3);t.CFrame=bcf
		t.Parent=car
		holdTarget(t,"CarGetIn","GET IN",.5,7,false,"CarGetIn");t:SetAttribute("EHWholeModel",true)
	end
end
function Service:_OnStallCheckIn(player)
	local b=self._boarding;local yard=self._yard
	if not b or b.closing or not yard or yard:GetAttribute("CheckedInAt") then return end
	local sw=yard:FindFirstChild("ServiceWindow",true);local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not sw or not root or (root.Position-sw.Position).Magnitude>16 then return end
	yard:SetAttribute("CheckedInAt",workspace:GetServerTimeNow())
	sw:SetAttribute("EHInteractionEnabled",false);CS:RemoveTag(sw,"EHInteractable")
	-- (Nov 2) the attendant talks to the crew first: every client plays Utilities.CheckInTalk from this time
	-- (each screen fills in its own player's name); he hands the keycard over during his last line
	local okT,Talk=pcall(require,game.ReplicatedStorage.Game.Shared.Utilities.CheckInTalk)
	local talkSeconds=okT and Talk.Duration or 0
	local cardAt=okT and Talk.KeycardAt or 0
	if okT then yard:SetAttribute("CheckInTalkAt",workspace:GetServerTimeNow()) end
	local function still()return self._yard==yard and self._boarding==b and not b.closing end
	-- (Oct 25) whoever checks in is handed the site keycard: it opens the works gate (card reader)
	task.delay(cardAt,function()
		if not still() then return end
		pcall(function()if self:_SurfaceKeycard() then self._inventory:Give(player,"SiteKeycard") end end) -- (in the left hand, seen by everyone)
	end)
	task.delay(talkSeconds,function()
		if not still() then return end
		-- (Nov 3) the talk is over: the crew walks back and anyone holds GET IN on the car (_OnCarGetIn)
		local t=yard:FindFirstChild("CarGetIn",true)
		if t then t:SetAttribute("EHInteractionEnabled",true);yard:SetAttribute("CarGetInReady",true)
		else self:_AllIntoCar() end -- (no car target: straight into the drive, as before)
	end)
end
-- everyone back in the car (never shown) and the drive in starts after a few seconds in the dark
-- (walking back, doors, seat belts - see ArrivalDrive.WatchCar)
function Service:_AllIntoCar()
	local yard=self._yard;if not yard or yard:GetAttribute("GateDriveAt") then return end
	local s=self._runs:GetSnapshot()
	for _,p in self._players:GetPlayers()do
		local rec=s and s.participants[tostring(p.UserId)]
		if rec and rec.connectionState=="Connected" and typeof(p)=="Instance" and p:IsA("Player") then self:_IntoCar(p,s) end
	end
	local t=yard:FindFirstChild("CarGetIn",true)
	if t then t:SetAttribute("EHInteractionEnabled",false);CS:RemoveTag(t,"EHInteractable") end
	yard:SetAttribute("GateDriveAt",workspace:GetServerTimeNow()+3.8)
end
function Service:_IntoCar(p,s)
	local b=self._boarding;b.carIn=b.carIn or {}
	if b.carIn[p.UserId] then return end
	b.carIn[p.UserId]=true;b.firstIn=b.firstIn or os.clock()
	p:SetAttribute("EHCarSeat",Slots.Index(p.UserId,s and s.originalRoster) or 1);p:SetAttribute("EHInCar",true)
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored=true;root.AssemblyLinearVelocity=Vector3.zero end
end
function Service:_OnCarGetIn(player)
	local b=self._boarding;local yard=self._yard
	if not b or b.closing or not yard or not yard:GetAttribute("CheckedInAt") or yard:GetAttribute("GateDriveAt") then return end
	local t=yard:FindFirstChild("CarGetIn",true);local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not t or not root or (root.Position-t.Position).Magnitude>t.Size.Magnitude/2+10 then return end
	local s=self._runs:GetSnapshot();local rec=s and s.participants[tostring(player.UserId)]
	if not rec then return end
	if not yard:GetAttribute("CarGetInReady") then return end -- (only once the talk at the window is over)
	-- (Nov 3) any one of the crew getting in takes the whole crew back to the car
	self:_AllIntoCar()
end
function Service:_GateDrive(s)
	local b=self._boarding;local yard=self._yard
	if not b or not yard or b.gateDone then return end
	local now=workspace:GetServerTimeNow()
	local at=yard:GetAttribute("GateDriveAt")
	if not at then
		if not b.firstIn then return end
		local inN,total=0,0
		for _,p in self._players:GetPlayers()do
			local rec=s.participants[tostring(p.UserId)]
			if rec and rec.connectionState=="Connected" then total+=1;if b.carIn[p.UserId] then inN+=1 end end
		end
		if yard:GetAttribute("CarInCount")~=inN then yard:SetAttribute("CarInCount",inN) end
		if yard:GetAttribute("CarCrew")~=total then yard:SetAttribute("CarCrew",total) end
		if (total>0 and inN>=total) or os.clock()-b.firstIn>25 then
			-- anyone still outside comes along too (nobody is left behind at the barrier)
			for _,p in self._players:GetPlayers()do
				local rec=s.participants[tostring(p.UserId)]
				if rec and rec.connectionState=="Connected" and typeof(p)=="Instance" and p:IsA("Player") then self:_IntoCar(p,s) end
			end
			local t=yard:FindFirstChild("CarGetIn",true)
			if t then t:SetAttribute("EHInteractionEnabled",false);CS:RemoveTag(t,"EHInteractable") end
			yard:SetAttribute("GateDriveAt",now+1.2)
		end
		return
	end
	if now<at+GATE_SWAP then return end
	b.gateDone=true
	local spawns=yard:FindFirstChild("YardSpawns")
	-- the car really is parked in its bay now
	local lotCar=spawns and spawns:FindFirstChild("LotCar");local car=yard:FindFirstChild("ArrivalCar",true)
	if car and lotCar then local t=car:FindFirstChild("CarGetIn");if t then t:Destroy() end;car:PivotTo(lotCar.CFrame) end
	-- the barrier stays up, the line across the approach is gone
	local ck=yard:FindFirstChild("Checkpoint",true)
	if ck then
		local blk=ck:FindFirstChild("CheckpointBlocker");if blk then blk:Destroy() end
		local post=ck:FindFirstChild("BarrierPost")
		if post and not ck:GetAttribute("BarrierRaised") then
			local P=Vector3.new(post.Position.X,post.Position.Y+.75,ck:GetAttribute("BarrierArmZ") or post.Position.Z)
			for _,c in ck:GetChildren()do if c.Name=="BarrierArm" and c:IsA("BasePart") then c.CFrame=CFrame.new(P)*CFrame.Angles(0,0,math.rad(-80))*CFrame.new(-P)*c.CFrame end end
			ck:SetAttribute("BarrierRaised",true)
		end
	end
	-- late joiners and respawns start in the car park from now on
	for i=1,4 do
		local lot=spawns and spawns:FindFirstChild("LotSpawn"..i)
		if lot then
			for _,n in {"YardSpawn"..i,"YardSpawnLocation"..i}do
				local p=yard:FindFirstChild(n,true)
				if p then local y=p.Position.Y;p.CFrame=CFrame.new(lot.Position.X,y,lot.Position.Z)*lot.CFrame.Rotation end
			end
		end
	end
	-- everyone out, standing beside the car
	for _,p in self._players:GetPlayers()do
		if typeof(p)=="Instance" and p:IsA("Player") then
			local character=p.Character;local i=Slots.Index(p.UserId,s.originalRoster) or 1
			local lot=spawns and spawns:FindFirstChild("LotSpawn"..i)
			if character and character:FindFirstChild("HumanoidRootPart") and lot then self:_PlaceSafely(p,character,lot.CFrame) end
			p:SetAttribute("EHInCar",nil);p:SetAttribute("EHCarSeat",nil)
		end
	end
	yard:SetAttribute("GateDriveDone",true)
end
function Service:_EndBoarding()
	if self._surfaceCard then pcall(function()self._inventory:RetireFloor("Surface")end);self._surfaceCard=nil end
	self._boarding=nil
	for _,p in self._players:GetPlayers()do if typeof(p)=="Instance" and p:IsA("Player") then p:SetAttribute("EHInCar",nil);p:SetAttribute("EHCarSeat",nil);p:SetAttribute("EHKeycard",nil);p:SetAttribute("EHSurfaceKit",nil) end end
	for _,p in self._players:GetPlayers()do if typeof(p)=="Instance" and p:IsA("Player") then p.RespawnLocation=self._environment.Spawn end end
	if self._yard then self._yard:Destroy();self._yard=nil end
	self._cabin:SetAttribute("Boarding",nil);self._cabin:SetAttribute("ArrivalCar",nil);if self._players==Players then game.ReplicatedStorage.Game:SetAttribute("SurfaceBoarding",nil) end
	if self._players==Players then game.ReplicatedStorage.Game:SetAttribute("SurfacePending",nil) end -- (test fixtures never touch it)
end
function Service:_CommitDescent()
	local b=self._boarding;if not b or b.closing or b.transition then return end
	b.closing=true;self._cabin:SetAttribute("DescendAt",workspace:GetServerTimeNow())
	self:_State("Closing","GOING DOWN")
	-- the elevator sequence starts here: every crew member is fully locked (InputController reads
	-- EHElevatorLock) and faces the lift doors until the intro hands over on the floor below
	local out=self:_DoorOutward()
	for _,p in self._players:GetPlayers()do
		if typeof(p)=="Instance" and p:IsA("Player") then
			p:SetAttribute("EHElevatorLock",true);p:SetAttribute("EHCrashFacing",out)
			if p.Character then p.Character:SetAttribute("EHFacing",out) end
		end
	end
end
function Service:_Aboard(s)
	local total,inside=0,0
	for _,p in self._players:GetPlayers()do
		local rec=s.participants[tostring(p.UserId)]
		local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if rec and rec.connectionState=="Connected" and root then total+=1;if Policy.InCabin(root.Position)then inside+=1 end end
	end
	return inside,total
end
function Service:_Board(s,dt)
	local b=self._boarding
	-- doors shut: hold the intro clock while every client fades to black and the light changes
	-- from daylight to the outage, with the lift motor already running beneath them
	if b.transition then
		self._cabin:SetAttribute("IntroPaused",true)
		-- once the screens are dark, line the crew up side by side across the cabin floor (they walked
		-- in wherever they liked and crew pass through each other, so they would otherwise overlap)
		if not b.lined and os.clock()-b.closedAt>=1.4 then
			b.lined=true;self._cabinSlotted=self._cabinSlotted or {}
			for _,p in self._players:GetPlayers()do
				local character=p.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
				if root and s.participants[tostring(p.UserId)] then
					self._cabinSlotted[p.UserId]=character
					character:PivotTo(self:_SlotFrame(p,s.originalRoster))
					root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
				end
			end
		end
		if os.clock()-b.closedAt>=3.4 then self._boarding=nil end
		return
	end
	pcall(self._ArrivalCar,self,s)
	-- (Oct 25) everyone on the surface carries the site keycard and has the torch out
	for _,p in self._players:GetPlayers()do
		if typeof(p)=="Instance" and p:IsA("Player") and s.participants[tostring(p.UserId)] and not p:GetAttribute("EHSurfaceKit") then
			p:SetAttribute("EHSurfaceKit",true)
		end
	end
	local okG,errG=pcall(self._GateDrive,self,s);if not okG then warn("[ElevatorHorror] gate drive: "..tostring(errG)) end
	self:_YardRespawns() -- (late joiners too)
	local spawns=self._yard and self._yard:FindFirstChild("YardSpawns")
	for _,p in self._players:GetPlayers()do
		local rec=s.participants[tostring(p.UserId)]
		local character=p.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
		-- each character starts out on the apron once, and only while it is brand new (a character
		-- that has already been standing in the world for a moment is never moved again)
		self._firstSeen=self._firstSeen or setmetatable({},{__mode="k"})
		if character and not self._firstSeen[character] then self._firstSeen[character]=os.clock() end
		if character and self._slotted[p.UserId]~=character and (character:GetAttribute("EHYardPlaced") or os.clock()-(self._firstSeen[character] or 0)>2) then
			self._slotted[p.UserId]=character
		end
		if rec and rec.connectionState=="Connected" and root and self._slotted[p.UserId]~=character then
			self._slotted[p.UserId]=character;character:SetAttribute("EHYardPlaced",true)
			local i=Slots.Index(p.UserId,s.originalRoster)
			local at=spawns and spawns:FindFirstChild("YardSpawn"..i)
			-- once the gate has shut for good, latecomers start just inside it instead
			local inside=b.hasClosed and self:_InsideGateFrame(p,s)
			if inside then self:_PlaceSafely(p,character,inside)
			elseif at then self:_PlaceSafely(p,character,at.CFrame) end
		end
	end
	self:_YardGate(s,b)
	local inside,total=self:_Aboard(s)
	-- surface only: the drop starts by itself once every connected crew member has been inside the
	-- cabin for a moment (no prompt)
	b.ready=(total>0 and inside==total) and (b.ready or 0)+dt or 0
	-- (Oct 23 c) never while the main gate is shutting behind the crew: walking straight into the lift
	-- used to start the fade to black on top of the closing shot, so nobody saw the gate close
	local gateBusy=false
	if self._yard and b.hasOpened then
		local ca=self._yard:GetAttribute("GateClosedAt")
		if not b.hasClosed then gateBusy=true
		elseif ca and workspace:GetServerTimeNow()-ca<GATE_CLOSE_DELAY+GATE_CLOSE_SECONDS+1.2 then gateBusy=true end
	end
	if not b.closing and b.ready>=1.2 and not gateBusy then self:_CommitDescent() end
	-- a straggler can't hold the crew forever: two minutes after the first crew member steps into the
	-- lift, the descent starts anyway. Nobody is moved here - the screens fade to black first and
	-- anyone still outside is brought aboard behind the black (below), as part of the lift transition.
	if inside>0 and not b.firstAboard then b.firstAboard=os.clock() end
	if not b.closing and b.firstAboard and os.clock()-b.firstAboard>120 then
		self:_CommitDescent()
	end
	-- once the descent is committed the doors close no matter what (every screen is already fading out)
	if b.closing then
		self:_Doors(self._alpha-dt/2)
		if self._alpha<=0 then
			-- anyone who stepped back out behind the closing doors is brought aboard before the yard goes
			for _,p in self._players:GetPlayers()do
				local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if root and s.participants[tostring(p.UserId)] and not Policy.InCabin(root.Position)then p.Character:PivotTo(self:_SlotFrame(p,s.originalRoster));root.AssemblyLinearVelocity=Vector3.zero end
			end
			self._sealed=true;self:_State("Closed","GOING DOWN");self:_EndBoarding()
			self._boarding={transition=true,closedAt=os.clock()}
			local motor=self._cabin:FindFirstChild("DescentMotor",true);if motor then motor.PlaybackSpeed=1;motor:Play()end
		end
	elseif self._alpha<1 then
		self:_Doors(self._alpha+dt/2);if self._alpha>=1 then self:_State("Open","BOARDING")end
	end
end
-- STUDIO ONLY test shortcuts (a server-side BindableFunction, Development.ElevatorDebug; nothing a
-- client can reach): 'SkipIntro' starts / fast-forwards the ride down, 'SkipFloor' finishes the
-- current floor and sends the lift down to the next one.
function Service:_Debug(cmd)
	local s=self._runs:GetSnapshot();if not s then return "NoRun" end
	local function aboard()
		for _,p in self._players:GetPlayers()do
			local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and s.participants[tostring(p.UserId)] then p.Character:PivotTo(self:_SlotFrame(p,s.originalRoster));root.AssemblyLinearVelocity=Vector3.zero end
		end
	end
	if cmd=="SkipIntro" then
		if self._boarding and not self._boarding.transition then aboard();self:_CommitDescent();return "Boarding->Descent" end
		if s.phase=="Intro" then self._elapsed=math.max(self._elapsed,self._introSeconds-.5);return "IntroSkipped" end
		return "Phase:"..s.phase
	elseif cmd=="SkipFloor" then
		if not self._floor or self.State~="Open" then return "NotOpen:"..tostring(self.State) end
		aboard()
		local f=self._floor
		if f.TestLift then f._stage=6;f:TestLift() elseif s.objectiveSnapshot.status~="Completed" then self:_Command("CompleteObjective");f._state="Completed" end
		task.wait(.2)
		local ok,code=self:RequestDeparture();return tostring(ok).." "..tostring(code)
	end
	return "UnknownCommand"
end
-- ADMIN FLOOR TRANSFER (testing): "/floor transfer <1-5>" in chat. Only the group's Owner and
-- Co-Owner (PandaPenguin472, Jay4980_p) can use it; everyone else's message is simply swallowed.
-- The whole crew is put in the lift, the current floor is finished and the lift goes straight to
-- the floor asked for (a normal ride, so every floor loads the way it does in a real run).
local ADMIN_IDS={[2403347306]=true,[544275681]=true} -- PandaPenguin472, Jay4980_p
local ADMIN_ROLES={Owner=true,["Co-Owner"]=true}
function Service:_IsAdmin(player)
	if typeof(player)~="Instance" or not player:IsA("Player") then return false end
	if ADMIN_IDS[player.UserId] then return true end
	if game.CreatorType==Enum.CreatorType.Group then
		local ok,role=pcall(player.GetRoleInGroup,player,game.CreatorId)
		if ok and ADMIN_ROLES[role] then return true end
	end
	return false
end
function Service:_ApplyAdminTarget()
	local n=self._adminTarget;if not n then return end
	self._adminTarget=nil
	if not self._runs:SetNextFloor(n) then warn("[ElevatorHorror] Floor transfer to "..n.." failed") end
end
function Service:AdminTransfer(player,n)
	if not self:_IsAdmin(player) then return false,"Not allowed." end
	if type(n)~="number" or n~=math.floor(n) or n<1 or n>5 then return false,"Use a floor from 1 to 5, e.g. /floor transfer 4" end
	local s=self._runs:GetSnapshot();if not s then return false,"No run is active." end
	if finished[s.phase] then return false,"This run is over." end
	local function aboard()
		for _,p in self._players:GetPlayers()do
			local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and s.participants[tostring(p.UserId)] then p.Character:PivotTo(self:_SlotFrame(p,s.originalRoster));root.AssemblyLinearVelocity=Vector3.zero end
		end
	end
	if self._boarding and not self._boarding.transition then
		self._adminTarget=n;aboard();self:_CommitDescent();return true,"Heading to floor "..n.."..."
	end
	if s.phase=="Intro" then
		self._adminTarget=n;return true,"Heading to floor "..n.."..."
	end
	if not self._floor or self.State~="Open" or (s.phase~="FloorActive" and s.phase~="FinaleActive") then
		return false,"The lift is moving. Try again in a few seconds."
	end
	self._adminTarget=n
	aboard()
	local f=self._floor
	if f.TestLift then f._stage=6;pcall(f.TestLift,f)
	elseif s.objectiveSnapshot.status~="Completed" then self:_Command("CompleteObjective");f._state="Completed" end
	task.delay(.2,function()
		local ok,code=self:RequestDeparture()
		if not ok then self._adminTarget=nil;warn("[ElevatorHorror] Floor transfer blocked: "..tostring(code)) end
	end)
	return true,"Heading to floor "..n.."..."
end
function Service:_AdminCommand()
	local TCS=game:GetService("TextChatService")
	local cmd=TCS:FindFirstChild("BlackwaterFloorTransfer")
	if not cmd then cmd=Instance.new("TextChatCommand");cmd.Name="BlackwaterFloorTransfer";cmd.PrimaryAlias="/floor";cmd.Parent=TCS;self._scope:Add(cmd) end
	local last=setmetatable({},{__mode="k"})
	self._scope:Add(cmd.Triggered:Connect(function(source,text)
		local player=source and self._players:GetPlayerByUserId(source.UserId);if not player then return end
		if not self:_IsAdmin(player) then return end -- (silently ignored for everyone else)
		if os.clock()-(last[player] or 0)<2 then return end;last[player]=os.clock()
		local n=tonumber(string.match(string.lower(text or ""),"^/floor%s+transfer%s+(%d+)") or string.match(string.lower(text or ""),"^/floor%s+(%d+)"))
		local ok,msg=self:AdminTransfer(player,n)
		player:SetAttribute("EHAdminReply",(ok and "" or "! ")..msg)
		player:SetAttribute("EHAdminReplySerial",(player:GetAttribute("EHAdminReplySerial") or 0)+1)
	end))
end
-- THE ARRIVAL DRIVE. Every client plays the same short cutscene from the yard's ArrivalCarAt
-- (ArrivalDrive): two typed lines over black, the crew's car coming along the highway, turning
-- right up the access road and pulling into the gatehouse driveway, then everyone gets out and
-- wakes up beside it. The clock starts once every connected crew member has been placed on the
-- surface (or after 15 s). Skipping is a crew vote, exactly like the lift ride: when everyone
-- connected has voted, ArrivalSkipAt is published and every screen cuts to the wake-up.
local ARRIVAL_SECONDS=(okAD and ArrivalTiming.Total or 34.5)+1 -- (follows ArrivalDrive.Total)
function Service:_ArrivalCar(s)
	local b=self._boarding;local yard=self._yard
	if not b or not yard or not yard:GetAttribute("ArrivalCar") then return end
	if not b.carAt then
		local ready,total=0,0
		for _,p in self._players:GetPlayers()do
			local rec=s.participants[tostring(p.UserId)]
			if rec and rec.connectionState=="Connected" then
				total+=1
				if p.Character and p.Character:GetAttribute("EHYardPlaced") then ready+=1 end
			end
		end
		if (total>0 and ready>=total) or os.clock()-b.started>15 then
			b.carAt=workspace:GetServerTimeNow()+1;yard:SetAttribute("ArrivalCarAt",b.carAt)
		end
		return
	end
	if yard:GetAttribute("ArrivalSkipAt") or workspace:GetServerTimeNow()>b.carAt+ARRIVAL_SECONDS then return end
	local voted,total=Intro.SkipTally(s.participants,self._carVotes or {})
	if yard:GetAttribute("ArrivalSkipVotes")~=voted then yard:SetAttribute("ArrivalSkipVotes",voted) end
	if yard:GetAttribute("ArrivalSkipCrew")~=total then yard:SetAttribute("ArrivalSkipCrew",total) end
	if total>0 and voted>=total then yard:SetAttribute("ArrivalSkipAt",workspace:GetServerTimeNow()) end
end
function Service:Start()
	if self._environment.Role~="Game" then return end
	self._active=true
	if self._players==Players then pcall(self._AdminCommand,self) end
	if game:GetService("RunService"):IsStudio() and self._players==Players then
		local dev=script.Parent.Parent:FindFirstChild("Development")
		if dev and not dev:FindFirstChild("ElevatorDebug") then
			local f=Instance.new("BindableFunction");f.Name="ElevatorDebug";f.Parent=dev;self._scope:Add(f)
			f.OnInvoke=function(cmd)local ok,r=pcall(self._Debug,self,cmd);return ok and r or ("Error "..tostring(r)) end
		end
	end
	-- Every run begins on the surface: until boarding has started, no character is created (see
	-- CharacterService.Spawn), so nobody ever appears in the lift before the yard.
	if self._players==Players and self._preloadEnabled and game.ServerStorage.GameAssets:FindFirstChild("SurfaceYard") then game.ReplicatedStorage.Game:SetAttribute("SurfacePending",true) end
	-- Any character created while boarding is placed on its apron spot in the same frame.
	local function watch(p)
		if typeof(p)~="Instance" or not p:IsA("Player") then return end
		self._scope:Add(p.CharacterAdded:Connect(function(character)
			local b=self._boarding;if not b or b.transition or b.closing or not self._yard then return end
			local s=self._runs:GetSnapshot();local spawns=self._yard:FindFirstChild("YardSpawns")
			local at=spawns and spawns:FindFirstChild("YardSpawn"..Slots.Index(p.UserId,s and s.originalRoster))
			-- (a character created after the gate has shut for good starts just inside it)
			local inside=b.hasClosed and self:_InsideGateFrame(p,s)
			local frame=inside or (at and at.CFrame)
			if frame then
				if character:FindFirstChild("HumanoidRootPart") then self:_PlaceSafely(p,character,frame) else setFacing(character,frame);character:PivotTo(frame) end
			end
			if inside or at then self._slotted[p.UserId]=character;character:SetAttribute("EHYardPlaced",true) end
		end))
	end
	if self._players==Players then
		self._scope:Add(Players.PlayerAdded:Connect(watch));for _,p in Players:GetPlayers()do watch(p)end
		-- hold-E on the main gate (see _GateHandle)
		local network=game.ReplicatedStorage.Game:FindFirstChild("Network")
		if network then
			local remote=network:FindFirstChild("GateRequest")
			if not remote then remote=Instance.new("RemoteEvent");remote.Name="GateRequest";remote.Parent=network;self._scope:Add(remote) end
			local last=setmetatable({},{__mode="k"})
			self._scope:Add(remote.OnServerEvent:Connect(function(player)
				if os.clock()-(last[player] or 0)<.5 then return end;last[player]=os.clock()
				pcall(self._OnGateRequest,self,player)
			end))
			-- the checkpoint: check in at the gatehouse, then get back in the car (see _CheckpointHandles)
			for name,fn in {StallCheckIn=self._OnStallCheckIn,CarGetIn=self._OnCarGetIn}do
				local r=network:FindFirstChild(name)
				if not r then r=Instance.new("RemoteEvent");r.Name=name;r.Parent=network;self._scope:Add(r) end
				local lastT=setmetatable({},{__mode="k"})
				self._scope:Add(r.OnServerEvent:Connect(function(player)
					if os.clock()-(lastT[player] or 0)<.5 then return end;lastT[player]=os.clock()
					pcall(fn,self,player)
				end))
			end
			-- skip vote for the arrival drive (see _ArrivalCar)
			local skip=network:FindFirstChild("ArrivalSkip")
			if not skip then skip=Instance.new("RemoteEvent");skip.Name="ArrivalSkip";skip.Parent=network;self._scope:Add(skip) end
			self._scope:Add(skip.OnServerEvent:Connect(function(player)
				local b=self._boarding;local yard=self._yard
				if not b or not yard or not b.carAt then return end
				local s=self._runs:GetSnapshot();local rec=s and s.participants[tostring(player.UserId)]
				if not rec or rec.connectionState~="Connected" then return end
				self._carVotes=self._carVotes or {};self._carVotes[tostring(player.UserId)]=true
				player:SetAttribute("EHCarSkipVoted",b.carAt)
			end))
		end
	end
	self._scope:Add(Heartbeat:Connect(function(dt)
		local ok,err=xpcall(function()self:_Step(math.min(dt,.25))end,debug.traceback)
		if not ok then warn("[ElevatorHorror] Elevator failure: "..tostring(err));self:_Failure("InternalError")end
	end))
end
function Service:Destroy()
	self._active=false;pcall(function()self:_EndBoarding()end);if self._preloaded then self._preloaded:Destroy();self._preloaded=nil end;self:_DisposeFloor();if self._scope then self._scope:Destroy()end
	if self._survival then self._survival:SetCabinProtection(nil)end
end
return table.freeze(Service)

