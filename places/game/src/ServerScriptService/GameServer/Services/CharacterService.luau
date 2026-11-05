--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Policy=require(Shared.Contracts.CharacterContract)
local Sprint=require(Shared.Utilities.SprintModel)
local MoveConfig=require(Shared.Config.MovementConfig)
local Physics=game:GetService("PhysicsService")
local GETUP=require(Shared.Utilities.IntroTimeline).GetUpSeconds
-- Down after a slip or the lift crash - lying there or still getting up (the client's get-up takes
-- GETUP s after the crash, .85 s after a slip): no sprinting until you are fully back on your feet.
local function isDown(player)
	if typeof(player)~="Instance" then return false end
	local t1=player:GetAttribute("EHKnockedUntil");if type(t1)~="number" then return false end
	local rise=player:GetAttribute("EHKnockStyle")=="Crash" and GETUP or .85
	return workspace:GetServerTimeNow()<t1+rise+.15
end
local Service={}
Service.__index=Service
function Service.new()
	return setmetatable({Name="CharacterService",Dependencies={"GameRunService"},_records={},_active=false},Service)
end
function Service:Init(dependencies)
	self._runs=dependencies.GameRunService
	self._scope=Scope.new()
    pcall(function()Physics:RegisterCollisionGroup("BlackwaterCabinCrew")end)
    Physics:CollisionGroupSetCollidable("BlackwaterCabinCrew","BlackwaterCabinCrew",false)
    -- vents: the duct sheet metal (authored in the BlackwaterVentDuct group) collides as normal
    pcall(function()Physics:RegisterCollisionGroup("BlackwaterVentDuct")end)
    -- Lying in a duct: the posed body never touches anything; the crawler's own client gives them a
    -- flat collision disc instead (HazardController).
    pcall(function()Physics:RegisterCollisionGroup("BlackwaterProneBody")end)
	self._oldAutoLoads=Players.CharacterAutoLoads
	Players.CharacterAutoLoads=false
	self._scope:Add(Shared.Parent:GetAttributeChangedSignal("SurfaceBoarding"):Connect(function()
		for p,r in self._records do pcall(self._Refresh,self,p,r) end
	end))
end
function Service:_Publish(player,r)
	player:SetAttribute("EHCharacterEpoch",r.epoch)
	player:SetAttribute("EHLifeState",r.life)
	player:SetAttribute("EHContext",r.context)
	player:SetAttribute("EHStamina",math.floor(r.sprint.stamina*10+.5)/10)
	player:SetAttribute("EHSprinting",r.sprint.sprinting)
	player:SetAttribute("EHExhausted",r.sprint.exhausted)
	player:SetAttribute("EHCrouching",r.crouch==true)
end
function Service:_Refresh(player,r)
	local view=self._runs:GetViewFor(player.UserId)
	local runId=view and view.runId or nil
	if r.runId and not runId and r.life~="Dead" then
		r.life="Alive";r.sprint=Sprint.New();r.modifiers={}
		if not r.humanoid or r.humanoid.Health<=0 then self:Spawn(player) end
	end
	r.runId=runId
	local context=Policy.ContextFor(view,r.life)
	if r.suspended and context~="Dead" and context~="Results" then context="Intro" end
	if r.admissionPending then context="Intro" end
	-- surface boarding: the crew can walk, run and crouch in first person from the yard into the
	-- lift (the flashlight stays unavailable in daylight, see EquipmentService)
	if context=="Intro" and not r.admissionPending and not r.suspended and Shared.Parent:GetAttribute("SurfaceBoarding")==true then context="ActiveFloor" end
	if context~=r.context then r.intent=false;r.crouch=false;r.expires=0;r.context=context;r.epoch+=1 end
	self:_Publish(player,r)
