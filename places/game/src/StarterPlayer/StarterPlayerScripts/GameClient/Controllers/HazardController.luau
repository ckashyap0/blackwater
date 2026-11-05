--!nonstrict
-- Client side of the Level 5 slip hazards and mop task.
--  * Knockdown pose for EVERY character from the replicated EHKnockedAt/EHKnockedUntil player
--    attributes: the rig's Root joint tips the body onto its back (applied after the Animator, like
--    the crouch pose), so all clients see the same fall and get-up.
--  * Local player: momentum is stripped on impact and the first-person camera drops to the floor,
--    tilts up and recovers when the lock ends. The camera module's own frame is restored before it
--    runs again, so the fall never accumulates into the player's aim.
--  * No outlines here: spills, drips and mops are found by looking around (only primary
--    objectives get the through-wall outline, see ObjectiveController).
--  * The carried mop is shown as a first-person view model (left hand, head trailing on the floor
--    ahead) and scrubs side to side while you hold MOP UP.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Crawl=require(Shared.Utilities.CrawlState)
local SinkCurve=require(Shared.Utilities.SinkCurve)
local ScreenFade=require(Shared.Utilities.ScreenFade)
local Controller={};Controller.__index=Controller
local FALL,RISE=.42,.85
-- Getting up after a puddle slip: a real get-up (onto the elbows, sit up, onto a knee, stand) and then
-- a groggy shake of the head, SLIP_RISE seconds in all; SLIP_SHAKE is the share of it that is the
-- head shake. You stay locked in place until the shake is nearly done.
local SLIP_RISE,SLIP_SHAKE=2.7,.3
local CLIMB_SECONDS=1.05 -- climbing into a vent (see _Vent / CLIMB_KEYS; Level5Floor uses the same)
local GETUP=require(Shared.Utilities.IntroTimeline).GetUpSeconds -- the crash get-up (EHKnockStyle 'Crash')
function Controller.new(player)return setmetatable({Name='HazardController',Dependencies={'InputController','CameraController'},_player=player,_rigs={},_highlights={}},Controller)end
function Controller:Init(deps)self._input=deps.InputController;self._scope=Scope.new()end
local function smooth(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
-- Knockdown state from the replicated attributes.
-- k: 0 standing .. 1 flat on the floor; impact: jolt as the body lands; style: 'Slip' or 'Crash';
-- g: crash get-up progress 0..1 once the lying time is over (nil otherwise).
local function knockAmount(p,t)
 local t0,t1=p:GetAttribute('EHKnockedAt'),p:GetAttribute('EHKnockedUntil')
 local style=p:GetAttribute('EHKnockStyle')=='Crash' and 'Crash' or 'Slip'
 local rise=style=='Crash' and GETUP or SLIP_RISE
 if type(t0)~='number' or type(t1)~='number' or t<t0 or t>t1+rise then return 0,0,style,nil end
 local fall=math.clamp((t-t0)/FALL,0,1)
 local k=fall*fall
 local g
 if t>t1 then g=math.clamp((t-t1)/rise,0,1);k=1-smooth(g)end
 -- short jolt right as the body hits the floor
 local impact=math.max(0,1-math.abs((t-t0)-FALL)/.18)
 return k,impact,style,g
end
local JOINTS={Root='LowerTorso',Waist='UpperTorso',LeftHip='LeftUpperLeg',RightHip='RightUpperLeg',LeftKnee='LeftLowerLeg',RightKnee='RightLowerLeg',
 LeftShoulder='LeftUpperArm',RightShoulder='RightUpperArm',LeftElbow='LeftLowerArm',RightElbow='RightLowerArm',Neck='Head'}
local BODY={'Head','UpperTorso','LowerTorso','LeftUpperArm','LeftLowerArm','LeftHand','RightUpperArm','RightLowerArm','RightHand',
 'LeftUpperLeg','LeftLowerLeg','LeftFoot','RightUpperLeg','RightLowerLeg','RightFoot','Torso','Left Arm','Right Arm','Left Leg','Right Leg'}
local function rig(c)
 local j={}
 for name,partName in JOINTS do local part=c:FindFirstChild(partName);local joint=part and part:FindFirstChild(name);if joint and (joint:IsA('Motor6D')or joint:IsA('AnimationConstraint'))then j[name]=joint end end
 local parts={};for _,n in BODY do local part=c:FindFirstChild(n);if part and part:IsA('BasePart')then table.insert(parts,part)end end
 return j,parts
end
-- Poses (degrees; X: + tips a limb/torso BACKWARD for the torso, FORWARD for legs/arms hanging down;
-- knees/elbows: - bends the shin back, + bends the forearm up). drop: share of the standing hip
-- height the body sinks (the floor fit below then seats it exactly on the floor).
local LIE={drop=1,z=.7,root={84,0,0},waist={0,0,0},lhip={18,0,-6},rhip={26,0,8},lknee={-28,0,0},rknee={-40,0,0},
 lsh={-20,0,-55},rsh={-10,0,60},lel={10,0,0},rel={10,0,0},neck={-18,0,0}}
-- The crash get-up, keyframed over GETUP seconds: a heavy nod as you come round, push up onto your
-- elbows, sit up propped on your hands, roll forward onto one knee with a hand on the other, push
-- yourself up, sway once and stand.
local GETUP_KEYS={
 {0,LIE},
 {.19,{drop=1,z=.7,root={83,0,0},waist={-4,0,0},lhip={20,0,-6},rhip={28,0,8},lknee={-31,0,0},rknee={-42,0,0},lsh={-26,0,-30},rsh={-22,0,34},lel={38,0,0},rel={34,0,0},neck={-46,0,0}}},
 {.386,{drop=1,z=.7,root={80,0,0},waist={-8,0,0},lhip={22,0,-6},rhip={30,0,8},lknee={-34,0,0},rknee={-44,0,0},lsh={-38,0,-14},rsh={-34,0,14},lel={70,0,0},rel={66,0,0},neck={-38,0,0}}},
 {.529,{drop=.8,z=.5,root={38,0,0},waist={-14,0,0},lhip={58,0,-4},rhip={76,0,6},lknee={-26,0,0},rknee={-72,0,0},lsh={-48,0,-12},rsh={-46,0,12},lel={12,0,0},rel={14,0,0},neck={-22,0,0}}},
 {.571,{drop=.8,z=.45,root={30,0,0},waist={-18,0,0},lhip={100,0,-6},rhip={106,0,6},lknee={-130,0,0},rknee={-136,0,0},lsh={-30,0,-12},rsh={-20,0,12},lel={16,0,0},rel={18,0,0},neck={-26,0,0}}},
 {.621,{drop=.65,z=.35,root={0,4,4},waist={-30,0,0},lhip={62,0,-4},rhip={14,0,4},lknee={-104,0,0},rknee={-122,0,0},lsh={10,0,-10},rsh={34,0,12},lel={20,0,0},rel={26,0,0},neck={-24,0,0}}},
 {.679,{drop=.5,z=.25,root={-24,6,8},waist={-12,0,0},lhip={104,0,-4},rhip={26,0,4},lknee={-96,0,0},rknee={-92,0,0},lsh={30,0,-8},rsh={46,0,10},lel={24,0,0},rel={30,0,0},neck={-26,0,0}}},
 {.814,{drop=.3,z=.1,root={-20,3,3},waist={-10,0,0},lhip={70,0,-3},rhip={52,0,3},lknee={-68,0,0},rknee={-74,0,0},lsh={24,0,-6},rsh={30,0,8},lel={30,0,0},rel={36,0,0},neck={-16,0,0}}},
 {.929,{drop=.06,z=0,root={-5,0,-3},waist={2,0,0},lhip={8,0,-2},rhip={10,0,2},lknee={-10,0,0},rknee={-12,0,0},lsh={4,0,-4},rsh={6,0,4},lel={10,0,0},rel={12,0,0},neck={8,0,0}}},
 {1,{drop=0,z=0,root={0,0,0},waist={0,0,0},lhip={0,0,0},rhip={0,0,0},lknee={0,0,0},rknee={0,0,0},lsh={0,0,0},rsh={0,0,0},lel={0,0,0},rel={0,0,0},neck={0,0,0}}},
}
local ZERO=GETUP_KEYS[#GETUP_KEYS][2]
local function blend(a,b,u)
 local o={drop=a.drop+(b.drop-a.drop)*u,z=a.z+(b.z-a.z)*u}
 for key,v in a do if type(v)=='table' then local w=b[key];o[key]={v[1]+(w[1]-v[1])*u,v[2]+(w[2]-v[2])*u,v[3]+(w[3]-v[3])*u}end end
 return o
end
local function getUpPose(g)
 for i=1,#GETUP_KEYS-1 do
  local a,b=GETUP_KEYS[i],GETUP_KEYS[i+1]
  if g<=b[1] then return blend(a[2],b[2],smooth((g-a[1])/(b[1]-a[1])))end
 end
 return ZERO
end
-- The slip get-up: from flat on your back, prop up on the elbows, then the same sit-up, kneel and
-- stand as the crash get-up (just quicker), then a dazed shake of the head - a few quick turns side
-- to side that die away, with a little sway through the body.
local function slipPose(g)
 local up=math.clamp(g/(1-SLIP_SHAKE),0,1)
 local pose
 if up<.16 then pose=blend(LIE,getUpPose(.386),smooth(up/.16))
 else pose=getUpPose(.386+(1-.386)*((up-.16)/.84)) end
 if g>1-SLIP_SHAKE then
  local s=(g-(1-SLIP_SHAKE))/SLIP_SHAKE
  local fade=(1-s)^1.4*math.min(1,s/.08)
  local turn=math.sin(s*math.pi*2*2.6)
  pose=blend(pose,pose,0)
  pose.neck={pose.neck[1]-6*fade,24*turn*fade,5*turn*fade}
  pose.waist={pose.waist[1],-5*turn*fade,0}
 end
 return pose
end
-- Climbing into a vent (every client, from the server's EHVentAt; the root itself follows the
-- climber's replicated path): crouch under the opening, spring up with both arms reaching, catch the
-- lip and hang, haul the chest over it, then fold forward into the crawl.
local CLIMB_KEYS={
 {0,{drop=0,z=0,root={0,0,0},waist={0,0,0},lhip={0,0,0},rhip={0,0,0},lknee={0,0,0},rknee={0,0,0},lsh={0,0,0},rsh={0,0,0},lel={0,0,0},rel={0,0,0},neck={0,0,0}}},
 {.2,{drop=0,z=0,root={-12,0,0},waist={-8,0,0},lhip={55,0,-4},rhip={55,0,4},lknee={-95,0,0},rknee={-95,0,0},lsh={20,0,-6},rsh={20,0,6},lel={25,0,0},rel={25,0,0},neck={18,0,0}}},
 {.42,{drop=0,z=0,root={-4,0,0},waist={-2,0,0},lhip={8,0,-2},rhip={8,0,2},lknee={-10,0,0},rknee={-10,0,0},lsh={165,0,-8},rsh={165,0,8},lel={8,0,0},rel={8,0,0},neck={28,0,0}}},
 {.62,{drop=0,z=0,root={-14,0,0},waist={-6,0,0},lhip={40,0,-4},rhip={30,0,4},lknee={-70,0,0},rknee={-55,0,0},lsh={150,0,-8},rsh={150,0,8},lel={55,0,0},rel={55,0,0},neck={25,0,0}}},
 -- chest over the lip: body nearly flat and legs trailing straight out behind (no folded knees
 -- poking through the wall below the opening), then it settles face down into the crawl
 {.84,{drop=0,z=0,root={-74,0,0},waist={-6,0,0},lhip={22,0,-3},rhip={16,0,3},lknee={-28,0,0},rknee={-20,0,0},lsh={70,0,-10},rsh={70,0,10},lel={30,0,0},rel={30,0,0},neck={40,0,0}}},
}
-- One heavy stroke of the low crawl, w = 0..1 through the cycle for one side:
-- reach (slow, 0-46%), a dead pause with the elbow planted (46-58%), then the drag back (58-100%).
-- 0 = arm drawn back under the shoulder / knee straight, 1 = elbow far forward / knee hauled up.
local function stroke(w)
 if w<.46 then return smooth(w/.46)elseif w<.58 then return 1 end
 return 1-smooth((w-.58)/.42)
end
-- Prone low crawl, face down with the chest almost on the duct floor, head first. Staggered
-- elbow-and-knee drag: the RIGHT elbow reaches forward while the LEFT knee is hauled up beside the
-- hip, then the body is dragged over them; the other pair follows half a cycle later. Forearms stay
-- flat on the sheet metal (shoulder + elbow = 180), the knees fold out sideways along the floor, so
-- nothing ever lifts toward the duct roof or swings past the duct walls (3.2 x 3.4 inside; measured
-- on a broad R15 avatar the arms stay within 1.66 of the centre line, the legs within 1.5 and
-- nothing rises above 2.3 - the Animator's walk swing is faded out underneath, see _Pose).
-- The torso rolls and turns a little toward each pulling arm; the head stays low, eyes up the duct.
-- With the torch on, the right hand holds it forward and makes only short, careful pulls.
-- Prone "swim" pull, belly flat on the duct floor: BOTH arms reach forward together, plant, then
-- drag the body up to them (the propulsive part), elbows tucked in under the chest. The arms
-- themselves are solved by proneArms below (two-bone IK inside a fixed corridor); the angles here
-- are only the rest of the body and a rough arm pose used while blending in from the climb.
-- pull(w): 0 = hands drawn back in front of the chest, 1 = reached right out ahead
local REACH_END,PLANT_END=.36,.44
local function pullCurve(w)
 if w<REACH_END then return smooth(w/REACH_END)elseif w<PLANT_END then return 1 end
 return 1-smooth((w-PLANT_END)/(1-PLANT_END))
end
-- Legs: the WHOLE leg works with the arms (thigh, knee and foot), a frog kick in time with the
-- pull: while the arms reach, both knees are drawn up and out to the sides along the floor (thighs
-- swing out and turn out, knees bend, feet tuck); during the drag the legs push back out straight.
-- Turned-out thighs keep the bent shins flat along the sheet metal instead of lifting at the roof.
local function legDraw(w)
 if w<REACH_END then return smooth(w/REACH_END)elseif w<PLANT_END then return 1 end
 return 1-smooth((w-PLANT_END)/(1-PLANT_END))
end
local function crawlPose(phase,move,light)
 local w=(phase/(2*math.pi))%1
 local f=.5+(pullCurve(w)-.5)*move
 local fL=f;local fR=.5+(pullCurve((w+.5)%1)-.5)*move
 local dL,dR=legDraw((w+.5)%1)*move,legDraw(w)*move -- (each knee draws up with the opposite arm's reach)
 -- body surges a hair during the drag
 local drag=(w>=PLANT_END) and math.sin((w-PLANT_END)/(1-PLANT_END)*math.pi)*move or 0
 -- slow side-to-side roll of the whole body, one sway per stroke
 local sway=math.sin(phase)*move
 local d=legDraw(w)*move
 return {drop=0,z=0,
  root={-90,0,2.6*sway},
  waist={-2-2*drag,0,-.9*sway},
  -- (Oct 25) arms pull in turn (left reaches while right drags), forearms low under the face
  rsh={118+44*fR,0,-22},rel={78-46*fR,0,0},
  lsh={118+44*fL,0,22},lel={78-46*fL,0,0},
  -- (prone, a POSITIVE hip pitch lowers the legs onto the floor - measured)
  lhip={11+5*dL,42*dL,-3-16*dL},lknee={-2-44*dL,0,0},
  rhip={11+5*dR,-42*dR,3+16*dR},rknee={-2-44*dR,0,0},
  -- face lifted just off the sheet metal, eyes up the duct; nods slightly with each pull
  -- (kept low: chin just clear of the floor so the silhouette stays flat in the duct)
  neck={44-3*drag,0,0}}
end
-- Two-bone IK for one arm, all in UpperTorso space (X right, Y toward the head = forward along the
-- duct when prone, Z away from the floor). Returns the shoulder and elbow Motor6D transforms that
-- put the wrist exactly on W with the elbow bent toward the pole.
local function rotationBetween(a,b)
 local d=math.clamp(a:Dot(b),-1,1)
 local axis=a:Cross(b)
 if axis.Magnitude<1e-6 then return d>0 and CFrame.identity or CFrame.fromAxisAngle(math.abs(a.X)<.9 and Vector3.xAxis or Vector3.yAxis,math.pi) end
 return CFrame.fromAxisAngle(axis.Unit,math.acos(d))
end
-- A joint's two frames (Part1 = Part0 * C0 * Transform * C1:Inverse()), for classic Motor6D rigs
-- and for the newer AnimationConstraint rigs (frames = the two rig attachments).
local function jointFrames(m)
 if not m then return nil end
 if m:IsA('Motor6D') then return m.C0,m.C1 end
 if m:IsA('AnimationConstraint') and m.Attachment0 and m.Attachment1 then return m.Attachment0.CFrame,m.Attachment1.CFrame end
 return nil
end
local function armRig(c,side)
 local n=side>0 and 'Right' or 'Left'
 local ua=c:FindFirstChild(n..'UpperArm');local la=c:FindFirstChild(n..'LowerArm');local hand=c:FindFirstChild(n..'Hand')
 local sh=ua and ua:FindFirstChild(n..'Shoulder');local el=la and la:FindFirstChild(n..'Elbow');local wr=hand and hand:FindFirstChild(n..'Wrist')
 local s0,s1=jointFrames(sh);local e0,e1=jointFrames(el);local w0=jointFrames(wr)
 if not(s0 and e0 and w0)then return nil end
 local v1=e0.Position-s1.Position;local v2=w0.Position-e1.Position
 if v1.Magnitude<.1 or v2.Magnitude<.1 then return nil end
 return {sh=sh,el=el,wr=wr,s0=s0,s1=s1,e0=e0,e1=e1,v1=v1.Unit,v2=v2.Unit,L1=v1.Magnitude,L2=v2.Magnitude,side=side}
end
-- The arm's rest direction (hanging down) is almost OPPOSITE to where a prone arm points (ahead),
-- and a shortest-arc rotation between near-opposite vectors swings its twist wildly with tiny
-- changes - that was the hands flicking back and forth. So each joint is first turned to a fixed
-- reference pose that already points the right way (arm forward, elbow half bent) and the IK only
-- adds the small correction from there: smooth and stable every frame.
local SHOULDER_REF=CFrame.Angles(math.rad(140),0,0)
local ELBOW_REF=CFrame.Angles(math.rad(45),0,0)
local function solveArm(a,W,pole)
 local S=a.s0.Position
 local toW=W-S;local D=math.clamp(toW.Magnitude,math.abs(a.L1-a.L2)+.02,a.L1+a.L2-.005)
 local u=toW.Magnitude>1e-4 and toW.Unit or Vector3.new(0,1,0)
 local along=(a.L1*a.L1-a.L2*a.L2+D*D)/(2*D)
 local hgt=math.sqrt(math.max(0,a.L1*a.L1-along*along))
 local perp=pole-u*pole:Dot(u);perp=perp.Magnitude>1e-4 and perp.Unit or Vector3.new(0,0,-1)
 local E=S+u*along+perp*hgt
 local Wc=S+u*D
 -- shoulder: rest upper-arm vector -> S->E
 local c0r,c1r=a.s0.Rotation,a.s1.Rotation
 local T1=rotationBetween(SHOULDER_REF*(c1r:Inverse()*a.v1),c0r:Inverse()*(E-S).Unit)*SHOULDER_REF
 local ua=c0r*T1*c1r:Inverse() -- upper arm orientation in torso space
 -- elbow: rest forearm vector -> E->W, expressed in the upper arm's frame
 local e0r,e1r=a.e0.Rotation,a.e1.Rotation
 local T2=rotationBetween(ELBOW_REF*(e1r:Inverse()*a.v2),e0r:Inverse()*(ua:Inverse()*(Wc-E).Unit))*ELBOW_REF
 return T1,T2,E
end
-- Corridor the forearms work in: wrists within 0.5 of the centre line (a 1-stud channel in front
-- of the chest), elbows tucked in under the torso and never wider than 1.25 (a 2.5-stud box).
-- (R27: hands now plant at about shoulder width - they used to meet under the chin, which read as
-- the hands being glued together from another player's view; still well inside a 3-stud duct)
local ARM_CORRIDOR,ELBOW_BOX=.95,1.5
local function proneArms(r,c,phase,move,weight,dt)
 if weight<=.001 then r.armSmooth=nil;return end
 r.armSmooth=r.armSmooth or {}
 r.arms=r.arms or {}
 for _,side in {1,-1}do
  local a=r.arms[side]
  if not a or not a.sh.Parent or not a.el.Parent then a=armRig(c,side);r.arms[side]=a end
  if a then
   local ut=c:FindFirstChild('UpperTorso')
   local depth=ut and ut.Size.Z or 1
   local S=a.s0.Position
   local floorZ=-depth/2-.12 -- chest just off the floor, propped on the forearms
   local w=(phase/(2*math.pi))%1
   local f=.5+(pullCurve(w)-.5)*move
   -- slow up-and-down sway: the hands rise in a soft arc as they reach forward and settle back
   -- onto the floor to pull, the whole arm lifting and dipping with the cadence
   local recover=w<REACH_END and math.sin(w/REACH_END*math.pi) or 0
   local heave=.03*math.sin(phase-math.pi/2)*move
   local reach=(a.L1+a.L2)*.9
   local yBack=S.Y+.35;local yFront=S.Y+math.max(.6,reach-.25)
   local W=Vector3.new(side*math.min(.72,ARM_CORRIDOR-.08),yBack+(yFront-yBack)*f,floorZ+.1+.15*recover*move+heave)
   -- torch on: the right hand stops pulling and holds the light out ahead, just off the duct floor,
   -- bobbing slightly with the body (the torch model is held in the RightHand, so it points up the duct)
   local lw=side>0 and (r.lightW or 0) or 0
   if lw>.001 then
    local bob=.04*math.sin(phase*2)*move
    local hold=Vector3.new(side*.5,S.Y+reach*.93,floorZ+.42+bob)
    W=W:Lerp(hold,lw)
   end
   -- elbows: back along the ribs and in under the chest
   local pole=Vector3.new(side*.35,-1,-.45).Unit -- elbows out to the sides, like a real army crawl
   local T1,T2,E=solveArm(a,W,pole)
   -- keep the elbow inside the 2.5-stud box (pull it toward the centre if a wide avatar pushes it out)
   if math.abs(E.X)>ELBOW_BOX then
    T1,T2,E=solveArm(a,W,Vector3.new(-side*1.6,-1,-.2).Unit)
   end
   -- every joint glides toward its solved angle (frame-rate independent), so even a sudden change
   -- in pace can never make a hand twitch
   local function set(m,t)
    if not m.Parent then return end
    local prev=r.armSmooth[m]
    local s=prev and prev:Lerp(t,1-math.exp(-(dt or 1/60)*13)) or t
    r.armSmooth[m]=s
    pcall(function()m.Transform=weight>=.999 and s or m.Transform:Lerp(s,weight)end)
   end
   set(a.sh,T1);set(a.el,T2)
   -- hand flat on the sheet metal, fingers forward
   set(a.wr,CFrame.Angles(math.rad((-10+12*f)*(1-lw)),0,0))
  end
 end
end
local function climbPose(u,phase,light)
 for i=1,#CLIMB_KEYS-1 do
  local a,b=CLIMB_KEYS[i],CLIMB_KEYS[i+1]
  if u<=b[1] then return blend(a[2],b[2],smooth((u-a[1])/(b[1]-a[1])))end
 end
 local last=CLIMB_KEYS[#CLIMB_KEYS]
 return blend(last[2],crawlPose(phase,0,light),smooth((u-last[1])/(1-last[1])))
end
-- crawl joint limits (degrees): {pitch min, pitch max, |yaw| max, |roll| max}
local CRAWL_LIMITS={
 root={-92,5,4,4},waist={-10,10,4,4},neck={0,75,4,6},
 lsh={0,165,8,40},rsh={0,165,8,40},lel={0,90,4,4},rel={0,90,4,4},
 -- legs trail straight back: tiny flutter only, nothing kicks up at the duct roof
 lhip={-5,20,48,22},rhip={-5,20,48,22},lknee={-50,0,4,4},rknee={-50,0,4,4},
}
local FIT_PARAMS=RaycastParams.new();FIT_PARAMS.FilterType=Enum.RaycastFilterType.Exclude;FIT_PARAMS.RespectCanCollide=true
function Controller:_Pose(p,t)
 local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 if not h or not root or h.Health<=0 then self._rigs[p]=nil;return end
 local k,_,style,g=knockAmount(p,t)
 local r=self._rigs[p]
 -- crawling through a vent (EHInVent): eases into a low prone crawl whose arms and legs move with
 -- your speed. The frame time comes from the local clock (the server clock is corrected now and then,
 -- and a step in it made every limb twitch).
 local now=os.clock()
 local dt=r and r.lastC and math.clamp(now-r.lastC,0,.1) or 0
 if r then r.lastC=now end
 -- lying down: only ever inside a duct (the local player's own state is used straight away)
 local lying=p:GetAttribute('EHInVent')~=nil or (p==self._player and Crawl.state=='Vent')
 local crawlTarget=lying and 1 or 0
 local crawlW=r and r.crawlW or 0
 if crawlW<.001 and crawlTarget==0 and k<.001 and not g then if r then r.lift=0;r.crawlW=0 end;return end
 if not r or r.c~=c then local j,parts=rig(c);r={c=c,j=j,parts=parts,lift=0,crawlW=0,lastC=now};self._rigs[p]=r end
 r.crawlW=crawlW+(crawlTarget-crawlW)*(1-math.exp(-dt*7));if math.abs(r.crawlW-crawlTarget)<.002 then r.crawlW=crawlTarget end
 local pose
 local ventAt=p:GetAttribute('EHVentAt')
 local climbU=p:GetAttribute('EHInVent')~=nil and type(ventAt)=='number' and (t-ventAt)/CLIMB_SECONDS or nil
 -- the torch arm comes up (and goes back down) smoothly when the flashlight is switched
 r.lightW=(r.lightW or 0)+(((p:GetAttribute('EHFlashlightOn')==true) and 1 or 0)-(r.lightW or 0))*(1-math.exp(-dt*8))
 if climbU and climbU>=0 and climbU<1 then
  -- climbing in: crouch, spring up, catch the lip, haul over it, fold into the crawl
  pose=climbPose(climbU,r.crawlPhase or 0,r.lightW)
  k,g,style=1,nil,'Climb'
  -- the lip takes the climber's weight with a dull metal knock everyone nearby hears
  if r.climbFor~=ventAt then
   r.climbFor=ventAt
   local knock=math.max(0,ventAt+CLIMB_SECONDS*.6-t)
   task.delay(knock,function()
    if not root.Parent then return end
    local snd=Instance.new('Sound');snd.Name='VentClimb';snd.SoundId='rbxassetid://9116642648';snd.Volume=.45;snd.PlaybackSpeed=1.2
    snd.RollOffMinDistance=4;snd.RollOffMaxDistance=45;snd.Parent=root;snd:Play();game:GetService('Debris'):AddItem(snd,3)
   end)
  end
 elseif r.crawlW>.001 then
  local v=root.AssemblyLinearVelocity;local speed=Vector3.new(v.X,0,v.Z).Magnitude
  -- (tiny physics creep while lying still is not crawling: below this the body is perfectly still)
  if speed<.4 then speed=0 end
  -- smoothed speed so the limbs don't twitch with every tiny change in velocity
  r.crawlSpeed=(r.crawlSpeed or 0)+(speed-(r.crawlSpeed or 0))*(1-math.exp(-dt*6))
  -- slow, even pushes: about one push of each foot per stud and a half of sliding
  -- heavy and slow: about one full elbow-knee cycle per 1.9 s at the duct crawl speed
  -- one two-arm pull per ~1.3 s at the duct crawl speed (5)
  r.crawlPhase=(r.crawlPhase or 0)+dt*math.clamp(r.crawlSpeed,0,8)*.78
  local move=math.clamp(r.crawlSpeed/4,0,1)
  pose=blend(ZERO,crawlPose(r.crawlPhase,move,r.lightW),smooth(r.crawlW))
  -- (lying still means still: no idle breathing sway - the body, the arms and the head-cam only
  -- move while you actually crawl)
  -- constrained joints: every limb angle is kept inside a safe range for a 3x3 / 4x4 duct and then
  -- eased frame-rate independently toward the target, so no joint can ever pop or jitter
  for key,lim in CRAWL_LIMITS do
   local a=pose[key];if a then a[1]=math.clamp(a[1],lim[1],lim[2]);a[2]=math.clamp(a[2],-lim[3],lim[3]);a[3]=math.clamp(a[3],-lim[4],lim[4])end
  end
  r.crawlSmooth=r.crawlSmooth and blend(r.crawlSmooth,pose,1-math.exp(-dt*11)) or pose
  pose=r.crawlSmooth
  k,g,style=1,nil,'Crawl'
 else
  pose=(style=='Crash' and g) and getUpPose(g) or (style=='Slip' and g) and slipPose(g) or blend(ZERO,LIE,k)
 end
 if style~='Crawl' then r.crawlSmooth=nil end
 local base=h:GetAttribute('EHStandingHipHeight')or h.HipHeight
 -- Floor fit: the lowest point of the body (last frame's pose) is seated exactly on the floor
 -- under you, so a fall never sinks halfway into the floor (or hovers over it), whatever the
 -- avatar's proportions. While falling it only ever lifts; once down it also lowers.
 local floorY
 local players={};for _,o in Players:GetPlayers()do if o.Character then table.insert(players,o.Character)end end
 FIT_PARAMS.FilterDescendantsInstances=players
 local hit=workspace:Raycast(root.Position,Vector3.new(0,-(base+root.Size.Y/2+3),0),FIT_PARAMS)
 if hit then floorY=hit.Position.Y end
 -- (no floor fit while hanging off the vent lip mid-climb)
 if floorY and #r.parts>0 and style~='Climb' then
  local lowest=math.huge
  for _,part in r.parts do
   if part.Parent then
    -- each body part as the ellipsoid inside its box (limbs and torsos are rounded, and avatar
    -- part boxes are often much fatter than the mesh, so the box corners would float the body)
    local cf,s=part.CFrame,part.Size
    local reach=math.sqrt((cf.RightVector.Y*s.X/2)^2+(cf.UpVector.Y*s.Y/2)^2+(cf.LookVector.Y*s.Z/2)^2)
    lowest=math.min(lowest,cf.Position.Y-reach)
   end
  end
  local err=(floorY+.03)-lowest
  local settled=g~=nil or k>.85 or style=='Crawl'
  if err>0 or settled then
   -- crawling: eased toward the fit at a frame-rate independent rate (no per-frame overshoot, so
   -- the body never shimmers up and down on the duct floor); falls keep the quick catch-up
   local gain=style=='Crawl' and (1-math.exp(-dt*10)) or .8
   r.lift=math.clamp(r.lift+err*gain,-1.5,2.5)
  end
  -- standing again: hand the height back to the Humanoid
  if g and g>.9 then r.lift*=1-smooth((g-.9)/.1) end
 else r.lift=0 end
 local drop=(base+root.Size.Y/2-.62)*pose.drop
 -- In the duct the crawl owns the limbs: the Animator's walk/idle swing is faded out underneath
 -- it (otherwise the arm swing of the walk cycle throws the elbows out into the duct walls).
 local keep=style=='Crawl' and 1-smooth(r.crawlW) or 1
 local function base_(t)return keep<1 and CFrame.identity:Lerp(t,keep) or t end
 local function apply(joint,v)if joint and joint.Parent then pcall(function()joint.Transform=CFrame.Angles(math.rad(v[1]),math.rad(v[2]),math.rad(v[3]))*base_(joint.Transform)end)end end
 local j=r.j
 -- Root translation is in the root's frame: down to the floor and a little backward, then the pitch.
 if j.Root and j.Root.Parent then
  local rv=pose.root
  pcall(function()j.Root.Transform=CFrame.new(0,-drop+r.lift,pose.z)*CFrame.Angles(math.rad(rv[1]),math.rad(rv[2]),math.rad(rv[3]))*base_(j.Root.Transform)end)
 end
 apply(j.Waist,pose.waist)
 apply(j.LeftHip,pose.lhip);apply(j.RightHip,pose.rhip);apply(j.LeftKnee,pose.lknee);apply(j.RightKnee,pose.rknee)
 apply(j.LeftShoulder,pose.lsh);apply(j.RightShoulder,pose.rsh);apply(j.LeftElbow,pose.lel);apply(j.RightElbow,pose.rel)
 apply(j.Neck,pose.neck)
 -- prone swim pull: the arms are solved (IK) inside the corridor, blended in over the climb's end
 if style=='Crawl' then
  r.ikW=(r.ikW or 0)+(1-(r.ikW or 0))*(1-math.exp(-dt*8))
  local move=math.clamp((r.crawlSpeed or 0)/4,0,1)
  proneArms(r,c,r.crawlPhase or 0,move,r.ikW*smooth(r.crawlW),dt)
  -- feet: toes tuck as the knees draw up, point back as the legs push straight
  local lw=((r.crawlPhase or 0)/(2*math.pi))%1
  local ld=legDraw(lw)*move*r.ikW
  for _,n in {'LeftFoot','RightFoot'}do
   local foot=c:FindFirstChild(n);local ank=foot and foot:FindFirstChild((n:gsub('Foot','Ankle')))
   if ank and (ank:IsA('Motor6D') or ank:IsA('AnimationConstraint')) then pcall(function()ank.Transform=CFrame.Angles(math.rad(-25+35*ld),0,0)end)end
  end
  r.pull=pullCurve(((r.crawlPhase or 0)/(2*math.pi))%1)
 else r.ikW=0;r.pull=nil end
end
------------------------------------------------------------------ local camera
function Controller:_ReleaseSlip(p)
 local s=self._slipLock;self._slipLock=nil
 if not s then return end
 if s.root and s.root.Parent then s.root.Anchored=s.anchored==true end
 if s.h.Parent then
  s.h.JumpHeight=s.jumpHeight;s.h.JumpPower=s.jumpPower;s.h.AutoRotate=s.autoRotate
  -- the server owns walk speed but only replicates changes, so never leave our local 0 behind
  if s.h.WalkSpeed<=0 then local M=require(Shared.Config.MovementConfig);s.h.WalkSpeed=p:GetAttribute('EHCrouching') and M.CrouchSpeed or M.WalkSpeed end
 end
 if self._controls and not self._mopLock then pcall(function()self._controls:Enable()end)end
end
-- Mopping lock: while MOP UP is being held on a spill the player stays planted (no walking,
-- strafing or jumping; looking around is still free). Movement comes back the moment the hold is
-- released, cancelled or the spill is finished. Shares the movement controls with the slip lock.
function Controller:_MopLock()
 local p=self._player;local c=p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 local mopping=h~=nil and root~=nil and h.Health>0
  and tostring(p:GetAttribute('EHActiveInteraction')or ''):sub(1,8)=='BW5Spill'
  and p:GetAttribute('EHInteractionState')=='Holding'
 if mopping then
  if not self._mopLock or self._mopLock.h~=h then
   self._mopLock={h=h,jumpHeight=h.JumpHeight,jumpPower=h.JumpPower}
   pcall(function()
    local ps=p:FindFirstChild('PlayerScripts');local mod=ps and ps:FindFirstChild('PlayerModule');if not mod then return end;local pm=require(mod)
    self._controls=self._controls or pm:GetControls();self._controls:Disable()
   end)
  end
  h.WalkSpeed=0;h.JumpHeight=0;h.JumpPower=0;h.Jump=false;h:Move(Vector3.zero)
  local v=root.AssemblyLinearVelocity;root.AssemblyLinearVelocity=Vector3.new(0,math.min(v.Y,0),0)
 elseif self._mopLock then
  local m=self._mopLock;self._mopLock=nil
  if m.h.Parent then
   m.h.JumpHeight=m.jumpHeight;m.h.JumpPower=m.jumpPower
   if m.h.WalkSpeed<=0 and not self._slipLock then local M=require(Shared.Config.MovementConfig);m.h.WalkSpeed=p:GetAttribute('EHCrouching') and M.CrouchSpeed or M.WalkSpeed end
  end
  -- the slip lock keeps the controls off if the player is also down
  if self._controls and not self._slipLock then pcall(function()self._controls:Enable()end)end
 end
end
-- First person through the crash: the camera rides on your head, so the view follows the body
-- exactly as it lies on the floor looking up, nods, sits up, rolls onto a knee and stands. Your own
-- body is shown (not the head) so you see your legs and hands as you get up. The last stretch eases
-- back into the normal camera with no snap.
-- on: true/false, or a number 0..1 = how hidden the body is (fades out instead of popping)
function Controller:_ShowBody(on)
 local c=self._player.Character;if not c then self._bodyShown=false;return end
 local hide=type(on)=='number' and math.clamp(on,0,1) or (on and 0 or 1)
 -- (your hands and legs come into view with the picture as the eyes open, never ahead of it)
 hide=math.max(hide,ScreenFade.Black())
 for _,n in BODY do local part=c:FindFirstChild(n);if part and part:IsA('BasePart') and n~='Head' then part.LocalTransparencyModifier=hide end end
 self._bodyShown=hide<1
end
function Controller:_CrashCamera(camera,c,h,k,g,t,style)
 local head=c and c:FindFirstChild('Head')
 local active=head and h and h.Health>0 and (k>.001 or (g and g<1)) and camera.CameraType==Enum.CameraType.Custom
 if not active then if self._bodyShown then self:_ShowBody(false)end;return end
 local base=camera.CFrame;self._cameraBase=base
 -- just in front of the eyes, looking where the face looks
 local eye=head.CFrame*CFrame.new(0,.12,-.28)
 -- a slow, dazed drift while you lie there (fades as you come round)
 local daze=g and (1-g) or 1
 local drift=CFrame.Angles(math.sin(t*.7)*.025*daze,math.sin(t*.53+1)*.03*daze,math.sin(t*.41+2)*.02*daze)
 local view=eye*drift
 -- going down: the view tips from where you were looking into the head-cam as you fall (no snap)
 if not g and k<1 then view=base:Lerp(view,smooth(k)) end
 -- Control comes back gradually: from partway through getting up, your own look (mouse / stick /
 -- touch) blends in more and more while the body-driven view eases out, so there is no moment
 -- where it visibly hands over.
 local w=g and smooth((g-.45)/.55) or 0
 w=w*w*(3-2*w)
 -- after a slip the head shake is felt in the view too: the head-cam keeps part of the say until the
 -- shake has died away, then hands over completely
 if style=='Slip' and g and g>1-SLIP_SHAKE then
  local sh=(g-(1-SLIP_SHAKE))/SLIP_SHAKE
  w=math.min(w,.45+.55*smooth(sh))
 end
 camera.CFrame=w>0 and view:Lerp(base,w) or view
 self:_ShowBody(w)
end
function Controller:_RestoreCamera()
 local camera=workspace.CurrentCamera
 if self._cameraBase and camera then camera.CFrame=self._cameraBase end
 self._cameraBase=nil
end
function Controller:_Camera(dt)
 local camera=workspace.CurrentCamera;if not camera then return end
 local p=self._player;local t=workspace:GetServerTimeNow()
 local k,impact,style,g=knockAmount(p,t)
 local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
 -- Impact: strip the remaining momentum once.
 local at=p:GetAttribute('EHKnockedAt')
 if at and at~=self._lastKnock then
  self._lastKnock=at
  if root and t-at<1 then local v=root.AssemblyLinearVelocity;root.AssemblyLinearVelocity=Vector3.new(0,math.min(v.Y,0),0);if h then h:Move(Vector3.zero)end end
 end
 -- Total control lock for the whole slip (fall, lying there, and the first half of getting up):
 -- no walking, no jumping, no turning, every movement input (keys, stick, touch pad) switched off.
 local t0,t1=p:GetAttribute('EHKnockedAt'),p:GetAttribute('EHKnockedUntil')
 -- (the crash keeps you locked through the whole get-up)
 -- (a slip keeps you locked through the whole get-up and nearly all of the head shake)
 local locked=h~=nil and root~=nil and type(t0)=='number' and type(t1)=='number' and t>=t0 and t<t1+(style=='Crash' and GETUP or SLIP_RISE*.93)
 if locked then
  if self._slipLock and self._slipLock.h~=h then self:_ReleaseSlip(p)end
  if not self._slipLock then
   -- the view direction at the moment of the fall is held for the whole lock (mouse, stick and
   -- touch look are all discarded), so the camera cannot be turned while you are down
   self._slipLock={h=h,root=root,jumpHeight=h.JumpHeight,jumpPower=h.JumpPower,autoRotate=h.AutoRotate,look=camera.CFrame.Rotation,anchored=root.Anchored}
   pcall(function()
    local ps=p:FindFirstChild('PlayerScripts');local mod=ps and ps:FindFirstChild('PlayerModule');if not mod then return end;local pm=require(mod)
    self._controls=self._controls or pm:GetControls();self._controls:Disable()
   end)
  end
  h.WalkSpeed=0;h.JumpHeight=0;h.JumpPower=0;h.AutoRotate=false;h.Jump=false;h:Move(Vector3.zero)
  -- the crash: while the screen is black the server turns everyone to face the lift doors
  -- (EHCrashFacing); the held view turns with the body, so you come round looking at the doors
  local facing=style=='Crash' and p:GetAttribute('EHCrashFacing')
  if typeof(facing)=='Vector3' and self._slipLock.faced~=facing then
   self._slipLock.faced=facing
   local flat=Vector3.new(facing.X,0,facing.Z)
   if flat.Magnitude>.1 then
    self._slipLock.look=CFrame.lookAt(Vector3.zero,flat.Unit).Rotation
    if root.Anchored then root.CFrame=CFrame.lookAt(root.Position,root.Position+flat.Unit) end
   end
  end
  local v=root.AssemblyLinearVelocity
  root.AssemblyLinearVelocity=Vector3.new(0,math.min(v.Y,0),0);root.AssemblyAngularVelocity=Vector3.zero
  -- pinned in place once on the ground: no sliding, nudging or turning at all
  if not root.Anchored and h.FloorMaterial~=Enum.Material.Air then root.Anchored=true end
  -- (getting up after the crash: your own look is allowed back in, see _CrashCamera)
  if not (g and g>.45) then
   camera.CFrame=CFrame.new(camera.CFrame.Position)*self._slipLock.look
   self._cameraBase=camera.CFrame
  end
 elseif self._slipLock then
  self:_ReleaseSlip(p)
 end
 local cc=self._grade
 -- (a slip uses the same head-cam: the view rides your head down, through the get-up and the head
 -- shake, and hands back to your own look as you stand)
 if style=='Crash' or style=='Slip' then
  if cc.Enabled then cc.Enabled=false end
  self:_CrashCamera(camera,c,h,k,g,t,style)
  return
 end
 if self._bodyShown then self:_ShowBody(false) end
 if k<.001 or camera.CameraType~=Enum.CameraType.Custom then if cc.Enabled then cc.Enabled=false end;return end
 local base=camera.CFrame;self._cameraBase=base
 local look=base.LookVector;local flat=Vector3.new(look.X,0,look.Z);flat=flat.Magnitude>.01 and flat.Unit or Vector3.new(0,0,-1)
 local eye=(h and (h:GetAttribute('EHStandingHipHeight')or h.HipHeight)or 2.6)+(root and root.Size.Y/2 or 1)+.4
 local pos=base.Position-Vector3.new(0,(eye-1.25)*k,0)-flat*.8*k
 local shake=impact*.06
 -- Flat on your back: whatever you were looking at, the view swings up toward the ceiling
 -- (an absolute pitch, so it reads the same even if you were looking at the floor).
 local yaw=math.atan2(-look.X,-look.Z);local pitch=math.asin(math.clamp(look.Y,-1,1))
 local lying=pitch+(math.rad(72)-pitch)*k
 local rot=CFrame.fromEulerAnglesYXZ(lying+math.sin(t*61)*shake,yaw+math.sin(t*47)*shake,0)*CFrame.Angles(0,0,math.rad(11)*k)
 camera.CFrame=CFrame.new(pos)*rot
 cc.Enabled=true;cc.Brightness=-.12*impact-.03*k;cc.Saturation=-.35*k;cc.Contrast=.08*k
end
------------------------------------------------------------------ first-person mop
-- The mop is a first-person view model in the LEFT hand, held by the rubber grip at the top of the
-- handle. It is one rigid model drawn at its TRUE size the whole time, so the shaft can never
-- stretch, shrink or slide through the hand. Two poses, blended by a slow, heavy spring:
--  * HOLD: the (unseen) left hand holds the grip at the lower left of the view and the shaft leans
--    away from you, the head hanging down ahead (screen fractions, so it frames the same on every
--    aspect ratio).
--  * MOP UP: the hand stays exactly where it is and the head is swung down onto the REAL floor
--    (raycast) at the one distance the fixed shaft length allows, sweeping side to side in slow,
--    weighty strokes.
-- The model stays in your hand through a slip and fall (it rolls with the camera).
-- Rendering: the view model is drawn as a tiny copy just in front of the lens, placed so it covers
-- exactly the same pixels as the full-size mop would. Nothing in the world can come between the
-- lens and it, so walls, pipes or the floor never cut into it. Against a wall it is stowed
-- (EHWallStow, shared with the flashlight and carried items).
local GRIP_ALONG,CLAMP_ALONG=2.2,-3.0          -- along the shaft from the Handle centre: hand grip, head clamp
local GRIP_TO_CLAMP=GRIP_ALONG-CLAMP_ALONG     -- 5.2 studs, fixed
local GRIP={depth=1.95,x=-.7,y=-.52}          -- where the left hand holds the grip (screen fractions at depth); a little
                                              -- closer than before (was 2.3) so the mop reads bigger in your hand
local EQUIP_SECONDS=.4                        -- picking a mop up: it rises into view; putting it back: it lowers out
local EQUIP_DROP=1.3                          -- how far below its hold pose it starts / ends (screen fraction)
local HOLD_DIR=Vector3.new(.06,.62,.78).Unit   -- view space, clamp -> grip: head hanging down ahead
-- real size of the drawn copy. Not smaller: the top of the 5.6-stud handle reaches back toward the
-- lens, and at .05 its copy fell inside the camera's near clip plane (~0.1 studs), so the visible
-- length of the wooden bar changed as it moved (it looked like it stretched and shrank). At .12
-- the whole rod stays well in front of the clip plane and keeps exactly the same length.
local MODEL_SCALE=.12
local STROKE=4.6                               -- rad/s: slow, heavy scrubbing strokes
local CLAMP_ABOVE_FLOOR=.45                    -- carrying: the clamp rides this far off the floor
-- The strands hang 0.87 studs down the shaft from the head clamp (measured on the rack mop). While
-- mopping, the clamp is held exactly high enough that the strand tips sit ON the water: the higher
-- the shaft is tilted up, the more of that length points down.
local STRAND=.87
local function clampLift(dirY,scale)return STRAND*(scale or 1)*math.clamp(dirY,.2,1)-.02 end
-- Smoothing: the pose is solved every frame, then eased toward in VIEW space by a critically
-- damped spring. Holding, the target never moves relative to the lens (still locked 1:1 when
-- you turn). Mopping, the head is planted on the puddle in the world, so a sudden camera jerk
-- moves the target across the screen; the spring carries the mop there fluidly instead of
-- popping. Softer while mopping (heavy, wet mop), stiff while just holding.
local VM_SPRING_HOLD,VM_SPRING_MOP=32,11      -- rad/s (critically damped)
local function springTo(x,v,target,w,dt)
 local delta=x-target
 local e=math.exp(-w*dt)
 local t=(v+delta*w)*dt
 return target+(delta+t)*e,(v-t*w)*e
end
-- Height of the water you are mopping (the top of its highest disc), cached per spill.
function Controller:_WaterTop(spill)
 self._waterTops=self._waterTops or {}
 local y=self._waterTops[spill]
 if y then return y end
 local water=spill.Parent and spill.Parent:FindFirstChild('Water')
 y=spill.Position.Y+spill.Size.Y/2
 if water then
  local top=-math.huge
  for _,p in water:GetChildren()do if p:IsA('BasePart') then top=math.max(top,p.Position.Y+math.min(p.Size.X,p.Size.Y,p.Size.Z)/2) end end
  if top>-math.huge then y=top end
 end
 self._waterTops[spill]=y
 return y
end
function Controller:_SpillSurface(id)
 if type(id)~='string' or id:sub(1,8)~='BW5Spill' then return nil end
 self._spillParts=self._spillParts or {}
 local part=self._spillParts[id]
 if part and part.Parent then return part end
 local runtime=workspace:FindFirstChild('Runtime')
 if runtime then for _,d in runtime:GetDescendants()do
  if d:IsA('BasePart') and d:GetAttribute('EHInteractionId')==id then self._spillParts[id]=d;return d end
 end end
 return nil
end
-- Anything a player carries (the mop, the fuse) is hidden on their body while they are inside a
-- vent, for everyone watching, and comes back the moment they climb out. (Your own third-person
-- copies are always hidden from you; you see the first-person view models instead.)
function Controller:_VentItems(p)
 local c=p.Character;if not c then return end
 local inVent=p:GetAttribute('EHInVent')~=nil
 local hide=(p==self._player or inVent) and 1 or 0
 for _,name in {'HeldMop','CarriedObjective'}do
  local m=c:FindFirstChild(name)
  if m then for _,d in {m,table.unpack(m:GetDescendants())}do
   if d:IsA('BasePart') and d.LocalTransparencyModifier~=hide then d.LocalTransparencyModifier=hide
   elseif d:IsA('SurfaceGui') and d.Enabled~=(hide==0) then d.Enabled=hide==0 end -- (Nov 3: the keycard's printing hides with it)
  end end
 end
end
function Controller:_ViewModel(dt)
 local p=self._player;local c=p.Character;local camera=workspace.CurrentCamera
 local held=c and c:FindFirstChild('HeldMop')
 local root=c and c:FindFirstChild('HumanoidRootPart');local h=c and c:FindFirstChildOfClass('Humanoid')
 -- (never inside a vent: nothing you carry is drawn while you crawl)
 local show=held and root and h and h.Health>0 and camera and camera.CameraType==Enum.CameraType.Custom and self._input:GetContext()=='ActiveFloor' and p:GetAttribute('EHInVent')==nil
 if held then for _,d in held:GetDescendants()do if d:IsA('BasePart') and d.LocalTransparencyModifier~=1 then d.LocalTransparencyModifier=1 end end end
 -- the third-person copy of a carried objective (and its detail parts) is for other players only
 local carried=c and c:FindFirstChild('CarriedObjective')
 -- (Nov 3: the copy itself too, not only its detail parts, and its printing - your own keycard used to show
 -- in your left hand beside the one in your view)
 if carried then for _,d in {carried,table.unpack(carried:GetDescendants())}do
  if d:IsA('BasePart') and d.LocalTransparencyModifier~=1 then d.LocalTransparencyModifier=1
  elseif d:IsA('SurfaceGui') and d.Enabled then d.Enabled=false end
 end end
 self._vmContact=nil
 if not show then
  -- put back on the rack (the held copy is gone but you are still here): the mop lowers out of view
  -- from where it was before it disappears, instead of vanishing
  if self._vm and held==nil and self._vmSpring and root and h and h.Health>0 and camera and p:GetAttribute('EHInVent')==nil and (self._vmEquip or 0)>0 then
   self._vmEquip=math.max(0,self._vmEquip-math.clamp(dt,0,.1)/EQUIP_SECONDS)
   local e=smooth(self._vmEquip)
   local view=camera.CFrame;local s=self._vmSpring
   local pV=s.p+Vector3.new(0,-(1-e)*EQUIP_DROP*math.tan(math.rad(camera.FieldOfView)/2)*GRIP.depth,0)
   local gripW=view:PointToWorldSpace(pV);local dirW=view:VectorToWorldSpace(s.d.Magnitude>.05 and s.d.Unit or HOLD_DIR)
   local copyGrip=view.Position+(gripW-view.Position)*MODEL_SCALE
   local up=view.RightVector:Cross(dirW);if up.Magnitude<.05 then up=view.UpVector end
   self._vm:PivotTo(CFrame.fromMatrix(copyGrip,dirW,up.Unit)*self._vmRef)
   ScreenFade.ApplyToModel(self._vm,ScreenFade.ViewAlpha(),0)
   if self._vmEquip>0 then return end
  end
  if self._vm then self._vm:Destroy();self._vm=nil;self._vmSource=nil end;return
 end
 if self._vmSource~=held then
  if self._vm then self._vm:Destroy()end
  local vm=held:Clone();vm.Name='MopViewModel'
  for _,d in vm:GetDescendants()do
   if d:IsA('JointInstance') or d:IsA('WeldConstraint') then d:Destroy()
   elseif d:IsA('BasePart') then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false;d.LocalTransparencyModifier=0 end
  end
  local handle=vm:FindFirstChild('Handle')
  if not handle or not vm:IsA('Model') then vm:Destroy();return end
  vm:ScaleTo(MODEL_SCALE) -- absolute: the hand-held copy may be drawn smaller in third person
  -- one rigid frame at the hand grip on the shaft (X = toward the top end), so every part keeps
  -- its exact offset and the head can never separate from the stick
  local axis=handle.CFrame.RightVector
  local gripPoint=handle.Position+axis*(GRIP_ALONG*MODEL_SCALE)
  self._vmRef=CFrame.fromMatrix(gripPoint,axis,handle.CFrame.UpVector):ToObjectSpace(vm:GetPivot())
  vm.Parent=camera;self._vm=vm;self._vmSource=held;self._scrub=0;self._vmPhase=0;self._sweep=0;self._vmSpring=nil;self._sweepAxis=nil
  self._vmEquip=0 -- (rises up into the hand: see EQUIP_SECONDS)
  self._vmHidden=false
 end
 dt=math.clamp(dt,0,.1)
 -- solved relative to the camera each frame (then eased, below)
 local view=camera.CFrame
 local cleaning=tostring(p:GetAttribute('EHActiveInteraction')or ''):sub(1,8)=='BW5Spill' and p:GetAttribute('EHInteractionState')=='Holding'
 self._scrub+=((cleaning and 1 or 0)-self._scrub)*(1-math.exp(-dt*7))
 local k=smooth(self._scrub)
 local stow=math.clamp(p:GetAttribute('EHWallStow') or 0,0,1)*(1-k)
 local tangent=math.tan(math.rad(camera.FieldOfView)/2)
 local horizontal=tangent*math.clamp(camera.ViewportSize.X/math.max(1,camera.ViewportSize.Y),.45,2.5)
 -- slow, heavy walking bob of the hand
 self._bob=self._bob or require(game.ReplicatedStorage.Game.Shared.Utilities.HeldSway).new() -- shared held-item motion
 local bobX,bobY,moving=self._bob:Bob(dt,root)
 local d=GRIP.depth
 self._vmEquip=math.min(1,(self._vmEquip or 1)+dt/EQUIP_SECONDS)
 local rise=(1-smooth(self._vmEquip))*EQUIP_DROP
 local gripV=Vector3.new((GRIP.x+bobX)*horizontal*d,(GRIP.y+bobY-stow*1.1-rise)*tangent*d,-d)
 local gripW=view:PointToWorldSpace(gripV)
 local dirW=view:VectorToWorldSpace(HOLD_DIR)
 if k>.001 then
  -- MOP UP: the head is put down dead-centre on the puddle being mopped (on its surface) and swept
  -- across it in slow strokes; the hand follows the fixed shaft back up toward its usual place
  -- (off the bottom-left of the screen if it has to), so the head never floats beside the water.
  self._sweep+=dt*STROKE*(.35+.65*k)
  local spill=self:_SpillSurface(p:GetAttribute('EHActiveInteraction'))
  -- the stroke axis is fixed in the WORLD (from you to the puddle), not to the camera, so
  -- looking around while mopping never throws the head across the puddle
  local look=view.LookVector;local flat=Vector3.new(look.X,0,look.Z)
  if spill then local toSpill=spill.Position-root.Position;toSpill=Vector3.new(toSpill.X,0,toSpill.Z);if toSpill.Magnitude>.3 then flat=toSpill end end
  flat=flat.Magnitude>.05 and flat.Unit or Vector3.new(root.CFrame.LookVector.X,0,root.CFrame.LookVector.Z).Unit
  self._sweepAxis=self._sweepAxis and self._sweepAxis:Lerp(flat,1-math.exp(-dt*4)).Unit or flat
  flat=self._sweepAxis
  local right=flat:Cross(Vector3.yAxis)
  local params=self._vmParams
  if not params then params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.RespectCanCollide=true;self._vmParams=params end
  params.FilterDescendantsInstances={c,camera}
  local centre,surfaceY
  if spill then
   centre=spill.Position;surfaceY=self:_WaterTop(spill)
  else
   centre=root.Position+flat*3
   local hit=workspace:Raycast(centre+Vector3.new(0,2.5,0),Vector3.new(0,-9,0),params)
   surfaceY=hit and hit.Position.Y or root.Position.Y-((h:GetAttribute('EHStandingHipHeight')or h.HipHeight)+root.Size.Y/2)
  end
  -- strokes across the puddle, left-right relative to the view, with a little push and pull
  local across=right*math.sin(self._sweep)*.9+flat*math.sin(self._sweep*2)*.25
  local contact=Vector3.new(centre.X,surfaceY,centre.Z)+across
  -- the strand tips land on the water plane (two passes: the lift depends on the shaft angle)
  local headW=contact+Vector3.new(0,CLAMP_ABOVE_FLOOR,0)
  for _=1,2 do
   local d=gripW-headW
   if d.Magnitude<.05 then break end
   headW=contact+Vector3.new(0,clampLift(math.max(d.Unit.Y,.35)),0)
  end
  local toHand=gripW-headW;if toHand.Magnitude<.05 then toHand=Vector3.yAxis end
  local cleanDir=toHand.Unit
  -- keep the shaft at least a little upright so the hand never ends up below the head
  if cleanDir.Y<.35 then cleanDir=(Vector3.new(cleanDir.X,0,cleanDir.Z).Unit*.94+Vector3.new(0,.35,0)).Unit end
  local cleanGrip=headW+cleanDir*GRIP_TO_CLAMP
  self._vmContact=k>.35 and contact or nil
  gripW=gripW:Lerp(cleanGrip,k)
  dirW=dirW:Lerp(cleanDir,k).Unit
 else self._sweep=0;self._sweepAxis=nil end
 -- ease the solved pose in view space (see VM_SPRING): no popping when the camera jerks
 do
  local tp,td=view:PointToObjectSpace(gripW),view:VectorToObjectSpace(dirW)
  local s=self._vmSpring
  if not s or (s.p-tp).Magnitude>6 then s={p=tp,v=Vector3.zero,d=td,dv=Vector3.zero};self._vmSpring=s end
  local w=VM_SPRING_HOLD+(VM_SPRING_MOP-VM_SPRING_HOLD)*k
  s.p,s.v=springTo(s.p,s.v,tp,w,dt)
  s.d,s.dv=springTo(s.d,s.dv,td,w,dt)
  gripW=view:PointToWorldSpace(s.p)
  if s.d.Magnitude>.05 then dirW=view:VectorToWorldSpace(s.d.Unit) end
 end
 -- the MODEL_SCALE copy at MODEL_SCALE x the distance covers the same pixels as the full-size mop
 local copyGrip=view.Position+(gripW-view.Position)*MODEL_SCALE
 local up=view.RightVector:Cross(dirW);if up.Magnitude<.05 then up=view.UpVector end
 self._vm:PivotTo(CFrame.fromMatrix(copyGrip,dirW,up.Unit)*self._vmRef)
 -- stowed against a wall = hidden; otherwise it fades in and out with the picture (black covers,
 -- HUD reveal) so it never pops in or shows as a dark shape over a black screen
 local hidden=stow>.97
 self._vmHidden=hidden
 ScreenFade.ApplyToModel(self._vm,ScreenFade.ViewAlpha(),hidden and 1 or 0)
end
------------------------------------------------------------------ scrubbing (every player)
-- Splash and suds where the mop head meets the floor. Other players' mops are posed so the head
-- is really planted on the floor ahead of them (the shaft slides down through the hand and pivots
-- there), sweeping side to side in the same slow strokes.
local function fxEmitters(part)
 local at=Instance.new('Attachment',part)
 local splash=Instance.new('ParticleEmitter');splash.Name='Splash';splash.Texture='rbxasset://textures/particles/sparkles_main.dds'
 splash.Color=ColorSequence.new(Color3.fromRGB(176,196,200));splash.LightInfluence=1;splash.Rate=0
 splash.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.09),NumberSequenceKeypoint.new(1,.02)})
 splash.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,.8)})
 splash.Lifetime=NumberRange.new(.22,.36);splash.Speed=NumberRange.new(1.6,3);splash.SpreadAngle=Vector2.new(50,50)
 splash.Acceleration=Vector3.new(0,-45,0);splash.EmissionDirection=Enum.NormalId.Top;splash.Drag=1.5;splash.Parent=at
 local foam=Instance.new('ParticleEmitter');foam.Name='Suds';foam.Texture='rbxasset://textures/particles/smoke_main.dds'
 foam.Color=ColorSequence.new(Color3.fromRGB(226,232,230));foam.LightInfluence=1;foam.Rate=0
 foam.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.25),NumberSequenceKeypoint.new(1,.7)})
 foam.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.45),NumberSequenceKeypoint.new(1,1)})
 foam.Lifetime=NumberRange.new(.8,1.3);foam.Speed=NumberRange.new(.2,.7);foam.SpreadAngle=Vector2.new(80,80)
 foam.Acceleration=Vector3.new(0,.6,0);foam.EmissionDirection=Enum.NormalId.Top;foam.Rotation=NumberRange.new(0,360);foam.RotSpeed=NumberRange.new(-40,40);foam.Parent=at
 return splash,foam
