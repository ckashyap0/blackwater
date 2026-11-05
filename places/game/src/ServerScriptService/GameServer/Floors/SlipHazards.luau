--!nonstrict
-- Level 5 side task: wet-floor slip hazards and the Janitor Closet mops.
--  * Spills (SpillZone parts with SlipHazard=true) knock down any crew member who SPRINTS through
--    them: momentum is stripped, movement and looking are locked for 4 s in all (KnockSeconds on
--    the floor plus the first half of getting up, see HazardController) and every client plays
--    the fall from the replicated EHKnockedAt/EHKnockedUntil player attributes. Carrying a mop gives
--    no protection (you keep hold of it while you are down); walking or crouching is always safe.
--  * Four mops wait on the rack in the Janitor Closet. Take one, hold MOP UP on a spill to remove
--    it, then hang the mop back on the rack. Mops return home automatically if the carrier dies,
--    leaves or the floor stops.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Hazards={};Hazards.__index=Hazards
-- Mopping (take a mop, MOP UP a spill, hang it back) always works on the two spill zones. The old
-- optional "Protocol 04" counter on the terminals only shows when the floor config asks for it.
local MOP_TASK=require(game.ReplicatedStorage.Game.Shared.Config.Level5).MopSideTask==true
Hazards.RefillSeconds=300 -- a mopped spill fills back up from the leak after five minutes
Hazards.KnockSeconds=3.6;Hazards.HeldScale=.62;Hazards.GraceSeconds=2;Hazards.SlipSpeed=13.5
-- A spill takes WIPES full passes of the mop. One pass is one sweep of the head across the puddle
-- (HazardController strokes at 4.6 rad/s, so one pass = pi/4.6 s). Progress is counted in whole
-- passes: let go part-way through a pass and only the finished passes are kept; the next hold
-- carries on from there (its hold time is cut to what is left).
Hazards.Wipes=5;Hazards.WipeSeconds=math.pi/4.6
Hazards.CleanSeconds=Hazards.Wipes*Hazards.WipeSeconds-.5 -- (InteractionService adds a 0.5 s hold bonus)
local SOUND={fall='rbxassetid://9113481033',mop='rbxassetid://9126206046'}
function Hazards.new(model)return setmetatable({Model=model,_spills={},_mops={},_carriers={},_knocked={},_grace={},_held={}},Hazards)end
local function now()return workspace:GetServerTimeNow()end
local function sound(parent,id,volume,speed)
 local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume or .8;s.PlaybackSpeed=speed or 1;s.RollOffMinDistance=6;s.RollOffMaxDistance=60;s.Parent=parent;s:Play()
 task.delay(6,function()s:Destroy()end);return s
