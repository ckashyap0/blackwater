--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Policy=require(Shared.Contracts.CharacterContract)
local Sprint=require(Shared.Utilities.SprintModel)
local Service={}
Service.__index=Service
function Service.new()
	return setmetatable({Name="CharacterService",Dependencies={"GameRunService"},_records={},_active=false},Service)
end
function Service:Init(dependencies)
	self._runs=dependencies.GameRunService
	self._scope=Scope.new()
	self._oldAutoLoads=Players.CharacterAutoLoads
	Players.CharacterAutoLoads=false
end
function Service:_Publish(player,r)
	player:SetAttribute("EHCharacterEpoch",r.epoch)
	player:SetAttribute("EHLifeState",r.life)
	player:SetAttribute("EHContext",r.context)
	player:SetAttribute("EHStamina",math.floor(r.sprint.stamina*10+.5)/10)
	player:SetAttribute("EHSprinting",r.sprint.sprinting)
	player:SetAttribute("EHExhausted",r.sprint.exhausted)
end
function Service:_Refresh(player,r)
	local view=self._runs:GetViewFor(player.UserId)
	local runId=view and view.runId or nil
	if r.runId and not runId then
		r.life="Alive";r.sprint=Sprint.New();r.modifiers={}
		if not r.humanoid or r.humanoid.Health<=0 then self:Spawn(player) end
	end
	r.runId=runId
	local context=Policy.ContextFor(view,r.life)
	if r.suspended and context~="Dead" and context~="Results" then context="Intro" end
	if r.admissionPending then context="Intro" end
	if context~=r.context then r.intent=false;r.expires=0;r.context=context;r.epoch+=1 end
	self:_Publish(player,r)
end
function Service:Spawn(player)
	local r=self._records[player]
	if not self._active or not r or r.loading then return false,"Unavailable" end
	-- Future survival/floor services must explicitly restore life before calling Spawn.
	if r.life~="Alive" and r.life~="Downed" then return false,"NotAlive" end
	if self._admissionRequired and not r.admitted then return false,"NotAdmitted" end
	r.loading=true
	task.spawn(function()
		if not self._active or self._records[player]~=r or player.Parent~=Players then r.loading=false;return end
		local ok,err=pcall(function() player:LoadCharacterAsync() end)
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
	r.epoch+=1;r.intent=false;r.expires=0
	self:_Publish(player,r)
	task.spawn(function()
		local humanoid=character:WaitForChild("Humanoid",10)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if not self._active or self._records[player]~=r or r.character~=character then return end
		if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
			player:SetAttribute("EHSpawnError","Missing character components");return
		end
		r.humanoid=humanoid;r.root=root;
		if r.returnFrame then
			character:PivotTo(r.returnFrame);r.returnFrame=nil
			player:SetAttribute("EHReturnSerial",(player:GetAttribute("EHReturnSerial") or 0)+1)
		end
		r.jumpPower=humanoid.JumpPower;r.jumpHeight=humanoid.JumpHeight
		player:SetAttribute("EHSpawnError",nil)
		r.characterScope:Add(humanoid.Died:Connect(function()
			if r.character~=character then return end
			r.life="Dead";r.intent=false
			self:_Refresh(player,r)
			-- Explicit lobby-only respawn. Active runs never use the default respawn path.
			if not self._runs:GetViewFor(player.UserId) then
				local epoch=r.epoch
				task.delay(3,function()
					if self._active and self._records[player]==r and r.epoch==epoch and not self._runs:GetViewFor(player.UserId) then
						r.life="Alive";r.sprint=Sprint.New();self:_Refresh(player,r);self:Spawn(player)
					end
				end)
			end
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
	r.intent=enabled;r.expires=enabled and os.clock()+1.5 or 0
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
	r.life="Alive";r.sprint=Sprint.New();r.modifiers={};r.intent=false;r.expires=0;r.suspended=false
	r.epoch+=1;r.returnFrame=frame;self:_Refresh(player,r)
	if not r.humanoid or r.humanoid.Health<=0 then return self:Spawn(player) end
	if frame and r.character then r.character:PivotTo(frame) end
	r.returnFrame=nil;r.humanoid.Health=r.humanoid.MaxHealth
	player:SetAttribute("EHReturnSerial",(player:GetAttribute("EHReturnSerial") or 0)+1)
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
			local modifier=1;for _,v in r.modifiers do modifier*=v end;modifier=math.clamp(modifier,0,2)
			local v=root.AssemblyLinearVelocity
			local moving=Vector3.new(v.X,0,v.Z).Magnitude>.75 and h.Health>0
			local speed
			r.sprint,speed=Sprint.Step(r.sprint,dt,r.intent and os.clock()<r.expires,moving,policy.sprint,modifier)
			local enabled=policy.movement and h.Health>0
			h.WalkSpeed=enabled and speed or 0;h.AutoRotate=enabled
			h.JumpPower=enabled and r.jumpPower or 0;h.JumpHeight=enabled and r.jumpHeight or 0
			-- Anchoring prevents residual motion while intro/results/downed controls are disabled.
			local locked=not policy.movement and h.Health>0
			if locked and not r.locked then r.wasAnchored=root.Anchored;root.Anchored=true;r.locked=true
			elseif not locked and r.locked then root.Anchored=r.wasAnchored;r.locked=false end
		end
		self:_Publish(player,r)
	end
end
function Service:Start()
	self._active=true
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
		if r.root and r.locked then r.root.Anchored=r.wasAnchored end
		self:_Remove(p)
	end
	if self._oldAutoLoads~=nil then Players.CharacterAutoLoads=self._oldAutoLoads end
end
return table.freeze(Service)
