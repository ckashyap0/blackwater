--!nonstrict
-- Client-side presentation for large mechanisms (the maintenance access gate). The server publishes
-- one timestamp ("<Name>OpenedAt" on the floor model); every client animates the visual leaf from it
-- in its own render step, so the motion is perfectly smooth and identical for late joiners.
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
function Controller.new()return setmetatable({Name='MechanismController',Dependencies={},_leaves={},_levers={},_swings={}},Controller)end
------------------------------------------------------------------ surface main gate
-- Both leaves of the main gate swing inward about their hinge from the yard's GateOpenedAt
-- (after a short unlock beat). Anyone still outside the wall at that moment gets a short
-- cutscene: the camera eases out to a fixed shot of the gate (GateCamera), holds while the locks
-- clunk and the leaves swing open, then eases back to your eyes. Movement is paused meanwhile.
local GATE_DELAY=.6
-- Closing (GateClosedAt, published by the server once the whole crew is inside and clear of the
-- leaves): a heavier motion than the opening - the motor takes the strain, the leaves gather speed,
-- slow into the stops and land with a slam and a small rebound. Both motions are computed on every
-- client from the server's timestamps, so they are frame-smooth and identical for everyone.
local CLOSE_DELAY,CLOSE_SECONDS=.4,3.6
local CUT={inn=.8,hold=4.1,out=.7}
local PRE_ROLL=.3 -- seconds held at your eyes before a shot leaves them (the flashlight goes down)
local function smooth(u)u=math.clamp(u,0,1);return u*u*(3-2*u)end
local function smoother(u)u=math.clamp(u,0,1);return u*u*u*(u*(u*6-15)+10)end
-- opening: one long, even, eased swing (no shiver)
local function openCurve(u)
 if u<=0 then return 0 end
 if u>=1 then return 1 end
 return smoother(u)
end
-- closing (0 = fully open, 1 = shut): one smooth, continuous motion - it gathers speed, carries
-- through and settles into the stops (no rebound, no jump). The clunk lands right at the end.
local IMPACT=.97
local function closeCurve(u)
 if u<=0 then return 0 end
 if u>=1 then return 1 end
 return smoother(u)
end
local function sound(id,parent,volume,speed)
 local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed;s.RollOffMinDistance=8;s.RollOffMaxDistance=120;s.Parent=parent;s:Play();game:GetService('Debris'):AddItem(s,8)
end
local function yardOf(inst)local a=inst.Parent;while a and a~=workspace do if a.Name=='SurfaceYard' and a:IsA('Model') then return a end;a=a.Parent end end
function Controller:_TrackSwing(m)
 if self._swings[m] or not m:IsA('Model') or not m:GetAttribute('YardGate') then return end
 local yard=yardOf(m);local off=m:GetAttribute('ClosedOffset')
 if not yard or not off or not m.PrimaryPart then return end
 self._swings[m]={yard=yard,off=off,deg=m:GetAttribute('SwingDegrees') or 90,secs=m:GetAttribute('SwingSeconds') or 3.4}
 m:SetAttribute('SwingTracked',true) -- (client-side marker, handy when testing)
end
-- Gate state from the two server timestamps: pose 0..1 (1 = open), whether it is moving, and the
-- phase ('open'/'close') with its progress.
function Controller:_GatePose(yard,secs,now)
 local opened=yard:GetAttribute('GateOpenedAt');local closed=yard:GetAttribute('GateClosedAt')
 if type(closed)=='number' and type(opened)=='number' and closed>opened then
  local u=(now-closed-CLOSE_DELAY)/CLOSE_SECONDS
  return 1-closeCurve(u),u>-CLOSE_DELAY/CLOSE_SECONDS and u<1,'close',u
 elseif type(opened)=='number' then
  local u=(now-opened-GATE_DELAY)/secs
  return openCurve(u),u>-GATE_DELAY/secs and u<1,'open',u
 end
 return 0,false,nil,0