end
function Hazards:_Remaining()
 -- The side task only counts spills that have never been mopped. A spill that fills back up from
 -- its leak later is a slip hazard again (and can be mopped again), but it never brings the task
 -- or its tracker back.
 local n=0;for _,s in self._spills do if s.active and not s.everCleaned then n+=1 end end
 if not MOP_TASK then n=0 end -- (no task: nothing to count or show)
 self.Model:SetAttribute('SpillsRemaining',n);self.Model:SetAttribute('SpillsTotal',MOP_TASK and #self._spills or 0)
 return n
end
function Hazards:Prepare(context)
 self._context=context
 for _,d in self.Model:GetDescendants()do
  if d:IsA('BasePart') and d:GetAttribute('SlipHazard') then
   local i=d:GetAttribute('SpillIndex') or (#self._spills+1)
   local surface=d.Parent:FindFirstChild('SpillSurface')
   d:SetAttribute('SlipActive',true);d:SetAttribute('CleanedAt',nil);d:SetAttribute('RefilledAt',nil)
   table.insert(self._spills,{zone=d,surface=surface,model=d.Parent,index=i,id='BW5Spill'..i,active=true,saved=0,
    -- (how the hitboxes were authored, so a refill puts them back exactly)
    zoneQuery=d.CanQuery,zoneTouch=d.CanTouch,surfaceQuery=surface and surface.CanQuery})
   d:SetAttribute('MopProgress',0);if surface then surface:SetAttribute('EHProgressBase',0)end
  elseif d:IsA('Model') and d:GetAttribute('MopIndex') then
   local handle=d:FindFirstChild('Handle')
   -- the generous invisible MopHitbox is what players aim at (falls back to the shaft)
   if handle then self._mops[d:GetAttribute('MopIndex')]={model=d,handle=handle,target=d:FindFirstChild('MopHitbox') or handle,home=d:GetPivot()} end
  end
 end
 table.sort(self._spills,function(a,b)return a.index<b.index end)
 -- (the drip sounds are played by every client in sync with each falling drop, see HazardController)
 self:_Remaining()
 -- ONE mop station: a single zone round the whole rack. Inside it the prompt is TAKE MOP while
 -- your hands are free and RETURN MOP while you carry one (the client swaps the label from
 -- EHLabelWithMop) - one prompt, one place, nothing to flicker between.
 local station
 for _,d in self.Model:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('Ref')=='MopStation' then station=d;break end end
 if station then
  self._station=station
  station:SetAttribute('EHLabelWithMop','RETURN MOP')
  context.RegisterInteraction({interactionId='BW5MopStation',target=station,interactionType='Panel',label='TAKE MOP',holdDuration=.35,
   allowedRunPhases={FloorActive=true},lineOfSightModel=station.Parent,
   canUse=function(p)
    if self._carriers[p] then return true end
    if p:GetAttribute('EHCarriedItem') then return false,'HandsFull' end
    if self:IsKnocked(p) then return false,'Knocked' end
    if not self:_FreeMop(p) then return false,'Unavailable' end
    return true
   end,
   complete=function(p)
    if self._carriers[p] then self:_Return(p);return true,'Returned' end
    local i=self:_FreeMop(p);if not i then return false,'Unavailable' end
    return self:_Take(p,i)
   end})
 end
 for i,m in (station and {} or self._mops) do
  self._perMop=true
  context.RegisterInteraction({interactionId='BW5Mop'..i,target=m.target,interactionType='Pickup',label='TAKE MOP',holdDuration=.35,
   allowedRunPhases={FloorActive=true},lineOfSightModel=m.model.Parent,
   canUse=function(p)
    if m.holder then return false,'Unavailable' end
    if self._carriers[p] then return false,'MopInHand' end
    if p:GetAttribute('EHCarriedItem') then return false,'HandsFull' end
    if self:IsKnocked(p) then return false,'Knocked' end
    return true
   end,
   complete=function(p)return self:_Take(p,i)end})
 end
 for _,s in self._spills do
  if s.surface then
   context.RegisterInteraction({interactionId=s.id,target=s.surface,interactionType='Panel',label='MOP UP SPILL',holdDuration=Hazards.CleanSeconds,
    allowedRunPhases={FloorActive=true},lineOfSightModel=s.model,
    canUse=function(p)
     if not s.active then return false,'Unavailable' end
     if not self._carriers[p] then return false,'NeedsMop' end
     if self:IsKnocked(p) then return false,'Knocked' end
     return true
    end,
    complete=function(p)
     if not s.active or not self._carriers[p] then return false,'Unavailable' end
     self:_Clean(s,p);return true,'Cleaned'
    end})
  end
 end
 local rail
 for _,d in self.Model:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('Ref')=='MopReturn' then rail=d;break end end
 if rail and not station then
  context.RegisterInteraction({interactionId='BW5MopReturn',target=rail,interactionType='Panel',label='RETURN MOP',holdDuration=.4,
   allowedRunPhases={FloorActive=true},lineOfSightModel=rail.Parent and rail.Parent.Parent,
   canUse=function(p)return self._carriers[p]~=nil,'NoMop' end,
   complete=function(p)if not self._carriers[p] then return false,'NoMop' end;self:_Return(p);return true,'Returned' end})
  -- clients only show RETURN MOP to a player who is actually carrying a mop
  rail:SetAttribute('EHNeedsMop',true)
 end
 -- Janitor Closet sinks: anyone can turn either tap on or off. While it runs, the plant's black
 -- water pours from the spout and fills the basin; shut off, it slowly drains away. Clients
 -- animate the stream, the fill level and the handles from WaterOn/WaterChangedAt/WaterLevelAt.
 self._sinks={}
 for _,m in self.Model:GetDescendants()do
  if m:IsA('Model') and m:GetAttribute('SinkId') then
   local ctl=m:FindFirstChild('TapControl',true)
   if ctl and ctl:IsA('BasePart') then
    local sink={model=m,control=ctl,id='BW5Sink'..tostring(m:GetAttribute('SinkId'))}
    table.insert(self._sinks,sink)
    m:SetAttribute('WaterOn',false);m:SetAttribute('WaterChangedAt',nil);m:SetAttribute('WaterLevelAt',0)
    context.RegisterInteraction({interactionId=sink.id,target=ctl,interactionType='Panel',label='TURN ON TAP',holdDuration=.25,
     allowedRunPhases={FloorActive=true},lineOfSightModel=m,
     canUse=function(p)if self:IsKnocked(p) then return false,'Knocked' end;return true end,
     complete=function()self:_ToggleSink(sink);return true,'Toggled' end})
   end
  end
 end
 local acc=0
 self._conn=RunService.Heartbeat:Connect(function(dt)acc+=dt;if acc>=.08 then acc=0;local ok,err=pcall(self._Step,self);if not ok then warn('[ElevatorHorror] slip hazards: '..tostring(err))end end end)
end
function Hazards:IsKnocked(p)return (p:GetAttribute('EHKnockedUntil') or 0)>now()end
------------------------------------------------------------------ mops
local function setVisible(model,visible)
 for _,d in model:GetDescendants()do
  if d:IsA('BasePart') then
   if d:GetAttribute('HomeTransparency')==nil then d:SetAttribute('HomeTransparency',d.Transparency)end
   d.Transparency=visible and d:GetAttribute('HomeTransparency') or 1
   if d.Name=='MopHitbox' then d.CanQuery=visible and not d:GetAttribute('StationOnly') end
  end
 end
end
function Hazards:_Held(p,i)
 local m=self._mops[i];local c=p.Character
 -- off hand: the flashlight is the primary (right-hand) tool, so the mop rides in the left hand
 local hand=c and (c:FindFirstChild('LeftHand') or c:FindFirstChild('Left Arm'))
 if not hand then return end
 local clone=m.model:Clone();clone.Name='HeldMop'
 for k in clone:GetAttributes()do clone:SetAttribute(k,nil)end
 clone:SetAttribute('HeldMopIndex',i)
 local box=clone:FindFirstChild('MopHitbox');if box then box:Destroy()end
 -- the rack mop is a big set-dressing prop; in a hand it is drawn at a believable size for the
 -- avatar (clients read HeldScale to pose it; the first-person view model resets to full size)
 clone:ScaleTo(Hazards.HeldScale);clone:SetAttribute('HeldScale',Hazards.HeldScale)
 local handle=clone:FindFirstChild('Handle')
 for _,d in clone:GetDescendants()do
  if d:IsA('BasePart') then
   for k in d:GetAttributes()do d:SetAttribute(k,nil)end
   d.Anchored=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.Massless=true
  end
 end
 -- Carried upright at the side, gripped at hand height (shaft X axis points toward the top), so
 -- the head rides just off the floor beside the feet and nothing sticks out into walls.
 -- The whole assembly is posed FIRST and only then welded to the shaft, so the head can never be
 -- left behind (WeldConstraints do not drag parts that are posed while outside the workspace).
 -- gripped higher up the shaft (toward the handle), so it leans forward a little more to keep the
 -- head just off the floor
 local dir=Vector3.new(-.08,.88,.47).Unit
 local side=(Vector3.new(1,0,0)-dir*dir.X).Unit
 local motor=Instance.new('Motor6D');motor.Name='MopGrip'
 motor.Part0=hand;motor.Part1=handle
 -- the shaft runs through the palm (the hand's grip attachment), not through the wrist
 local palm=hand:FindFirstChild('LeftGripAttachment')
 motor.C0=CFrame.fromMatrix(palm and palm.Position or Vector3.new(0,-.1,0),dir,side)
 -- gripped by the rubber grip at the top of the handle (2.2 studs above the shaft's centre);
 -- every client then poses the rigid shaft from the hand down to the floor (HazardController)
 -- Where the hand closes on the shaft is fitted to the avatar: carried at the side the head should
 -- hang just clear of the floor, so the grip sits that far up the handle (never past the rubber
 -- grip at the top). Clients pose the rigid shaft from this point (HazardController).
 local root=c:FindFirstChild('HumanoidRootPart');local hum=c:FindFirstChildOfClass('Humanoid')
 local along=2.2
 if root and hum then
  local floorY=root.Position.Y-(hum.HipHeight+root.Size.Y/2)
  local handHeight=(palm and palm.WorldPosition.Y or hand.Position.Y)-floorY
  along=math.clamp((handHeight-.6)/Hazards.HeldScale-3.0,.6,2.2)
 end
 motor.C1=CFrame.new(along*Hazards.HeldScale,0,0)
 local target=hand.CFrame*motor.C0*motor.C1:Inverse()
 clone:PivotTo(target*handle.CFrame:ToObjectSpace(clone:GetPivot()))
 for _,d in clone:GetDescendants()do if d:IsA('BasePart') and d~=handle then local w=Instance.new('WeldConstraint');w.Name='MopAssembly';w.Part0=handle;w.Part1=d;w.Parent=d end end
 clone.Parent=c
 motor.Parent=hand
 self._held[p]=clone
end
-- the free mop nearest to the player (any free one will do)
function Hazards:_FreeMop(p)
 local root=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
 local best,bestD=nil,math.huge
 for i,m in self._mops do
  if not m.holder then
   local d=root and (m.home.Position-root.Position).Magnitude or i
   if d<bestD then best,bestD=i,d end
  end
 end
 return best
end
function Hazards:_Take(p,i)
 local m=self._mops[i];if not m or m.holder then return false,'Unavailable' end
 if self._carriers[p] then return false,'AlreadyCarrying' end
 m.holder=p;self._carriers[p]=i
 pcall(self._Held,self,p,i) -- clone while the rack copy is still visible
 setVisible(m.model,false)
 if self._perMop and self._context.SetInteractionEnabled then self._context.SetInteractionEnabled('BW5Mop'..i,false)end
 p:SetAttribute('EHCarryingMop',i)
 self:_Publish()
 return true,'MopTaken'
end
function Hazards:_Return(p)
 local i=self._carriers[p];if not i then return end
 local m=self._mops[i]
 self._carriers[p]=nil;m.holder=nil
 m.model:PivotTo(m.home);setVisible(m.model,true)
 if self._perMop and self._context.SetInteractionEnabled then self._context.SetInteractionEnabled('BW5Mop'..i,true)end
 if p.Parent then p:SetAttribute('EHCarryingMop',nil)end
 local held=self._held[p];self._held[p]=nil;if held then held:Destroy()end
 local c=p.Character;local hand=c and (c:FindFirstChild('LeftHand') or c:FindFirstChild('Left Arm'));local grip=hand and hand:FindFirstChild('MopGrip');if grip then grip:Destroy()end
 self:_Publish()
end
------------------------------------------------------------------ sinks
-- the fill/drain curve lives in Shared.Utilities.SinkCurve so clients draw exactly this level
local SinkCurve=require(game.ReplicatedStorage.Game.Shared.Utilities.SinkCurve)
function Hazards.SinkLevel(m,t) return SinkCurve.FromModel(m,t) end
function Hazards:_ToggleSink(s)
 local m=s.model;local t=now()
 local level=Hazards.SinkLevel(m,t);local on=m:GetAttribute('WaterOn')~=true
 m:SetAttribute('WaterLevelAt',level);m:SetAttribute('WaterChangedAt',t);m:SetAttribute('WaterOn',on)
 s.control:SetAttribute('EHInteractionLabel',on and 'TURN OFF TAP' or 'TURN ON TAP')
 pcall(function()sound(s.control,'rbxassetid://9113662828',.22,1.7)end) -- stiff old valve
end
------------------------------------------------------------------ spills
-- the live mop progress of one spill (0..1), published for every client to fade the water by
function Hazards:_SetProgress(s,live,saved)
 if saved then
  s.saved=saved
  if s.surface then s.surface:SetAttribute('EHProgressBase',saved)end -- the hold bar starts from here
  if self._context.SetInteractionHoldScale then self._context.SetInteractionHoldScale(s.id,math.max(.05,1-saved))end
 end
 live=math.clamp(live,0,1)
 if math.abs((s.zone:GetAttribute('MopProgress') or 0)-live)>.004 or live==0 or live==1 then s.zone:SetAttribute('MopProgress',live)end
end
-- Follows whoever is mopping each spill: the progress grows with every finished pass, a quiet wipe
-- plays per pass, and letting go keeps the finished passes (never stuck half-way, never lost).
function Hazards:_MopProgress()
 for _,s in self._spills do
  if s.active and s.surface then
   local holder
   for p in self._carriers do if p:GetAttribute('EHActiveInteraction')==s.id and p:GetAttribute('EHInteractionState')=='Holding' then holder=p break end end
   if holder then
    local started=holder:GetAttribute('EHInteractionStarted') or now()
    local dur=math.max(.05,holder:GetAttribute('EHInteractionDuration') or 1)
    local live=s.saved+(1-s.saved)*math.clamp((now()-started)/dur,0,1)
    local passes=math.floor(live*Hazards.Wipes+1e-6)
    if passes>(s.passes or 0) and passes<Hazards.Wipes then pcall(function()sound(s.surface,SOUND.mop,.55,.95+math.random()*.1)end)end
    s.passes=math.max(s.passes or 0,passes);s.live=live;s.holding=true
    self:_SetProgress(s,live)
   elseif s.holding then
    -- released (or interrupted) before the end: keep the whole passes only
    s.holding=false
    local kept=math.floor((s.live or s.saved)*Hazards.Wipes+1e-6)/Hazards.Wipes
    s.passes=math.floor(kept*Hazards.Wipes+.5)
    if s.active then self:_SetProgress(s,kept,kept)end
   end
  end
 end
end
function Hazards:_Clean(s,p)
 s.active=false;s.everCleaned=true;s.zone:SetAttribute('SlipActive',false)
 s.holding=false;s.passes=0
 self:_SetProgress(s,1,0)
 -- the spill is gone: nothing left to slip on, aim at or block a ray
 s.zone.CanQuery=false;s.zone.CanTouch=false
 if s.surface then s.surface.CanQuery=false end
 if self._context.SetInteractionEnabled then self._context.SetInteractionEnabled(s.id,false)end
 local remaining=self:_Remaining()
 self:_Publish()
 -- Every client animates the water drying away from this shared timestamp (HazardController):
 -- the standing water shrinks back toward the drip, then the damp edge fades. The leak above
 -- keeps dripping onto the clean floor, and after RefillSeconds the spill has built back up.
 s.zone:SetAttribute('RefilledAt',nil);s.zone:SetAttribute('CleanedAt',now())
 pcall(function()sound(s.surface,'rbxassetid://9126205694',.6,1)end)
 local serial=(s.serial or 0)+1;s.serial=serial
 task.delay(Hazards.RefillSeconds,function()
  if self._stopped or s.serial~=serial or s.active then return end
  self:_Refill(s)
 end)
 return remaining
end
function Hazards:_Refill(s)
 s.active=true;s.zone:SetAttribute('SlipActive',true)
 s.zone.CanQuery=s.zoneQuery~=false;s.zone.CanTouch=s.zoneTouch~=false
 if s.surface then s.surface.CanQuery=s.surfaceQuery~=false end
 s.passes=0;s.holding=false;self:_SetProgress(s,0,0)
 s.zone:SetAttribute('CleanedAt',nil);s.zone:SetAttribute('RefilledAt',now())
 if self._context.SetInteractionEnabled then self._context.SetInteractionEnabled(s.id,true)end
 self:_Remaining();self:_Publish()
end
function Hazards:_Knock(p,root)
 local t=now()
 self._knocked[p]=t+Hazards.KnockSeconds
 p:SetAttribute('EHKnockStyle',nil);p:SetAttribute('EHKnockedAt',t);p:SetAttribute('EHKnockedUntil',t+Hazards.KnockSeconds)
 if self._context.SetSpeedModifier then self._context.SetSpeedModifier(p,'Slip',0)end
 pcall(function()sound(root,SOUND.fall,1,1)end)
 if self._context.EmitNoise then pcall(self._context.EmitNoise,{kind='Fall',userId=p.UserId,position=root.Position,runId=self._context.RunId})end
end
function Hazards:_Recover(p)
 self._knocked[p]=nil;self._grace[p]=now()+Hazards.GraceSeconds
 if self._context.SetSpeedModifier then self._context.SetSpeedModifier(p,'Slip',nil)end
end
function Hazards:_Step()
 if self._stopped then return end
 local t=now()
 local suspended=self._context.IsSuspended and self._context.IsSuspended()
 for p,until_ in self._knocked do if t>=until_ or p.Parent~=Players then self:_Recover(p)end end
 self:_MopProgress()
 for p,i in self._carriers do
  local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
  if p.Parent~=Players or not h or h.Health<=0 or p:GetAttribute('EHLifeState')~='Alive' or not (self._held[p] and self._held[p].Parent==c) then self:_Return(p)end
 end
 if suspended then return end
 for _,p in Players:GetPlayers()do
  local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
  if root and h and h.Health>0 and p:GetAttribute('EHLifeState')=='Alive' and not self._knocked[p] and (self._grace[p] or 0)<t
   and p:GetAttribute('EHSprinting')==true then
   local v=root.AssemblyLinearVelocity;local speed=Vector3.new(v.X,0,v.Z).Magnitude
   if speed>Hazards.SlipSpeed then
    for _,s in self._spills do
     if s.active then
      local lp=s.zone.CFrame:PointToObjectSpace(root.Position)
      if math.abs(lp.X)<s.zone.Size.X/2-.25 and math.abs(lp.Z)<s.zone.Size.Z/2-.25 and lp.Y>-1 and lp.Y<5.5 then self:_Knock(p,root);break end
     end
    end
   end
  end
 end
end
function Hazards:_Publish()
 local n=0;for _ in self._carriers do n+=1 end
 self.Model:SetAttribute('MopsOut',n)
end
function Hazards:Stop()
 if self._stopped then return end
 self._stopped=true
 if self._conn then self._conn:Disconnect()end
 for p in self._knocked do pcall(self._Recover,self,p)end
 for p in self._carriers do pcall(self._Return,self,p)end
 for _,p in Players:GetPlayers()do p:SetAttribute('EHCarryingMop',nil)end
end
return Hazards
