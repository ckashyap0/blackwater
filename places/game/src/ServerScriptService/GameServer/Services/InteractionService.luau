--!nonstrict
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Tags=game:GetService("CollectionService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local V=require(Shared.Utilities.Validation)
local Service={};Service.__index=Service
-- Every hold in the game takes this much longer than the time its interaction asks for, so
-- nothing completes from a quick tap (the progress bar reads the final duration).
Service.HoldBonus=.5
function Service.new(options)
	options=options or {}
	return setmetatable({Name="InteractionService",Dependencies={"GameRunService","CharacterService"},
		_defs={},_holds={},_locks={},_players=options.players or Players,_clock=options.clock or os.clock,
		_holdBonus=options.holdBonus or Service.HoldBonus},Service)
end
function Service:Init(deps) self._runs=deps.GameRunService;self._characters=deps.CharacterService;self._scope=Scope.new() end
function Service:Register(def)
	assert(V.IsIdentifier(def.interactionId,64) and not self._defs[def.interactionId],"Invalid/duplicate interaction")
	assert(typeof(def.target)=="Instance" and def.target:IsA("BasePart"),"Interaction requires BasePart")
	assert(type(def.complete)=="function" and type(def.allowedRunPhases)=="table","Missing interaction behavior")
	assert(V.IsIdentifier(def.runId,64) and V.IsIdentifier(def.floorInstanceId,64),"Missing run scope")
	local count=0;for _ in self._defs do count+=1 end;assert(count<192,"Interaction limit")
	def=table.clone(def)
	def.maximumDistance=def.maximumDistance or 8;def.holdDuration=(def.holdDuration or .5)+(def.quick and 0 or self._holdBonus)
	def.baseHoldDuration=def.holdDuration
	assert(type(def.maximumDistance)=="number" and def.maximumDistance>0 and def.maximumDistance<=8,"Invalid range")
	assert(type(def.holdDuration)=="number" and def.holdDuration>=0 and def.holdDuration<=30,"Invalid hold")
	def.requiresLineOfSight=def.requiresLineOfSight~=false;def.exclusive=def.exclusive~=false
	def.enabled=def.enabled~=false;def.allowedLifeStates=def.allowedLifeStates or {Alive=true}
	self._defs[def.interactionId]=def
	local t=def.target;t:SetAttribute("EHInteractionId",def.interactionId);t:SetAttribute("EHInteractionType",def.interactionType or "Generic")
	t:SetAttribute("EHInteractionLabel",def.label or "Use");t:SetAttribute("EHHoldDuration",def.holdDuration)
	t:SetAttribute("EHMaximumDistance",def.maximumDistance);t:SetAttribute("EHInteractionEnabled",def.enabled)
	Tags:AddTag(t,"EHInteractable")
	return function() self:Unregister(def.interactionId) end
end
function Service:SetEnabled(id,enabled)
	local d=self._defs[id];if not d then return false end
	d.enabled=enabled==true;d.target:SetAttribute("EHInteractionEnabled",d.enabled)
	if not d.enabled then for p,h in self._holds do if h.id==id then self:Cancel(p,"Disabled") end end end
	return true
end
-- Rescale one interaction's hold (e.g. a vent cover gets 25% quicker once its screws are out).
-- Scales the final duration the player actually holds for (applies from the next hold).
function Service:SetHoldScale(id,scale)
	local d=self._defs[id];if not d or type(scale)~="number" or scale<=0 then return false end
	d.holdDuration=math.clamp(d.baseHoldDuration*scale,0,30);d.target:SetAttribute("EHHoldDuration",d.holdDuration)
	return true
end
function Service:Unregister(id)
	local d=self._defs[id];if not d then return end
	for p,h in self._holds do if h.id==id then self:Cancel(p,"Removed") end end
	self._defs[id]=nil;self._locks[id]=nil;Tags:RemoveTag(d.target,"EHInteractable")
	d.target:SetAttribute("EHInteractionEnabled",false)
end
local RANGE_SLACK=1.5
function Service:_Validate(player,d,epoch)
	if not self._active or player.Parent~=self._players then return false,"Unavailable" end
	if player:GetAttribute("EHAwaitingReconnect") then return false,"AwaitingReconnect" end
	if (player:GetAttribute("EHProtectionUntil") or 0)>workspace:GetServerTimeNow() then return false,"Protected" end
	if player:GetAttribute("EHCharacterEpoch")~=epoch then return false,"StaleCharacter" end
	local life=player:GetAttribute("EHLifeState")
	if not d.allowedLifeStates[life] then return false,"InvalidLifeState" end
	local c=player.Character;local root=c and c:FindFirstChild("HumanoidRootPart");local h=c and c:FindFirstChildOfClass("Humanoid")
	if not root or not h or h.Health<=0 then return false,"NoCharacter" end
	local view=self._runs:GetViewFor(player.UserId)
	-- (Oct 25) "Surface" scope: things on the surface yard (the site keycard) are used before any floor exists
	local floorOk=view and (view.floorInstanceId==d.floorInstanceId or (d.floorInstanceId=="Surface" and view.floorInstanceId==false))
	if not view or view.runId~=d.runId or not floorOk or not d.allowedRunPhases[view.phase] then return false,"WrongPhase" end
	if not d.enabled or not d.target:IsDescendantOf(workspace) then return false,"TargetUnavailable" end
	-- (a little slack over the range the client shows the prompt at: the server sees your body a moment
	-- late, so a press made right at the edge must not come back as "Move closer")
	if (root.Position-d.target.Position).Magnitude>d.maximumDistance+RANGE_SLACK then return false,"OutOfRange" end
	if d.requiresLineOfSight then
		local origin=(c:FindFirstChild("Head") or root).Position
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
		local ignore={c};for _,v in Tags:GetTagged("EHInvisibleCollider") do table.insert(ignore,v) end;params.FilterDescendantsInstances=ignore
		-- only solid things block the view (thin decor - papers lying on top of each other, stains, labels,
		-- clutter on a desk - never does), and whatever the target is resting on or tucked against right
		-- beside it doesn't count either: that is what made papers say "Something's in the way."
		params.RespectCanCollide=true
		local toTarget=d.target.Position-origin
		local hit=workspace:Raycast(origin,toTarget,params)
		if hit and hit.Instance~=d.target and not hit.Instance:IsDescendantOf(d.target) and not (d.lineOfSightModel and hit.Instance:IsDescendantOf(d.lineOfSightModel))
			and hit.Distance<toTarget.Magnitude-math.max(.6,math.max(d.target.Size.X,d.target.Size.Y,d.target.Size.Z)*.5) then return false,"Occluded" end
	end
	if d.canUse then local ok,reason=d.canUse(player);if not ok then return false,reason or "Unavailable" end end
	return true,view.phase
end
function Service:_Notify(player,state,id,reason,started,duration)
	player:SetAttribute("EHActiveInteraction",id)
	player:SetAttribute("EHInteractionReason",reason);player:SetAttribute("EHInteractionStarted",started)
	player:SetAttribute("EHInteractionDuration",duration)
	player:SetAttribute("EHInteractionState",state)
	player:SetAttribute("EHInteractionSerial",(player:GetAttribute("EHInteractionSerial") or 0)+1)
end
function Service:Begin(player,id,epoch)
	local d=self._defs[id];if not d then return false,"UnknownInteraction" end
	local ok,phase=self:_Validate(player,d,epoch);if not ok then self:_Notify(player,"Rejected",nil,phase);return false,phase end
	if self._holds[player] then return false,"AlreadyInteracting" end
	if d.exclusive and self._locks[id] then self:_Notify(player,"Rejected",nil,"Busy");return false,"Busy" end
	local now=self._clock()
	self._holds[player]={id=id,epoch=epoch,phase=phase,started=now,expires=now+1.5}
	if d.exclusive then self._locks[id]=player end
	self:_Notify(player,"Holding",id,nil,workspace:GetServerTimeNow(),d.holdDuration)
	return true,"Started"
end
function Service:Continue(player,id,epoch)
	local h=self._holds[player]
	if not h or h.id~=id or h.epoch~=epoch then return false,"NoMatchingHold" end
	if self._clock()>h.expires then self:Cancel(player,"Expired");return false,"HoldExpired" end
	h.expires=self._clock()+1.5;return true,"Continued"
end
-- Letting go the instant the bar fills: the release can reach the server a moment before its own
-- completion check runs, which used to throw the finished hold away (bar full, task not done). A
-- release within RELEASE_GRACE of the end now counts as finished, if the hold is still valid.
local RELEASE_GRACE=.2
function Service:Cancel(player,reason,id,epoch)
	local h=self._holds[player]
	if not h or (id and h.id~=id) or (epoch and h.epoch~=epoch) then return false,"NoMatchingHold" end
	if reason=="Released" then
		local d=self._defs[h.id]
		if d and self._clock()-h.started>=d.holdDuration-RELEASE_GRACE then
			local ok,phase=self:_Validate(player,d,h.epoch)
			if ok and phase==h.phase then self:_Complete(player,h,d);return true,"Completed" end
		end
	end
	self._holds[player]=nil;if self._locks[h.id]==player then self._locks[h.id]=nil end
	self:_Notify(player,"Canceled",nil,reason or "Released")
	return true,"Canceled"
end
function Service:_Step()
	local now=self._clock()
	for player,h in self._holds do
		local d=self._defs[h.id]
		local ok,phase=false,"Removed"
		if d then ok,phase=self:_Validate(player,d,h.epoch) end
		if not ok or phase~=h.phase or now>h.expires then self:Cancel(player,not ok and phase or "Interrupted")
		elseif now-h.started>=d.holdDuration then
			self:_Complete(player,h,d)
		end
	end
end
-- The bar is full: run the job's completion (which marks the task solved and updates the
-- objectives), then tell the client so the bar closes.
function Service:_Complete(player,h,d)
	if self._holds[player]~=h then return end
	-- All shipped completion callbacks are synchronous transactions.
	self._holds[player]=nil
	local called,success,reason=pcall(d.complete,player)
	if self._locks[h.id]==player then self._locks[h.id]=nil end
	if not called then warn("[ElevatorHorror] Interaction callback failed: "..h.id.." "..tostring(success));reason="InternalError" end
	self:_Notify(player,called and success~=false and "Completed" or "Rejected",nil,reason)
end
function Service:Start()
	self._active=true
	-- checked every frame, so a hold finishes the moment its bar is full
	self._scope:Add(RunService.Heartbeat:Connect(function() self:_Step() end))
	self._scope:Add(self._runs:Subscribe(function() self:_Step() end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p) self:Cancel(p,"Disconnected") end))
end
function Service:Destroy()
	self._active=false
	for p in self._holds do self:Cancel(p,"Shutdown") end
	for id in self._defs do self:Unregister(id) end
	if self._scope then self._scope:Destroy() end
	
	
end
return table.freeze(Service)