end
-- Third person (every player's mop, posed on every client): the server welds the mop's rubber
-- grip into the left hand's grip attachment (MopGrip) and draws it at HeldScale, a believable
-- size for the avatar. Each frame the rigid shaft is aimed from the hand down toward the floor at
-- its fixed length, so it can never stretch or slide through the hand:
--  * carrying: the head rides just off the floor beside the left foot and swings like a pendulum
--    with the walk cycle (bigger, quicker swings when running), settling when you stop;
--  * mopping: the head is planted on the floor ahead and swept side to side in slow strokes.
function Controller:_PlantMop(c,grip,k,t,s,dt)
 local root=c:FindFirstChild('HumanoidRootPart');local h=c:FindFirstChildOfClass('Humanoid')
 if not root or not h or not grip.Part0 then grip.Transform=CFrame.identity;return nil end
 local held=grip.Part1 and grip.Part1.Parent
 local scale=held and held:GetAttribute('HeldScale') or 1
 -- the server fits the grip point to the avatar (MopGrip.C1); the head clamp is CLAMP_ALONG down the shaft
 local length=math.max(.5,grip.C1.Position.X-CLAMP_ALONG*scale)
 local joint=grip.Part0.CFrame*grip.C0
 local look=root.CFrame.LookVector;local flat=Vector3.new(look.X,0,look.Z)
 if flat.Magnitude<.05 then grip.Transform=CFrame.identity;return nil end
 flat=flat.Unit;local right=flat:Cross(Vector3.yAxis)
 local floorY=root.Position.Y-((h:GetAttribute('EHStandingHipHeight')or h.HipHeight)+root.Size.Y/2)
 -- walking pendulum, driven by ground speed so it matches the avatar's own stride
 s=s or {};dt=dt or 1/60
 local v=root.AssemblyLinearVelocity;local speed=Vector3.new(v.X,0,v.Z).Magnitude
 local moving=math.clamp(speed/12,0,1.6)
 s.swingPhase=((s.swingPhase or 0)+dt*(2.4+speed*.42))%(math.pi*2)
 s.swingAmp=(s.swingAmp or 0)+((moving*.32)-(s.swingAmp or 0))*(1-math.exp(-dt*5))
 local swing=math.sin(s.swingPhase)*s.swingAmp
 local a=math.sin(t*STROKE)*.45-.12
 -- mopping: sweep toward the puddle this player is mopping (their active interaction)
 local aim=flat
 local player=Players:GetPlayerFromCharacter(c)
 local spill=k>.01 and player and self:_SpillSurface(player:GetAttribute('EHActiveInteraction'))
 if spill then local d=spill.Position-joint.Position;d=Vector3.new(d.X,0,d.Z);if d.Magnitude>.2 then aim=d.Unit end end
 local aimRight=aim:Cross(Vector3.yAxis)
 local sweep=(aim*math.cos(a)+aimRight*math.sin(a)).Unit
 -- carrying: the mop hangs from the hand, leaning a little forward and out to the left, and
 -- rocks fore and aft with the stride; the head only touches down if the hand is low enough
 local lean=math.rad(13)+swing*.55
 local outward=(flat*math.cos(.5)-right*math.sin(.5))
 local carryDir=(-Vector3.yAxis*math.cos(lean)+(flat*math.sin(lean)+(-right)*.12)).Unit
 local carryHead=joint.Position+carryDir*length
 local minY=floorY+CLAMP_ABOVE_FLOOR*scale+.12
 if carryHead.Y<minY then
  local drop=joint.Position.Y-minY
  local out=math.sqrt(math.max(length*length-drop*drop,.01))
  carryHead=Vector3.new(joint.Position.X,minY,joint.Position.Z)+outward.Unit*out
 end
 -- cleaning: the hand slides up the handle (never past the rubber grip) far enough for the head to
 -- reach the floor at a comfortable angle, and the head is planted there
 -- planted on the water you are mopping (its real surface), strand tips touching it
 local surfaceY=spill and self:_WaterTop(spill) or floorY
 local clampY=surfaceY+CLAMP_ABOVE_FLOOR*scale
 local drop,reach
 for _=1,2 do
  drop=joint.Position.Y-clampY
  reach=math.clamp(drop*1.3,length,(GRIP_ALONG-CLAMP_ALONG)*scale)
  clampY=surfaceY+clampLift(drop/math.max(reach,.05),scale)
 end
 drop=joint.Position.Y-clampY
 reach=math.clamp(drop*1.3,length,(GRIP_ALONG-CLAMP_ALONG)*scale)
 local slide=(reach-length)*k
 local out=math.sqrt(math.max(reach*reach-drop*drop,.01))
 local cleanHead=Vector3.new(joint.Position.X,clampY,joint.Position.Z)+sweep*out
 local target=carryHead:Lerp(cleanHead,k)
 local x=(joint.Position-target).Unit
 local y=joint.YVector-x*joint.YVector:Dot(x);if y.Magnitude<.05 then y=right end
 -- slide the shaft down through the hand (along its own axis) so the planted head stays on the floor
 grip.Transform=joint:ToObjectSpace(CFrame.fromMatrix(joint.Position-x*slide,x,y.Unit))
 return k>.05 and Vector3.new(target.X,floorY,target.Z) or nil
end
function Controller:_Scrub(dt)
 local t=os.clock()
 self._scrubs=self._scrubs or {}
 for _,p in Players:GetPlayers()do
  local c=p.Character;local hand=c and (c:FindFirstChild('LeftHand')or c:FindFirstChild('Left Arm'));local grip=hand and hand:FindFirstChild('MopGrip')
  local s=self._scrubs[p]
  local cleaning=grip~=nil and tostring(p:GetAttribute('EHActiveInteraction')or ''):sub(1,8)=='BW5Spill' and p:GetAttribute('EHInteractionState')=='Holding'
  if not s then s={k=0};self._scrubs[p]=s end
  s.k+=((cleaning and 1 or 0)-s.k)*(1-math.exp(-dt*3.2))
  local contact
  if grip then contact=self:_PlantMop(c,grip,s.k*s.k*(3-2*s.k),t,s,dt)end
  if p==self._player then contact=self._vmContact end
  if s.k>.05 and contact then
   if not s.fx or not s.fx.Parent then
    local part=Instance.new('Part');part.Name='ScrubFX';part.Size=Vector3.new(.2,.2,.2);part.Transparency=1;part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false;part.Parent=workspace.CurrentCamera
    s.fx=part;s.splash,s.foam=fxEmitters(part)
   end
   s.fx.CFrame=CFrame.new(contact+Vector3.new(0,.08,0))
   s.acc=(s.acc or 0)+dt
   if s.acc>.09 then s.acc=0;s.splash:Emit(math.random(1,3))end
   s.foam.Rate=14*s.k
  elseif s.fx then s.foam.Rate=0;if s.k<.01 then s.fx:Destroy();s.fx=nil end end
 end
 for p,s in self._scrubs do if p.Parent~=Players then if s.fx then s.fx:Destroy()end;self._scrubs[p]=nil end end
end
------------------------------------------------------------------ active leaks
-- Each spill is fed by a real drip: a drop swells on the ceiling stain, lets go, falls for exactly
-- the measured drop time and lands where a ripple spreads. The leak never stops - after the floor
-- is mopped the drops keep falling onto the bare concrete.
-- Mopping (server attribute CleanedAt) dries the water away smoothly: every disc of standing
-- water shrinks back toward the drip point, then the damp edge fades. Five minutes later
-- (RefilledAt) the spill spreads back out from under the drip over a few seconds.
local DRY,DAMP,REFILL=2.8,5.5,4.5
local function ease(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
function Controller:_Water(L,zone,serverNow)
 if not L.parts then
  L.parts={}
  local water=zone.Parent:FindFirstChild('Water')
  local cx,cz=zone:GetAttribute('DripX') or zone.Position.X,zone:GetAttribute('DripZ') or zone.Position.Z
  if water then for _,p in water:GetChildren()do if p:IsA('BasePart') then
   table.insert(L.parts,{p=p,size=p.Size,cf=p.CFrame,film=p.Name=='SpillFilm',center=Vector3.new(cx,p.Position.Y,cz)})
  end end end
 end
 local cleaned=zone:GetAttribute('CleanedAt');local refilled=zone:GetAttribute('RefilledAt')
 local wet,damp=1,1
 if cleaned then
  local e=serverNow-cleaned
  wet=1-ease(e/DRY);damp=1-ease((e-.6)/DAMP)
 elseif refilled then
  local e=serverNow-refilled
  wet=ease(e/REFILL);damp=ease(e/(REFILL*.8))
 end
 -- While someone mops (server MopProgress 0..1, grows pass by pass) the water thins out and turns
 -- see-through; the eased value never jumps, and it stays faded through the drying above.
 local mop=math.clamp(zone:GetAttribute('MopProgress') or 0,0,1)
 local clock=os.clock();local dt=math.clamp(clock-(L.clock or clock),0,.1);L.clock=clock
 L.mop=(L.mop or mop)+(mop-(L.mop or mop))*(1-math.exp(-dt*7))
 if math.abs(L.mop-mop)<.002 then L.mop=mop end
 if L.wet==wet and L.damp==damp and L.mopShown==L.mop then return end
 L.wet,L.damp,L.mopShown=wet,damp,L.mop
 local m=L.mop*L.mop*(3-2*L.mop)
 for _,e in L.parts do
  local p=e.p
  if p.Parent then
   local a=e.film and damp or wet
   -- the whole puddle (one merged sheet) thins out and fades away smoothly as it is mopped and
   -- dries - no discs shrinking, so no circles ever show; the damp ring lingers a moment longer
   local m2=(e.film and .5 or .85)*m
   local lt=a<.02 and 1 or 1-(1-m2)*a
   if math.abs(p.LocalTransparencyModifier-lt)>.002 then p.LocalTransparencyModifier=lt end
   local cg=e.film and p:FindFirstChild('Fade',true);if cg and math.abs(cg.GroupTransparency-lt)>.002 then cg.GroupTransparency=lt end
  end
 end
end
-- Janitor Closet sinks (server: SlipHazards). Black water pours from the spout as a solid stream
-- with a slow sheen running down it, splashes and churns where it lands, and the basin fills and
-- drains on the server's curve (Shared.Utilities.SinkCurve - both sides use the same function):
--  * tap on: the stream's leading end falls from the spout to the basin; once it lands the flow
--    builds up and ONE smooth surface rises - steadily at first, slowing heavily near the rim. The
--    drawn surface also follows that level through a critically damped filter, so it never steps
--    or jumps, and a slow, heavy heave rolls through it while the stream is pouring in;
--  * tap off: the water already in the air keeps falling - the stream's top end drops away from the
--    spout down into the basin (it never runs backward up the spout) - then the surface sinks evenly,
--    slowing as it empties, while a vortex forms over the plughole (_DrainSwirl).
-- Look: ONE opaque, oily, near-black body (no see-through layers, no glass - those were what
-- flashed as they faded in and out): a dull oily reflection, and a slow murky swirl drifting across
-- its top face (a Texture, tiled in studs so it never stretches as the surface changes size), plus
-- dingy flat foam that drifts out from where the stream lands. Handles turn a quarter turn.
-- Below FILM the water no longer fills the basin: it gathers into a shrinking puddle (over the
-- plughole when draining, under the stream when filling) that is never thinner than MIN_T, so its
-- top always stays clear above the drain fittings - nothing is ever coplanar, nothing z-fights.
local DRAIN_FILM=.035 -- below this depth the water is a puddle gathering at the plughole
local MIN_T=.019      -- the drawn surface never sinks lower than this above the basin floor
local SINK_FOLLOW=5 -- how quickly the drawn surface catches up with the true level (per second)
local function sinkLook(S)
 local w=S.water
 w.Material=Enum.Material.SmoothPlastic;w.Color=Color3.fromRGB(9,11,10);w.Reflectance=.16;w.CastShadow=false;w.Transparency=1
 -- murk: a slow, faint oily swirl on the top face only
 for _,name in {'Murk','Oil'}do local old=w:FindFirstChild(name);if old then old:Destroy()end end
 local murk=Instance.new('Texture');murk.Name='Murk';murk.Face=Enum.NormalId.Top;murk.Texture='rbxasset://textures/particles/smoke_main.dds'
 murk.Color3=Color3.fromRGB(58,50,36);murk.Transparency=.8;murk.StudsPerTileU=1.7;murk.StudsPerTileV=1.3;murk.ZIndex=1;murk.Parent=w
 local oil=Instance.new('Texture');oil.Name='Oil';oil.Face=Enum.NormalId.Top;oil.Texture='rbxasset://textures/particles/smoke_main.dds'
 oil.Color3=Color3.fromRGB(34,44,46);oil.Transparency=.86;oil.StudsPerTileU=.9;oil.StudsPerTileV=1.1;oil.ZIndex=2;oil.Parent=w
 S.murkTex,S.oilTex=murk,oil
 -- foam: flat, dingy bubbles that spread out over the surface from where the stream lands
 if S.bottomAtt then
  local f=Instance.new('ParticleEmitter');f.Name='SinkFoam';f.Texture='rbxasset://textures/particles/smoke_main.dds'
  f.Orientation=Enum.ParticleOrientation.VelocityPerpendicular;f.EmissionDirection=Enum.NormalId.Top
  f.Color=ColorSequence.new(Color3.fromRGB(58,56,50),Color3.fromRGB(34,34,31));f.LightInfluence=1;f.LightEmission=0
  f.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.04),NumberSequenceKeypoint.new(.4,.22),NumberSequenceKeypoint.new(1,.34)})
  f.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.15,.62),NumberSequenceKeypoint.new(.7,.78),NumberSequenceKeypoint.new(1,1)})
  -- nearly straight-up launch + VelocityPerpendicular = the flakes lie flat on the surface
  f.Lifetime=NumberRange.new(1.4,2.4);f.Speed=NumberRange.new(.03,.08);f.SpreadAngle=Vector2.new(25,25)
  f.Rotation=NumberRange.new(0,360);f.RotSpeed=NumberRange.new(-12,12);f.Drag=2.5;f.Rate=0;f.ZOffset=.02
  f.Parent=S.bottomAtt;S.foam=f
 end
