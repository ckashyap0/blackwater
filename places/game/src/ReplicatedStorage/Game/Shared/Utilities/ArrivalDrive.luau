--!nonstrict
-- THE ARRIVAL (client presentation). Two drives, both played from server clocks on the yard:
--  1. Play (ArrivalCarAt, ElevatorService._ArrivalCar): two typed lines over black, the crew's car comes
--     along the highway, turns up the access road and stops at the closed checkpoint barrier. The
--     picture fades back in with everyone standing beside the car (no wake-up yet).
--  2. (on foot) someone checks in at the gatehouse window (E), then everyone gets back in the car (E).
--     Getting in is never shown: you go to black and wait for the rest of the crew (WatchCar).
--  3. PlayGate (GateDriveAt, ElevatorService._GateDrive): the red-and-white barrier swings up, the car
--     drives through and parks in its bay in the car park, black - then the wake-up
--     (AtmosphereController._StartWake) beside the parked car.
-- Seats fit the crew (up to four); the passengers are seated, anchored local copies of the crew.
-- Nothing here touches the server.
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local CAS=game:GetService('ContextActionService')
local M={}
-- (Nov 4, Ryan's script - a little sleepy)
M.Lines={"I did not want to get up at 5 this morning.","On the bright side, I'm starting a new job today.","The place looked old and run down, but maybe that's just how water facilities are.","Better get going before I'm late."}
-- (cruise: the first seconds of the drive, the car simply bowling along the highway seen from beside it)
-- (the lines play one after another and SPACE skips to the next; the drive waits for the last one)
local T={line1=.6,cps=32,lineHold=1.6,textFade=.6,lineGap=.2,driveAt=9.7,reveal=1.0,cruise=6,drive=14.3,park=1.0,fade=.8,fadeIn=1.1,outHold=2.4}
local DRIVE_END=T.driveAt+T.cruise+T.drive
local FADE_AT=DRIVE_END+T.park
M.Total=FADE_AT+T.fade
-- the gate drive: barrier up, through, into the bay
local G={fadeOut=.6,reveal=1.2,revealLen=.8,armAt=2.0,armLen=2.6,driveAt=3.9,drive=11.5,park=.8,fade=.8}
G.DRIVE_END=G.driveAt+G.drive
G.FADE_AT=G.DRIVE_END+G.park
M.GateBlackAt=G.FADE_AT+G.fade      -- the screen is fully black from here (the server moves everyone then)
M.GateTotal=M.GateBlackAt+.1
local Y0=102.15 -- road-top height as authored (the yard is lowered at runtime: Y is read from the car)
-- (seated well back on the cushions and reclined a little, so heads stay clear of the windscreen and roof)
local SEATS={Vector3.new(-1.45,0,-.5),Vector3.new(1.45,0,-.5),Vector3.new(-1.45,0,3.0),Vector3.new(1.45,0,3.0)}
local RECLINE=CFrame.Angles(math.rad(9),0,0)
local CUSHION=1.85 -- seat cushion top (car space)
local HEAD_MAX=4.7 -- highest anything (head, hair, hats) may reach: under the roof lining (5.0)
local TYRE_R=1.2
local SHOT_DIP=.32
local function smooth(u)u=math.clamp(u,0,1);return u*u*(3-2*u)end
local function smoother(u)u=math.clamp(u,0,1);return u*u*u*(u*(u*6-15)+10)end
------------------------------------------------------------------ paths
local Path={};Path.__index=Path
local function newPath(pts)
 local len={0}
 for i=2,#pts do len[i]=len[i-1]+(pts[i]-pts[i-1]).Magnitude end
 return setmetatable({pts=pts,len=len,L=len[#len]},Path)
end
function Path:pos(s)
 local pts,len=self.pts,self.len
 s=math.clamp(s,0,self.L)
 for i=2,#pts do if len[i]>=s then local a=(s-len[i-1])/math.max(1e-6,len[i]-len[i-1]);return pts[i-1]:Lerp(pts[i],a) end end
 return pts[#pts]
end
function Path:dir(s)
 local d=self:pos(s+2.5)-self:pos(s-2.5)
 if d.Magnitude<1e-3 then d=self:pos(self.L)-self:pos(self.L-1) end
 return d.Unit
end
function Path:cf(s)local p=self:pos(s);return CFrame.lookAt(p,p+self:dir(s))end
local function bezier(add,P0,P1,P2,P3,n)
 for i=1,n do local t=i/n;local mt=1-t;local p=P0*mt^3+P1*3*mt*mt*t+P2*3*mt*t*t+P3*t^3;add(p.X,p.Y) end
end
-- along the highway (eastbound lane), a right turn up the access road, then up to the stop
local function arrivalPath(Y,stop,x0)
 local pts={};local function add(x,z)table.insert(pts,Vector3.new(x,Y,z))end
 for x=x0 or -175,stop.X-26,3 do add(x,-437.5) end
 -- (Oct 25) one smooth bezier turn: the steering winds on and off gradually (no kink in or out)
 add(stop.X-24,-437.5)
 bezier(function(x,z)add(x,z)end,Vector2.new(stop.X-24,-437.5),Vector2.new(stop.X-10.5,-437.5),Vector2.new(stop.X,-433.5),Vector2.new(stop.X,-421),44)
 local z=-421;while z<stop.Z-1.5 do z+=1.5;add(stop.X,math.min(z,stop.Z)) end
 add(stop.X,stop.Z)
 return newPath(pts)
end
-- from the barrier straight up the access road, then an S into the bay
local function gatePath(Y,from,bay)
 local pts={};local function add(x,z)table.insert(pts,Vector3.new(x,Y,z))end
 local z=from.Z;add(from.X,z)
 local R,zt,za=8,-305,-297 -- turn off the road at zt, along the car-park link at za (clear of the hedges), into the bay
 while z<zt do z=math.min(z+1.5,zt);add(from.X,z) end
 local c1=Vector2.new(from.X-R,zt)
 for i=1,16 do local a=(i/16)*math.pi/2;add(c1.X+R*math.cos(a),c1.Y+R*math.sin(a)) end
 local x=c1.X;local x2=bay.X+R
 while x>x2 do x=math.max(x-1.5,x2);add(x,za) end
 local c2=Vector2.new(x2,za+R)
 for i=1,16 do local a=-math.pi/2-(i/16)*math.pi/2;add(c2.X+R*math.cos(a),c2.Y+R*math.sin(a)) end
 z=c2.Y;while z<bay.Z do z=math.min(z+1.5,bay.Z);add(bay.X,z) end
 return newPath(pts)
end
local function yawOf(v)return math.atan2(-v.X,-v.Z)end
-- (Oct 23 c) a natural speed along a path: pulls away gently, holds its speed on the straights,
-- slows into each bend (lateral grip limit) and eases to a stop at the end. The whole profile is
-- scaled to take exactly `dur` seconds. Returns sAt(u) for u = 0..1 of that time, and speedAt(s) in studs/s.
local function speedProfile(path,dur)
 local L=path.L;local N=math.max(8,math.ceil(L/.5));local ds=L/N
 local GRIP,ACC,DEC,VC=.017,.016,.006,.6 -- (in units of the straight-line speed: a radius-8 bend is taken at ~45%)
 local v={}
 for i=0,N do
  local sp=i*ds
  local a,b=path:dir(math.max(0,sp-1.5)),path:dir(math.min(L,sp+1.5))
  local k=math.acos(math.clamp(a:Dot(b),-1,1))/3
  v[i]=math.min(VC,k>1e-4 and math.sqrt(GRIP/k) or 1) -- (Oct 25) never faster than one steady cruise
 end
 -- from the first bend to the bay: one steady speed (the bend speed) - no speeding up between or after the bends
 local firstBend;for i=0,N do if v[i]<VC-.001 then firstBend=i;break end end
 if firstBend then local vb=1;for i=firstBend,N do vb=math.min(vb,v[i]) end;for i=firstBend,N do v[i]=vb end end
 v[0]=0;v[N]=0
 for i=1,N do v[i]=math.min(v[i],math.sqrt(v[i-1]^2+2*ACC*ds)) end
 for i=N-1,0,-1 do v[i]=math.min(v[i],math.sqrt(v[i+1]^2+2*DEC*ds)) end
 local T={0}
 for i=1,N do T[i+1]=T[i]+ds/math.max((v[i]+v[i-1])/2,.02) end
 local Tn=T[N+1]
 local function sAt(u)
  local t=math.clamp(u,0,1)*Tn
  local lo,hi=1,N+1
  while hi-lo>1 do local m=(lo+hi)//2;if T[m]<=t then lo=m else hi=m end end
  local f=(t-T[lo])/math.max(T[hi]-T[lo],1e-6)
  return math.min(L,((lo-1)+f)*ds)
 end
 local function speedAt(sp)local i=math.clamp(math.floor(sp/ds),0,N);return v[i]*Tn/dur end
 return sAt,speedAt
end
------------------------------------------------------------------ the car copy
local function setHidden(m,hide)
 for _,d in m:GetDescendants()do
  if d:IsA('BasePart') or d:IsA('Decal') then d.LocalTransparencyModifier=hide and 1 or 0
  elseif d:IsA('Light') then
   if hide then if d.Enabled then d:SetAttribute('ArrivalOff',true);d.Enabled=false end
   elseif d:GetAttribute('ArrivalOff') then d:SetAttribute('ArrivalOff',nil);d.Enabled=true end
  end
 end
end
local function copyCar(orig,folder)
 local copy=orig:Clone();copy.Name='ArrivalDriveCar';copy.Parent=folder
 local parts={}
 for _,d in copy:GetDescendants()do
  if d:IsA('BasePart') then d.CastShadow=false;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;local lc=d:GetAttribute('CarLocal');if lc then table.insert(parts,{p=d,l=lc}) end end
 end
 for _,n in {'Collision','CarGetIn'} do local c=copy:FindFirstChild(n);if c then c:Destroy() end end
 local axle={}
 for _,e in parts do local k=e.p.Name:match('^Car_Tyre(%u%u)$');if k then axle[k]=e.l.Position end end
 for _,e in parts do local k=e.p.Name:match('^Car_Tyre(%u%u)$') or e.p.Name:match('^Car_Hub(%u%u)$');if k and axle[k] then e.axle=axle[k];e.front=k:sub(1,1)=='F' end end
 return copy,parts
end
local function poseCar(parts,cf,spin,steer)
 for _,e in parts do
  if e.axle then
   local a=e.axle
   e.p.CFrame=cf*CFrame.new(a)*CFrame.Angles(0,e.front and steer or 0,0)*CFrame.Angles(spin,0,0)*CFrame.new(-a)*e.l
  else e.p.CFrame=cf*e.l end
 end
end
------------------------------------------------------------------ passengers
-- seated pose (joint transforms; the copy has no Animator, so nothing resets them)
local POSE={
 LeftHip=CFrame.Angles(math.rad(88),0,math.rad(-4)),RightHip=CFrame.Angles(math.rad(88),0,math.rad(4)),
 LeftKnee=CFrame.Angles(math.rad(-84),0,0),RightKnee=CFrame.Angles(math.rad(-84),0,0),
 LeftShoulder=CFrame.Angles(math.rad(22),0,0),RightShoulder=CFrame.Angles(math.rad(22),0,0),
 LeftElbow=CFrame.Angles(math.rad(55),0,0),RightElbow=CFrame.Angles(math.rad(55),0,0),
 ['Left Hip']=CFrame.Angles(0,0,math.rad(-90)),['Right Hip']=CFrame.Angles(0,0,math.rad(90)),
}
local DRIVER={LeftShoulder=CFrame.Angles(math.rad(58),0,math.rad(8)),RightShoulder=CFrame.Angles(math.rad(58),0,math.rad(-8)),
 LeftElbow=CFrame.Angles(math.rad(25),0,0),RightElbow=CFrame.Angles(math.rad(25),0,0)}
local function passenger(ch,folder,driver)
 local was=ch.Archivable;ch.Archivable=true;local ok,c=pcall(function()return ch:Clone()end);ch.Archivable=was
 if not ok or not c then return nil end
 for _,d in c:GetDescendants()do
  if d:IsA('LuaSourceContainer') or d:IsA('ForceField') or d:IsA('Tool') or d:IsA('Sound') or d:IsA('BillboardGui') or d:IsA('Light') or d:IsA('Animator') then d:Destroy()
  elseif d:IsA('BasePart') then d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.LocalTransparencyModifier=0 end
 end
 for k in c:GetAttributes()do c:SetAttribute(k,nil)end
 c.Name='ArrivalPassenger'
 local hum=c:FindFirstChildOfClass('Humanoid');local root=c:FindFirstChild('HumanoidRootPart')
 if not hum or not root then c:Destroy();return nil end
 hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None;hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff
 hum.PlatformStand=true;hum.EvaluateStateMachine=false
 c.Parent=folder
 -- the joint tree from the root, solved by hand every frame (all anchored: no one-frame lag).
 -- Current avatars are rigged with AnimationConstraints between rig attachments (older ones Motor6Ds).
 local joints={}
 for _,j in c:GetDescendants()do
  if (j:IsA('Motor6D') or j:IsA('Weld')) and j.Part0 and j.Part1 then table.insert(joints,{inst=j,a=j.Part0,b=j.Part1,c0=j.C0,c1=j.C1,name=j.Name})
  elseif j:IsA('WeldConstraint') and j.Part0 and j.Part1 then table.insert(joints,{a=j.Part0,b=j.Part1,name=j.Name})
  elseif (j:IsA('AnimationConstraint') or j:IsA('RigidConstraint')) and j.Attachment0 and j.Attachment1 and j.Attachment0.Parent:IsA('BasePart') and j.Attachment1.Parent:IsA('BasePart') then
   table.insert(joints,{inst=j,att=true,a=j.Attachment0.Parent,b=j.Attachment1.Parent,c0=j.Attachment0.CFrame,c1=j.Attachment1.CFrame,name=j.Name}) end
 end
 local order,seen={}, {[root]=true}
 local changed=true
 while changed do
  changed=false
  for _,j in joints do
   if not j.done then
    if seen[j.a] and not seen[j.b] then j.done=true;seen[j.b]=true;table.insert(order,j);changed=true
    elseif seen[j.b] and not seen[j.a] then j.a,j.b=j.b,j.a;j.inv=true;j.done=true;seen[j.b]=true;table.insert(order,j);changed=true end
   end
  end
 end
 local function capture()for _,j in order do if not j.inst then j.off=j.a.CFrame:ToObjectSpace(j.b.CFrame) end end end
 capture()
 for _,d in c:GetDescendants()do
  if d:IsA('JointInstance') or d:IsA('WeldConstraint') or d:IsA('Constraint') then pcall(function()d.Enabled=false end) end
  if d:IsA('BasePart') then d.Anchored=true;if not seen[d] then d.LocalTransparencyModifier=1;d.Transparency=1 end end
 end
 local pose={}
 for _,j in order do pose[j]=(driver and DRIVER[j.name]) or POSE[j.name] or CFrame.identity end
 local function rel(j,useTr)
  if j.off then return j.off end
  local m=j.c0*(useTr and pose[j] or CFrame.identity)*j.c1:Inverse()
  return j.inv and m:Inverse() or m
 end
 local function solve(rootCF,useTr)
  root.CFrame=rootCF
  for _,j in order do j.b.CFrame=j.a.CFrame*rel(j,useTr) end
 end
 local function hipY()
  for _,j in order do if (j.name=='LeftHip' or j.name=='Left Hip') and j.c0 then return (j.a.CFrame*(j.inv and j.c1 or j.c0)).Position.Y end end
  return -1
 end
 solve(CFrame.identity,false)
 local rootY=CUSHION+.45-hipY()
 -- the tallest point of the whole avatar (hair, hoods and hats included) stays under the roof
 local top=-1e9
 for _,q in c:GetDescendants()do if q:IsA('BasePart') and seen[q] and q~=root then top=math.max(top,rootY+q.Position.Y+q.Size.Y/2) end end
 if top>HEAD_MAX then
  local hipAt=CUSHION+.45
  local sc=math.clamp((HEAD_MAX-hipAt)/(top-hipAt),.5,1)
  if pcall(function()c:ScaleTo(sc)end) then
   for _,j in order do if j.att then j.c0=j.inst.Attachment0.CFrame;j.c1=j.inst.Attachment1.CFrame elseif j.inst then j.c0=j.inst.C0;j.c1=j.inst.C1 end end
   capture()
   rootY=CUSHION+.45-hipY()
  end
 end
 return {model=c,root=root,rootY=rootY,solve=function(cf)solve(cf,true)end}
end
local function seatAll(folder,list) -- list: {{player=,seat=}}
 local out={}
 for _,e in list do
  local ch=e.player.Character
  if ch and ch:FindFirstChild('HumanoidRootPart') then
   local ok,ps=pcall(passenger,ch,folder,e.seat==1)
   if ok and ps then ps.seat=e.seat;table.insert(out,ps) end
  end
 end
 return out
end
local function placeCrew(passengers,cf)
 for _,p in passengers do local seat=SEATS[p.seat] or SEATS[1];p.solve(cf*CFrame.new(seat.X,p.rootY,seat.Z)*RECLINE) end
end
------------------------------------------------------------------ screen + crew hiding
local function newScreen(player,name)
 local gui=Instance.new('ScreenGui');gui.Name=name;gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=60;gui.ScreenInsets=Enum.ScreenInsets.None
 local black=Instance.new('Frame');black.Name='Black';black.Size=UDim2.fromScale(1,1);black.BackgroundColor3=Color3.new(0,0,0);black.BorderSizePixel=0;black.Parent=gui
 gui.Parent=player:WaitForChild('PlayerGui')
 return gui,black
end
local hideCount=0
local function crewHidden(on)
 hideCount+=on and 1 or -1
 if on and hideCount==1 then
  RunService:BindToRenderStep('BlackwaterArrivalHide',Enum.RenderPriority.Last.Value+5,function()
   for _,p in Players:GetPlayers()do local ch=p.Character
    if ch then for _,d in ch:GetDescendants()do if d:IsA('BasePart') or d:IsA('Decal') then d.LocalTransparencyModifier=1 end end end
   end
  end)
 elseif not on and hideCount==0 then
  RunService:UnbindFromRenderStep('BlackwaterArrivalHide')
  for _,p in Players:GetPlayers()do if p.Character and not p:GetAttribute('EHInCar') then for _,d in p.Character:GetDescendants()do if d:IsA('BasePart') or d:IsA('Decal') then d.LocalTransparencyModifier=0 end end end end
 end
end
local function handBack(player,camera,fov0)
 local ch=player.Character;local head=ch and ch:FindFirstChild('Head');local f=ch and ch:GetAttribute('EHFacing')
 if head then local d=typeof(f)=='Vector3' and Vector3.new(f.X,0,f.Z) or Vector3.zAxis;if d.Magnitude<.05 then d=Vector3.zAxis end;camera.CFrame=CFrame.lookAt(head.Position,head.Position+d.Unit) end
 camera.CameraType=Enum.CameraType.Custom;camera.FieldOfView=fov0
end
-- one-shot sound effects (2D, local to this screen)
local SFX={door=121381393291287,door2=133231702959443,open=119661318727626,belt=9120394153,steps=74849259058998,start=5830481291,stop=112900933408192,beep=9125540218,servo=9118433430}
local function sfx(name,vol,speed,delay,len)
 task.delay(delay or 0,function()
  local e=Instance.new('Sound');e.SoundId='rbxassetid://'..SFX[name];e.Volume=vol or .5;e.PlaybackSpeed=speed or 1
  e.Parent=game:GetService('SoundService');e:Play();e.Ended:Once(function()e:Destroy()end);task.delay(len or 12,function()if e.Parent then e:Destroy() end end)
 end)
end
M.Sfx=sfx
-- While a cutscene car is moving, the yard's shadow-casting lamps cast no shadows on this screen: their
-- shadow maps only refresh every few frames, so a moving car's shadow lagged and flickered as it drove
-- and turned. (Restored as soon as the cutscene ends.)
local quieted,yardLights,culled,lastCull={},{},{},0
local function lightPos(l)local p=l.Parent;if p:IsA('Attachment') then return p.WorldPosition elseif p:IsA('BasePart') then return p.Position end end
local function lampShadows(yard,quiet)
 if quiet then
  if not yard then return end
  table.clear(yardLights)
  for _,l in yard:GetDescendants()do if (l:IsA('SpotLight') or l:IsA('PointLight') or l:IsA('SurfaceLight')) then
   if l.Shadows then l.Shadows=false;quieted[l]=true end
   local p=l.Parent;if not (p:GetAttribute('BlinkRate') or p:GetAttribute('GateStatus') or p:GetAttribute('Flicker')) then table.insert(yardLights,l) end
  end end
 else
  for l in quieted do if l.Parent then l.Shadows=true end end
  table.clear(quieted)
  for l in culled do if l.Parent then l.Enabled=true end end
  table.clear(culled);table.clear(yardLights)
 end
end
-- Far-off yard lights are switched off on this screen while a cutscene car moves (their glow is never
-- seen from the shot): fewer lights in view keeps the renderer from dropping the headlights' pool on the
-- road for a frame, which is what flickered at the start and in the turns.
local function cullFar(camPos)
 if os.clock()-lastCull<.3 then return end;lastCull=os.clock()
 for _,l in yardLights do
  local p=l.Parent and lightPos(l)
  if p then
   local far=(p-camPos).Magnitude>170
   if far and l.Enabled and not culled[l] then l.Enabled=false;culled[l]=true
   elseif not far and culled[l] then l.Enabled=true;culled[l]=nil end
  end
 end
end
-- getting out of the car (getting in is in WatchCar): door open, step out, doors shut
local function getOut(d)d=d or 0;sfx('open',.5,1,d+.3);sfx('open',.35,.93,d+.6);sfx('steps',.4,1,d+.95,1.25);sfx('door',.55,1,d+1.6);sfx('door2',.4,.95,d+2.0) end
local function engineFor(copy,folder)
 local e=Instance.new('Sound');e.SoundId='rbxassetid://9112889325';e.Looped=true;e.Volume=0;e.RollOffMaxDistance=200;e.Parent=copy.PrimaryPart or folder;e:Play()
 return e
end
------------------------------------------------------------------ 1. the drive up to the barrier
-- opts: player, yard (or env to find it in), cover (join cover gui), fadeIn (fade up instead of a wake-up), onDone()
function M.Play(opts)
 local player,yard=opts.player,opts.yard
 local gui,black=newScreen(player,'ArrivalDrive')
 -- (Nov 4) the look is authored in StarterGui.ArrivalText (Line, SkipPrompt): same font and fixed size as the talk
 -- box; a long line wraps onto the next line, still centred (never shrinks)
 local tpl=player:WaitForChild('PlayerGui'):WaitForChild('ArrivalText',5) or game.StarterGui:FindFirstChild('ArrivalText')
 local lines={}
 for i=1,#M.Lines do
  local l=tpl.Line:Clone();l.Name='Line'..i;l.Text='';l.Parent=gui
  lines[i]=l
 end
 local linePos=lines[1].Position
 if opts.cover then task.defer(function()if opts.cover.Parent then opts.cover:Destroy() end end) end
 player:SetAttribute('EHCinematic',true)
 local prompt=tpl.SkipPrompt:Clone();prompt.TextTransparency=1;prompt.Parent=gui
 prompt.Text=game:GetService('UserInputService').TouchEnabled and not game:GetService('UserInputService').KeyboardEnabled and 'Tap to skip' or 'Press SPACE to skip'
 local skipReq=false
 prompt.Activated:Connect(function()skipReq=true end)
 CAS:BindActionAtPriority('BWArrivalSkip',function(_,st)if st==Enum.UserInputState.Begin then skipReq=true end;return Enum.ContextActionResult.Sink end,false,Enum.ContextActionPriority.High.Value+50,Enum.KeyCode.Space,Enum.KeyCode.ButtonA)
 local function unbindSkip()pcall(function()CAS:UnbindAction('BWArrivalSkip')end);if prompt.Parent then prompt:Destroy() end end
 local done=false
 local orig,passengers,conn,engine,folder,hid=nil,{},nil,nil,nil,false
 local camera=workspace.CurrentCamera;local fov0=camera.FieldOfView
 -- (Oct 25) no touch controls popping up during the arrival cutscene
 local pg=Players.LocalPlayer:FindFirstChild('PlayerGui');local pc=pg and pg:FindFirstChild('PlayerControls');local pcWas=pc and pc.Enabled
 if pc then pc.Enabled=false end;local tcWas=game.GuiService.TouchControlsEnabled;pcall(function()game.GuiService.TouchControlsEnabled=false end)
 local function finish()
  if done then return end
  done=true
  if pc and pcWas~=nil then pc.Enabled=pcWas end;pcall(function()game.GuiService.TouchControlsEnabled=tcWas end)
  if conn then conn:Disconnect() end
  if hid then crewHidden(false) end
  lampShadows(nil,false)
  if engine then engine:Destroy() end
  if folder then folder:Destroy() end
  if orig then setHidden(orig,false) end
  unbindSkip()
  handBack(player,camera,fov0)
  black.BackgroundTransparency=0
  for _,l in lines do l.Visible=false end
  local function handOff()local ok,err=pcall(opts.onDone);if not ok then warn('[ElevatorHorror] arrival drive hand-off: '..tostring(err)) end end
  if opts.fadeIn then
   -- a moment in the dark to get out (door, footsteps, doors shut), then the picture fades back up beside the car
   getOut(0)
   local t0=os.clock()+T.outHold
   task.delay(T.outHold-.05,function()handBack(player,camera,fov0);handOff()end)
   local c;c=RunService.RenderStepped:Connect(function()
    local a=math.clamp((os.clock()-t0)/T.fadeIn,0,1)
    black.BackgroundTransparency=smooth(a)
    if a>=1 then c:Disconnect();gui:Destroy() end
   end)
  else
   handOff()
   task.delay(.15,function()gui:Destroy()end)
  end
 end
 task.spawn(function()
  yard=yard or (opts.env and opts.env:WaitForChild('SurfaceYard',15))
  if not yard then finish();return end
  local t0=yard:GetAttribute('ArrivalCarAt')
  local waitStart=os.clock()
  while not t0 and os.clock()-waitStart<25 and yard.Parent do task.wait(.1);t0=yard:GetAttribute('ArrivalCarAt') end
  if not t0 or workspace:GetServerTimeNow()-t0>M.Total-.5 then finish();return end
  local base=os.clock()-(workspace:GetServerTimeNow()-t0)
  orig=yard:FindFirstChild('ArrivalCar',true)
  if not orig or not orig.PrimaryPart then finish();return end
  local endCF=orig.PrimaryPart.CFrame
  local Y=endCF.Position.Y;local DY=Vector3.new(0,Y-Y0,0)
  local Lb=arrivalPath(Y,endCF.Position).L
  local v0=2.3*Lb/T.drive              -- highway speed (where the old start began)
  local extra=v0*T.cruise
  local path=arrivalPath(Y,endCF.Position,-175-extra)
  local L=path.L
  folder=Instance.new('Folder');folder.Name='ArrivalDriveLocal';folder.Parent=workspace
  lampShadows(yard,true)
  local copy,parts=copyCar(orig,folder)
  setHidden(orig,true)
  -- passengers: seat i <- whoever stands on YardSpawn i
  local spawns=yard:FindFirstChild('YardSpawns')
  local list,taken={},{}
  for i=1,4 do
   local spot=spawns and spawns:FindFirstChild('YardSpawn'..i)
   if spot then
    local best,bd
    for _,p in Players:GetPlayers()do local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart');if r and not taken[p] then local d=(r.Position-spot.Position).Magnitude;if d<7 and (not bd or d<bd) then best,bd=p,d end end end
    if best then taken[best]=true;table.insert(list,{player=best,seat=i}) end
   end
  end
  passengers=seatAll(folder,list);for _,d in folder:GetDescendants()do if d:FindFirstAncestor('ArrivalPassenger') and (d:IsA('BasePart') or d:IsA('Decal')) then d.Transparency=1 end end
  hid=true;crewHidden(true)
  engine=engineFor(copy,folder)
  -- headlights come up gradually once the picture is revealed
  local heads={};for _,l in copy:GetDescendants()do if l:IsA('SpotLight') then heads[l]=l.Brightness;l.Brightness=0 end end
  task.spawn(function()while folder.Parent do local t=os.clock()-base;local k=math.clamp((t-T.driveAt)/1.8,0,1);k=k*k*(3-2*k);for l,b in heads do l.Brightness=b*k end;if k>=1 then break end;RunService.RenderStepped:Wait() end end)
  camera.CameraType=Enum.CameraType.Scriptable;camera.FieldOfView=55
  local WIDE=Vector3.new(-40,106,-447)+DY
  local GH0,GH1=Vector3.new(-5.9,106.7,-368.8)+DY,Vector3.new(-5.6,106.2,-371.0)+DY
  local SHOT_AT={.42,.8}
  local MAIN=T.driveAt+T.cruise
  local function sAt(t)local u=math.clamp((t-MAIN)/T.drive,0,1);return t<MAIN and v0*math.max(0,t-T.driveAt) or extra+Lb*(1-(1-u)^2.3) end
  local sCut=(endCF.Position.X-16)-(-175-extra)-10 -- just before the turn off the highway: one unbroken tracking shot until then
  local tCut do local lo,hi=T.driveAt,DRIVE_END;for _=1,30 do local mid=(lo+hi)/2;if sAt(mid)<sCut then lo=mid else hi=mid end end;tCut=lo end
  local tLast=MAIN+SHOT_AT[2]*T.drive
  local camPos,camLook,steer,lastShot,camYaw=nil,nil,0,nil,nil
  local sfxDone={}
  -- (the words start when this screen is ready, not on the server clock)
  local txBase=os.clock();local textDone=os.clock()-base>T.driveAt+2;local cur,lineStart,lineEnd=1,T.line1,nil
  if textDone then for _,l in lines do l.Visible=false end;unbindSkip() end
  local tWide=MAIN+SHOT_AT[1]*T.drive
  local xm=path:pos(extra).X -- where the car is when the old wide shot began
  conn=RunService.RenderStepped:Connect(function(dt)
   dt=math.min(dt,1/20)
   local t=os.clock()-base
   if not textDone then
    local tx=os.clock()-txBase;local line=M.Lines[cur]
    lineEnd=lineEnd or (lineStart+#line/T.cps+T.lineHold)
    if skipReq then skipReq=false;if tx>=lineStart then lineEnd=math.min(lineEnd,tx) end end
    for i,l in lines do l.Visible=i==cur and tx>=lineStart end
    local l=lines[cur];local n=math.clamp(math.floor((tx-lineStart)*T.cps),0,#line)
    l.Text=string.sub(line,1,n)..'<font transparency="1">'..string.sub(line,n+1)..'</font>'
    -- each line types in, holds, then fades out while drifting gently down (eased, no snap)
    local out=tx<lineEnd and 0 or smooth((tx-lineEnd)/T.textFade)
    l.TextTransparency=out
    l.Position=linePos+UDim2.fromOffset(0,math.floor(10*out+.5))
    local pv=tx>=lineStart+.25 and tx<lineEnd
    if prompt.Parent then prompt.TextTransparency+=((pv and .3 or 1)-prompt.TextTransparency)*(1-math.exp(-dt*(pv and 6 or 14))) end
    if tx>=lineEnd+T.textFade then
     l.Visible=false;cur+=1;lineEnd=nil;lineStart=tx+T.lineGap
     if cur>#M.Lines then textDone=true;unbindSkip();if t<T.driveAt then base=os.clock()-T.driveAt;t=T.driveAt end end
    end
    if not textDone and t>=T.driveAt then t=T.driveAt-.001;base=os.clock()-t end -- the drive waits for the words
   end
   local fadeAt=FADE_AT
   

   local b=1
   if t>=T.driveAt then b=1-smooth((t-T.driveAt)/T.reveal) end
   if t>=fadeAt then b=smooth((t-fadeAt)/T.fade) end
   for _,tc in {tWide,tLast} do b=math.max(b,1-smooth(math.abs(t-tc)/SHOT_DIP)) end
   black.BackgroundTransparency=1-b
   if t>=fadeAt+T.fade then finish();return end
   -- the car (fast off the highway, easing to a stop at the barrier)
   local u=math.clamp((t-MAIN)/T.drive,0,1)
   local s=t<MAIN and v0*math.max(0,t-T.driveAt) or extra+Lb*(1-(1-u)^2.3)
   local cf=path:cf(s)
   local dy=yawOf(path:dir(s+4))-yawOf(path:dir(s));dy=(dy+math.pi)%(2*math.pi)-math.pi
   steer+=(math.clamp(dy*1.6,-.55,.55)-steer)*(1-math.exp(-dt*8))
   local ek=smooth((s-(L-6))/6)
   if ek>0 then cf=cf:Lerp(endCF,ek);steer*=1-ek end
   poseCar(parts,cf,-s/TYRE_R,steer)
   placeCrew(passengers,cf)
   local speed=t<MAIN and v0 or ((t<DRIVE_END) and 2.3*Lb*(1-u)^1.3/T.drive or 0)
   engine.Volume=math.clamp(.15+speed*.012,0,.45)*(1-b)*(1-smooth((t-DRIVE_END)/.35));engine.PlaybackSpeed=.7+math.min(speed,40)*.012
   -- camera: across the highway -> behind the car -> from beside the gatehouse as it pulls up
   local target=cf.Position+Vector3.new(0,2.2,0)
   local shot=(t<tWide and 1) or (t<tLast and 2) or 3
   local wantPos,wantLook
   if shot==0 then wantPos=(cf*CFrame.new(-7.5,2.6,-2.5)).Position;wantLook=(cf*CFrame.new(0,1.7,-3)).Position -- alongside it on the highway
   elseif shot==1 then local cx=cf.Position.X;wantPos=Vector3.new(cx<xm and WIDE.X-(xm-cx)*.75 or WIDE.X,WIDE.Y,WIDE.Z);wantLook=target -- across the highway, one unbroken shot
   elseif shot==2 then -- chase: the camera swings round after the car lazily, not locked to its nose
     local hy=yawOf(path:dir(s));camYaw=camYaw and camYaw+((hy-camYaw+math.pi)%(2*math.pi)-math.pi)*(1-math.exp(-dt*1.8)) or hy
     local ccf=CFrame.new(cf.Position)*CFrame.Angles(0,camYaw,0);wantPos=(ccf*CFrame.new(3.8,5.8,20)).Position;wantLook=(ccf*CFrame.new(0,2.2,-12)).Position
   else
    local push=smooth((t-(MAIN+SHOT_AT[2]*T.drive))/(T.drive*(1-SHOT_AT[2])+T.park))
    wantPos=GH0:Lerp(GH1,push);wantLook=target
   end
   if shot~=lastShot or not camPos then camPos,camLook=wantPos,wantLook;lastShot=shot end
   camPos=shot==0 and wantPos or camPos:Lerp(wantPos,1-math.exp(-dt*(shot==1 and 3 or shot==2 and 6 or 12)));camLook=camLook:Lerp(wantLook,1-math.exp(-dt*8))
   cullFar(camPos)
   camera.CFrame=CFrame.lookAt(camPos,camLook)
  end)
 end)
end
------------------------------------------------------------------ 3. through the barrier and into the bay
-- opts: player, yard, onDone() (called once the screen is black and you are standing in the car park)
function M.PlayGate(opts)
 local player,yard=opts.player,opts.yard
 local at=yard:GetAttribute('GateDriveAt')
 local orig=yard:FindFirstChild('ArrivalCar',true)
 local spawns=yard:FindFirstChild('YardSpawns')
 local lotCar=spawns and spawns:FindFirstChild('LotCar')
 if not at or not orig or not orig.PrimaryPart or not lotCar then if opts.onDone then pcall(opts.onDone) end;return end
 M._gatePlaying=true
 local gui,black=newScreen(player,'ArrivalGate')
 black.BackgroundTransparency=0
 player:SetAttribute('EHCinematic',true)
 local camera=workspace.CurrentCamera;local fov0=camera.FieldOfView
 local base=os.clock()-(workspace:GetServerTimeNow()-at)
 local startCF=orig.PrimaryPart.CFrame;local endCF=lotCar.CFrame
 local Y=startCF.Position.Y;local DY=Vector3.new(0,Y-Y0,0)
 local path=gatePath(Y,startCF.Position,endCF.Position);local L=path.L
 local sAtU,speedAt=speedProfile(path,G.drive)
 -- where the car leaves the gate shot: once it is well past the barrier
 local switchS=math.min(L*.4,(-358)-startCF.Position.Z)
 local tSwitch=G.driveAt+G.drive*.5
 do -- solve the eased travel for the time it reaches switchS
  local lo,hi=0,1
  for _=1,30 do local mid=(lo+hi)/2;if sAtU(mid)<switchS then lo=mid else hi=mid end end
  tSwitch=G.driveAt+lo*G.drive
 end
 local folder=Instance.new('Folder');folder.Name='ArrivalDriveLocal';folder.Parent=workspace
 lampShadows(yard,true)
 local copy,parts=copyCar(orig,folder)
 setHidden(orig,true)
 -- the barrier arm (the server leaves it up for good once the car is through)
 local ck=yard:FindFirstChild('Checkpoint',true)
 local post=ck and ck:FindFirstChild('BarrierPost')
 local arms={}
 if ck and post and not ck:GetAttribute('BarrierRaised') then
  local P=Vector3.new(post.Position.X,post.Position.Y+.75,ck:GetAttribute('BarrierArmZ') or post.Position.Z) -- (the arm hangs on the post's road face, so it swings up clear of the post)
  -- (each arm's pose is taken back to closed first, whatever this screen last showed)
  for _,c in ck:GetChildren()do if c.Name=='BarrierArm' and c:IsA('BasePart') then local _,_,rz=c.CFrame:ToOrientation();table.insert(arms,{p=c,rel=CFrame.Angles(0,0,-rz)*CFrame.new(P):ToObjectSpace(c.CFrame),P=P}) end end
 end
 -- crew in their seats (EHCarSeat from the server; anyone without one takes a free seat)
 local list,used={}, {}
 for _,p in Players:GetPlayers()do local s=p:GetAttribute('EHCarSeat');if type(s)=='number' and not used[s] then used[s]=true;table.insert(list,{player=p,seat=s}) end end
 for _,p in Players:GetPlayers()do
  if p:GetAttribute('EHInCar') and type(p:GetAttribute('EHCarSeat'))~='number' then for i=1,4 do if not used[i] then used[i]=true;table.insert(list,{player=p,seat=i});break end end end
 end
 local passengers=seatAll(folder,list);for _,d in folder:GetDescendants()do if d:FindFirstAncestor('ArrivalPassenger') and (d:IsA('BasePart') or d:IsA('Decal')) then d.Transparency=1 end end
 crewHidden(true)
 local engine=engineFor(copy,folder)
 local armSound
 local sfxDone={}
local G1,G1b=Vector3.new(-6.8,105.4,-359.5)+DY,Vector3.new(-6.2,105.0,-361.5)+DY -- (the whole arm across the frame, the car behind it)
 local LOT0,LOT1=Vector3.new(-37,110.5,-262.5)+DY,Vector3.new(-34,109.5,-265)+DY
 local camPos,camLook,steer,lastShot=nil,nil,0,nil
 local done=false
 local conn
 local function finish()
  if done then return end
  done=true
  if conn then conn:Disconnect() end
  crewHidden(false)
  lampShadows(nil,false)
  if engine then engine:Destroy() end
  folder:Destroy()
  setHidden(orig,false)
  for _,a in arms do if a.p.Parent and not ck:GetAttribute('BarrierRaised') then a.p.CFrame=CFrame.new(a.P)*CFrame.Angles(0,0,math.rad(-80))*a.rel end end
  black.BackgroundTransparency=0
  M._gatePlaying=false
  -- hold black until the server has put this character beside the parked car (or 3 s)
  task.spawn(function()
   local w=os.clock()
   task.wait(T.outHold-1.0) -- (the doors and footsteps play over the black: getOut above)
   while os.clock()-w<4 do
    local r=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if r and (r.Position-endCF.Position).Magnitude<12 then break end
    task.wait(.05)
   end
   task.wait(.1)
   handBack(player,camera,fov0)
   local ok,err=pcall(opts.onDone)
   if not ok then warn('[ElevatorHorror] gate drive hand-off: '..tostring(err)) end
   task.delay(.2,function()gui:Destroy()end)
  end)
 end
 camera.CameraType=Enum.CameraType.Scriptable;camera.FieldOfView=55
 conn=RunService.RenderStepped:Connect(function(dt)
  dt=math.min(dt,1/20)
  local t=os.clock()-base
  -- black: down while you "get in", up on the barrier, a dip between shots, down once parked
  local b=0
  if t<G.reveal then b=1 else b=1-smooth((t-G.reveal)/G.revealLen) end -- (already black from getting in: one fade, straight onto the barrier)
  b=math.max(b,1-smooth(math.abs(t-tSwitch)/SHOT_DIP))
  if t>=G.FADE_AT then b=smooth((t-G.FADE_AT)/G.fade) end
  black.BackgroundTransparency=1-b
  if t>=M.GateBlackAt then finish();return end
  if not sfxDone.start and t>=.15 then sfxDone.start=true;sfx('start',.45) end
  if not sfxDone.servo and t>=G.armAt-.05 and #arms>0 then sfxDone.servo=true;sfx('servo',.35,.6) end
  -- (second, deeper servo removed Oct 25)
  
  if not sfxDone.doors and t>=G.FADE_AT+.2 then sfxDone.doors=true;getOut(0) end
  -- the barrier swings up
local ak=smoother((t-G.armAt)/G.armLen)
  for _,a in arms do a.p.CFrame=CFrame.new(a.P)*CFrame.Angles(0,0,math.rad(-80*ak))*a.rel end
  if not armSound and t>=G.armAt and #arms>0 then
   armSound=Instance.new('Sound');armSound.SoundId='rbxassetid://9119630180';armSound.Volume=.3;armSound.PlaybackSpeed=.7;armSound.Parent=arms[1].p;armSound:Play()
  end
  -- the car: pulls away from the barrier, up the road and round into the bay (smooth in and out)
  local u=math.clamp((t-G.driveAt)/G.drive,0,1)
  local s=sAtU(u)
  local cf=path:cf(s)
  local dy=yawOf(path:dir(s+4))-yawOf(path:dir(s));dy=(dy+math.pi)%(2*math.pi)-math.pi
  steer+=(math.clamp(dy*1.6,-.55,.55)-steer)*(1-math.exp(-dt*8))
  local ek=smooth((s-(L-6))/6)
  if ek>0 then cf=cf:Lerp(endCF,ek);steer*=1-ek end
  if s<.01 then cf=startCF end
  poseCar(parts,cf,-s/TYRE_R,steer)
  placeCrew(passengers,cf)
  local v=(u>0 and u<1) and speedAt(s) or 0
  engine.Volume=math.clamp(.18+v*.012,0,.45)*(1-b)*(1-smooth((t-G.DRIVE_END)/.35));engine.PlaybackSpeed=.7+math.min(v,40)*.012
  -- camera: the barrier and the car from beside it -> the car park as it pulls into the bay
  local target=cf.Position+Vector3.new(0,2.0,0)
  local shot=t<tSwitch and 1 or 2
  local wantPos,wantLook
  if shot==1 then
   G._lookA=nil;wantPos=G1:Lerp(G1b,smooth((t-G.reveal)/(tSwitch-G.reveal)))
   local gateMid=Vector3.new(1.5,104.0,-373)+DY
   wantLook=gateMid:Lerp(target,smooth((t-G.armAt)/(G.driveAt+1.5-G.armAt)))
  else
   -- (Oct 25) no chasing the car round its turns: one slow, steady drift toward the bay till the end
    G._lookA=G._lookA or target
    local q=math.clamp((t-tSwitch)/(G.FADE_AT-tSwitch),0,1)
    wantPos=LOT0:Lerp(LOT1,.6*q);wantLook=G._lookA:Lerp(endCF.Position+Vector3.new(0,2,0),1-(1-q)^1.5)
  end
  if shot~=lastShot or not camPos then camPos,camLook=wantPos,wantLook;lastShot=shot end
  camPos=camPos:Lerp(wantPos,1-math.exp(-dt*10));camLook=camLook:Lerp(wantLook,1-math.exp(-dt*7))
  cullFar(camPos)
  camera.CFrame=CFrame.lookAt(camPos,camLook)
 end)
end
------------------------------------------------------------------ 2. getting in (never shown)
-- Characters in the car (EHInCar, set by the server) are hidden on every screen; your own screen goes
-- black with a short line until the whole crew is in and the gate drive starts.
function M.WatchCar(player)
 local gui,label
 local shown=0
 local wasIn=false
 RunService:BindToRenderStep('BlackwaterInCar',Enum.RenderPriority.Last.Value+4,function(dt)
  for _,p in Players:GetPlayers()do
   local ch=p.Character
   if ch then
    local hide=p:GetAttribute('EHInCar')==true
    if hide or ch:GetAttribute('EHInCarHidden') then
     for _,d in ch:GetDescendants()do if d:IsA('BasePart') or d:IsA('Decal') then d.LocalTransparencyModifier=hide and 1 or 0 end end
     ch:SetAttribute('EHInCarHidden',hide or nil)
    end
   end
  end
  local inCar=player:GetAttribute('EHInCar')==true
  if inCar and not wasIn then sfx('steps',.4,1,.6,1.4);sfx('open',.5,1,1.3);sfx('door',.55,1,2.2);sfx('door2',.4,1.05,2.6) end
  wasIn=inCar
  local want=inCar and not M._gatePlaying
  shown=M._gatePlaying and 0 or math.clamp(shown+(want and 1 or -1)*dt/.45,0,1)
  if shown>0 and not gui then
   gui=Instance.new('ScreenGui');gui.Name='InCar';gui.IgnoreGuiInset=true;gui.ResetOnSpawn=false;gui.DisplayOrder=58;gui.ScreenInsets=Enum.ScreenInsets.None
   local f=Instance.new('Frame');f.Name='Black';f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=Color3.new(0,0,0);f.BorderSizePixel=0;f.Parent=gui
   label=Instance.new('TextLabel');label.BackgroundTransparency=1;label.AnchorPoint=Vector2.new(.5,.5);label.Position=UDim2.fromScale(.5,.5);label.Size=UDim2.fromScale(.7,.05)
   label.Font=Enum.Font.SpecialElite;label.TextScaled=true;label.TextColor3=Color3.fromRGB(200,196,180);label.Parent=f
   local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=26;c.Parent=label
   gui.Parent=player:WaitForChild('PlayerGui')
  end
  if gui then
   if shown<=0 and not want then gui:Destroy();gui=nil;return end
   gui.Black.BackgroundTransparency=1-smooth(shown)
   local yard=workspace:FindFirstChild('Runtime') and workspace.Runtime:FindFirstChild('DescentEnvironment') and workspace.Runtime.DescentEnvironment:FindFirstChild('SurfaceYard')
   local n,m=yard and yard:GetAttribute('CarInCount') or 1,yard and yard:GetAttribute('CarCrew') or 1
   label.Text=m>1 and string.format('Waiting for the others to get in...  %d/%d',n,m) or ''
   label.TextTransparency=1-smooth(shown)
  end
 end)
end
return M