end
function Service:Spawn(player)
	local r=self._records[player]
	if not self._active or not r or r.loading then return false,"Unavailable" end
	if r.spawnedOnce then return false,"RespawnsDisabled" end
	-- Future survival/floor services must explicitly restore life before calling Spawn.
	if r.life~="Alive" and r.life~="Downed" then return false,"NotAlive" end
	if self._admissionRequired and not r.admitted then return false,"NotAdmitted" end
	r.loading=true
	task.spawn(function()
		if not self._active or self._records[player]~=r or player.Parent~=Players then r.loading=false;return end
		-- A run always starts on the surface: while the surface yard is about to be set up
		-- (SurfacePending) the character is not created yet, so it can never appear inside the lift
		-- first and then jump outside. It is created the moment boarding starts, straight onto its
		-- own spot on the apron (ElevatorService points RespawnLocation there). The crew can take up
		-- to the session's 45 s arrival window to all load in, so the safety cap sits past that (75 s).
		local waited=0
		while typeof(player)=="Instance" and Shared.Parent:GetAttribute("SurfacePending")==true and Shared.Parent:GetAttribute("SurfaceBoarding")~=true and waited<75 do
			waited+=task.wait(.1)
			if not self._active or self._records[player]~=r or player.Parent~=Players then r.loading=false;return end
		end
		local ok,err=pcall(function() player:LoadCharacterAsync() end)
		if ok then r.spawnedOnce=true end
		r.loading=false
		if not ok and player.Parent==Players then
			player:SetAttribute("EHSpawnError",tostring(err))
			warn("[ElevatorHorror] Character spawn failed for "..player.UserId)
		end
	end)
	return true,"Spawning"
end
function Service:_Attach(player,r,character)
	if r.character==character then return end
	if r.characterScope then r.characterScope:Destroy() end
	r.characterScope=Scope.new();r.character=character;r.humanoid=nil;r.root=nil;r.locked=false
	r.epoch+=1;r.intent=false;r.crouch=false;r.expires=0
	self:_Publish(player,r)
	task.spawn(function()
		local humanoid=character:WaitForChild("Humanoid",10)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if not self._active or self._records[player]~=r or r.character~=character then return end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			player:SetAttribute("EHSpawnError","Missing character components");return
		end
		r.humanoid=humanoid;r.root=root;r.partGroups={}
        local function track(p)if p:IsA("BasePart")then r.partGroups[p]=p.CollisionGroup end end
        for _,p in character:GetDescendants()do track(p)end
        r.characterScope:Add(character.DescendantAdded:Connect(track))
        r.characterScope:Add(function()for p,g in r.partGroups do if p.Parent then p.CollisionGroup=g end end end)
		if r.returnFrame then
			character:PivotTo(r.returnFrame);r.returnFrame=nil
			player:SetAttribute("EHReturnSerial",(player:GetAttribute("EHReturnSerial") or 0)+1)
		end
		-- Jumping is removed from the game (crouch replaces it).
		humanoid.JumpPower=0;humanoid.JumpHeight=0
		player:SetAttribute("EHSpawnError",nil)
		r.characterScope:Add(humanoid.Died:Connect(function()
			if r.character~=character then return end
			r.life="Dead";r.intent=false
			self:_Refresh(player,r)
			-- Death is final for this session. Initial admission still creates one character.

		end))
		self:_Refresh(player,r)
	end)
end
function Service:_Add(player)
	if self._records[player] then return end
	local r={admissionPending=self._admissionRequired==true,admitted=not self._admissionRequired,epoch=0,life="Alive",context="Lobby",intent=false,expires=0,sprint=Sprint.New(),modifiers={},scope=Scope.new()}
	self._records[player]=r
	r.scope:Add(player.CharacterAdded:Connect(function(c) self:_Attach(player,r,c) end))
	r.scope:Add(player.CharacterRemoving:Connect(function(c)
		if r.character~=c then return end
		if r.characterScope then r.characterScope:Destroy();r.characterScope=nil end
		r.character=nil;r.humanoid=nil;r.root=nil;r.intent=false
	end))
	self:_Refresh(player,r)
	if player.Character then self:_Attach(player,r,player.Character) else self:Spawn(player) end
end
function Service:_Remove(player)
	local r=self._records[player];if not r then return end
	self._records[player]=nil
	r.scope:Destroy();if r.characterScope then r.characterScope:Destroy() end
end
function Service:SetAdmissionRequired(value) self._admissionRequired=value==true end
function Service:Admit(player,life,frame,stamina)
	local r=self._records[player];if not r then return false end
	r.admitted=true;r.admissionPending=true;r.life=life;r.suspended=true;r.returnFrame=frame
	if type(stamina)=="number" then r.sprint.stamina=math.clamp(stamina,0,100) end
	self:_Refresh(player,r)
	if life=="Dead" then return true end
	return self:Spawn(player)
end
function Service:IsCharacterReady(player,life)
	local r=self._records[player]
	return r and (life=="Dead" or (r.humanoid and r.humanoid.Health>0 and r.root~=nil))