end
function Controller:_Sink(m,serverNow,dt)
 self._sinks=self._sinks or {}
 local S=self._sinks[m]
 if not S then
  local water=m:FindFirstChild('BlackWater',true);local target=m:FindFirstChild('FlowTarget',true)
  local start=m:FindFirstChild('FlowStart',true)
   local drain=m:FindFirstChild('DrainThroat',true) or m:FindFirstChild('DomeStrainer',true) or m:FindFirstChild('Strainer',true)
  S={water=water,target=target,start=start,stream=m:FindFirstChild('Stream',true),glint=m:FindFirstChild('StreamGlint',true),
   splash=m:FindFirstChild('Splash',true),murk=m:FindFirstChild('Murk',true),drain=drain and drain.Position,
   sound=m:FindFirstChild('RunningWater',true),bottom=water and water:GetAttribute('Bottom') or 0,depth=water and water:GetAttribute('MaxDepth') or .5,
   handles={},turn=0,head=0,tail=1}
  -- a local, movable top for the stream so it can detach from the spout when the tap closes
  local endAtt=target and target:FindFirstChildOfClass('Attachment')
  if target and endAtt then
   -- (S.flowTop - not S.top, which is the water surface height below; sharing the name broke the stream)
   local top=Instance.new('Attachment');top.Name='FlowTop';top.Parent=target;S.flowTop=top;S.bottomAtt=endAtt
   for _,beam in {S.stream,S.glint}do if beam then beam.Attachment0=top end end
  end
  for _,h in m:GetDescendants()do if h:IsA('Model') and h:GetAttribute('PivotFrame') then table.insert(S.handles,{m=h,frame=h:GetPivot(),sign=h.Name=='HotHandle' and 1 or -1})end end
  if water then pcall(sinkLook,S);if S.foam then self._scope:Add(S.foam)end
   S.full=water.Size;S.centre=water.CFrame
   -- (Bottom is authored just above the basin floor; if the sink was moved, fall back to the part)
   if math.abs(S.bottom-water.Position.Y)>1 then S.bottom=water.Position.Y-.0295 end
  end
  S.level=SinkCurve.FromModel(m,serverNow);S.agit=0;S.flow=0
  S.widths={}
  for _,beam in {S.stream,S.glint}do if beam then S.widths[beam]={beam.Width0,beam.Width1} end end
  self._sinks[m]=S
 end
 local on=m:GetAttribute('WaterOn')==true
 local level=SinkCurve.FromModel(m,serverNow)
 -- the drawn level eases after the true one, so a late attribute or a clock correction never pops
 S.level+=(level-S.level)*(1-math.exp(-dt*SINK_FOLLOW))
 level=S.level
 -- draining: the whole surface goes down smoothly; the last film gathers into a round pool over
 -- the plughole and swirls away (_DrainSwirl)
 local draining=not on and level>.0005
 local depth=S.depth*level
 -- a slow, heavy heave while the stream pours in (eases in and out, a few millimetres at most)
 S.agit+=(((on and S.head>=1) and 1 or 0)-S.agit)*(1-math.exp(-dt*(on and 1.2 or .7)))
 local heave=S.agit*math.min(1,depth/.08)*(.0045*math.sin(serverNow*1.7)+.0025*math.sin(serverNow*2.9+1.3))
 -- SLOSH: the surface is a damped spring that tilts and bobs. The pouring stream keeps kicking it
 -- (small random pushes where it lands), turning the tap on or off gives it a shove, and it rings
 -- down on its own once the tap is off - so the water rocks and settles like real water.
 do
  local W,Z=2*math.pi*1.4,.14
  S.ax=S.ax or 0;S.az=S.az or 0;S.vx=S.vx or 0;S.vz=S.vz or 0;S.by=S.by or 0;S.vy=S.vy or 0
  if S.wasOn~=nil and S.wasOn~=on then S.vx+=(math.random()-.5)*.09;S.vz+=(math.random()-.5)*.09;S.vy-=.05 end
  S.wasOn=on
  local pour=(on and S.head>=1) and (S.flow or 0) or 0
  local deep=math.min(1,depth/.06)
  if pour>0 then local k=pour*deep*dt*1.6;S.vx+=(math.random()-.5)*k;S.vz+=(math.random()-.5)*k;S.vy+=(math.random()-.5)*k*.6 end
  local h=math.min(dt,1/30)
  for _=1,2 do
   S.vx+=(-W*W*S.ax-2*Z*W*S.vx)*h*.5;S.ax+=S.vx*h*.5
   S.vz+=(-W*W*S.az-2*Z*W*S.vz)*h*.5;S.az+=S.vz*h*.5
   S.vy+=(-W*W*1.6*S.by-2*Z*W*S.vy)*h*.5;S.by+=S.vy*h*.5
  end
  S.ax=math.clamp(S.ax,-.022,.022)*deep;S.az=math.clamp(S.az,-.022,.022)*deep;S.by=math.clamp(S.by,-.006,.006)
  heave+=S.by*deep
 end
 S.ax,S.az,heave=0,0,0 -- (Oct 18: no slosh, the surface stays flat)
 if S.water and S.full then
  -- footprint: the whole basin above FILM; below it a puddle that gathers toward the plughole
  -- (draining) or spreads out from under the stream (filling) - it changes SIZE, never fades
  -- through see-through, except the last few millimetres of a tiny puddle sitting right over the
  -- black plughole (dark on dark, so even that is invisible)
  local f=math.clamp(depth/DRAIN_FILM,0,1);local g=f^.7
  local cf0=S.centre
  local anchor=cf0.Position
  if draining and S.drain then anchor=Vector3.new(S.drain.X,cf0.Y,S.drain.Z)
  elseif S.bottomAtt then local p=S.bottomAtt.WorldPosition;anchor=Vector3.new(p.X,cf0.Y,p.Z) end
  local small=.24
  local sx=small+(S.full.X-small)*g;local sz=small+(S.full.Z-small)*g
  -- keep the puddle inside the basin
  local lp=cf0:PointToObjectSpace(anchor:Lerp(cf0.Position,g))
  lp=Vector3.new(math.clamp(lp.X,-(S.full.X-sx)/2,(S.full.X-sx)/2),0,math.clamp(lp.Z,-(S.full.Z-sz)/2,(S.full.Z-sz)/2))
  local t=math.max(MIN_T,depth+heave)
  -- (the last of the puddle fades with the depth itself, all the way to zero - no cut-off pop)
  local alpha=math.clamp(f/.12,0,1)
  local shown=alpha>.003
  S.water.Transparency=shown and (1-alpha)^1.5 or 1
  if shown then
   S.water.Size=Vector3.new(sx,t,sz)
   S.water.CFrame=cf0*CFrame.new(lp.X,S.bottom-cf0.Y+t/2,lp.Z)*CFrame.Angles(S.ax or 0,0,S.az or 0)
  end
  S.top=S.bottom+t;S.foot=math.min(sx,sz)
  if S.murkTex then S.murkTex.OffsetStudsU=serverNow*.035;S.murkTex.OffsetStudsV=serverNow*.021;S.oilTex.OffsetStudsU=-serverNow*.022;S.oilTex.OffsetStudsV=serverNow*.031 end
 end
 -- (drain swirl removed Oct 18: the water simply drains away)
 local surface=S.bottom+depth
 local spout=S.start and S.start.WorldPosition
 -- head = how far the leading end has fallen, tail = how far the trailing end has fallen (0 at the
 -- spout, 1 at the water). Opening: head falls, tail stays at the spout. Closing: tail falls too.
 local fall=dt/.32
 if on then
  if S.tail>=1 then S.head=0;S.tail=0 end -- a fresh pour
  S.tail=0;S.head=math.min(1,S.head+fall)
 else
  S.tail=math.min(1,S.tail+fall*(S.tail<1 and 1 or 0))
  if S.head<1 then S.head=math.min(1,S.head+fall)end
 end
 local flowing=S.tail<1 and S.head>0
 if spout and S.flowTop and S.bottomAtt then
  local function at(k)k=k*k;return Vector3.new(spout.X,spout.Y+(surface-spout.Y)*k,spout.Z)end -- accelerating fall
  S.flowTop.WorldPosition=at(S.tail);S.bottomAtt.WorldPosition=at(S.head)
 end
 if S.stream then S.stream.Enabled=flowing end
 if S.glint then S.glint.Enabled=flowing end
 -- the flow builds as the tap opens and chokes off as it closes: the stream starts as a thin
 -- trickle, swells to a full pour, and thins out again before the last of it falls away
 S.flow=(S.flow or 0)+(((on and 1 or 0))-(S.flow or 0))*(1-math.exp(-dt*(on and 2.6 or 5)))
 if S.widths then
  local k=.28+.72*S.flow
  -- (the falling column necks down a little as it speeds up, like a real pour)
  for beam,w in S.widths do beam.Width0=w[1]*k;beam.Width1=w[2]*k*(.78+.22*S.flow) end
 end
 local landed=flowing and S.head>=1
 -- RIPPLES: rings of disturbed water spread out from where the stream hits and fade as they go
 -- (glossy discs that grow and thin out; capped to the basin)
 S.ripples=S.ripples or {}
 if false and landed then -- ripples removed Oct 18
  S.rippleT=(S.rippleT or 0)-dt
  if S.rippleT<=0 then
   S.rippleT=.22+math.random()*.18
   local cam=workspace.CurrentCamera
   if cam and #S.ripples<6 then
    local r=Instance.new('Part');r.Name='SinkRipple';r.Shape=Enum.PartType.Cylinder;r.Material=Enum.Material.Glass
    r.Color=Color3.fromRGB(70,74,72);r.Reflectance=.35;r.Anchored=true;r.CanCollide=false;r.CanQuery=false;r.CanTouch=false;r.CastShadow=false
    r.Transparency=1;r.Parent=cam;self._scope:Add(r)
    local p=S.bottomAtt.WorldPosition
    table.insert(S.ripples,{p=r,x=p.X,z=p.Z,age=0,life=1+math.random()*.3,max=math.min(S.full.X,S.full.Z)*(.45+math.random()*.12)})
   end
  end
 end
 for i=#S.ripples,1,-1 do
  local q=S.ripples[i];q.age+=dt
  local u=q.age/q.life
  if u>=1 or not q.p.Parent then q.p:Destroy();table.remove(S.ripples,i)
  else
   local e=1-(1-u)^2
   local d=math.max(.05,q.max*e*2)
   q.p.Size=Vector3.new(.004,d,d)
   q.p.CFrame=CFrame.new(q.x,(S.top or S.bottom)+.004,q.z)*CFrame.Angles(0,0,math.rad(90))
   q.p.Transparency=.62+.38*u
  end
 end
 -- the falling stream is never perfectly steady: its thickness wavers a little all the time
 if flowing and S.widths then
  local n=1+.07*math.noise(serverNow*3.1,.37)+.05*math.sin(serverNow*17.3)
  for beam,w in S.widths do beam.Width0*=n;beam.Width1*=(2-n) end
 end
 -- loose droplets breaking off the stream and falling beside it
 if S.start and not S.drops then
  local e=Instance.new('ParticleEmitter');e.Name='StreamDrops';e.Texture='rbxasset://textures/particles/sparkles_main.dds'
  e.Color=ColorSequence.new(Color3.fromRGB(40,44,42));e.LightEmission=0;e.LightInfluence=1
  e.Size=NumberSequence.new(.025);e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.3),NumberSequenceKeypoint.new(1,.6)})
  e.Orientation=Enum.ParticleOrientation.VelocityParallel;e.Squash=NumberSequence.new(1.6)
  e.EmissionDirection=Enum.NormalId.Bottom;e.Speed=NumberRange.new(.2,.6);e.SpreadAngle=Vector2.new(8,8)
  e.Acceleration=Vector3.new(0,-workspace.Gravity*.28,0);e.Rate=0;e.Parent=S.start;S.drops=e;self._scope:Add(e)
 end
 if S.drops then
  local h=math.max(.05,(S.start.WorldPosition.Y-(S.top or S.bottom)))
  S.drops.Lifetime=NumberRange.new(math.sqrt(2*h/(workspace.Gravity*.28))*.95)
  S.drops.Rate=0
 end
 if S.splash then S.splash.Enabled=landed;S.splash.Rate=level>.15 and 30 or 55 end
 if S.murk then S.murk.Enabled=landed and level>.05 end
 if S.foam then
  -- foam builds where the stream lands once there is water to float on, and stops with the tap
  S.foam.Rate=0
 end
 if S.sound then
  local v=flowing and .55 or 0
  S.sound.Volume+= (v-S.sound.Volume)*(1-math.exp(-dt*(flowing and 8 or 4)))
  if S.sound.Volume>.01 and not S.sound.IsPlaying then S.sound:Play()elseif S.sound.Volume<=.01 and S.sound.IsPlaying then S.sound:Stop()end
 end
 S.turn+=((on and 1 or 0)-S.turn)*(1-math.exp(-dt*9))
 -- the hot/cold cross handles turn a quarter turn as the tap opens (and back as it closes)
 for _,h in S.handles do if h.m.Parent then h.m:PivotTo(h.frame*CFrame.Angles(h.sign*S.turn*math.rad(90),0,0)) end end
