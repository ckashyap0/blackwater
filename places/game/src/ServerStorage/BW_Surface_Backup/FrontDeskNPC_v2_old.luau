--!nonstrict
-- FrontDeskNPC (Oct 26 b): the gatehouse attendant (model tagged "FrontDeskNPC", 4 bones: Root /
-- Chest / Neck / Head, see the vault note "NPC - Front Desk Guy"). He never moves around.
--  * idle: slow breathing (Chest rotation only, ~4.8 s a breath), a slow tired head drift and now and
--    then his head slowly sinks (nodding off) and slowly comes back up - no snaps.
--  * he watches you: when the camera is within NOTICE studs (or any time after the crew checked in,
--    the yard's CheckedInAt / the model's HeadFollow attribute) ONLY his head turns to follow it,
--    40% neck / 60% head, limited to +-65 deg yaw and -20..+25 deg pitch.
--  * every angle runs through a critically damped spring (no frame-to-frame snapping) and the aim is
--    measured from the head's REST position (cached once), so the turn never feeds back into itself.
--  * runs in BindToRenderStep after the camera, so it uses this frame's camera position.
local RunService=game:GetService('RunService');local CS=game:GetService('CollectionService')
local M={};local started=false
local YAW,PDOWN,PUP=math.rad(65),math.rad(20),math.rad(25)
local NOTICE,AFTER=28,70
local W=3.2   -- spring stiffness (rad/s): higher = quicker head
-- (NOT a weak table: Instance keys in a weak table get dropped when Luau recycles the wrapper, which
-- reset the state every few frames - that was the 'teleporting' head/breathing. Cleared on removal.)
local state={}
CS:GetInstanceRemovedSignal('FrontDeskNPC'):Connect(function(m) state[m]=nil end)
local function bones(m)
 local rp=m:FindFirstChild('RootPart');local root=rp and rp:FindFirstChild('Root')
 local chest=root and root:FindFirstChild('Chest');local neck=chest and chest:FindFirstChild('Neck');local head=neck and neck:FindFirstChild('Head')
 if chest and neck and head then return root,chest,neck,head end
end
local function checkedIn(m)
 if m:GetAttribute('HeadFollow')==true then return true end
 local a=m.Parent
 while a and a~=workspace do if a:GetAttribute('CheckedInAt') then return true end;a=a.Parent end
 return false
end
local function spring(x,v,target,w,dt)
 -- exact critically damped step (stable for any dt)
 local d=x-target;local e=math.exp(-w*dt)
 local nx=target+(d+(v+w*d)*dt)*e
 local nv=(v-(v+w*d)*w*dt)*e
 return nx,nv
end
local function smooth01(x) x=math.clamp(x,0,1) return x*x*(3-2*x) end
local function step(dt)
 dt=math.min(dt,1/15)
 local cam=workspace.CurrentCamera;if not cam then return end
 local cp=cam.CFrame.Position;local t=os.clock()
 for _,m in CS:GetTagged('FrontDeskNPC')do
  if m:IsDescendantOf(workspace) then
   local root,chest,neck,head=bones(m)
   if root then
    local s=state[m]
    if not s then
     -- rest position of the head in Root space (taken before we ever move it)
     head.Transform=CFrame.identity;neck.Transform=CFrame.identity
     s={yaw=0,yv=0,pitch=0,pv=0,nod=0,nv=0,phase=math.random()*10,nextNod=t+20+math.random()*20,
        rest=root.WorldCFrame:PointToObjectSpace(head.WorldPosition)}
     state[m]=s
    end
    local rootCF=root.WorldCFrame
    local headW=rootCF:PointToWorldSpace(s.rest)
    local dist=(headW-cp).Magnitude
    if dist<160 then
     local tt=t+s.phase
     -- breathing: rotation only, smooth sine
     local br=math.sin(tt*2*math.pi/4.8)
     chest.Transform=CFrame.Angles(math.rad(1.1)*br,0,math.rad(.25)*math.sin(tt*2*math.pi/9.6))
     local follow=(dist<NOTICE) or (checkedIn(m) and dist<AFTER)
     local ty,tp
     if follow then
      local d=rootCF:VectorToObjectSpace(cp-headW)   -- bones face their -Z
      ty=math.clamp(math.atan2(-d.X,-d.Z),-YAW,YAW)
      tp=math.clamp(math.atan2(d.Y,math.sqrt(d.X*d.X+d.Z*d.Z)),-PDOWN,PUP)
      s.nodStart=nil
     else
      ty=math.rad(5)*math.noise(tt*.07,1.7);tp=math.rad(-4)+math.rad(2)*math.noise(tt*.09,4.1)
      if t>=s.nextNod and not s.nodStart then s.nodStart=t end
     end
     -- nodding off: sinks over 4 s, holds 1.5 s, lifts over 3 s (eased, no snap)
     local nodT=0
     if s.nodStart then
      local e=t-s.nodStart
      if e<4 then nodT=smooth01(e/4) elseif e<5.5 then nodT=1 elseif e<8.5 then nodT=1-smooth01((e-5.5)/3)
      else s.nodStart=nil;s.nextNod=t+25+math.random()*20 end
     end
     s.yaw,s.yv=spring(s.yaw,s.yv,ty,W,dt)
     s.pitch,s.pv=spring(s.pitch,s.pv,tp,W,dt)
     s.nod,s.nv=spring(s.nod,s.nv,math.rad(13)*nodT,2,dt)
     local roll=math.rad(1.2)*math.noise(tt*.06,7.3)
     neck.Transform=CFrame.Angles(s.pitch*.4-s.nod*.5,s.yaw*.4,0)
     head.Transform=CFrame.Angles(s.pitch*.6-s.nod*.5,s.yaw*.6,roll)
    end
   end
  end
 end
end
function M.Start()
 if started then return end;started=true
 RunService:BindToRenderStep('FrontDeskNPC',Enum.RenderPriority.Camera.Value+2,step)
end
return M