end
function Service:RetargetAdmission(player,life,frame)
	local r=self._records[player];if not r then return false end
	r.life=life;r.intent=false;r.returnFrame=frame
	if frame and r.character and r.root then r.character:PivotTo(frame);r.returnFrame=nil end
	self:_Refresh(player,r)
	if life~="Dead" and not r.loading and (not r.humanoid or r.humanoid.Health<=0) then self:Spawn(player) end
	return true
end
function Service:RestoreAdmissionStamina(player,stamina)
	local r=self._records[player]
	if r and type(stamina)=="number" then r.sprint.stamina=math.clamp(stamina,0,100);self:_Publish(player,r)end
end
function Service:SetAdmissionReady(player,value)
	local r=self._records[player];if not r then return end
	r.admissionPending=not value;self:_Refresh(player,r)
end
function Service:SetSprint(player,epoch,enabled)
	local r=self._records[player]
	if not r or r.epoch~=epoch then return false,"StaleCharacter" end
	if enabled and (not Policy.Contexts[r.context].sprint or r.life~="Alive" or not r.humanoid or r.humanoid.Health<=0) then return false,"SprintUnavailable" end
	if enabled and typeof(player)=="Instance" and player:GetAttribute("EHInVent") then return false,"InVent" end
	if enabled and isDown(player) then r.intent=false;r.expires=0;return false,"Knocked" end
	r.intent=enabled;r.expires=enabled and os.clock()+1.5 or 0
	if enabled and r.crouch then r.crouch=false;self:_Publish(player,r) end -- sprinting stands the player up
	return true,"OK"
end
function Service:SetCrouch(player,epoch,enabled)
	local r=self._records[player]
	if not r or r.epoch~=epoch then return false,"StaleCharacter" end
	if enabled and (not Policy.Contexts[r.context].movement or r.life~="Alive" or not r.humanoid or r.humanoid.Health<=0) then return false,"CrouchUnavailable" end
	-- (crouch works from the moment you spawn, surface included; the cinematic contexts stand you up)
	-- locked crouched while crawling through a vent
	if not enabled and typeof(player)=="Instance" and player:GetAttribute("EHInVent") then r.crouch=true;self:_Publish(player,r);return false,"InVent" end
	r.crouch=enabled==true
	if r.crouch then r.intent=false;r.expires=0 end -- crouching cancels a sprint
	self:_Publish(player,r)
	return true,"OK"
end
function Service:SetLifeState(player,life)
	if life~="Alive" and life~="Downed" and life~="Dead" then return false,"InvalidLifeState" end
	local r=self._records[player];if not r then return false,"Unavailable" end
	if life=="Alive" and r.humanoid and r.humanoid.Health<=0 then return false,"RequiresRespawn" end
	r.life=life;r.intent=false;self:_Refresh(player,r)
	return true,"OK"
end
function Service:SetSuspended(player,value)
	local r=self._records[player];if not r then return end
	r.suspended=value==true;r.intent=false;self:_Refresh(player,r)
end
function Service:RestoreForFloor(player,frame)
	local r=self._records[player];if not r then return false end
	if r.life=="Dead" or (r.humanoid and r.humanoid.Health<=0) then return false,"RespawnsDisabled" end
	r.life="Alive";r.sprint=Sprint.New();r.modifiers={};r.intent=false;r.crouch=false;r.expires=0;r.suspended=false
	r.epoch+=1;r.returnFrame=frame;self:_Refresh(player,r)
	if not r.humanoid or r.humanoid.Health<=0 then return self:Spawn(player) end
	if frame and r.character then r.character:PivotTo(frame) end
	r.returnFrame=nil;r.humanoid.Health=r.humanoid.MaxHealth
	if frame then player:SetAttribute("EHReturnSerial",(player:GetAttribute("EHReturnSerial") or 0)+1)end
	return true
end
function Service:SetSpeedModifier(player,key,value)
	local r=self._records[player]
	if not r or type(key)~="string" or #key==0 or #key>48 then return false end
	if value~=nil and (type(value)~="number" or value~=value or value<0 or value>2) then return false end
	if value~=nil and r.modifiers[key]==nil then local n=0 for _ in r.modifiers do n+=1 end if n>=8 then return false end end
	r.modifiers[key]=value;return true