end
-- A draining sink: the surface sinks evenly while a vortex forms over the plughole - a dark dimple
-- with a black core, and thin glossy streaks that spiral in faster the closer they get, then vanish
-- down the drain. Once only a film is left (DRAIN_FILM), it gathers into a round pool centred on
-- the plughole that shrinks and swirls away. Everything round: nothing spins visibly as a shape.
function Controller:_DrainSwirl(S,draining,depth,t,dt)
 local w=S.water
 S.swirl=S.swirl or 0
 S.swirl+=(((draining and depth>.002) and 1 or 0)-S.swirl)*(1-math.exp(-(dt or .016)*(draining and 3 or 6)))
 local k=S.swirl
 if k<.01 or not w or not S.top then
  for _,p in S.vortex or {} do p.Transparency=1 end
  return
 end
 local cam=workspace.CurrentCamera;if not cam then return end
 local function part(name,round)
  local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
  if round then p.Shape=Enum.PartType.Cylinder end
  -- (plain plastic: glass flashes bright as it fades in and out)
  p.Material=Enum.Material.SmoothPlastic;p.Transparency=1;p.Parent=cam;self._scope:Add(p);return p
 end
 if not S.vortex then
  local dark=Color3.fromRGB(4,5,5)
  local dimple=part('DrainDimple',true);dimple.Color=dark;dimple.Reflectance=.04
  local core=part('DrainCore',true);core.Color=Color3.fromRGB(8,10,10);core.Material=Enum.Material.SmoothPlastic
  S.vortex={dimple=dimple,core=core}
  S.streaks={}
  -- black water: the streaks are only a faint oily sheen, never bright
  for i=1,6 do local p=part('DrainStreak');p.Color=Color3.fromRGB(34,38,37);p.Reflectance=.08;S.streaks[i]=p;S.vortex['s'..i]=p end
 end
 local centre=Vector3.new(w.Position.X,0,w.Position.Z)
 local drain=S.drain and Vector3.new(S.drain.X,0,S.drain.Z) or centre
 -- vortex over the plughole, in thin layers stacked clear of the surface and of each other
 -- (dimple, then core, then streaks - each its own height, so nothing is ever coplanar)
 local surf=S.top+.001
 local R=math.max(.08,(S.foot or .3)*.42)
 local strength=k*math.clamp(depth/.008,0,1)*(1-w.Transparency)
 local v=S.vortex
 local dd=R*1.15
 v.dimple.Size=Vector3.new(.002,dd,dd);v.dimple.CFrame=CFrame.new(drain.X,surf+.001,drain.Z)*CFrame.Angles(0,0,math.pi/2)
 v.dimple.Transparency=1 -- (no extra disc: just the dark core and a few streaks)
 local cd=math.min(dd*.6,.07+.03*strength)
 v.core.Size=Vector3.new(.002,cd,cd);v.core.CFrame=CFrame.new(drain.X,surf+.004,drain.Z)*CFrame.Angles(0,0,math.pi/2)
 v.core.Transparency=1-.8*strength
 local n=#S.streaks
 for i,p in S.streaks do
  local u=(t*.5+i/n)%1                     -- 0 at the rim .. 1 at the drain
  local r=.04+R*(1-u)^1.6
  local a=i*2.399+t*1.3+math.log(R/r+1)*5   -- angular speed climbs toward the centre
  local radial=Vector3.new(math.cos(a),0,math.sin(a))
  local pos=Vector3.new(drain.X,surf+.007,drain.Z)+radial*r
  local tangent=Vector3.new(-radial.Z,0,radial.X)
  local dir=(tangent-radial*.35).Unit
  p.Size=Vector3.new(.018,.002,.04+.16*math.clamp(r/math.max(R,.05),0,1))
  p.CFrame=CFrame.lookAt(pos,pos+dir)
  local fade=math.clamp(math.min(u/.18,(1-u)/.3),0,1)
  p.Transparency=1-.6*fade*strength
 end
