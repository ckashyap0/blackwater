--!nonstrict
local Crawl=require(game.ReplicatedStorage.Game.Shared.Utilities.CrawlState)
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local HeldMotion=require(Shared.Utilities.HeldItemMotion)
local Stride=require(Shared.Utilities.StrideState)
local HeldView=require(Shared.Utilities.HeldView)
local ScreenFade=require(Shared.Utilities.ScreenFade)
local Lock=require(Shared.Utilities.ControlLock)
-- Cutscenes (the gate shot, waking up, the lift ride - anything that takes the controls): the light
-- in your hand is LOWERED out of view as the cutscene starts and RAISED back up once you have control
-- again, with the same motion as putting it away at a wall. It is never faded in or out (a see-through
-- flashlight looked wrong).
local CUT_DOWN,CUT_UP=14,6 -- how fast it goes down / comes back up (per second)
local DROP_SPIN=.8 -- rad/s of gentle tumble when an item leaves the hand
local V=Vector3.new
-- Flashlight cosmetics (Config.CosmeticsConfig, found in the lobby's secret room), seen by everyone:
--   EHFlashlightSkin  -> which held model (Assets.<Model>, e.g. PhantomFlashlight)
--   EHFlashlightColor -> beam / hand-bounce colour
-- Nothing equipped = the standard maintenance light with the warm white beam.
local Cosmetics=require(Shared.Config.CosmeticsConfig)
local SKINS,BEAM,BOUNCE,RAINBOW,PULSE={},{},{},{},{}
for _,e in Cosmetics.Flashlight do SKINS[e.Id]=e.Model end
for _,e in Cosmetics.Beam do
 BEAM[e.Id]=Color3.fromRGB(e.Beam[1],e.Beam[2],e.Beam[3])
 BOUNCE[e.Id]=Color3.fromRGB(e.Bounce[1],e.Bounce[2],e.Bounce[3])
 if e.Rainbow then RAINBOW[e.Id]=true end
 if e.Pulse then PULSE[e.Id]=Color3.fromRGB(e.Pulse[1],e.Pulse[2],e.Pulse[3]) end
end
-- beam + hand-bounce colour; a Rainbow beam slowly cycles through every hue, a Pulse beam drifts to its
-- second colour and back
local function beamColors(id)
 if RAINBOW[id] then local c=Color3.fromHSV((os.clock()*.12)%1,.72,1);return c,c:Lerp(Color3.new(),.3) end
 if PULSE[id] then local k=.5-.5*math.cos(os.clock()*.9);local c=BEAM[id]:Lerp(PULSE[id],k);return c,c:Lerp(Color3.new(),.3) end
 return BEAM[id],BOUNCE[id]
end
local function skinOf(player)
 local s=player:GetAttribute('EHFlashlightSkin')
 return (type(s)=='string' and SKINS[s]) and s or 'Default'
end
local function colorOf(player)
 local s=player:GetAttribute('EHFlashlightColor')
 return (type(s)=='string' and BEAM[s]) and s or 'Default'
end
local function prepareDisplay(model)
 for _,node in model:GetDescendants()do
  if node:IsA('BasePart')then
   node.Anchored=true;node.CanCollide=false;node.CanTouch=false;node.CanQuery=false;node.Massless=true;node.CastShadow=false
  elseif node:IsA('LuaSourceContainer')or node:IsA('JointInstance')or node:IsA('Constraint')
   or node:IsA('ProximityPrompt')or node:IsA('ClickDetector')or node:IsA('BodyMover')then
   node:Destroy()
  end
 end
end
-- Top-tier skins have moving pieces (gears, halos, orbiting shards: Shared.Utilities.OrbitParts); they
-- turn every frame, in your hand and in other players' hands.
local OrbitParts=require(Shared.Utilities.OrbitParts)
local function orbiters(model)local list=OrbitParts.Collect(model);return #list>0 and list or nil end
local function spinOrbiters(model,list)if list then OrbitParts.Step(list,os.clock()) end end
-- held lights are drawn a little smaller than the art, in your view and in other players' hands
local HOLD_SCALE=.85
-- a few skins are built shorter than the rest; held a bit bigger so they read the same size in hand
local SKIN_SCALE={UFO=1.3}
-- Beam direction inside a duct: the view's look, held to the crawl direction (fwd) - at most 65
-- degrees either side and 25 down / 22 up - so it always points up the duct, never back into you.
local VENT_YAW,VENT_DOWN,VENT_UP=math.rad(65),math.rad(-25),math.rad(22)
local function ventBeam(look,fwd)
 local flat=V(look.X,0,look.Z);flat=flat.Magnitude>.05 and flat.Unit or fwd
 local yaw=math.clamp(math.atan2(fwd:Cross(flat).Y,fwd:Dot(flat)),-VENT_YAW,VENT_YAW)
 local h=CFrame.fromAxisAngle(Vector3.yAxis,yaw)*fwd
 local pitch=math.clamp(math.asin(math.clamp(look.Y,-1,1)),VENT_DOWN,VENT_UP)
 return h*math.cos(pitch)+V(0,math.sin(pitch),0)
end
-- Third person (what everyone else sees): the light is locked to a neutral hold - straight out
-- along the body, a touch below level. It never pitches with that player's camera.
local NEUTRAL_PITCH=math.rad(-8)
-- how far the tail end sits behind the model's origin (so a hand can hold it by the tail)
local function tailOf(model)
 local cf,size=model:GetBoundingBox()
 return model:GetPivot():PointToObjectSpace(cf.Position).Z+size.Z/2
end
-- the light in a hand: tail end just behind the fist, pointing down the arm, top kept up. Same shape for
-- slim R15 hands, block hands and R6 arms (the locker preview uses the same rule).
local function holdFrame(hand,r15,tailZ)
 local fwd=-hand.CFrame.UpVector
 local fist=hand.Position+fwd*hand.Size.Y*(r15 and .15 or .4)
 local origin=fist+fwd*(tailZ-.12)
 return CFrame.lookAt(origin,origin+fwd,Vector3.yAxis)
end
function Controller.new(player)return setmetatable({Name='EquipmentController',Dependencies={'StateController','InputController','CameraController'},_player=player,_beams={},_phase=0,_sprint=0,_draw=0,_aimElapsed=0},Controller)end
function Controller:Init(deps)self._state=deps.StateController;self._input=deps.InputController;self._cameraController=deps.CameraController;self._scope=Scope.new();self._lightMotion=HeldMotion.New();self._carryMotion=HeldMotion.New()end
function Controller:_Add(player)
 if self._beams[player]then return end
 local part=Instance.new('Part');part.Name='LocalFlashlightBeam';part.Size=V(.1,.1,.1);part.Transparency=1;part.Anchored=true;part.CanQuery=false;part.CanTouch=false;part.CanCollide=false;part.Parent=workspace
 local light=Instance.new('SpotLight',part);light.Name='Flashlight';light.Angle=30;light.Range=64;light.Brightness=2.6;light.Face=Enum.NormalId.Front;light.Color=Color3.fromRGB(237,231,196);light.Shadows=true;light.Enabled=false
 -- a soft, wide spill around the hot spot, like a real reflector throws (no shadows, cheap)
 local spill=Instance.new('SpotLight',part);spill.Name='Spill';spill.Angle=48;spill.Range=16;spill.Brightness=.12;spill.Face=Enum.NormalId.Front;spill.Shadows=false;spill.Enabled=false
 -- a tight, paler hot spot in the middle of the beam, so the centre of the light always reads clearly
 -- (and dead centre) whatever colour the beam is - deep colours used to smear into one flat blob
 local core=Instance.new('SpotLight',part);core.Name='Core';core.Angle=9;core.Range=56;core.Brightness=.8;core.Face=Enum.NormalId.Front;core.Shadows=false;core.Enabled=false
 local bounce=Instance.new('PointLight',part);bounce.Name='HandBounce';bounce.Range=3.5;bounce.Brightness=.45;bounce.Shadows=false;bounce.Color=Color3.fromRGB(169,177,145);bounce.Enabled=false
 self._beams[player]={part=part,light=light,bounce=bounce}
end
function Controller:_Assets()
 local assets=Shared.Parent:FindFirstChild('Assets')
 if not assets then return end
 self._toolTemplate=assets:FindFirstChild('SkinRustbelt') or assets:FindFirstChild('MaintenanceFlashlight') -- (the default flashlight is the rusty one)
 self._skinTemplates={}
 for id,model in SKINS do self._skinTemplates[id]=assets:FindFirstChild(model) end
 self._skinTemplates.Default=self._toolTemplate
end
function Controller:_Skin(player)
 local skin=skinOf(player)
 local t=self._skinTemplates and self._skinTemplates[skin]
 if not t then skin='Default';t=self._toolTemplate end
 return skin,t
end
-- Right-hand (flashlight) motion, layered on top of the camera (which already carries the head bob).
-- The left-hand carried item deliberately does NOT use this; see _View.
--
--  * Stride-locked: reads the same footfall clock as the camera bob (StrideState), so hands and
--    head land on the same steps. The hands trail the head slightly (phase lag) and swing wider,
--    which reads as arms carrying the item rather than an object glued to the screen.
--  * Sprint: much bigger, faster swing plus a forward pump and a tucked-in, tilted carry pose.
--  * Look inertia: turning the camera makes the item lag behind and spring back.
--  * Everything is spring-smoothed and clamped; reduced-motion players get a still hold.
-- `weight` scales it per item (heavier things lag and swing more).
local function spring(state,key,target,dt,freq)
 local x,v=state[key] or 0,state[key..'v'] or 0
 local steps=math.max(1,math.ceil(dt*120));local s=dt/steps
 for _=1,steps do v+=(freq*freq*(target-x)-2*freq*v)*s;x+=v*s end
 state[key],state[key..'v']=x,v;return x
end
function Controller:_Sway(dt,camera,weight)
 local st=self._swayState;if not st then st={};self._swayState=st end
 dt=math.clamp(dt,1/240,.1)
 local reduced=self._player:GetAttribute('EHReduceMotion')==true
 if not reduced then local ok,pref=pcall(function()return game:GetService('GuiService').ReducedMotionEnabled end);reduced=ok and pref==true end
 -- Camera turn rate (rad/s) in camera space, measured once per frame and shared by all items.
 if st.frame~=self._viewFrame then
  st.frame=self._viewFrame
  local look=camera.CFrame;local yawRate,pitchRate=0,0
  if st.look then
   local rel=st.look:ToObjectSpace(look);local rx,ry=rel:ToEulerAnglesYXZ()
   yawRate,pitchRate=math.clamp(ry/dt,-12,12),math.clamp(rx/dt,-12,12)
  end
  st.look=look
  local fresh=os.clock()-(Stride.updated or 0)<.25
  st.phase=fresh and Stride.phase or (st.phase or 0)
  st.moving=spring(st,'mv',fresh and Stride.moving or 0,dt,10)
  st.sprint=spring(st,'sp',fresh and Stride.sprint or 0,dt,7)
  st.impact=fresh and Stride.impact or 0
  st.yaw=spring(st,'yaw',reduced and 0 or math.clamp(-yawRate*.022,-.14,.14),dt,9)
  -- no lag when looking up or down: the light stays put in the hand instead of dipping and tilting
  st.pitch=0
 end
 if reduced then return CFrame.identity end
 local m,sp=st.moving,st.sprint
 local p=st.phase-.45 -- hands trail the head a little
 local sway=math.cos(p)                         -- side to side, one cycle per stride
 local lift=math.abs(math.sin(p))               -- up on each step
 local ampX=(.028+.075*sp)*m*weight
 local ampY=(.02+.06*sp)*m*weight
 local x=sway*ampX
 local y=(lift-.5)*ampY-st.impact*(.012+.035*sp)*weight
 local z=math.sin(p*2)*.03*sp*m*weight            -- forward/back pump when running
 local roll=sway*math.rad(1.6+4.5*sp)*m*weight
 local pitch=-st.impact*math.rad(1.2+3*sp)*weight+math.sin(p*2)*math.rad(1.5)*sp*m
 -- Running pose: pull the item in and down, tipped toward the body.
 local pose=CFrame.new(.06*sp,-.1*sp,.12*sp)*CFrame.Angles(math.rad(-7)*sp,math.rad(6)*sp,math.rad(8)*sp)
 return CFrame.Angles(st.pitch*weight,st.yaw*weight,0)*CFrame.new(x+st.yaw*.35*weight,y+st.pitch*.3*weight,z)*CFrame.Angles(pitch,0,roll)*pose
end
function Controller:_View(dt,camera,b)
 self._viewFrame=(self._viewFrame or 0)+1
 local character=self._player.Character
 if character~=self._viewCharacter then
  self._viewCharacter=character;self._lightMotion=HeldMotion.New();self._carryMotion=HeldMotion.New()
 end
 local skin,template=self:_Skin(self._player)
 if self._tool and self._toolSkin~=skin then self._tool:Destroy();self._tool=nil end
 if not self._tool and template then
  self._tool=template:Clone();self._tool.Name='BlackwaterViewLight';prepareDisplay(self._tool);self._toolSkin=skin
  self._tool:ScaleTo(self._tool:GetScale()*HeldMotion.Near*HOLD_SCALE*(SKIN_SCALE[skin] or 1)) -- drawn compressed toward the eye
  self._toolOrbit=orbiters(self._tool)
 end
 b.light.Color,b.bounce.Color=beamColors(colorOf(self._player))
 local context=self._input:GetContext()
 -- lowered for a cutscene: wanted down while the controls are taken, eased down quickly and back up
 -- gently (frame-rate independent)
 -- (down for the shot itself; it starts coming back up the moment the shot hands back - while
 -- the view glides home - instead of waiting for the controls to unlock afterwards)
 local p=self._player
 local away=p:GetAttribute('EHCinematic')==true or (Lock.active==true and (p:GetAttribute('EHElevatorLock')==true or p:GetAttribute('EHSpawnHold')==true))
 local cut=self._cut or 1
 cut+=((away and 1 or 0)-cut)*(1-math.exp(-math.min(dt,.1)*(away and CUT_DOWN or CUT_UP)))
 if math.abs(cut-(away and 1 or 0))<.002 then cut=away and 1 or 0 end
 self._cut=cut
 -- (as a shot starts the camera has already left your eyes: the light still goes down in front of
 -- it for that first moment, then is put away until control comes back)
 local onFloor=character and (context=='ActiveFloor'or context=='Transit')
 local active=onFloor and (camera.CameraType==Enum.CameraType.Custom or cut<.98)
 if not onFloor then self._cut=1 end
 if not active or not self._tool then
  if self._tool then self._tool.Parent=nil end
  if self._carryView then self._carryView.Parent=nil end
  self._swayState=nil -- no stale look-lag spike when the view comes back
  b.light.Enabled=false;b.bounce.Enabled=false;if self._viewFill then self._viewFill.Fill.Enabled=false end;return
 end
 -- Read one stable server result, not several independently replicated sprint/equip flags.
 local on=self._player:GetAttribute('EHFlashlightOn')==true
 self._draw=HeldMotion.StepSimple(self._lightMotion,on,dt)
 local aspect=camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y)
 local width=math.clamp(aspect/1.6,.58,1)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 params.FilterDescendantsInstances={character,camera};params.RespectCanCollide=true
 local hit=workspace:Raycast(camera.CFrame.Position,camera.CFrame.LookVector*3,params)
 -- Wall stow: walking up flush to a wall (straight ahead, or where either hand would be) lowers
 -- both held items out of view with the same draw/stow motion as the flashlight, and raises them
 -- again on stepping back. Shared with the mop view model through EHWallStow (local only).
 local nearest=99
 local look=camera.CFrame.LookVector;local flat=V(look.X,0,look.Z)
 local level=flat.Magnitude>.05 and CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+flat) or camera.CFrame
 -- (in a duct the walls are always close beside you: only something right in front of your face -
 -- a closed cover, the duct's end - puts the flashlight away there)
 local inVent=self._player:GetAttribute('EHInVent')~=nil
 for _,ray in (inVent and {V(0,0,-1)} or {V(0,0,-1),V(-.45,-.06,-1),V(.45,-.06,-1)})do -- level rays: a desk or floor you look down at does not count
  local r=workspace:Raycast(camera.CFrame.Position,level:VectorToWorldSpace(ray.Unit)*2.6,params)
  if r then nearest=math.min(nearest,r.Distance)end
 end
 -- (Oct 23 c) no wall stow: held items stay in your hands next to walls (only the duct exit below tucks them)
 local stowTarget=0
 -- (Oct 23) climbing out of a duct: the light is tucked away until you are standing outside again
 if Crawl.exiting then stowTarget=1;self._ventExitT=os.clock() end
 if os.clock()-(self._ventExitT or -9)<.45 then stowTarget=1 end -- (stays tucked a beat after you are out, then comes up)
 do local va=self._player:GetAttribute('EHVentAt') -- climbing in: tucked during the climb, free to bring out once you are lying in the duct
  if self._player:GetAttribute('EHInVent') and type(va)=='number' and workspace:GetServerTimeNow()-va<1.15 then stowTarget=1 end end
 if self._player:GetAttribute('EHCinematic') then stowTarget=1 end -- (Oct 25) cutscenes (e.g. the gate opening): the torch tucks down
 self._stow=(self._stow or 0)+(stowTarget-(self._stow or 0))*(1-math.exp(-math.min(dt,.1)*(stowTarget>(self._stow or 0) and 12 or 7)))
 if math.abs((self._player:GetAttribute('EHWallStow')or 0)-self._stow)>.004 then self._player:SetAttribute('EHWallStow',self._stow)end
 local stow=self._stow*self._stow*(3-2*self._stow)
 -- Lower-right hold, recessed toward the body so the grip sits where an (unseen) hand would be,
 -- pushed right to line up with the touch controls. A very small, critically damped motion layer
 -- (stride sine + look inertia from _Sway at 14% weight) trails the camera slightly instead of
 -- being locked 1:1, then a second low-pass smooths it so it never jitters or snaps.
 -- One spring layer only (inside _Sway). The old second low-pass trailed sudden camera turns and
 -- sprint stops and then caught up a few frames later, which read as a hitch.
 local lag=self:_Sway(dt,camera,.1)
 -- mirrored with the left-hand item: same fraction of the half-width, measured at the tool depth
 local tangent=math.tan(math.rad(camera.FieldOfView)/2)
 local spread=1.8*tangent*math.clamp(aspect,.45,2.5)*HeldMotion.HandSpread
 local cutK=self._cut*self._cut*(3-2*self._cut)
 local draw=self._draw*(1-stow)*(1-cutK)
 local toolFrame=camera.CFrame*lag*CFrame.new(spread,-1.14-(1-draw)*1.5,-1.8)
  *CFrame.Angles(math.rad(-4-(1-draw)*12),math.rad(7),math.rad(-3))
 self._tool:PivotTo(HeldMotion.Compress(camera.CFrame.Position,toolFrame))
 spinOrbiters(self._tool,self._toolOrbit)
 self._tool.Parent=draw>.001 and camera or nil
 self._tool:SetAttribute('DrawAmount',draw)
 local carried=self._player:GetAttribute('EHCarriedItem')
 -- a pick-up predicted on this screen (InteractionController) is shown straight away; the server's
 -- own answer takes over the moment it lands (or the guess is dropped if it never does)
 local predicted=self._player:GetAttribute('EHPredictCarry')
 if predicted~=nil then
  local at=self._player:GetAttribute('EHPredictCarryAt') or 0
  if carried~=nil or os.clock()-at>1.5 then
   self._player:SetAttribute('EHPredictCarry',nil);predicted=nil
  elseif carried==nil then carried=predicted end
 end
 -- the world copy of a predicted item is hidden here at once, so it is never in two places
 if self._predictHidden and self._predictHidden.id~=predicted then
  for _,d in self._predictHidden.parts do if d.Parent then d.LocalTransparencyModifier=0 end end
  -- (the printing comes back only if the card really is lying in the world again - after a confirmed pick-up
  -- it stays off; switching it on here left the ACCESS label floating where the card had been)
  for _,g in self._predictHidden.guis or {} do
   local part=g.Parent;local st=part and part:GetAttribute('EHItemState')
   if part then g.Enabled=part.Transparency<.99 and (st=='Dropped' or st=='AtSpawn') end
  end
  self._predictHidden=nil
 end
 if predicted and not self._predictHidden then
  for _,part in game:GetService('CollectionService'):GetTagged('EHInteractable')do
   if part:IsA('BasePart') and part:GetAttribute('EHInteractionId')==predicted then
    local parts,guis={part},{};for _,d in part:GetDescendants()do if d:IsA('BasePart') or d:IsA('Decal') then table.insert(parts,d) elseif d:IsA('SurfaceGui') and d.Enabled then table.insert(guis,d) end end
    for _,d in parts do d.LocalTransparencyModifier=1 end
    for _,g in guis do g.Enabled=false end -- (Nov 3: the card's printing goes with it)
    self._predictHidden={id=predicted,parts=parts,guis=guis}
    break
   end
  end
 end
 -- A drop/fit is instant: the item leaves the hand this frame (no lowering animation that
 -- would leave it hanging in front of the camera). While a local drop is in flight the view
 -- stays empty even before the server confirms.
 if self._dropPredict and (carried==nil or os.clock()-self._dropPredict>1.2) then self._dropPredict=nil end
 if self._dropPredict then carried=nil end
 if carried==nil and self._carryMotion.item~=nil then
  self._carryMotion=HeldMotion.New()
   self:_ClearCarryTool()
 end
 local carryDraw=HeldMotion.Step(self._carryMotion,carried,dt)
 if self._carryId~=self._carryMotion.item then
   self:_ClearCarryTool()
  self._carryId=self._carryMotion.item;self._nextCarryResolve=0
 end
 if self._carryId and not self._carryTool and os.clock()>=(self._nextCarryResolve or 0)then
  self._nextCarryResolve=os.clock()+.05
  -- (only the tagged interactables are searched - walking every part of the level here made the
  -- pick-up hitch and show up late)
  local runtime=workspace:FindFirstChild('Runtime')
  if runtime then for _,part in game:GetService('CollectionService'):GetTagged('EHInteractable')do
   if part:IsA('BasePart')and part:GetAttribute('EHInteractionId')==self._carryId and part:IsDescendantOf(runtime) then
    self._carryTool=HeldMotion.CloneDisplayPart(part,'HeldObjective');self._carryFlat=part:GetAttribute('DropFlat')==true
    self._carryTool.Transparency=0;self._carryTool.Anchored=true
    self._carryTool.CanCollide=false;self._carryTool.CanTouch=false;self._carryTool.CanQuery=false;self._carryTool.CastShadow=false
    -- this full-size copy stays out of the world (it is the template for a drop); a compressed
    -- copy is what is drawn in front of the lens
    local view=Instance.new('Model');view.Name='HeldObjectiveView'
    local copy=self._carryTool:Clone();copy.Parent=view;view.PrimaryPart=copy
    view:ScaleTo(HeldMotion.Near*(part:GetAttribute('HeldViewScale') or 1));self._carryView=view;self._carryDrop=part:GetAttribute('HeldViewDrop') -- (an item can ask to be drawn a little bigger in the hand: HeldViewScale)
    break
   end
  end end
 end
 if self._carryTool then
  -- Stays up the whole time (also while sprinting). Its motion is its own, not the camera's:
  -- a slow breathing sway when standing still, and a very small bob when moving.
  local t=os.clock();local m=math.clamp(self._swayState and self._swayState.moving or 0,0,1);local idle=1-m
  local reduced=self._player:GetAttribute('EHReduceMotion')==true
  self._carryPhase=(self._carryPhase or 0)+dt*math.pi*2*1.7*m
  local k=reduced and 0 or 1
  local x=math.sin(t*1.1)*(.016*idle+.004*m)
  local y=math.sin(t*1.6+.6)*(.012*idle+.003*m)+math.sin(self._carryPhase)*.007*m
  local float=CFrame.new(x*k,y*k,0)*CFrame.Angles(math.rad(math.sin(t*.9+.3)*.5*idle)*k,0,math.rad(math.sin(t*1.05+1.2)*(.7*idle+.3*m))*k)
  local amount=carryDraw*(1-stow)*(1-cutK)
  -- on a computer the item is framed a little further in from the left edge
  local desktop=game:GetService('UserInputService').PreferredInput==Enum.PreferredInput.KeyboardAndMouse
  local world=camera.CFrame*float*HeldMotion.CarryPose(self._carryTool.Size,aspect,camera.FieldOfView,amount,desktop and HeldMotion.DesktopCarrySpread or nil)
  do local drop=self._carryDrop;if drop then world=world-camera.CFrame.UpVector*drop end end -- (an item can sit a little lower in the hand: HeldViewDrop)
   self._carryTool.CFrame=world
  if self._carryView then
   self._carryView:PivotTo(HeldMotion.Compress(camera.CFrame.Position,world))
   self._carryView.Parent=amount>.001 and camera or nil
  end
 end
 -- Inside a vent the flashlight stays in view (you can see what you're holding while you crawl);
 -- a carried item is not drawn there. The beam itself is locked to the camera, not to the hand model.
 local screwing=tostring(self._player:GetAttribute('EHActiveInteraction')or ''):sub(1,8)=='BW5Screw' and self._player:GetAttribute('EHInteractionState')=='Holding'
 if screwing then self._tool.Parent=nil end -- (while unscrewing a vent screw the hand on the screwdriver is drawn instead)
 if (self._player:GetAttribute('EHInVent')~=nil or screwing) and self._carryView then self._carryView.Parent=nil end
 -- the held view models fade in with the picture (black cover / HUD reveal), never popping in
 -- or showing as dark shapes over a black screen
 -- (only a black screen hides them now; around cutscenes they are lowered and raised instead of faded)
 local viewAlpha=1-ScreenFade.Black();self._viewAlpha=viewAlpha
 if self._tool.Parent then ScreenFade.ApplyToModel(self._tool,viewAlpha) end
 if self._carryView and self._carryView.Parent then ScreenFade.ApplyToModel(self._carryView,viewAlpha) end
 self:_StepGhost()
 -- The light is locked to the camera: a fixed origin just below-right of the eye, aimed exactly
 -- along the view. It never follows the hand model's sway, draw or sprint pose, so the lit circle
 -- cannot shift, twitch or hitch at the screen edge. Switching on/off (and re-raising after a
 -- sprint) fades the brightness with the draw amount instead of moving the beam.
 local k=math.clamp(self._draw,0,1);k=k*k*(3-2*k)*(self._viewAlpha or 1)*(1-(self._cut or 0)) -- (the light goes down and comes back up with the flashlight)
 -- (tucked away while climbing out of a duct, and it fades back up with the torch afterwards - it used to
 -- pop back to full brightness the moment the climb-out ended)
 if Crawl.exiting or os.clock()-(self._ventExitT or -9)<2.5 then local s=self._stow or 0;k=k*(1-s*s*(3-2*s)) end
 -- The light starts almost exactly at the eye: a lamp offset from the eye throws hard, pitch-black
 -- shadow slivers beside every strap, bolt and edge you look at (read as black lines and dots);
 -- from the eye those shadows fall straight behind the objects and stay out of sight.
 -- (exactly on the line of sight: the hot spot, and the glints it makes on shiny surfaces, sit dead
 -- centre on the aim dot instead of a little low and to the right; and the origin never ends up
 -- inside a wall you are pressed against, which used to blank the light or make it flicker)
 local ahead=hit and math.clamp(hit.Distance-.12,.02,.22) or .22
 local point=camera.CFrame*Vector3.new(0,0,-ahead)
 -- In a duct the torch shines from just in front of your face along the duct: the origin is
 -- always ahead of the head (never inside your own body) and the beam is held to the way you are
 -- crawling (up to 65 degrees either side, a little up or down), so it can never swing back or
 -- down into your own character however you turn the view.
 local dir=camera.CFrame.LookVector
 local head=character and character:FindFirstChild('Head');local root=character and character:FindFirstChild('HumanoidRootPart')
 -- (Nov 3) going into and out of a duct the beam GLIDES between the two holds (ventW eases 0 <-> 1) instead
 -- of jumping from the eye to the duct hold the frame EHInVent changes
 local inV=self._player:GetAttribute('EHInVent')~=nil
 local wT=inV and 1 or 0
 self._ventW=(self._ventW or wT)+(wT-(self._ventW or wT))*(1-math.exp(-math.min(dt,.1)*(inV and 7 or 4.5)))
 if math.abs(self._ventW-wT)<.002 then self._ventW=wT end
 local vw=self._ventW*self._ventW*(3-2*self._ventW)
 if head and root and vw>0 then
  local fwd=V(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z);fwd=fwd.Magnitude>.05 and fwd.Unit or V(0,0,-1)
  local vdir=ventBeam(dir,fwd)
  local from=head.Position+V(0,.12,0) -- (Oct 18) start past the reaching hands: from .6 the crawling arms shadowed the whole beam
  local hitAhead=workspace:Raycast(from,fwd*1.7,params)
  local vpoint=from+fwd*(hitAhead and math.max(.3,hitAhead.Distance-.2) or 1.5)
  point=point:Lerp(vpoint,vw);dir=dir:Lerp(vdir,vw);dir=dir.Magnitude>.01 and dir.Unit or vdir
 end
 b.part.CFrame=CFrame.lookAt(point,point+dir)
 b.light.Shadows=vw<.01 -- (no shadows while in or easing out of a duct: the crawling arms would cut the beam)
 local lit=k>.01
 b.light.Enabled=lit;b.bounce.Enabled=lit
 -- The view models are drawn compressed toward the eye (HeldItemMotion.Near), so the hand bounce
 -- that used to wash over them now sits out past them. A tiny matching fill light in the same
 -- compressed space lights them exactly as the full-size bounce did.
 local fill=self._viewFill
 if not fill then
  fill=Instance.new('Part');fill.Name='ViewModelFill';fill.Size=V(.01,.01,.01);fill.Transparency=1;fill.Anchored=true;fill.CanCollide=false;fill.CanQuery=false;fill.CanTouch=false
  local l=Instance.new('PointLight',fill);l.Name='Fill';l.Shadows=false;l.Color=b.bounce.Color
  self._viewFill=fill;self._scope:Add(fill)
 end
 fill.Parent=camera
 -- the in-hand fill stays mostly warm white, so gold reads as gold (and every finish keeps its
 -- true colour) whatever colour the beam is; it only takes a hint of the beam's tint
 fill.Fill.Color=b.bounce.Color:Lerp(Color3.fromRGB(255,238,210),.65)
 fill.CFrame=camera.CFrame*CFrame.new(V(.32,-.28,-.25)*HeldMotion.Near)
 fill.Fill.Range=b.bounce.Range*HeldMotion.Near*1.15;fill.Fill.Brightness=b.bounce.Brightness*2.4;fill.Fill.Enabled=lit
 -- (Oct 23: a narrower, gentler torch - a beam, not a floodlight)
 b.light.Brightness=2.6*k;b.bounce.Brightness=.45*k
 local spill=b.part:FindFirstChild('Spill')
 if spill then spill.Enabled=lit;spill.Color=b.light.Color;spill.Brightness=.12*k end
 local core=b.part:FindFirstChild('Core')
 if core then core.Enabled=lit;core.Color=b.light.Color:Lerp(Color3.new(1,1,1),.5);core.Brightness=.8*k end
 self._aimElapsed+=dt
 if on and self._aimElapsed>=.25 then
  self._aimElapsed=0;local v=camera.CFrame.LookVector
  self._state:SendAction('FlashlightAim',{characterEpoch=self._player:GetAttribute('EHCharacterEpoch'),yaw=math.atan2(-v.X,-v.Z),pitch=math.clamp(math.asin(v.Y),-1.35,1.35)})
 end
end
-- Local fall of a just-dropped item, so the drop starts the instant the key is pressed. The ghost
-- carries the whole fall on this client (no waiting on the network, so it never hangs in mid-air);
-- the server's copy stays hidden here until both have come to rest, then the ghost glides the last
-- few millimetres onto the server's resting spot and hands over.
function Controller:_ClearCarryTool()
 if self._carryTool then self._carryTool:Destroy();self._carryTool=nil end
 if self._carryView then self._carryView:Destroy();self._carryView=nil end
end
function Controller:_BeginDrop()
 local tool=self._carryTool
 if not tool or not self._carryView or not self._carryView.Parent then return nil end
 local frame=tool.CFrame
 -- the full-size item is released where it appears to be; if that is inside a wall (it is drawn
 -- over geometry), release it just this side of the wall instead
 local camera=workspace.CurrentCamera
 if camera then
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
  params.FilterDescendantsInstances={self._player.Character,camera};params.RespectCanCollide=true
  local eye=camera.CFrame.Position;local d=frame.Position-eye
  local r=d.Magnitude>.01 and workspace:Raycast(eye,d,params)
  if r then frame=CFrame.new(r.Position-d.Unit*(math.max(tool.Size.X,tool.Size.Y,tool.Size.Z)*.5+.12))*frame.Rotation end
 end
 local root=self._player.Character and self._player.Character:FindFirstChild('HumanoidRootPart')
 local look=root and Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z).Unit or Vector3.zero
 local ghost=tool:Clone();ghost.Name='DroppingObjective';ghost.CFrame=frame
 local flat
 if self._carryFlat then
  -- (Nov 3) a flat item (the keycard) falls straight down and settles face up - the same resting spot the
  -- server picks (HeldItemMotion.FlatRest) - turning flat on the way down instead of tumbling
  local rest=HeldMotion.FlatRest(frame.Position,look,tool.Size,{self._player.Character,camera,ghost})
  if rest then flat={from=frame,to=rest,t0=os.clock(),dur=math.clamp(math.sqrt(2*math.max(.05,frame.Position.Y-rest.Position.Y)/workspace.Gravity)*1.25,.22,.6)} end
 end
 ghost.CanQuery=false;ghost.CanTouch=false;ghost.CastShadow=true
 if flat then ghost.Anchored=true;ghost.CanCollide=false;ghost.Parent=workspace
 else
  ghost.Anchored=false;ghost.CanCollide=true;ghost.Massless=false
  ghost.CustomPhysicalProperties=PhysicalProperties.new(1.4,1.2,.02,100,100);ghost.Parent=workspace
  ghost.AssemblyLinearVelocity=(root and root.AssemblyLinearVelocity*.85 or Vector3.zero)+look*2.2+Vector3.new(0,.8,0)
  ghost.AssemblyAngularVelocity=Vector3.new(math.random(-10,10)/10,math.random(-6,6)/10,math.random(-10,10)/10).Unit*DROP_SPIN
 end
 if self._ghost then self:_EndGhost()end
 self._ghost={part=ghost,id=self._carryId,started=os.clock(),flat=flat}
 self:_ClearCarryTool();self._carryMotion=HeldMotion.New();self._dropPredict=os.clock()
 return frame
end
local function hideReal(real,hidden)
 if not real then return end
 local k=hidden and 1 or 0
 real.LocalTransparencyModifier=k
 -- (Nov 3) the printing on an item (the keycard's SurfaceGuis, decals) is hidden with it: it used to stay
 -- where the server copy was while the ghost fell, so the label looked like it came off the card
 for _,d in real:GetDescendants()do
  if d:IsA('BasePart') or d:IsA('Decal') then d.LocalTransparencyModifier=k
  elseif d:IsA('SurfaceGui') or d:IsA('BillboardGui') then
   if hidden then if d:GetAttribute('EHGhostWas')==nil then d:SetAttribute('EHGhostWas',d.Enabled) end;d.Enabled=false
   elseif d:GetAttribute('EHGhostWas')~=nil then
    local st=real:GetAttribute('EHItemState')
    d.Enabled=real.Transparency<.99 and (st=='Dropped' or st=='AtSpawn' or st=='Installed');d:SetAttribute('EHGhostWas',nil)
   end
  end
 end
end
function Controller:_EndGhost()
 local g=self._ghost;if not g then return end
 if g.part.Parent then g.part:Destroy()end
 hideReal(g.target,false);self._ghost=nil
end
function Controller:_StepGhost()
 local g=self._ghost;if not g then return end
 local now=os.clock();local dt=math.clamp(now-(g.last or now),0,.1);g.last=now
 if not g.part.Parent or now-g.started>8 then self:_EndGhost();return end
 -- a flat item's fall: drops with gravity (eases in) while it turns to lie flat (eases out), lands with a
 -- tiny settle - all on this screen, no physics, so it can never bounce onto its back
 local fl=g.flat
 if fl and not g.from then
  local u=math.clamp((now-fl.t0)/fl.dur,0,1)
  local down=u*u;local turn=1-(1-u)^3
  local p=fl.from.Position:Lerp(fl.to.Position,down)
  local r=fl.from.Rotation:Lerp(fl.to.Rotation,turn)
  local settle=u>=1 and math.max(0,1-(now-fl.t0-fl.dur)/.12) or 0
  g.part.CFrame=CFrame.new(p+Vector3.new(0,.012*math.sin(settle*math.pi),0))*r
  if u>=1 and not fl.landed then fl.landed=now end
 end
 if not g.target or not g.target.Parent then
  g.target=nil
  local runtime=workspace:FindFirstChild('Runtime')
  if runtime then for _,part in runtime:GetDescendants()do if part:IsA('BasePart')and part:GetAttribute('EHInteractionId')==g.id then g.target=part;break end end end
 end
 local real=g.target;if not real then return end
 local state=real:GetAttribute('EHItemState')
 if state=='Carried' then
  if now-g.started>.6 then self:_EndGhost()end -- refused, or someone already grabbed it
  return
 end
 if state~='Dropped' then self:_EndGhost();return end
 hideReal(real,true)
 -- watch both bodies come to rest
 if not real.Anchored then g.sawPhysics=true end
 local moving=g.part.AssemblyLinearVelocity.Magnitude+g.part.AssemblyAngularVelocity.Magnitude*.25
 if not g.part.Anchored then g.still=moving<.5 and (g.still or 0)+dt or 0 end
 local settled=real.Anchored and (g.sawPhysics or now-g.started>1.2 or (fl and fl.landed and now-fl.landed>.12))
 -- the server's copy has come to rest: it is authoritative, so the ghost settles onto it now
 -- (even if this client's fall ended slightly differently)
 if settled and (fl and fl.landed and now-fl.landed>.12 or (not fl and ((g.still or 0)>=.1 or now-g.started>.6))) then
  if not g.from then g.part.Anchored=true;g.from=g.part.CFrame;g.blend=0 end
  g.blend=math.min(1,g.blend+dt/.25)
  local a=g.blend*g.blend*(3-2*g.blend)
  g.part.CFrame=g.from:Lerp(real.CFrame,a)
  if g.blend>=1 then self:_EndGhost()end
 end
end
-- Flashlight switch: two different single-click recordings (Pro Sound Effects), trimmed to start
-- right on the click. 'On' is a crisp, slightly brighter click; 'off' a lower, softer one.
local CLICK={on={id='rbxassetid://9116283749',from=.08,speed=1.05,volume=.55},off={id='rbxassetid://9116283546',from=.14,speed=.94,volume=.45}}
function Controller:_Click(on,parent)
 local c=on and CLICK.on or CLICK.off
 if not parent then
  -- Own switch: two preloaded 2D sounds, so the click lands on the same frame as the key press.
  self._clicks=self._clicks or {}
  local s=self._clicks[on]
  if not s then s=Instance.new('Sound');s.Name=on and 'FlashlightOn' or 'FlashlightOff';s.SoundId=c.id;s.Volume=c.volume;s.Parent=game:GetService('SoundService');self._clicks[on]=s end
  s.PlaybackSpeed=c.speed+math.random(-2,2)/100;s.TimePosition=c.from;s:Play();return
 end
 local s=Instance.new('Sound');s.SoundId=c.id;s.Volume=c.volume*.7
 s.PlaybackSpeed=c.speed+math.random(-2,2)/100
 s.RollOffMinDistance=3;s.RollOffMaxDistance=30
 s.TimePosition=c.from;s.Parent=parent
 s.Ended:Connect(function()s:Destroy()end);s:Play()
 task.delay(2,function()if s.Parent then s:Destroy()end end)
end
function Controller:_PreloadClicks()
 for _,on in {true,false}do
  local c=on and CLICK.on or CLICK.off
  local s=Instance.new('Sound');s.Name=on and 'FlashlightOn' or 'FlashlightOff';s.SoundId=c.id;s.Volume=c.volume;s.Parent=game:GetService('SoundService')
  self._clicks=self._clicks or {};self._clicks[on]=s;self._scope:Add(s)
 end
 task.spawn(function()pcall(function()game:GetService('ContentProvider'):PreloadAsync({self._clicks[true],self._clicks[false]})end)end)
end
function Controller:_CanToggle()
 local p=self._player
 if p:GetAttribute('EHFlashlightAllowed')~=true then return false end
 if p:GetAttribute('EHSprinting')==true then return false end
 if p:GetAttribute('EHLifeState')~='Alive' then return false end
 local context=self._input:GetContext();if context~='ActiveFloor' and context~='Transit' then return false end
 if (p:GetAttribute('EHKnockedUntil') or 0)>workspace:GetServerTimeNow() then return false end
 if os.clock()-(self._lastLocalToggle or -math.huge)<.25 then return false end
 return true
end
function Controller:_FlushFlashlight()
 local wanted=self._wantedOn
 if wanted==nil then return end
 if self._player:GetAttribute('EHFlashlightAllowed')~=true then self._wantedOn=nil;return end
 -- Compare against the player's chosen state, not EHFlashlightOn: sprinting stows the light
 -- without changing that choice, and must not trigger toggle retries.
 local chosen=self._player:GetAttribute('EHFlashlightWanted');if chosen==nil then chosen=self._player:GetAttribute('EHFlashlightOn')end
 if (chosen==true)==wanted and os.clock()>=(self._nextToggle or 0)then self._wantedOn=nil;return end
 if os.clock()<(self._nextToggle or 0)then return end
 self._nextToggle=os.clock()+.28
 self._state:SendAction('ToggleFlashlight',{characterEpoch=self._player:GetAttribute('EHCharacterEpoch'),on=wanted})
end
function Controller:_Render(dt)
 self:_FlushFlashlight()
 local camera=workspace.CurrentCamera;if not camera then return end
 if not self._toolTemplate then self:_Assets()end
 for player,b in self._beams do
  if player==self._player then self:_View(dt,camera,b)
  else
   local c=player.Character;local hand=c and(c:FindFirstChild('RightHand')or c:FindFirstChild('Right Arm'));local h=c and c:FindFirstChildOfClass('Humanoid')
   local active=hand and h and h.Health>0 and player:GetAttribute('EHFlashlightAllowed')==true and player:GetAttribute('EHFlashlightOn')==true
     and not player:GetAttribute('EHInCar') and hand.LocalTransparencyModifier<.9 -- (Oct 25) never floating in the air while their body is hidden in a cutscene
   local skin,template=self:_Skin(player)
   if b.tool and b.toolSkin~=skin then b.tool:Destroy();b.tool=nil end
   if not b.tool and template then
    b.tool=template:Clone();b.tool.Name='PeerFlashlight';prepareDisplay(b.tool);b.toolSkin=skin
    b.tool:ScaleTo(b.tool:GetScale()*HOLD_SCALE*(SKIN_SCALE[skin] or 1))
    b.toolOrbit=orbiters(b.tool)
    local lens=b.tool:FindFirstChild('Lens',true)
    b.lensZ=lens and b.tool:GetPivot():PointToObjectSpace(lens.Position).Z or -.7
    b.tailZ=tailOf(b.tool)
   end
   b.light.Color=beamColors(colorOf(player))
   if b.tool then b.tool.Parent=active and workspace or nil end
   b.light.Enabled=active and player:GetAttribute('EHFlashlightOn')==true or false
   b.active=active and true or false
   if active then
    -- the aim arrives a few times a second; ease toward it so the arm moves smoothly
    local target=player:GetAttribute('EHLightAim') or c:GetPivot().LookVector
    if typeof(target)~='Vector3' or target.Magnitude<.01 then target=c:GetPivot().LookVector end
    target=target.Unit
    b.aim=b.aim and b.aim:Lerp(target,1-math.exp(-math.min(dt,.1)*12)).Unit or target
    -- held properly: the grip sits in the hand and the light points down the arm, which
    -- raises toward where they're aiming (so looking up or down moves the arm, not the light in the hand)
    local grip=holdFrame(hand,hand.Name=='RightHand',b.tailZ or .4)
    if b.tool then b.tool:PivotTo(grip);spinOrbiters(b.tool,b.toolOrbit)end
    local lensPos=grip*Vector3.new(0,0,(b.lensZ or -.8)-.05)
    -- locked, neutral orientation: the beam goes straight out along their body (the way they face),
    -- a touch below level - it never pitches up or down with their camera
    local root=c:FindFirstChild('HumanoidRootPart')
    local body=root and root.CFrame.LookVector or c:GetPivot().LookVector
    local flat=Vector3.new(body.X,0,body.Z);flat=flat.Magnitude>.05 and flat.Unit or Vector3.new(0,0,-1)
    local head=c:FindFirstChild('Head')
    -- (Nov 3) their beam glides between the hand hold and the duct hold (b.ventW) as they crawl in or climb
    -- out, and their arm eases into / out of its held pose with it (_PosePeers), so nothing jumps
    local wT=(player:GetAttribute('EHInVent')~=nil) and 1 or 0
    b.ventW=(b.ventW or wT)+(wT-(b.ventW or wT))*(1-math.exp(-math.min(dt,.1)*(wT>.5 and 7 or 4.5)))
    if math.abs(b.ventW-wT)<.002 then b.ventW=wT end
    local vw=b.ventW*b.ventW*(3-2*b.ventW)
    local beam=flat*math.cos(NEUTRAL_PITCH)+Vector3.new(0,math.sin(NEUTRAL_PITCH),0)
    local o,d=lensPos,beam
    if head and vw>0 then
     -- crawling in a duct: shines up the duct from just in front of their face
     local vo=head.Position+flat*1.5+Vector3.new(0,.12,0)
     o=lensPos:Lerp(vo,vw);d=beam:Lerp(flat,vw).Unit
    end
    b.part.CFrame=CFrame.lookAt(o,o+d);b.light.Shadows=vw<.01
   end
  end
 end
end
-- Other players hold their flashlight in one fixed, relaxed pose: the right arm a little forward and
-- down, held slightly out from the body (never pinned into the side). It is tied to their torso only -
-- never to where they look - so it is the same whether they look up, down, walk or sprint. The
-- flashlight is glued to the hand. Set after their animations run (PreSimulation), only for the
-- shoulder, only on this client.
local DOWN=Vector3.new(0,-1,0)
local ARM_DROP=math.rad(50) -- below straight ahead
local ARM_OUT=.22           -- out to the side, away from the body
local function jointFrame(joint)
 if joint:IsA('Motor6D') and joint.Part0 then return joint.Part0.CFrame*joint.C0,joint.Part0 end
 if joint:IsA('AnimationConstraint') and joint.Attachment0 then return joint.Attachment0.WorldCFrame,joint.Attachment0.Parent end
end
function Controller:_PosePeers()
 for player,b in self._beams do
  local hold=1-((b.ventW or 0)*(b.ventW or 0)*(3-2*(b.ventW or 0))) -- (Nov 3: the held pose fades out/in with the duct)
  if player~=self._player and b.active and hold>.001 then
   local c=player.Character
   local h=c and c:FindFirstChildOfClass('Humanoid')
   local r15=h and h.RigType==Enum.HumanoidRigType.R15
   local joint=c and c:FindFirstChild(r15 and 'RightShoulder' or 'Right Shoulder',true)
   local frame,torso
   if joint then frame,torso=jointFrame(joint) end
   if frame and torso then
    local fwd=frame:VectorToObjectSpace(torso.CFrame.LookVector)
    local down=frame:VectorToObjectSpace(-torso.CFrame.UpVector)
    local out=frame:VectorToObjectSpace(torso.CFrame.RightVector)
    local to=(fwd*math.cos(ARM_DROP)+down*math.sin(ARM_DROP)+out*ARM_OUT).Unit
    local axis=DOWN:Cross(to)
    local angle=math.acos(math.clamp(DOWN:Dot(to),-1,1))
    local pose=axis.Magnitude>1e-4 and CFrame.fromAxisAngle(axis.Unit,angle) or CFrame.identity
    joint.Transform=hold>=.999 and pose or joint.Transform:Lerp(pose,hold) -- (blended with their crawl animation while easing)
   end
  end
 end
end
function Controller:Start()
 if Shared.Parent:GetAttribute('PlaceRole')~='Game'then return end
 self._scope:Add(RunService.PreSimulation:Connect(function()self:_PosePeers()end))
  HeldView.BeginDrop=function()return self:_BeginDrop()end
 self:_PreloadClicks()
 self._scope:Add(function()HeldView.BeginDrop=nil end)
 self._scope:Add(self._input:Register('Flashlight',function(state)
  if state=='Begin'then local epoch=self._player:GetAttribute('EHCharacterEpoch');if type(epoch)=='number'and epoch>0 then
   -- Same rules as the server (EquipmentService.Toggle): if the switch cannot actually change
   -- right now (sprinting, daylight at the surface, not on a floor, down/dead, knocked over or
   -- still in the toggle cooldown) nothing happens at all - no click.
   if not self:_CanToggle() then return end
   local current=self._wantedOn;if current==nil then local chosen=self._player:GetAttribute('EHFlashlightWanted');if chosen==nil then chosen=self._player:GetAttribute('EHFlashlightOn')end;current=chosen==true end
   self._wantedOn=not current;self._lastLocalToggle=os.clock();self:_Click(self._wantedOn);self:_FlushFlashlight()
  end end
 end))
 local function available()self._input:SetAvailable('Flashlight',self._player:GetAttribute('EHFlashlightAllowed')==true)end
 self._scope:Add(self._player:GetAttributeChangedSignal('EHFlashlightAllowed'):Connect(available));available()
 -- Other players' switches click in 3D at their position.
 local function listen(p)
  if p==self._player then return end
  -- only a real switch flip clicks: EHFlashlightWanted also drops when the light becomes
  -- unavailable (daylight, downed, context change), which is not a click
  local wasAllowed=p:GetAttribute('EHFlashlightAllowed')==true
  self._scope:Add(p:GetAttributeChangedSignal('EHFlashlightAllowed'):Connect(function()
   task.defer(function()wasAllowed=p:GetAttribute('EHFlashlightAllowed')==true end)
  end))
  self._scope:Add(p:GetAttributeChangedSignal('EHFlashlightWanted'):Connect(function()
   if not wasAllowed or p:GetAttribute('EHFlashlightAllowed')~=true then return end
   local head=p.Character and p.Character:FindFirstChild('Head')
   if head then self:_Click(p:GetAttribute('EHFlashlightWanted')==true,head)end
  end))
 end
 for _,p in Players:GetPlayers()do listen(p)end;self._scope:Add(Players.PlayerAdded:Connect(listen))
 for _,p in Players:GetPlayers()do self:_Add(p)end
 self._scope:Add(Players.PlayerAdded:Connect(function(p)self:_Add(p)end))
 self._scope:Add(Players.PlayerRemoving:Connect(function(p)local b=self._beams[p];if b then b.part:Destroy();if b.tool then b.tool:Destroy()end;self._beams[p]=nil end end))
 RunService:BindToRenderStep('BlackwaterEquipment',Enum.RenderPriority.Camera.Value+6,function(dt)self:_Render(dt)end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('BlackwaterEquipment')end)
end
function Controller:Destroy()
 if self._scope then self._scope:Destroy()end
 for _,b in self._beams do b.part:Destroy();if b.tool then b.tool:Destroy()end end;table.clear(self._beams)
 self:_ClearCarryTool()
 if self._ghost then self:_EndGhost()end
 if self._tool then self._tool:Destroy()end
end
return table.freeze(Controller)