end
function Service:_Step(dt)
	for player,r in self._records do
		local h,root=r.humanoid,r.root
		if h and root and root.Parent then
			local policy=Policy.Contexts[r.context]
            local pos=root.Position
            -- crew never collide with each other anywhere in the game place (they pass straight through one
            -- another in corridors, doorways and the cabin); everything else still collides normally
            local cabin=Shared.Parent:GetAttribute("PlaceRole")=="Game"
            local inVent=typeof(player)=="Instance" and player:GetAttribute("EHInVent")~=nil
            local prone=inVent
            if prone and policy.movement then r.crouch=true;r.intent=false end
            if isDown(player) then r.intent=false;r.expires=0 end -- no sprint while down or getting up
            if r.wasProne and not prone then r.crouch=false end -- out of the vent / got up: stand back up
            r.wasProne=prone
            for part,original in r.partGroups or {} do if part.Parent then part.CollisionGroup=(prone and part~=root) and "BlackwaterProneBody" or (cabin and "BlackwaterCabinCrew" or original) end end
			local modifier=1;for _,v in r.modifiers do modifier*=v end;modifier=math.clamp(modifier,0,2)
			local v=root.AssemblyLinearVelocity
			local moving=Vector3.new(v.X,0,v.Z).Magnitude>.75 and h.Health>0
			local speed
			if not policy.movement or h.Health<=0 then r.crouch=false end
			r.sprint,speed=Sprint.Step(r.sprint,dt,r.intent and not r.crouch and os.clock()<r.expires,moving,policy.sprint,modifier)
			if r.crouch and not r.sprint.sprinting then speed=(prone and (MoveConfig.VentCrawlSpeed or 5) or MoveConfig.CrouchSpeed)*modifier end -- lying down: a slow belly drag
			-- inside a duct the speed is fixed: no sprint, no slow/boost modifiers, always the same tense crawl
			if inVent then speed=MoveConfig.VentCrawlSpeed or 5 end
			-- the lift sequence (doors closing on the surface -> intro on the floor below): movement is
			-- switched off at the source, exactly like the intro itself, so nothing the player does
			-- (keys, mouse flicks, the stick) can move or turn the body until the floor hands over
			local liftHold=typeof(player)=="Instance" and player:GetAttribute("EHElevatorLock")==true
			local enabled=policy.movement and h.Health>0 and not liftHold
			h.WalkSpeed=enabled and speed or 0;h.AutoRotate=enabled
			h.JumpPower=0;h.JumpHeight=0 -- no jumping anywhere
			-- Anchoring prevents residual motion while intro/results/downed controls are disabled.
			-- Never anchored in mid-air: a character that is still falling (dropping off a ledge, out of
			-- the lift) lands first, otherwise it would hang in the air. When the lock ends the root is
			-- always freed and handed straight back to its own player's physics (network owner), so
			-- there is no moment where the server holds it and other screens see it float or lag.
			local locked=(not policy.movement or liftHold) and h.Health>0
			local airborne=h.FloorMaterial==Enum.Material.Air
			if locked and not r.locked and not airborne then root.Anchored=true;r.locked=true
			elseif not locked and r.locked then
				root.Anchored=false;r.locked=false
				if typeof(player)=="Instance" and player:IsA("Player") then pcall(function()root:SetNetworkOwner(player)end) end
			end
		end
		self:_Publish(player,r)
	end
end
function Service:Start()
	self._active=true
	-- the body that never collides while lying in a duct
	for _,g in Physics:GetRegisteredCollisionGroups() do pcall(function()Physics:CollisionGroupSetCollidable("BlackwaterProneBody",g.name,false)end) end
	self._scope:Add(Players.PlayerAdded:Connect(function(p) self:_Add(p) end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p) self:_Remove(p) end))
	self._scope:Add(self._runs:Subscribe(function() for p,r in self._records do self:_Refresh(p,r) end end))
	local elapsed=0
	self._scope:Add(RunService.Heartbeat:Connect(function(dt) elapsed+=dt;if elapsed>=.1 then local step=elapsed;elapsed=0;self:_Step(step) end end))
	for _,p in Players:GetPlayers() do self:_Add(p) end
end
function Service:Destroy()
	self._active=false
	if self._scope then self._scope:Destroy() end
	for p,r in self._records do
		if r.root and r.locked then r.root.Anchored=false end
		self:_Remove(p)
	end
	if self._oldAutoLoads~=nil then Players.CharacterAutoLoads=self._oldAutoLoads end
end
return table.freeze(Service)