end
-- One real drop of water: a small glassy bead lets go of the ceiling, falls under gravity for the
-- measured drop time (stretching into a streak as it speeds up) and bursts on the floor into a
-- crown of tiny droplets - a proper splash into standing water, a small splat on bare concrete.
local WATER=Color3.fromRGB(150,170,172)
function Controller:_SplashFX()
 local fx=self._splashPart
 if fx and fx.Parent then return fx end
 fx=Instance.new('Part');fx.Name='DripSplashFX';fx.Size=Vector3.new(.1,.1,.1);fx.Transparency=1;fx.Anchored=true;fx.CanCollide=false;fx.CanQuery=false;fx.CanTouch=false;fx.Parent=workspace.CurrentCamera
 local crown=Instance.new('ParticleEmitter');crown.Name='Crown';crown.Texture='rbxasset://textures/particles/sparkles_main.dds'
 crown.Color=ColorSequence.new(WATER);crown.LightInfluence=1;crown.LightEmission=.05;crown.Rate=0
 crown.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,.015)})
 crown.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.1),NumberSequenceKeypoint.new(1,.85)})
 crown.Lifetime=NumberRange.new(.16,.3);crown.Speed=NumberRange.new(1.2,2.4);crown.SpreadAngle=Vector2.new(48,48)
 crown.Acceleration=Vector3.new(0,-38,0);crown.Drag=1;crown.EmissionDirection=Enum.NormalId.Top;crown.Parent=fx
 local mist=Instance.new('ParticleEmitter');mist.Name='Mist';mist.Texture='rbxasset://textures/particles/smoke_main.dds'
 mist.Color=ColorSequence.new(WATER);mist.LightInfluence=1;mist.Rate=0
 mist.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.06),NumberSequenceKeypoint.new(1,.22)})
 mist.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.75),NumberSequenceKeypoint.new(1,1)})
 mist.Lifetime=NumberRange.new(.2,.35);mist.Speed=NumberRange.new(.3,.8);mist.SpreadAngle=Vector2.new(80,80);mist.Parent=fx
 self._splashPart=fx;self._scope:Add(fx)
 return fx