end
-- Beacons, status lamps, motor sound and the ground rumble around the gate.
function Controller:_GateFx(yard,moving,phase,u,pose,now)
 local fx=self._gateFx
 if not fx or fx.yard~=yard then
  fx={yard=yard,beacons={},lamps={}}
  local gate=yard:FindFirstChild('GateTrigger',true)
  for _,d in yard:GetDescendants()do
   if d:IsA('BasePart') and d:GetAttribute('GateBeacon') then table.insert(fx.beacons,{p=d,base=d.CFrame})
   elseif d:IsA('BasePart') and d:GetAttribute('GateStatus') then table.insert(fx.lamps,{p=d,kind=d:GetAttribute('GateStatus')}) end
  end
  if gate then
   local a=Instance.new('Attachment');a.WorldPosition=gate.CFrame*Vector3.new(0,3,7.3);a.Parent=workspace.Terrain
   local motor=Instance.new('Sound');motor.SoundId='rbxassetid://9112889325';motor.Looped=true;motor.Volume=0;motor.PlaybackSpeed=.42;motor.RollOffMinDistance=10;motor.RollOffMaxDistance=140;motor.Parent=a
   local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=8;eq.MidGain=-2;eq.HighGain=-14;eq.Parent=motor
   fx.anchor=a;fx.motor=motor;fx.gatePos=a.WorldPosition
   self._scope:Add(a)
  end
  self._gateFx=fx
 end
 -- motion events: start clunk, mid creak, closing slam
 local key=phase and (phase..tostring(yard:GetAttribute(phase=='close' and 'GateClosedAt' or 'GateOpenedAt')))
 if key~=fx.key then fx.key=key;fx.started=false;fx.creaked=false;fx.slammed=false end
 if phase and fx.anchor then
  if not fx.started and u>-.02 and u<.5 then fx.started=true;if phase=='close' then sound('rbxassetid://9119630180',fx.anchor,.8,.8) end end
  -- (the opening's clunk and creak are played by the gate cutscene below)
  if phase=='close' and not fx.creaked and u>.2 and u<.6 then fx.creaked=true;sound('rbxassetid://9116799448',fx.anchor,.7,.95) end
  if phase=='close' and not fx.slammed and u>=IMPACT and u<1.2 then
   fx.slammed=true;sound('rbxassetid://9114533169',fx.anchor,1,.62);sound('rbxassetid://9119630180',fx.anchor,.9,.55)
   fx.jolt=os.clock()
  end
 end
 if fx.motor then
  local want=moving and u>0 and u<IMPACT and .5 or 0
  fx.motor.Volume+=(want-fx.motor.Volume)*.12
  if fx.motor.Volume>.01 and not fx.motor.IsPlaying then fx.motor:Play() elseif fx.motor.Volume<=.01 and fx.motor.IsPlaying then fx.motor:Stop() end
  fx.motor.PlaybackSpeed=.38+.1*math.clamp(u,0,1)
 end
 -- rotating amber beacons only while the gate moves
 local t=os.clock()
 for _,b in fx.beacons do
  if b.p.Parent then
   if moving then b.p.CFrame=b.base*CFrame.Angles(0,t*7,0);b.p.Transparency=.05 else b.p.CFrame=b.base;b.p.Transparency=.8 end
   local sw=b.p:FindFirstChild('Sweep');local gl=b.p:FindFirstChild('Glow')
   if sw then sw.Brightness=moving and 4 or 0 end;if gl then gl.Brightness=moving and 1.4 or 0 end
  end
 end
 -- status stacks: red = shut, amber flashing = moving, green = open
 local state=moving and 'Amber' or (pose>.5 and 'Green' or 'Red')
 local flash=(t*2.4)%1<.55
 for _,l in fx.lamps do if l.p.Parent then local on=l.kind==state and (state~='Amber' or flash);l.p.Transparency=on and 0 or .85
  -- each signal lens also throws a little coloured light while it is lit
  local gl=l.p:FindFirstChildWhichIsA('Light');if gl and gl.Enabled~=on then gl.Enabled=on end end end
 -- (no camera rumble or slam jolt any more: the gate's own motion is the whole effect, and the
 -- picture stays perfectly steady while it opens and closes)
 fx.jolt=nil
 self._shake=0
end
function Controller:_GateCut(yard,at,closing)
 local key=(closing and 'close' or 'open')..tostring(at)
 if self._cutFor==key then return end
 self._cutFor=key
 local player=game:GetService('Players').LocalPlayer
 local c=player.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local head=c and c:FindFirstChild('Head')
 local shotPart=yard:FindFirstChild(closing and 'GateCameraInside' or 'GateCamera',true);local trigger=yard:FindFirstChild('GateTrigger',true)
 if not root or not head or not shotPart or not trigger then return end
 local gatePos=trigger.CFrame*Vector3.new(0,3,7.3)
 if not closing then
  -- 3D sounds at the gate for everyone, inside or out
  local anchor=Instance.new('Attachment');anchor.WorldPosition=gatePos;anchor.Parent=workspace.Terrain;game:GetService('Debris'):AddItem(anchor,10)
  task.delay(math.max(0,at+.3-workspace:GetServerTimeNow()),function()sound('rbxassetid://9119630180',anchor,.9,1.15)end)
  task.delay(math.max(0,at+GATE_DELAY-workspace:GetServerTimeNow()),function()sound('rbxassetid://9116799448',anchor,.55,1.25)end)
 end
 -- Every crew member is taken into the same shot at the same moment (server timestamp), wherever
 -- they are; a late joiner who arrives after it has started does not get yanked into it.
 -- Closing: the shot holds on the gate and the leaves slam shut exactly as the camera starts
 -- back to your eyes.
 local cut=closing and {inn=.7,hold=CLOSE_DELAY+IMPACT*CLOSE_SECONDS,out=.7} or CUT
 if workspace:GetServerTimeNow()-at>1 then return end
 if player:GetAttribute('EHCinematic') then return end -- (already in a cutscene: waking up)
 local camera=workspace.CurrentCamera;if not camera then return end
 -- (no waiting here: the shot must start on the same frame for everyone; movement, sprint,
 -- crouch, interact and the touch buttons are locked by InputController via EHCinematic)
 local controls
 pcall(function()local pm=player.PlayerScripts:FindFirstChild('PlayerModule');if pm then controls=require(pm):GetControls();controls:Disable() end end)
 local from=camera.CFrame
 local shot=shotPart.CFrame
 -- the shot always hands back to the same fixed facing (up the road, through the gate), never to
 -- wherever you happened to be looking (ControlLock squares the body up to it on the same frame)
 local Lock=require(game.ReplicatedStorage.Game.Shared.Utilities.ControlLock)
 local f=Lock.FacingFor(player,'Cinematic')
 local backRot=f and Lock.LevelRotation(f) or from.Rotation
 -- (EHCinematic tells the first-person camera to stay out of the way for the shot)
 player:SetAttribute('EHCinematic',true)
 camera.CameraType=Enum.CameraType.Scriptable
 local function ease(u)u=math.clamp(u,0,1);return u*u*(3-2*u)end
 -- The shot runs on the local clock (started from the server timestamp once), so server clock
 -- corrections can never make the camera hitch mid-shot.
 local t0=os.clock()-(workspace:GetServerTimeNow()-at)
 local name='BlackwaterGateCut'..key
 local back,bound=false,true
 local function done()
  if not bound then return end
  bound=false
  RunService:UnbindFromRenderStep(name)
  player:SetAttribute('EHCinematic',nil)
  camera.CameraType=Enum.CameraType.Custom
  if controls then pcall(function()controls:Enable()end)end
 end
 -- runs after the first-person camera has updated (Camera+3), so the way back can glide into its
 -- live result instead of jumping to it
 RunService:BindToRenderStep(name,Enum.RenderPriority.Camera.Value+3,function()
  -- a short beat at your own eyes first, while the flashlight is lowered out of view, and only
  -- then does the camera glide away into the shot
  local t=os.clock()-t0-PRE_ROLL
  if t<0 then camera.CFrame=from;return end
  local push=shot*CFrame.new(0,0,-1.4*ease((t-cut.inn)/(cut.hold-cut.inn)))
  if t<cut.inn then camera.CFrame=from:Lerp(shot,ease(t/cut.inn))
  elseif t<cut.hold then camera.CFrame=push
  elseif t<cut.hold+cut.out then
   -- the way back: the first-person camera is switched on again underneath ('Return' keeps the
   -- controls locked) and the view glides from the end of the shot into your own eyes, turning back
   -- to where you were looking. The last frame here is exactly the first-person view.
   if not back then back=true;player:SetAttribute('EHCinematic','Return');camera.CameraType=Enum.CameraType.Custom end
   local u=ease((t-cut.hold)/cut.out)
   local live=camera.CFrame
   local endShot=shot*CFrame.new(0,0,-1.4)
   local rot=endShot.Rotation:Lerp(backRot,u)
   camera.CFrame=CFrame.new(endShot.Position:Lerp(live.Position,u))*rot
   -- (the control lock holds the view at exactly what is drawn here, so when the shot lets go
   -- nothing turns on its own - no little extra swing at the end)
   Lock.heldRot=rot
  else
   -- the last frame is exactly your own eyes along the fixed facing, so handing back is seamless
   if back and camera.CameraType==Enum.CameraType.Custom then
    camera.CFrame=CFrame.new(camera.CFrame.Position)*backRot
    if Lock.active then Lock.heldRot=backRot end
   end
   done()
  end
 end)
 self._scope:Add(done)
end
-- Breaker handles (SwitchLever<id>): a heavy industrial pull. The handle resists for a moment,
-- then swings through, overshoots a touch and settles with a small damped bounce, driven by the
-- floor's Circuit<id>At timestamp so every client (and late joiners) see the same motion.
local LEVER_SECONDS=.8
local function leverCurve(a)
 if a<=0 then return 0 end
 if a>=1 then return 1 end
 if a<.2 then local u=a/.2;return .1*u*u*(3-2*u) end                      -- takes the strain
 if a<.58 then local u=(a-.2)/.38;u=u*u*(3-2*u);return .1+(1.07-.1)*u end -- swings through
 local u=(a-.58)/.42;return 1+.07*math.exp(-4*u)*math.cos(u*math.pi*2.5)*(1-u) -- settles
end
function Controller:_TrackLever(part)
 if self._levers[part] or not part:IsA('BasePart') then return end
 local ref=part:GetAttribute('Ref');local id=type(ref)=='string' and ref:match('^SwitchLever(%w+)$')
 local pivot=part:GetAttribute('PivotFrame')
 -- the shaft-gate release lever: a long, heavy pull from the floor's GateReleaseAt, with the cable
 -- linkage (MechanismOf = GateRelease) drawn down as it goes
 local key=id and ('Circuit'..id..'At')
 local linkage
 if ref=='GateRelease' and pivot then
  id='GateRelease';key='GateReleaseAt';linkage={}
  local floor=part.Parent;while floor and floor~=workspace and not floor:GetAttribute('EncounterId') do floor=floor.Parent end
  if floor==workspace then floor=nil end
  if floor then for _,d in floor:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('MechanismOf')=='GateRelease' and typeof(d:GetAttribute('MoveOffset'))=='Vector3' then linkage[d]={from=d.CFrame,by=d:GetAttribute('MoveOffset')} end end end
 end
 if not id or not pivot then return end
 local attached={}
 for _,d in (part.Parent and (ref=='GateRelease' and part.Parent:GetDescendants() or part.Parent:GetChildren()) or {})do
  if d:IsA('BasePart') and d:GetAttribute('LeverOf')==ref then attached[d]=part.CFrame:ToObjectSpace(d.CFrame)end
 end
 self._levers[part]={id=id,key=key,secs=id=='GateRelease' and 1.25 or LEVER_SECONDS,linkage=linkage,pivot=pivot,offset=pivot:ToObjectSpace(part.CFrame),attached=attached,degrees=part:GetAttribute('SwingDegrees')or -55,floor=nil}
end
function Controller:Init()self._scope=Scope.new()end
local function floorOf(inst)local a=inst.Parent;while a and a~=workspace do if a:GetAttribute('EncounterId')then return a end;a=a.Parent end end
function Controller:_Track(m)
 if self._leaves[m] or not m:IsA('Model') or not m:GetAttribute('OpenOffset') then return end
 local core=m.PrimaryPart;local closed=core and core:GetAttribute('ClosedFrame')
 if not closed then return end
 self._leaves[m]={closed=closed,floor=floorOf(m),key=(m:GetAttribute('MechanismOf') or 'Gate')..'OpenedAt'}
end
function Controller:Start()
 local function scan(root)for _,d in root:GetDescendants()do if d:IsA('Model')and d:GetAttribute('OpenOffset')then self:_Track(d)elseif d:IsA('Model') and d:GetAttribute('YardGate') then self:_TrackSwing(d)elseif d:IsA('BasePart') and d:GetAttribute('SwingDegrees') then self:_TrackLever(d)end end end
 local runtime=workspace:WaitForChild('Runtime',30)
 if runtime then
  scan(runtime)
  self._scope:Add(runtime.DescendantAdded:Connect(function(d)
   if d:IsA('Model')and d:GetAttribute('OpenOffset')then task.defer(function()self:_Track(d)end)
   elseif d:IsA('Model') and d:GetAttribute('YardGate') then task.delay(.2,function()if d.Parent then self:_TrackSwing(d)end end)
   elseif d:IsA('BasePart') and d:GetAttribute('SwingDegrees') then task.delay(.5,function()if d.Parent then self:_TrackLever(d)end end)end
  end))
 end
 -- gate rumble: added on top of whatever the camera did this frame (never accumulates)
 RunService:BindToRenderStep('BlackwaterGateShake',Enum.RenderPriority.Camera.Value+5,function()
  local a=self._shake or 0
  if a>.001 then
   local t=os.clock()
   local cam=workspace.CurrentCamera
   if cam then cam.CFrame=cam.CFrame*CFrame.new(math.noise(t*23,1.3)*a,math.noise(t*29,7.1)*a,0)*CFrame.Angles(math.noise(t*17,3.3)*a*.12,math.noise(t*19,5.9)*a*.12,0) end
  end
 end)
 self._scope:Add(RunService.RenderStepped:Connect(function()
  -- a smoothed copy of the server clock: it follows GetServerTimeNow but never jumps when the
  -- engine corrects the clock, so the gate (and levers) move without a single hitch
  local raw,base=workspace:GetServerTimeNow(),os.clock()
  local off=raw-base
  -- (eased by real time, so it behaves the same at 30 or 240 fps)
  local dt=math.clamp(base-(self._lastClock or base),0,.1);self._lastClock=base
  if not self._clockOff or math.abs(off-self._clockOff)>.5 then self._clockOff=off else self._clockOff+=(off-self._clockOff)*(1-math.exp(-dt*1.2)) end
  local now=base+self._clockOff
  -- the surface yard is cloned in for every run: look for its gate leaves twice a second
  if os.clock()-(self._swingScan or 0)>.5 then
   self._swingScan=os.clock()
   local env=workspace:FindFirstChild('Runtime') and workspace.Runtime:FindFirstChild('DescentEnvironment')
   local yard=env and env:FindFirstChild('SurfaceYard')
   if yard then for _,d in yard:GetDescendants()do if d:IsA('Model') and d:GetAttribute('YardGate') and not self._swings[d] then self:_TrackSwing(d) end end end
  end
  self._shake=0
  for _,s in self._swings do s.fxDone=false end
  for m,s in self._swings do
   if not m.Parent or not m:IsDescendantOf(workspace) or not m.PrimaryPart then self._swings[m]=nil;continue end
   -- (both leaves share one set of effects per frame)
   for _,o in self._swings do if o~=s and o.yard==s.yard and o.fxDone then s.fxDone=true end end
   local at=s.yard:GetAttribute('GateOpenedAt')
   -- (the cutscene plays for each new opening: a reopening for a straggler shows them the gate too)
   if at and s.started~=at then s.started=at;self:_GateCut(s.yard,at,false) end
   local cl=s.yard:GetAttribute('GateClosedAt')
   if cl and at and cl>at and s.closeStarted~=cl then s.closeStarted=cl;self:_GateCut(s.yard,cl,true) end
   local pose,moving,phase,u=self:_GatePose(s.yard,s.secs,now)
   if not s.fxDone then s.fxDone=true;self:_GateFx(s.yard,moving,phase,u,pose,now) end
   if pose~=s.a then
    s.a=pose
    m:PivotTo(s.yard:GetPivot()*s.off*CFrame.Angles(0,math.rad(s.deg*pose),0))
   end
  end
  for part,s in self._levers do
   if not part.Parent or not part:IsDescendantOf(workspace)then self._levers[part]=nil;continue end
   s.floor=s.floor or floorOf(part)
   local at=s.floor and s.floor:GetAttribute(s.key)
   local a=at and math.clamp((now-at)/s.secs,0,1) or 0
   if a~=s.a then
    s.a=a
    local frame=s.pivot*CFrame.Angles(math.rad(s.degrees*leverCurve(a)),0,0)*s.offset
    part.CFrame=frame
    for d,off in s.attached do if d.Parent then d.CFrame=frame*off end end
    if s.linkage then local k=smoother(math.clamp((a-.15)/.6,0,1));for d,l in s.linkage do if d.Parent then d.CFrame=l.from+l.by*k end end end
    if s.id=='GateRelease' then
     -- the station's amber beacon comes on once the gate has been released
     s.beacon=s.beacon or (part:FindFirstAncestorWhichIsA('Model') and part:FindFirstAncestorWhichIsA('Model'):FindFirstChild('BeaconGlow',true))
     if s.beacon then s.beacon.Enabled=a>.3 end
     local dome=s.beacon and s.beacon.Parent
     if dome and dome:IsA('BasePart') then dome.Material=a>.3 and Enum.Material.Neon or Enum.Material.SmoothPlastic end
    end
   end
  end
  for m,s in self._leaves do
   if not m.Parent or not m:IsDescendantOf(workspace)then self._leaves[m]=nil;continue end
   s.floor=s.floor or floorOf(m)
   local at=s.floor and s.floor:GetAttribute(s.key)
   local secs=m:GetAttribute('OpenSeconds')or 2.4
   local a=at and math.clamp((now-at)/secs,0,1)or 0
   if a~=s.a then
    s.a=a
    -- (one even, eased lift - gentle start, steady middle, soft stop - instead of the old snap)
    local eased=smoother(a)
    m:PivotTo(s.closed+(m:GetAttribute('OpenOffset')*eased))
    for _,l in m.Parent:GetDescendants()do if l:IsA('Light')and l.Name=='GateBeaconLight'then l.Enabled=a>0 and a<1 end end
   end
  end
 end))
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end;pcall(function()RunService:UnbindFromRenderStep('BlackwaterGateShake')end)end
return table.freeze(Controller)
