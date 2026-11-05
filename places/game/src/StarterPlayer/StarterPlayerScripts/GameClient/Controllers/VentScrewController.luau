--!nonstrict
-- Vent cover screws (client side, cosmetic only).
--   * While you hold UNSCREW on a corner screw a gloved hand with a screwdriver appears on it and
--     twists it out in quick wrist turns; the screw itself starts backing out of its hole at once.
--   * When the server says a screw is out (CornerScrew.UnscrewedAt) every client spins its own
--     copy the rest of the way out, lets it drop to the floor and tink - no waiting, no physics.
-- The real screw parts are only ever hidden locally; the server removes them a moment later.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local SoundFade=require(game.ReplicatedStorage.Game.Shared.Utilities.SoundFade)
local Controller={};Controller.__index=Controller
local TURN_SFX='rbxassetid://9118855986'
local TINK_SFX='rbxassetid://9116672975'
local CYCLE=.16          -- one wrist turn + regrip (seconds)
local TURN_SHARE=.62     -- part of the cycle spent turning (the rest is the hand rolling back)
local BACKOUT=.36        -- how far a screw travels out of its hole before it is free
local SCREW_PARTS={Head=true,Washer=true,Shank=true,Slot=true}
local function smooth(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
function Controller.new(player)return setmetatable({Name='VentScrewController',Dependencies={'InputController'},_player=player,_spins={}},Controller)end
function Controller:Init(deps)self._input=deps.InputController;self._scope=Scope.new()end
-- outward (into the room) axis of a screw: from its head toward its grab box
local function frameOf(model)
 local head=model:FindFirstChild('Head');local hit=model:FindFirstChild('ScrewHit')
 if not head or not hit then return nil end
 local n=hit.Position-head.Position;if n.Magnitude<1e-3 then n=-head.CFrame.RightVector else n=n.Unit end
 local tip=head.Position+n*(head.Size.X/2)
 return CFrame.lookAt(tip,tip+n),n -- -Z = out into the room
end
local function part(parent,size,color,material,shape)
 local p=Instance.new('Part');p.Size=size;p.Color=color;p.Material=material or Enum.Material.SmoothPlastic;p.Anchored=true
 p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 if shape then p.Shape=shape end;p.Parent=parent;return p
end
-- A local copy of the screw's visible parts, posed relative to its axis frame.
function Controller:_Copy(model)
 local base=frameOf(model);if not base then return nil end
 local copy={parts={},base=base}
 local folder=Instance.new('Model');folder.Name='ScrewSpin';copy.model=folder
 for _,p in model:GetChildren()do
  if p:IsA('BasePart') and SCREW_PARTS[p.Name]then
   local c=part(folder,p.Size,p.Color,p.Material,p.Shape);c.Reflectance=p.Reflectance
   table.insert(copy.parts,{part=c,offset=base:ToObjectSpace(p.CFrame)})
   p.LocalTransparencyModifier=1
  end
 end
 folder.Parent=workspace.CurrentCamera or workspace
 return copy
end
local function poseCopy(copy,angle,out)
 -- positive angle = counter-clockwise as seen from the room (unscrewing)
 local f=copy.base*CFrame.new(0,0,-out)*CFrame.Angles(0,0,-angle)
 for _,e in copy.parts do e.part.CFrame=f*e.offset end
 return f
end
local function restoreReal(model)
 if not model then return end
 for _,p in model:GetChildren()do if p:IsA('BasePart') and SCREW_PARTS[p.Name]then p.LocalTransparencyModifier=0 end end
end
local function sound(id,at,volume,speed)
 local holder=Instance.new('Attachment');holder.WorldPosition=at;holder.Parent=workspace.Terrain
 local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume;s.PlaybackSpeed=speed;s.RollOffMinDistance=4;s.RollOffMaxDistance=40;s.Parent=holder
 s:Play();game:GetService('Debris'):AddItem(holder,3)
 return s
end
------------------------------------------------------------------ hand + screwdriver
function Controller:_Hand()
 if self._handModel then return self._handModel end
 local m=Instance.new('Model');m.Name='ScrewdriverHand'
 local DARK=Color3.fromRGB(32,33,32);local GLOVE=Color3.fromRGB(58,52,44);local SLEEVE=Color3.fromRGB(46,58,64)
 local h={}
 h.bit=part(m,Vector3.new(.06,.028,.028),Color3.fromRGB(120,122,120),Enum.Material.Metal,Enum.PartType.Cylinder)
 h.shaft=part(m,Vector3.new(.5,.045,.045),Color3.fromRGB(168,170,166),Enum.Material.Metal,Enum.PartType.Cylinder)
 h.ferrule=part(m,Vector3.new(.07,.09,.09),Color3.fromRGB(150,152,148),Enum.Material.Metal,Enum.PartType.Cylinder)
 h.handle=part(m,Vector3.new(.42,.15,.15),Color3.fromRGB(196,150,36),Enum.Material.Plastic,Enum.PartType.Cylinder)
 h.grip=part(m,Vector3.new(.24,.158,.158),DARK,Enum.Material.Rubber,Enum.PartType.Cylinder)
 h.palm=part(m,Vector3.new(.2,.3,.34),GLOVE,Enum.Material.Fabric)
 h.fingers=part(m,Vector3.new(.13,.22,.3),GLOVE,Enum.Material.Fabric)
 h.thumb=part(m,Vector3.new(.09,.09,.22),GLOVE,Enum.Material.Fabric)
 h.cuff=part(m,Vector3.new(.3,.28,.12),DARK,Enum.Material.Fabric)
 h.forearm=part(m,Vector3.new(1,.26,.26),SLEEVE,Enum.Material.Fabric,Enum.PartType.Cylinder)
 self._hand=h;self._handModel=m;self._scope:Add(m)
 return m
end
-- tool: CFrame looking out along the screw axis from the screw head (-Z = out), already rolled
function Controller:_PoseHand(tool,handRoll,camera)
 local h=self._hand
 local alongX=CFrame.Angles(0,math.rad(90),0) -- cylinder length (X) along the axis
 h.bit.CFrame=tool*CFrame.new(0,0,-.03)*alongX
 h.shaft.CFrame=tool*CFrame.new(0,0,-.31)*alongX
 h.ferrule.CFrame=tool*CFrame.new(0,0,-.59)*alongX
 h.handle.CFrame=tool*CFrame.new(0,0,-.83)*alongX
 h.grip.CFrame=tool*CFrame.new(0,0,-.86)*alongX
 -- the hand wraps the grip; it rolls with the turn and rolls back on the regrip
 local hand=tool*CFrame.Angles(0,0,-handRoll)
 h.palm.CFrame=hand*CFrame.new(.15,0,-.86)
 h.fingers.CFrame=hand*CFrame.new(-.13,-.01,-.86)
 h.thumb.CFrame=hand*CFrame.new(.02,.13,-.74)*CFrame.Angles(0,0,math.rad(20))
 h.cuff.CFrame=hand*CFrame.new(.05,0,-1.08)
 -- the forearm runs from the wrist back toward your shoulder (below and right of the view)
 local wrist=(hand*CFrame.new(.05,0,-1.12)).Position
 local shoulder=camera.CFrame*Vector3.new(.55,-.85,.1)
 local dir=shoulder-wrist;local len=math.min(dir.Magnitude,1.6)
 if dir.Magnitude>1e-3 then
  h.forearm.Size=Vector3.new(len,.26,.26)
  h.forearm.CFrame=CFrame.lookAt(wrist+dir.Unit*len/2,shoulder)*alongX
 end
end
------------------------------------------------------------------ hold + spin-out
function Controller:_Holding()
 local p=self._player
 local id=p:GetAttribute('EHActiveInteraction')
 if type(id)~='string' or id:sub(1,8)~='BW5Screw' or p:GetAttribute('EHInteractionState')~='Holding' then return nil end
 local runtime=workspace:FindFirstChild('Runtime')
 if self._holdTarget and self._holdTarget.Parent and self._holdTarget:GetAttribute('EHInteractionId')==id then return self._holdTarget,id end
 self._holdTarget=nil
 if runtime then for _,d in runtime:GetDescendants()do if d.Name=='ScrewHit' and d:GetAttribute('EHInteractionId')==id then self._holdTarget=d;break end end end
 return self._holdTarget,id
end
function Controller:_EndHold(keepCopy)
 local hold=self._hold;self._hold=nil
 if self._handModel then self._handModel.Parent=nil end
 if hold then
  if hold.sound then SoundFade.Out(hold.sound,.12) end
  if not keepCopy then if hold.copy then hold.copy.model:Destroy() end;restoreReal(hold.model) end
 end
end
function Controller:_SpinOut(model,copy,angle,out)
 if self._spins[model] then return end
 copy=copy or self:_Copy(model);if not copy then return end
 local spin={copy=copy,angle=angle or 0,out=out or 0,t=0,model=model}
 self._spins[model]=spin
 -- where it lands: straight down from the hole
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances={copy.model,model.Parent or model};params.RespectCanCollide=true
 local start=copy.base.Position
 local r=workspace:Raycast(start+copy.base.LookVector*.45,Vector3.new(0,-30,0),params)
 spin.floor=r and r.Position.Y+.04 or start.Y-7
end
function Controller:_StepSpins(dt)
 for model,s in self._spins do
  s.t+=dt
  if not s.dropAt then
   -- spin the rest of the way out: fast, about two and a half turns
   s.angle+=dt*math.pi*2*9;s.out=math.min(BACKOUT,s.out+dt*BACKOUT/.24)
   local f=poseCopy(s.copy,s.angle,s.out)
   if s.out>=BACKOUT then
    s.dropAt=s.t;s.from=f;s.tumble=Vector3.new(math.random()-.5,math.random()-.5,math.random()-.5)*14
    s.fallTime=math.clamp(math.sqrt(2*math.max(.2,s.from.Position.Y-s.floor)/(workspace.Gravity*.55)),.25,.9)
   end
  else
   local u=(s.t-s.dropAt)/s.fallTime
   local k=math.min(u,1)
   local pos=s.from.Position+s.from.LookVector*.5*k+Vector3.new(0,-(s.from.Position.Y-s.floor)*k*k,0)
   local rot=(s.from-s.from.Position)*CFrame.fromEulerAnglesXYZ(s.tumble.X*k,s.tumble.Y*k,s.tumble.Z*k)
   local f=CFrame.new(pos)*rot
   for _,e in s.copy.parts do e.part.CFrame=f*e.offset end
   if u>=1 and not s.landed then s.landed=true;sound(TINK_SFX,pos,.35,1.7+math.random()*.3) end
   if u>=1 then
    local fade=math.clamp((u-1)*s.fallTime/.6,0,1)
    for _,e in s.copy.parts do e.part.Transparency=fade end
    if fade>=1 then s.copy.model:Destroy();self._spins[model]=nil end
   end
  end
 end
end
function Controller:_Watch(model)
 if self._watched[model] then return end
 self._watched[model]=true
 local function check()
  if model:GetAttribute('UnscrewedAt')==nil then return end
  -- our own hold already has the screw half out: carry on from exactly there
  local hold=self._hold
  if hold and hold.model==model then
   local copy,angle,out=hold.copy,hold.angle,hold.out
   self:_EndHold(true)
   self:_SpinOut(model,copy,angle,out)
  else
   self:_SpinOut(model)
  end
 end
 self._scope:Add(model:GetAttributeChangedSignal('UnscrewedAt'):Connect(check))
 check()
end
function Controller:_Render(dt)
 local camera=workspace.CurrentCamera;if not camera then return end
 local target,id=self:_Holding()
 local model=target and target.Parent
 if model and model:GetAttribute('UnscrewedAt')==nil and not self._spins[model] then
  local hold=self._hold
  if not hold or hold.model~=model then
   self:_EndHold(false)
   hold={model=model,copy=self:_Copy(model),angle=0,out=0,cycle=0}
   self._hold=hold
   if hold.copy then hold.sound=sound(TURN_SFX,hold.copy.base.Position,.55,1.35) end
  end
  if hold.copy then
   -- quick ratcheting wrist turns: turn, regrip, turn...
   local before=hold.cycle%1
   hold.cycle+=dt/CYCLE
   local u=hold.cycle%1
   local turn=smooth(u/TURN_SHARE)
   local prev=smooth(before/TURN_SHARE)
   if u<before then prev=0 end -- wrapped into a new cycle
   local delta=(u<=TURN_SHARE and (turn-prev) or (before<TURN_SHARE and 1-prev or 0))*math.rad(95)
   hold.angle+=delta
   hold.out=math.min(BACKOUT*.45,hold.out+delta/(math.pi*2)*.05)
   poseCopy(hold.copy,hold.angle,hold.out)
   -- hand roll: sweeps through the turn, then rolls back while the driver stays put
   local roll=u<=TURN_SHARE and (turn-.5)*math.rad(95) or (.5-smooth((u-TURN_SHARE)/(1-TURN_SHARE)))*math.rad(95)
   self:_Hand().Parent=camera
   local tool=hold.copy.base*CFrame.new(0,0,-(hold.out+.06))*CFrame.Angles(0,0,-hold.angle)
   self:_PoseHand(tool,roll-hold.angle,camera)
  end
 elseif self._hold then
  local hold=self._hold
  if self._player:GetAttribute('EHInteractionState')=='Completed' and (hold.pending==nil or os.clock()-hold.pending<.8) then
   -- finished: the hand is gone at once and the half-out screw waits for the server's word
   -- (usually the same frame) so it never pops back into its hole first
   hold.pending=hold.pending or os.clock()
   if self._handModel then self._handModel.Parent=nil end
   if hold.sound then SoundFade.Out(hold.sound,.12);hold.sound=nil end
  else
   -- let go early (or refused): the screw goes back into place
   self:_EndHold(false)
  end
 end
 self:_StepSpins(dt)
end
function Controller:Start()
 self._watched=setmetatable({},{__mode='k'})
 local function consider(d)if d:IsA('Model') and d.Name=='CornerScrew' then self:_Watch(d)end end
 local function hookRuntime(r)
  for _,d in r:GetDescendants()do consider(d)end
  self._scope:Add(r.DescendantAdded:Connect(consider))
 end
 local runtime=workspace:FindFirstChild('Runtime');if runtime then hookRuntime(runtime)end
 self._scope:Add(workspace.ChildAdded:Connect(function(c)if c.Name=='Runtime' then hookRuntime(c)end end))
 RunService:BindToRenderStep('BlackwaterVentScrews',Enum.RenderPriority.Camera.Value+7,function(dt)
  local ok,err=pcall(self._Render,self,math.min(dt,.1))
  if not ok and not self._warned then self._warned=true;warn('[ElevatorHorror] vent screws: '..tostring(err))end
 end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('BlackwaterVentScrews')end)
end
function Controller:Destroy()
 self:_EndHold(false)
 for _,s in self._spins do s.copy.model:Destroy() end;table.clear(self._spins)
 if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