end
-- One drip sound per drop, played at the exact spot and moment it lands (the drip sounds follow the
-- drops instead of looping on their own). A few close takes, pitched a little, so no two match.
local DRIP_SFX={'rbxassetid://9120519525','rbxassetid://9120519909','rbxassetid://9114175929'}
function Controller:_DripSound(pos,wet)
 local cam=workspace.CurrentCamera;if not cam or (cam.CFrame.Position-pos).Magnitude>60 then return end
 -- never heard from inside the lift during the descent cinematic (no ticking while you come round)
 if self._player:GetAttribute('EHContext')~='ActiveFloor' or game.ReplicatedStorage.Game:GetAttribute('SurfaceBoarding') then return end
 local host=Instance.new('Part');host.Name='DripSound';host.Size=Vector3.new(.05,.05,.05);host.Transparency=1;host.Anchored=true;host.CanCollide=false;host.CanQuery=false;host.CanTouch=false;host.CFrame=CFrame.new(pos);host.Parent=cam
 local s=Instance.new('Sound');s.SoundId=DRIP_SFX[math.random(1,#DRIP_SFX)];s.Volume=wet and .32 or .2;s.PlaybackSpeed=(wet and .92 or 1.08)+(math.random()-.5)*.14
 s.RollOffMode=Enum.RollOffMode.InverseTapered;s.RollOffMinDistance=3;s.RollOffMaxDistance=45;s.Parent=host;s:Play()
 game:GetService('Debris'):AddItem(host,3)
end
function Controller:_Droplet(from,floorY,fall,wet)
 local cam=workspace.CurrentCamera;if not cam then return end
 -- never start above the ceiling (the drop would be seen falling through it)
 local up=RaycastParams.new();up.FilterType=Enum.RaycastFilterType.Exclude;up.FilterDescendantsInstances={cam,self._player.Character}
 local roof=workspace:Raycast(Vector3.new(from.X,floorY+.6,from.Z),Vector3.new(0,math.max(.1,from.Y-floorY),0),up)
 if roof and roof.Position.Y<from.Y then from=Vector3.new(from.X,roof.Position.Y-.04,from.Z)end
 local height=from.Y-floorY;if height<=.1 then return end
 fall=math.min(fall or 9,math.sqrt(2*height/workspace.Gravity))
 local drop=Instance.new('Part');drop.Name='FallingDrop';drop.Shape=Enum.PartType.Ball;drop.Material=Enum.Material.Glass
 drop.Color=WATER;drop.Transparency=.2;drop.Reflectance=.35;drop.Size=Vector3.new(.07,.07,.07)
 drop.Anchored=true;drop.CanCollide=false;drop.CanQuery=false;drop.CanTouch=false;drop.CastShadow=false
 local mesh=Instance.new('SpecialMesh',drop);mesh.MeshType=Enum.MeshType.Sphere
 drop.CFrame=CFrame.new(from);drop.Parent=cam
 local start=os.clock();local conn
 conn=RunService.RenderStepped:Connect(function()
  local a=math.min((os.clock()-start)/fall,1)
  local speed=2*height*a/fall -- studs/s, constant acceleration
  local stretch=1+math.min(speed/12,2.2)
  mesh.Scale=Vector3.new(1/math.sqrt(stretch),stretch,1/math.sqrt(stretch))
  drop.CFrame=CFrame.new(from.X,from.Y-height*a*a+.035*stretch,from.Z)
  if a>=1 then
   conn:Disconnect();drop:Destroy()
   local fx=self:_SplashFX();fx.CFrame=CFrame.new(from.X,floorY+.02,from.Z)
   fx.Crown:Emit(wet and math.random(8,12) or math.random(2,4));if wet then fx.Mist:Emit(3)end
    -- (Oct 25) into a puddle: the little rebound column a real drop throws back up, then two rings
    if wet then
     local jet=Instance.new('Part');jet.Name='Rebound';jet.Shape=Enum.PartType.Ball;jet.Material=Enum.Material.Glass;jet.Color=WATER;jet.Transparency=.25;jet.Reflectance=.3
     jet.Size=Vector3.new(.05,.05,.05);jet.Anchored=true;jet.CanCollide=false;jet.CanQuery=false;jet.CanTouch=false;jet.CastShadow=false;jet.Parent=cam
     local t0=os.clock();local rc;rc=RunService.RenderStepped:Connect(function()local u=(os.clock()-t0)/.32;if u>=1 or not jet.Parent then rc:Disconnect();jet:Destroy();return end
      jet.CFrame=CFrame.new(from.X,floorY+.02+.22*4*u*(1-u),from.Z);jet.Transparency=.25+.6*u end)
     for k=0,1 do task.delay(k*.14,function()
      local r=Instance.new('Part');r.Name='Ripple';r.Shape=Enum.PartType.Cylinder;r.Anchored=true;r.CanCollide=false;r.CanQuery=false;r.CanTouch=false;r.CastShadow=false
      r.Material=Enum.Material.Glass;r.Color=Color3.fromRGB(150,165,168);r.Reflectance=.25;r.Transparency=.55+.15*k
      r.Size=Vector3.new(.004,.08,.08);r.CFrame=CFrame.new(from.X,floorY+.012,from.Z)*CFrame.Angles(0,0,math.pi/2);r.Parent=cam
      local tw=game:GetService('TweenService'):Create(r,TweenInfo.new(.9-.2*k,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.004,.9-.3*k,.9-.3*k),Transparency=1})
      tw.Completed:Connect(function()r:Destroy()end);tw:Play() end) end
    end
   self:_DripSound(Vector3.new(from.X,floorY+.05,from.Z),wet)
  end
 end)
 task.delay(fall+1,function()if conn.Connected then conn:Disconnect()end;if drop.Parent then drop:Destroy()end end)
end
function Controller:_Leaks(dt)
 self._leaks=self._leaks or {}
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 local floor=env and (env:FindFirstChild('Level5') or env:FindFirstChild('Level4'))
 if not floor then return end
 local now=os.clock();local serverNow=workspace:GetServerTimeNow()
 if floor~=self._leakFloor or now>(self._leakScan or 0) then
  self._leakFloor=floor;self._leakScan=now+25;self._leakZones={} -- (per floor; a slow re-sweep only)
  self._ambientDrips={};self._sinkModels={}
  for _,d in floor:GetDescendants()do
   if d:IsA('BasePart') and d:GetAttribute('SlipHazard') then table.insert(self._leakZones,d)
   elseif d:IsA('Model') and d:GetAttribute('AmbientDrip') then table.insert(self._ambientDrips,d)
   elseif d:IsA('Model') and d:GetAttribute('SinkId') then table.insert(self._sinkModels,d)end
  end
 end
 for _,m in self._sinkModels do if m.Parent then pcall(self._Sink,self,m,serverNow,dt)end end
 -- Ambient ceiling leaks (authored CeilingDrip models): the same swelling drop, a falling streak
 -- the whole height of the room, and a small ripple on the damp patch below - continuously.
 for _,m in self._ambientDrips do
  if m.Parent then
   local A=self._leaks[m]
   if not A then
    local stain=m:FindFirstChild('LeakStain')
    -- a drop lets go every 1-4 s (random each time); its sound plays as it lands
    local first=1+math.random()*3
    A={next=now+first*math.random(),drop=m:FindFirstChild('HangingDrop'),pe=stain and stain:FindFirstChild('Drops',true),fall=stain and stain:GetAttribute('DropFallSeconds') or .52,
     x=m:GetAttribute('DripX'),z=m:GetAttribute('DripZ'),y=(m:GetAttribute('FloorY') or 20)+.045,period=first}
    self._leaks[m]=A
   end
   if A.drop then
    local grow=math.clamp(1-(A.next-now)/A.period,0,1)
    local s=.05+.09*grow;A.drop.Size=Vector3.new(s,s*1.2,s)
   end
   if now>=A.next and (A.pe or A.drop) then
    A.period=1+math.random()*3;A.next=now+A.period
    if A.x then self:_Droplet(A.drop and A.drop.Position or Vector3.new(A.x,A.y+10,A.z),A.y,A.fall,false)end
    -- (only now and then a faint ring - never a stack of circles)
    if false and A.x then task.delay(A.fall,function() -- (Oct 25: no ring on the bare floor under ambient drips)
     local r=Instance.new('Part');r.Name='Ripple';r.Shape=Enum.PartType.Cylinder;r.Anchored=true;r.CanCollide=false;r.CanQuery=false;r.CanTouch=false;r.CastShadow=false
     r.Material=Enum.Material.SmoothPlastic;r.Color=Color3.fromRGB(120,132,132);r.Reflectance=.1;r.Transparency=.8
     r.Size=Vector3.new(.004,.1,.1);r.CFrame=CFrame.new(A.x,A.y,A.z)*CFrame.Angles(0,0,math.pi/2);r.Parent=workspace.CurrentCamera
     local tw=game:GetService('TweenService'):Create(r,TweenInfo.new(.5,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.004,.6,.6),Transparency=1})
     tw.Completed:Connect(function()r:Destroy()end);tw:Play()
    end)end
   end
  end
 end
 for _,zone in self._leakZones do
  if zone.Parent then
   local L=self._leaks[zone]
   if not L then
    local spill=zone.Parent;local stain=spill:FindFirstChild('LeakStain')
    local first=1+math.random()*3
    L={next=now+first*math.random(),period=first,drop=spill:FindFirstChild('HangingDrop'),pe=stain and stain:FindFirstChild('Drops',true),fall=stain and stain:GetAttribute('DropFallSeconds') or .52}
    self._leaks[zone]=L
   end
   pcall(self._Water,self,L,zone,serverNow)
   local wet=L.wet or 1
   if L.drop then
    local grow=math.clamp(1-(L.next-now)/(L.period or 2),0,1)
    local s=.06+.1*grow;L.drop.Size=Vector3.new(s,s*1.15,s);L.drop.LocalTransparencyModifier=0
   end
   if now>=L.next and (L.pe or L.drop) then
    -- a drop every 1-4 s (random each time)
    L.period=1+math.random()*3;L.next=now+L.period
    local x,z=zone:GetAttribute('DripX'),zone:GetAttribute('DripZ')
    if x then self:_Droplet(L.drop and L.drop.Position or Vector3.new(x,30,z),wet>.3 and 20.104 or 20.045,L.fall,wet>.3)end
    -- (one faint ring for some of the drops only - the puddle is never covered in circles)
    if x and wet<=.3 and math.random()<.4 then task.delay(L.fall,function()
     local w=(self._leaks[zone] and self._leaks[zone].wet) or 1
     local r=Instance.new('Part');r.Name='Ripple';r.Shape=Enum.PartType.Cylinder;r.Anchored=true;r.CanCollide=false;r.CanQuery=false;r.CanTouch=false;r.CastShadow=false
     r.Material=Enum.Material.SmoothPlastic;r.Color=Color3.fromRGB(120,132,132);r.Reflectance=.1;r.Transparency=w>.3 and .78 or .85
     local top=w>.3 and 20.075 or 20.045
     r.Size=Vector3.new(.004,.12,.12);r.CFrame=CFrame.new(x,top,z)*CFrame.Angles(0,0,math.pi/2);r.Parent=workspace.CurrentCamera
     local final=w>.3 and .8 or .35 -- on bare concrete the drop just splats
     local tw=game:GetService('TweenService'):Create(r,TweenInfo.new(w>.3 and .75 or .35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.006,final,final),Transparency=1})
     tw.Completed:Connect(function()r:Destroy()end);tw:Play()
    end)end
   end
  end
 end
 for z in self._leaks do if not z.Parent then self._leaks[z]=nil end end
end
------------------------------------------------------------------ vents (local player)
-- CLIMB IN (either end of a duct): a real climb rather than a hop - you step in under the opening
-- and crouch, spring up and catch the lip, haul yourself up and slide forward over it onto your
-- hands and knees, facing along the duct (CLIMB_SECONDS, one C1-smooth spline on the server clock).
-- The body is moved by this client's physics (unanchored, the climber's own assembly), so the climb
-- REPLICATES: everyone else sees you jump, catch the lip and pull yourself in, with the matching
-- body pose from _Pose. While being moved the character doesn't collide (no snagging on the lip or
-- a dropped cover) and the Humanoid is held (PlatformStand) so it never fights the path.
-- Inside, the character rides low (HipHeight) on hands and knees; the server keeps the crouch
-- locked. Crawling out of an open end hands over to a short climb-out: you slide over the lip and
-- drop down onto your feet below it (EXIT_SECONDS), again moved smoothly and replicated.
local CrouchState=require(Shared.Utilities.CrouchState)
local VENT_HIP=.35
local EXIT_SECONDS=.8
local function inVolume(volume,pos)
 local p=volume.CFrame:PointToObjectSpace(pos);local h=volume.Size/2
 return math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y and math.abs(p.Z)<=h.Z
end
function Controller:_FindVent(id)
 local runtime=workspace:FindFirstChild('Runtime')
 for _,d in (runtime and runtime:GetDescendants() or {})do
  if d:IsA('Model') and d:GetAttribute('VentId')==id and d:GetAttribute('EntryFrameA') then return d end
 end
end
-- Catmull-Rom through the climb's key points (C1-smooth: no kinks in speed or direction)
local function catmull(p0,p1,p2,p3,u)
 local u2,u3=u*u,u*u*u
 return ((p1*2)+(p2-p0)*u+(p0*2-p1*5+p2*4-p3)*u2+(p1*3-p0-p2*3+p3)*u3)*.5
end
local function climbPath(keys,times,u)
 for i=1,#keys-1 do
  if u<=times[i+1] or i==#keys-1 then
   local w=math.clamp((u-times[i])/(times[i+1]-times[i]),0,1)
   return catmull(keys[math.max(1,i-1)],keys[i],keys[i+1],keys[math.min(#keys,i+2)],w)
  end
 end
 return keys[#keys]
end
-- the local character is moved along a scripted path: no collisions, Humanoid held
local function hold(v,c,h,on)
 if on and not v.held then
  v.held=true;v.saved={}
  for _,d in c:GetDescendants()do if d:IsA('BasePart') then v.saved[d]=d.CanCollide;d.CanCollide=false end end
  h.PlatformStand=true
 elseif not on and v.held then
  v.held=false
  for d,cc in v.saved or {}do if d.Parent then d.CanCollide=cc end end;v.saved=nil
  if h.Parent then h.PlatformStand=false;pcall(function()h:ChangeState(Enum.HumanoidStateType.Running)end)end
 end
end
-- one physics step along a path: the position for this step, and the velocity toward the next
-- point, so the replicated body (and every other client's interpolation) moves smoothly
local function drive(root,keys,times,u,seconds,rot)
 local pos=climbPath(keys,times,u)
 local du=math.min(.04,1-u)
 local ahead=climbPath(keys,times,u+du)
 root.CFrame=CFrame.new(pos)*rot
 root.AssemblyLinearVelocity=du>1e-3 and (ahead-pos)/(du*seconds) or Vector3.zero
 root.AssemblyAngularVelocity=Vector3.zero
end
-- In the duct the body is turned by a physics constraint (AlignOrientation on the root), never by
-- writing root.CFrame every frame: the solver turns it smoothly between physics steps, so the
-- first-person camera (which rides the root) and the body never stutter against the duct floor.
-- Prone collision: while you lie in the duct the upright root box stops colliding and a flat
-- cylinder 2.5 studs wide and 1.5 high (welded under the root, its base just off the sheet metal)
-- is what touches the duct walls. Round, so turning round in the duct can never wedge it. Jumping
-- and standing are locked out; the Humanoid's hip height is worked out from your avatar so the
-- torso lies flat on the floor.
local PRONE_W,PRONE_H,PRONE_GAP=2.5,1.5,.08
local function proneHip(c,root)
 local lt=c:FindFirstChild('LowerTorso');local ut=c:FindFirstChild('UpperTorso')
 local r0=jointFrames(lt and lt:FindFirstChild('Root'))
 local pivotY=r0 and r0.Position.Y or -1
 local chest=(ut and ut.Size.Z/2 or .5)+.12 -- half the chest depth, propped on the forearms
 return math.clamp(chest-pivotY-root.Size.Y/2,.05,1.2)
end
local function prone(v,c,h,root,on)
 if on and not v.prone then
  local hip=v.proneHip or VENT_HIP
  local hb=Instance.new('Part');hb.Name='ProneHitbox';hb.Shape=Enum.PartType.Cylinder
  hb.Size=Vector3.new(PRONE_H,PRONE_W,PRONE_W) -- cylinder length (X) is the height
  hb.Transparency=1;hb.CanCollide=true;hb.CanQuery=false;hb.CanTouch=false;hb.Massless=true;hb.CastShadow=false
  hb.CustomPhysicalProperties=PhysicalProperties.new(.7,0,0,100,100) -- slides along the sheet metal, never grips
  local offset=PRONE_GAP+PRONE_H/2-(hip+root.Size.Y/2)
  local w=Instance.new('Weld');w.Part0=root;w.Part1=hb;w.C0=CFrame.new(0,offset,0)*CFrame.Angles(0,0,math.rad(90))
  hb.CFrame=root.CFrame*w.C0;w.Parent=hb;hb.Parent=c
  v.prone={hb=hb,collide=root.CanCollide,jump=h:GetStateEnabled(Enum.HumanoidStateType.Jumping),walk=h.WalkSpeed}
  root.CanCollide=false
  h:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
 elseif not on and v.prone then
  local s=v.prone;v.prone=nil
  if s.hb then s.hb:Destroy() end
  if root.Parent then root.CanCollide=s.collide end
  for _,n in {'UpperTorso','LowerTorso','Torso'} do local bp=c:FindFirstChild(n);if bp and bp:IsA('BasePart') then bp.CanCollide=true end end
  if h.Parent then h:SetStateEnabled(Enum.HumanoidStateType.Jumping,s.jump~=false) end
 end
end
local function dropAlign(v)
 if v.align then v.align:Destroy();v.align=nil end
 if v.alignAtt then v.alignAtt:Destroy();v.alignAtt=nil end
end
local function ensureAlign(v,root)
 if v.align and v.align.Parent==root then return v.align end
 dropAlign(v)
 local att=Instance.new('Attachment');att.Name='VentAlignAttachment';att.Parent=root
 local al=Instance.new('AlignOrientation');al.Name='VentAlign'
 al.Mode=Enum.OrientationAlignmentMode.OneAttachment;al.Attachment0=att
 al.RigidityEnabled=false;al.Responsiveness=10;al.MaxTorque=math.huge
 al.MaxAngularVelocity=math.rad(170) -- turning round in the duct is a slow, heavy shuffle
 al.CFrame=root.CFrame.Rotation;al.Parent=root
 v.align,v.alignAtt=al,att
 return al
end
-- The crawl's pace: one fixed, steady speed (MovementConfig.VentCrawlSpeed = 5), no sprint or
-- slow-down modifiers, and the body's flat velocity is never allowed past it.
-- It eases in and out instead of starting and stopping dead (_CrawlSteer, right after the control
-- module has set this frame's move): what you press is glided toward - about a quarter of a second
-- to get going, a little quicker to stop - and handed back to the Humanoid as its move. Let go and
-- you come to a soft stop: no drift, no lurch.
local CRAWL_ACCEL,CRAWL_BRAKE=8,60 -- (Oct 25: let go and you stop within a hand's width - it used to slide on half a stud)
local UIS=game:GetService('UserInputService')
local KEYS={{Enum.KeyCode.W,0,-1},{Enum.KeyCode.Up,0,-1},{Enum.KeyCode.S,0,1},{Enum.KeyCode.Down,0,1},
 {Enum.KeyCode.A,-1,0},{Enum.KeyCode.Left,-1,0},{Enum.KeyCode.D,1,0},{Enum.KeyCode.Right,1,0}}
-- what you are pressing right now (keys or the left stick), as a world direction from the camera
local function heldMove(noStrafe)
 if UIS:GetFocusedTextBox() then return Vector3.zero end
 local x,z=0,0
 for _,k in KEYS do if UIS:IsKeyDown(k[1]) then x+=k[2];z+=k[3] end end
 x,z=math.clamp(x,-1,1),math.clamp(z,-1,1)
 local ok,states=pcall(UIS.GetGamepadState,UIS,Enum.UserInputType.Gamepad1)
 if ok then for _,s in states do if s.KeyCode==Enum.KeyCode.Thumbstick1 and s.Position.Magnitude>.2 then x+=s.Position.X;z-=s.Position.Y end end end
 -- (in a duct left/right does nothing at all: only forward/back crawl you along it)
 if noStrafe then x=0 end
 local cf=workspace.CurrentCamera.CFrame
 local fwd=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z)
 if fwd.Magnitude<1e-3 then fwd=Vector3.new(cf.UpVector.X,0,cf.UpVector.Z) end
 fwd=fwd.Unit
 local w=Vector3.new(-fwd.Z,0,fwd.X)*x-fwd*z
 return w.Magnitude>1 and w.Unit or w
end
function Controller:_CrawlSteer(dt)
 local v=self._vent
 local h=v and v.h
 if not v or v.phase~='crawl' or not h or not h.Parent then if v then v.move=nil end;return end
 -- (touch: the on-screen stick drives the Humanoid directly)
 if UIS.PreferredInput==Enum.PreferredInput.Touch then v.move=nil;return end
 local want=next(self._input._blocks)~=nil and Vector3.zero or heldMove(true)
 -- a duct only goes two ways: what you press is taken along the duct only (looking to the side while
 -- you hold W never pushes you sideways into a wall)
 if v.axis then
  local d=want:Dot(v.axis);local mag=want.Magnitude -- (Oct 25 fix) the view only picks the DIRECTION along the duct, never the speed (it used to be cos(view angle): full speed only looking straight along it)
   want=(mag>1e-3 and math.abs(d)/mag>=.35) and v.axis*math.sign(d)*math.min(1,mag) or Vector3.zero
  -- (pressing left/right only leaves a sliver along the duct: that sliver is ignored, it never creeps
  -- you along or turns you round)
  if want.Magnitude<.35 then want=Vector3.zero end
 end
 local s=v.move or Vector3.zero
 s=s:Lerp(want,1-math.exp(-math.clamp(dt,0,.1)*(want.Magnitude>s.Magnitude+1e-3 and CRAWL_ACCEL or CRAWL_BRAKE)))
 if s.Magnitude<.01 and want.Magnitude<.01 then s=Vector3.zero end
 v.move=s
 h:Move(s,false)
end
function Controller:_CrawlPace(holder,h,dt)
 local M=require(Shared.Config.MovementConfig)
 local pace=M.VentCrawlSpeed or 5
 holder.pace=pace
 if math.abs(h.WalkSpeed-pace)>.01 then h.WalkSpeed=pace end
 h.Jump=false
 local root=h.Parent and h.Parent:FindFirstChild('HumanoidRootPart')
 if root and not root.Anchored then
  local v=root.AssemblyLinearVelocity;local flat=Vector3.new(v.X,0,v.Z)
  local axis=holder.axis
  if axis then
   -- no sideways sliding at all: only movement along the duct is kept, plus a gentle pull back to the
   -- duct's centre line (so you never drift into, or rub along, a wall)
   -- (Oct 18) the speed along the duct is SET from what you are pressing, not left to the physics: the Humanoid
    -- pushing a frictionless round hit box (plus the speed the climb-in path left on the body) made the crawl
    -- surge forward and keep sliding after you let go
    local intent=holder.move or h.MoveDirection
    local id=intent:Dot(axis);local im=intent.Magnitude -- (same fix: the pace never depends on where you look)
     local along=axis*(((im>1e-3 and math.abs(id)/im>=.35) and math.sign(id)*math.min(1,im) or 0)*pace)
   local side=Vector3.new(-axis.Z,0,axis.X)
   local pull=Vector3.zero
   if holder.volume then local off=(root.Position-holder.volume.Position):Dot(side);pull=math.abs(off)>.15 and side*math.clamp(-(off-math.sign(off)*.15)*2,-.6,.6) or Vector3.zero end
   flat=along+pull
   if flat.Magnitude>pace+.05 then flat=flat.Unit*pace end
   root.AssemblyLinearVelocity=Vector3.new(flat.X,math.min(v.Y,0),flat.Z)
  elseif flat.Magnitude>pace+.05 then flat=flat.Unit*pace;root.AssemblyLinearVelocity=Vector3.new(flat.X,math.min(v.Y,0),flat.Z) end
 end
end
-- In a duct your own body casts no shadow on this screen: the torch shines from just in front of
-- your face, so the arms and hands under it threw big black shapes on the duct floor whenever you
-- looked down. (Everyone else still sees your shadow as normal.)
-- The duct's own thin metal sheets are taken out of shadow casting too: lit by a torch only a stud
-- or two away at a grazing angle, the floor sheet shadowed itself and the floor in front of you went
-- pitch black whenever you looked down. (Locally only, and only while you're inside.)
function Controller:_VentShadows(c,on,route)
 local s=self._ventShadow
 if on and c and (not s or s.c~=c or s.route~=route) then
  if s then self:_VentShadows(nil,false) end
  s={c=c,route=route,parts={}};self._ventShadow=s
  for _,d in c:GetDescendants()do if d:IsA('BasePart') and d.CastShadow then s.parts[d]=true;d.CastShadow=false end end
  if route then for _,d in route:GetDescendants()do if d:IsA('BasePart') and d.CastShadow then s.parts[d]=true;d.CastShadow=false end end end
  s.conn=c.DescendantAdded:Connect(function(d)if d:IsA('BasePart') and d.CastShadow then s.parts[d]=true;d.CastShadow=false end end)
 elseif not on and s then
  self._ventShadow=nil
  if s.conn then s.conn:Disconnect() end
  for d in s.parts do if d.Parent then d.CastShadow=true end end
 end
end
function Controller:_Vent(dt)
 local p=self._player;local c=p.Character
 local h=c and c:FindFirstChildOfClass('Humanoid');local root=c and c:FindFirstChild('HumanoidRootPart')
 local id=p:GetAttribute('EHInVent')
 pcall(function()self:_VentShadows(c,id~=nil and c~=nil,id~=nil and (self._vent and self._vent.route or self:_FindVent(id)) or nil)end)
 local v=self._vent
 -- the duct you are lying in (CameraController keeps the lens inside it)
 Crawl.volume=(v and id and v.phase=='crawl' and v.volume) or nil
 -- climbing back in before the last exit was fully cleared: the server stamps a new EHVentAt for
 -- every entry, so a different stamp means a NEW climb. The old record (still 'exit'/'done', which
 -- hands walking pace and full-height collision back) is cleaned up and the climb starts fresh -
 -- this was the speed-up and the physics lag when you went straight back into a duct.
 if v and id and h and root and v.ventAt~=nil and p:GetAttribute('EHVentAt')~=v.ventAt and (v.phase=='done' or v.phase=='exit') then
  dropAlign(v);hold(v,v.c,v.h,false);prone(v,v.c,v.h,root,false);if v.h.Parent then v.h.AutoRotate=true;v.h.HipHeight=v.hip end
  Crawl.exitPath=nil
  self._vent=nil;v=nil
 end
 if v and (v.h~=h or not h or not root or h.Health<=0) then dropAlign(v);if v.c and v.h then hold(v,v.c,v.h,false);local r0=v.c:FindFirstChild('HumanoidRootPart');if r0 then prone(v,v.c,v.h,r0,false)end;if v.h.Parent then v.h.AutoRotate=true end end;self._vent=nil;v=nil end
 if not h or not root then return end
 if id and not v then
  local route=self:_FindVent(id);if not route then return end
  local volume;for _,d in route:GetChildren()do if d.Name=='VentVolume' then volume=d end end
  local to=route:GetAttribute('EntryFrame'..(p:GetAttribute('EHVentEnd') or 'A'));if not to then return end
  local inward=to.LookVector;local lip=to.Position-inward*1.9 -- centre of the opening, at crawl height
  local from=root.Position
  -- key points: start; crouched under the opening; springing up; hands on the lip, hanging;
  -- chest over the lip; on hands and knees inside the duct
  -- kept clear of the wall face (the body is about a stud deep), so nothing pushes into the wall,
  -- the frame or the flanges while you climb
  local under=Vector3.new(lip.X,from.Y-.5,lip.Z)-inward*1.55
  local spring=Vector3.new(lip.X,lip.Y-1.7,lip.Z)-inward*1.3
  local hang=Vector3.new(lip.X,lip.Y-1.05,lip.Z)-inward*.95
  local over=Vector3.new(lip.X,to.Position.Y+.4,lip.Z)+inward*.35
  v={id=id,c=c,h=h,route=route,volume=volume,hip=h:GetAttribute('EHStandingHipHeight') or h.HipHeight,proneHip=proneHip(c,root),
   start=workspace:GetServerTimeNow(),fromRot=root.CFrame.Rotation,to=to,
   keys={from,under,spring,hang,over,to.Position},times={0,.2,.42,.62,.84,1},phase='climb',ventAt=p:GetAttribute('EHVentAt')}
  self._vent=v
  CrouchState.wanted=true
  hold(v,c,h,true)
 end
 if not v then return end
 if v.phase=='climb' then
  local u=math.clamp((workspace:GetServerTimeNow()-v.start)/CLIMB_SECONDS,0,1)
  local turn=smooth(math.clamp(u/.3,0,1))
  drive(root,v.keys,v.times,u,CLIMB_SECONDS,v.fromRot:Lerp(v.to.Rotation,turn))
  -- the view turns with you to look down the duct as you climb in (yaw only, eased), so you come out
  -- of the climb already facing the way you'll crawl - no body swinging round afterwards
  local cam=workspace.CurrentCamera
  if cam and u<.9 then
   local look=cam.CFrame.LookVector;local flat=Vector3.new(look.X,0,look.Z)
   local inw=v.to.LookVector;inw=Vector3.new(inw.X,0,inw.Z)
   if flat.Magnitude>.05 and inw.Magnitude>.05 then
    local cur=math.atan2(-flat.X,-flat.Z);local tgt=math.atan2(-inw.X,-inw.Z)
    local d=(tgt-cur+math.pi)%(2*math.pi)-math.pi
    local step=d*(1-math.exp(-math.clamp(dt or 1/60,0,.1)*5))
    cam.CFrame=CFrame.new(cam.CFrame.Position)*CFrame.Angles(0,step,0)*cam.CFrame.Rotation
   end
  end
  -- the body only folds down to duct height as it slides in over the lip
  h.HipHeight=v.hip+(v.proneHip-v.hip)*smooth(math.clamp((u-.6)/.4,0,1))
  if u>=1 then
   root.CFrame=v.to;root.AssemblyLinearVelocity=Vector3.zero
   hold(v,c,h,false);h.HipHeight=v.proneHip;v.phase='crawl'
   prone(v,c,h,root,true)
  end
  return
 end
 if v.phase=='crawl' then
  if h.HipHeight~=v.proneHip then h.HipHeight=v.proneHip end
  CrouchState.wanted=true
  prone(v,c,h,root,true)
  -- only the round prone hitbox touches the duct: the torso and head (lying flat in the crawl pose)
  -- would scrape the walls and floor and make the crawl stick and stutter
  for _,n in {'UpperTorso','LowerTorso','Torso','Head'} do local bp=c:FindFirstChild(n);if bp and bp:IsA('BasePart') and bp.CanCollide then bp.CanCollide=false end end
  -- belly drag: no jumping or standing, and the pace surges with each two-arm pull
  self:_CrawlPace(v,h,dt)
  -- the body lies along the duct whatever way you look: looking around turns only the head-cam,
  -- and turning round to crawl back is a slow, heavy shuffle (no body swinging into the walls)
  if v.volume then
   if not v.axis then
    local s=v.volume.Size;local cf=v.volume.CFrame
    v.axis=(s.X>=s.Y and s.X>=s.Z) and cf.RightVector or (s.Z>=s.Y and cf.LookVector or cf.UpVector)
    v.axis=Vector3.new(v.axis.X,0,v.axis.Z).Unit
   end
   h.AutoRotate=false
   -- The body only turns round when you actually CRAWL the other way - never just because you look
   -- behind you (turning the body moved your eye to the other end of it, so looking back while lying
   -- still made you slide). At the start it faces the way you came in.
   local sign=v.facing
   if not sign then local f=root.CFrame.LookVector;sign=Vector3.new(f.X,0,f.Z):Dot(v.axis)>=0 and 1 or -1 end
   -- (decided by how you are actually MOVING along the duct, not by keys or the stick: a side key,
   -- or the stick's direction, never spins you round while you lie still)
   local vel=root.AssemblyLinearVelocity
   local along=Vector3.new(vel.X,0,vel.Z):Dot(v.axis)
   if math.abs(along)>1.2 then sign=along>0 and 1 or -1 end
   v.facing=sign
   ensureAlign(v,root).CFrame=CFrame.lookAt(Vector3.zero,v.axis*sign)
   -- no leftover spin from the climb
   local av=root.AssemblyAngularVelocity
   if math.abs(av.X)+math.abs(av.Z)>.01 then root.AssemblyAngularVelocity=Vector3.new(0,av.Y,0) end
  end
  if v.volume and not inVolume(v.volume,root.Position) then
   -- past one end of the duct: if that end is open, climb out and drop down to the floor below
   local best,bestE
   for _,E in {'A','B'}do local fr=v.route:GetAttribute('EntryFrame'..E);if fr then local d=(fr.Position-root.Position).Magnitude;if not best or d<best then best,bestE=d,E end end end
   local fr=bestE and v.route:GetAttribute('EntryFrame'..bestE)
   if fr then
    local outward=-fr.LookVector;local lip=fr.Position+outward*1.9
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={c};params.RespectCanCollide=true
    -- (far enough out that the eye, which is ahead of the body while you crawl, keeps moving forward
    -- as you drop - it never has to back up to where you land)
    local params0=RaycastParams.new();params0.FilterType=Enum.RaycastFilterType.Exclude;params0.FilterDescendantsInstances={c};params0.RespectCanCollide=true
    local ahead=workspace:Raycast(lip,outward*6,params0)
    local out=math.clamp(ahead and ahead.Distance-1.1 or 4.4,1.5,4.4)
    local landing=Vector3.new(lip.X,lip.Y,lip.Z)+outward*out
    local hit=workspace:Raycast(landing,Vector3.new(0,-14,0),params)
    local floorY=hit and hit.Position.Y or landing.Y-6
    local standY=floorY+v.hip+root.Size.Y/2
    local start=root.Position
    v.exitKeys={start,Vector3.new(lip.X,lip.Y-.15,lip.Z)+outward*.55,Vector3.new(landing.X,math.max(standY+.9,floorY+2.6),landing.Z)-outward*.3,Vector3.new(landing.X,standY,landing.Z)}
    v.exitTimes={0,.3,.68,1}
    v.exitRot=CFrame.lookAt(Vector3.zero,outward).Rotation
    v.exitFrom=root.CFrame.Rotation
    v.exitAt=os.clock();v.phase='exit'
    -- the eye's own path out (CameraController): from where it is now to standing height over the
    -- landing spot, leaving at the crawl's pace and arriving at rest - one smooth curve, no second
    -- dip or rise afterwards. You stand straight back up (no crouch left over from the duct).
    Crawl.exitPath={t0=os.clock(),dur=EXIT_SECONDS,to=v.exitKeys[4],rot=v.exitRot,vel=root.AssemblyLinearVelocity}
    CrouchState.wanted=false
    dropAlign(v)
    prone(v,c,h,root,false)
    hold(v,c,h,true)
   end
  elseif not id then
   dropAlign(v);h.AutoRotate=true;prone(v,c,h,root,false)
   v.phase='done'
  end
  return
 end
 if v.phase=='exit' then
  local u=math.clamp((os.clock()-v.exitAt)/EXIT_SECONDS,0,1)
  drive(root,v.exitKeys,v.exitTimes,u,EXIT_SECONDS,v.exitFrom:Lerp(v.exitRot,smooth(u/.5)))
  -- unfold from hands and knees back to standing as you drop
  h.HipHeight=v.proneHip+(v.hip-v.proneHip)*smooth(math.clamp((u-.25)/.75,0,1))
  if u>=1 then hold(v,c,h,false);h.HipHeight=v.hip;h.AutoRotate=true;v.phase='done' end
  return
 end
 if v.phase=='done' then
  dropAlign(v);prone(v,c,h,root,false)
  -- hand walking pace back to the server's value
  if v.pace then v.pace=nil;local M=require(Shared.Config.MovementConfig);h.WalkSpeed=p:GetAttribute('EHCrouching') and M.CrouchSpeed or M.WalkSpeed end
  if h.HipHeight~=v.hip then h.HipHeight=v.hip end
  -- the record is kept until the server clears EHInVent, so the climb-in is never replayed
  if not id then self._vent=nil end
 end
end
------------------------------------------------------------------ duct walls fade
-- While you are in a duct (or climbing in / out), the vent COVER you look at close up turns
-- see-through (LocalTransparencyModifier, this screen only), so you can see into the room beyond -
-- in case something is waiting there. Rubbing up against it fades it too. No pushing needed: just look. It glides in and
-- out softly, the floor under you never fades, and everyone else still sees the duct as normal.
local FADE_LOOK,FADE_TOUCH=.66,.5 -- how far a panel fades: looked at close up / brushed against
local LOOK_RANGE=5.5             -- studs: panels further away than this stay solid
local BODY_R=1.25 -- the prone body's flat collision disc (PRONE_W/2)
-- the eye's rays: straight ahead, and a little to each side, up and down (so a glance is enough)
local LOOK_RAYS={CFrame.identity,CFrame.Angles(0,math.rad(16),0),CFrame.Angles(0,math.rad(-16),0),CFrame.Angles(math.rad(13),0,0),CFrame.Angles(math.rad(-13),0,0)}
local LOOK_PARAMS=RaycastParams.new();LOOK_PARAMS.FilterType=Enum.RaycastFilterType.Include
function Controller:_DuctFade(dt)
 local v=self._vent;local camera=workspace.CurrentCamera
 local route=v and v.route
 local fr=self._fadeRoute
 if fr and fr.route~=route then
  for part in fr.parts do if part.Parent then part.LocalTransparencyModifier=0 end end
  self._fadeRoute=nil;fr=nil
 end
 if not route or not camera then return end
 if not fr then
  fr={route=route,parts={},list={}}
  -- only the vent COVERS turn see-through (to peek into the room beyond); the duct's own walls,
  -- roof and floor always stay solid
  for _,d in route:GetDescendants()do if d:IsA('BasePart') and d.Transparency<1 and d:FindFirstAncestor('VentCover') then fr.parts[d]=0;table.insert(fr.list,d) end end
  self._fadeRoute=fr
 end
 local c=self._player.Character
 local root=c and c:FindFirstChild('HumanoidRootPart')
 local view=camera.CFrame
 local eye=view.Position
 local body=root and root.Position
 -- what the eye is looking at: each panel hit gets a fade by how close it is (never the floor)
 local seen={}
 LOOK_PARAMS.FilterDescendantsInstances=fr.list
 for _,turn in LOOK_RAYS do
  local dir=(view.Rotation*turn).LookVector
  local hit=workspace:Raycast(eye,dir*LOOK_RANGE,LOOK_PARAMS)
  if hit and hit.Normal.Y<.6 then
   local k=FADE_LOOK*smooth((LOOK_RANGE-hit.Distance)/2)
   if k>(seen[hit.Instance] or 0) then seen[hit.Instance]=k end
  end
 end
 for part,cur in fr.parts do
  if part.Parent then
   local target=seen[part] or 0
   -- brushing against a wall or the end cover beside / ahead of you at body height
   if body and target<FADE_TOUCH then
    local hs=part.Size/2
    local l=part.CFrame:PointToObjectSpace(body)
    local q=part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X,-hs.X,hs.X),math.clamp(l.Y,-hs.Y,hs.Y),math.clamp(l.Z,-hs.Z,hs.Z)))
    local flat=Vector3.new(body.X-q.X,0,body.Z-q.Z)
    local gap=flat.Magnitude-BODY_R
    local beside=q.Y>body.Y-.3 and q.Y<body.Y+1.2 and flat.Magnitude>.2
    if beside and gap<.35 then target=math.max(target,FADE_TOUCH*smooth((.35-gap)/.35)) end
   end
   -- glides out over about a fifth of a second, and back in a little slower
   local rate=target>cur and 7 or 3.5
   cur+=(target-cur)*(1-math.exp(-dt*rate));if math.abs(cur-target)<.003 then cur=target end
   fr.parts[part]=cur
   if math.abs(part.LocalTransparencyModifier-cur)>.003 then part.LocalTransparencyModifier=cur end
  else fr.parts[part]=nil end
 end
end
-- Vent air: each open-able duct breathes dust and stale air out through its louvres; when a cover
-- comes away (ExhaustSource GustAt) there is a stronger gust that settles back over a few seconds.
function Controller:_VentAir()
 local now=workspace:GetServerTimeNow()
 local list=self._ventAir
 -- (rescan only when the floor in play changes, plus a slow safety sweep: walking every object in
 -- the world every 3 s was a regular frame spike on the big floors)
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 local key='';if env then for _,m in env:GetChildren()do if m:GetAttribute('EncounterId') then key..=m.Name end end end
 if not list or key~=self._ventAirKey or os.clock()-(self._ventAirScan or 0)>30 then
  self._ventAirKey=key;self._ventAirScan=os.clock();list={};self._ventAir=list
  for _,d in (runtime and runtime:GetDescendants() or {})do
   if d:IsA('ParticleEmitter') and d.Parent and d.Parent.Name=='ExhaustSource' then
    if d:GetAttribute('BaseRate')==nil then d:SetAttribute('BaseRate',d.Rate) end
    table.insert(list,d)
   end
  end
 end
 for _,e in list do
  if e.Parent then
   local gust=e.Parent:GetAttribute('GustAt')
   local k=type(gust)=='number' and math.exp(-math.max(0,now-gust)/1.4) or 0
   local rate=(e:GetAttribute('BaseRate') or e.Rate)*(1+2.2*k)
   if math.abs(e.Rate-rate)>.05 then e.Rate=rate end
  end
 end
end
function Controller:Start()
 local cc=Instance.new('ColorCorrectionEffect');cc.Name='SlipGrade';cc.Enabled=false;cc.Parent=game:GetService('Lighting');self._grade=self._scope:Add(cc)
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)pcall(self._Leaks,self,dt)end))
 self._scope:Add(RunService.PreSimulation:Connect(function()
  local t=workspace:GetServerTimeNow()
  for _,p in Players:GetPlayers()do pcall(self._Pose,self,p,t);pcall(self._VentItems,self,p)end
  for p in self._rigs do if p.Parent~=Players then self._rigs[p]=nil end end
 end))
 RunService:BindToRenderStep('EHHazardRestore',Enum.RenderPriority.Camera.Value-1,function()self:_RestoreCamera();pcall(self._MopLock,self)end)
 -- the vent climb is stepped with physics (not rendering), so it is smooth and replicates at any frame rate
 self._scope:Add(RunService.PreSimulation:Connect(function(dt)
  local ok,err=pcall(self._Vent,self,dt);if not ok then warn(err)end
  -- shared with CameraController / CrawlController: the body is on a scripted path (climb in or out),
  -- and whether you are on the way out (the eye starts rising with the body, not after it)
  local v=self._vent
  Crawl.scripted=v~=nil and (v.phase=='climb' or v.phase=='exit')
  Crawl.exiting=v~=nil and (v.phase=='exit' or v.phase=='done')
 end))
 -- (right after the control module, which runs at Input priority)
 RunService:BindToRenderStep('EHCrawlSteer',Enum.RenderPriority.Input.Value+2,function(dt)local ok,err=pcall(self._CrawlSteer,self,dt);if not ok then warn(err)end end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('EHCrawlSteer')end)
 RunService:BindToRenderStep('EHHazardDuct',Enum.RenderPriority.Camera.Value+6,function(dt)
  dt=math.clamp(dt,0,.1)
  local ok,err=pcall(self._DuctFade,self,dt);if not ok then warn(err)end
 end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('EHHazardDuct')end)
 self._scope:Add(RunService.Heartbeat:Connect(function()pcall(self._VentAir,self)end))
 RunService:BindToRenderStep('EHHazardCamera',Enum.RenderPriority.Camera.Value+4,function(dt)local ok,err=pcall(self._Camera,self,dt);if not ok then warn(err)end end)
 RunService:BindToRenderStep('EHHazardMop',Enum.RenderPriority.Camera.Value+5,function(dt)local ok,err=pcall(self._ViewModel,self,math.clamp(dt,0,.1));if not ok then warn(err)end end)
 -- every hand-held mop is posed through its MopGrip joint after the Animator has run and before the
 -- physics step (PreSimulation), so the pose is what actually gets simulated, replicated and drawn
 self._scope:Add(RunService.PreSimulation:Connect(function(dt)local ok,err=pcall(self._Scrub,self,math.clamp(dt,0,.1));if not ok then warn(err)end end))
 self._scope:Add(function()RunService:UnbindFromRenderStep('EHHazardRestore');RunService:UnbindFromRenderStep('EHHazardCamera');RunService:UnbindFromRenderStep('EHHazardMop')end)
end
function Controller:Destroy()
 self:_RestoreCamera()
 if self._vm then self._vm:Destroy()end
 if self._fadeRoute then for part in self._fadeRoute.parts do if part.Parent then part.LocalTransparencyModifier=0 end end end
 if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
