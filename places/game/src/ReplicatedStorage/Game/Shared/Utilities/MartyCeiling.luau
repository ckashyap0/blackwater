--!nonstrict
-- (Nov 15, v2) Marty on the lift ceiling - the "daydream" on the ride from Level 5 down to Level 4.
-- About a second after the lift starts down from Level 5, the picture cuts to a pulp-red view straight
-- up at the cabin ceiling: Marty is clinging to it right above you (belly to the ceiling, hands and feet
-- flat on it). His head creaks round towards you in jerky snaps, bones cracking, then he launches
-- himself at your face with a screech - still red - and the screen drops to black almost at once. The
-- black lifts and the cabin is empty; the ride carries on to Level 4.
-- He keeps his normal colours here (the grey flicker belongs only to the maintenance-gate peek, MartyPeek).
-- Each screen runs its own copy (nothing is replicated).
--  * Pose: ReplicatedStorage.MartyStages.CeilingRig (standing frame, front = -Z; hands/feet on z = -REACH).
--  * Overlay: StarterGui.MartyScare > Red (the red wash), Black (the quick fade out) - edit them there.
--  * Trigger: AtmosphereController calls M.Step() every frame; it plays once per ride whose cabin has
--    TravelFromFloor == 5 (set by ElevatorService:_Seal, which also makes that ride 8 s long).
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local SoundService=game:GetService('SoundService')
local Lighting=game:GetService('Lighting')
local M={}
M.FROM_FLOOR=5     -- the ride it plays on (leaving this floor)
M.START=.9         -- seconds into the ride
-- timeline (seconds after it starts)
local CREAKS={      -- the head snaps round in steps: {time, fraction of the turn done}
 {.55,.28},{1.15,.52},{1.7,.78},{2.2,1},
}
local TILT_AT=2.45  -- a last sharp tilt of the head
local LUNGE_AT=2.75 -- he lets go and launches at you
local LUNGE=.32     -- seconds to reach your face
local BLACK=.1      -- quick fade to black
local HOLD=.45      -- black held
local UP=.55        -- picture fades back
local TURN=165      -- degrees his head turns from facing the ceiling to facing you
local REACH=1.86    -- how far his hands and feet reach in front of him
local S={
 hit={'rbxassetid://9120188288',1.6,.55},       -- heavy metal slam as the picture cuts in
 sting={'rbxassetid://130018094603454',.9,.9},  -- horror stinger
 static={'rbxassetid://9117060042',.25,.8},
 heart={'rbxassetid://176554627',1.2,1.25},     -- fast heartbeat under the creaking
 crackA={'rbxassetid://9113546532',1.3,1},      -- bone cracks
 crackB={'rbxassetid://9113542694',1.3,1.1},
 screech={'rbxassetid://9125474505',2,.82},     -- creature screech on the lunge
 screech2={'rbxassetid://9125474863',1.4,1.05},
 lungeHit={'rbxassetid://9120188618',1.8,.6},
}
local active=nil
local played={}
local function sound(key,pitch,vol)
 local d=S[key];local s=Instance.new('Sound');s.SoundId=d[1];s.Volume=vol or d[2];s.PlaybackSpeed=pitch or d[3];s.Parent=SoundService;s:Play()
 task.delay(8,function()s:Destroy()end)
 return s
end
local function ease(x)x=math.clamp(x,0,1);return x*x*(3-2*x)end
local function cabinNow()
 local r=workspace:FindFirstChild('Runtime');local e=r and r:FindFirstChild('DescentEnvironment')
 return e and e:FindFirstChild('Elevator')
end
local function eyeIn(cabin)
 local centre=cabin:FindFirstChild('CabinCentre',true);local ceiling=cabin:FindFirstChild('Ceiling',true)
 local mid=(centre and centre:IsA('BasePart')) and centre.Position or (ceiling and ceiling.Position)
 if not mid then return nil end
 local char=Players.LocalPlayer.Character;local head=char and char:FindFirstChild('Head')
 if not head then return nil end
 local d=head.Position-mid
 if Vector2.new(d.X,d.Z).Magnitude>9 or math.abs(d.Y)>9 then return nil end -- not in the cabin
 return head.Position,mid
end
-- Hands and feet flat on the ceiling, never through it or through the lights hanging from it: he is
-- turned about his head (12 headings) and nudged (up to 1.6 studs) to the spot where all four limbs meet
-- the ceiling at the same height, then raised/lowered so the palms just touch (wrist bone PALM below).
local PALM=.34
local function aabb(p)
 local cf,sz=p.CFrame,p.Size
 local e=Vector3.new(math.abs(cf.RightVector.X)*sz.X+math.abs(cf.UpVector.X)*sz.Y+math.abs(cf.LookVector.X)*sz.Z,
  math.abs(cf.RightVector.Y)*sz.X+math.abs(cf.UpVector.Y)*sz.Y+math.abs(cf.LookVector.Y)*sz.Z,
  math.abs(cf.RightVector.Z)*sz.X+math.abs(cf.UpVector.Z)*sz.Y+math.abs(cf.LookVector.Z)*sz.Z)/2
 return p.Position-e,p.Position+e
end
local function settle(m,cabin,under)
 local boxes={}
 for _,p in cabin:GetDescendants() do if p:IsA('BasePart') and p.Transparency<.95 then
  local lo,hi=aabb(p);if hi.Y>=under-.05 and lo.Y>under-1.2 then table.insert(boxes,{lo,hi}) end
 end end
 local limbs,head={},nil
 for _,b in m:GetDescendants() do if b:IsA('Bone') then
  if b.Name:find('Hand') or b.Name:find('Foot') then table.insert(limbs,b) elseif b.Name=='Head' then head=b end
 end end
 local function clear(pos)
  local best=under
  for _,bx in boxes do local lo,hi=bx[1],bx[2]
   if pos.X+.45>lo.X and pos.X-.45<hi.X and pos.Z+.45>lo.Z and pos.Z-.45<hi.Z and lo.Y<best then best=lo.Y end
  end
  return best-pos.Y
 end
 local base=m:GetPivot();local hp=head and head.WorldPosition or base.Position
 local bestScore,bestCF=-math.huge,base
 for yw=0,330,30 do for dx=-4,4 do for dz=-4,4 do
  local cf=CFrame.new(dx*.4,0,dz*.4)*CFrame.new(hp)*CFrame.Angles(0,math.rad(yw),0)*CFrame.new(-hp)*base
  m:PivotTo(cf)
  local lo,hi=math.huge,-math.huge
  for _,b in limbs do local c=clear(b.WorldPosition);lo=math.min(lo,c);hi=math.max(hi,c) end
  local score=-(hi-lo)-.01*(math.abs(dx)+math.abs(dz))-.0005*math.min(yw,360-yw)
  if score>bestScore then bestScore=score;bestCF=cf end
 end end end
 m:PivotTo(bestCF)
 local mn=math.huge;for _,b in limbs do mn=math.min(mn,clear(b.WorldPosition)) end
 if mn==math.huge then return bestCF end
 local final=CFrame.new(0,mn-PALM,0)*bestCF
 m:PivotTo(final)
 return final
end
local function cleanup(a)
 RunService:UnbindFromRenderStep('MartyCeilingCam')
 if a.conn then a.conn:Disconnect() end
 if a.model and a.model.Parent then a.model:Destroy() end
 if a.grade then a.grade:Destroy() end
 if a.heart then a.heart:Stop();a.heart:Destroy() end
 local cam=workspace.CurrentCamera
 if cam then if a.camType then cam.CameraType=a.camType end;if a.fov then cam.FieldOfView=a.fov end end
 for _,g in a.hidden or {} do if g.Parent then g.Enabled=true end end
 if a.gui then a.gui.Enabled=false end
 active=nil
end
function M.Showing() return active~=nil end
-- called every frame (AtmosphereController); starts the scare once on the ride down from Level 5
function M.Step()
 if active or not RunService:IsClient() then return end
 local cabin=cabinNow();if not cabin then return end
 local started=cabin:GetAttribute('TravelStartedAt')
 if type(started)~='number' or cabin:GetAttribute('TravelFromFloor')~=M.FROM_FLOOR or played[started] then return end
 local e=workspace:GetServerTimeNow()-started
 if e<M.START then return end
 played[started]=true
 if e>M.START+1 then return end -- joined late: never start it half way
 M.Play(cabin)
end
function M.Play(cabin)
 if active or not RunService:IsClient() then return end
 local tpl=game:GetService('ReplicatedStorage'):FindFirstChild('MartyStages');tpl=tpl and tpl:FindFirstChild('CeilingRig')
 local ceiling=cabin and cabin:FindFirstChild('Ceiling',true)
 if not (tpl and ceiling and ceiling:IsA('BasePart')) then return end
 local cam=workspace.CurrentCamera;if not cam then return end
 local eye,mid=eyeIn(cabin);if not eye then return end
 local pg=Players.LocalPlayer:FindFirstChild('PlayerGui');if not pg then return end
 local under=ceiling.Position.Y-ceiling.Size.Y/2
 -- he lies along the line from you to the far side of the cabin, his head right above you
 local flat=Vector3.new(eye.X-mid.X,0,eye.Z-mid.Z);if flat.Magnitude<.5 then flat=Vector3.new(0,0,1) end;flat=flat.Unit
 local bodyMid=Vector3.new(eye.X,0,eye.Z)-flat*2.2
 local yaw=CFrame.lookAt(Vector3.zero,flat)
 local rot=yaw*CFrame.Angles(0,math.pi,0)*CFrame.Angles(math.rad(90),0,0) -- standing up (+Y) -> towards you, front (-Z) -> up
 local pivot=CFrame.new(Vector3.new(bodyMid.X,under-REACH,bodyMid.Z))*rot*CFrame.new(0,-3.8,0)
 local m=tpl:Clone()
 for _,d in m:GetDescendants() do if d:IsA('BasePart') then d.Anchored=true;d.CanCollide=false;d.CanQuery=false;d.CanTouch=false;d.CastShadow=false end end
 m:PivotTo(pivot)
 pivot=settle(m,cabin,under)
 -- a dim red light from below, so he reads in the dark cabin (in his own colours, washed red)
 local lp=Instance.new('Part');lp.Name='Light';lp.Transparency=1;lp.Anchored=true;lp.CanCollide=false;lp.CanQuery=false;lp.Size=Vector3.one*.2
 lp.Position=eye+Vector3.new(0,.8,0);lp.Parent=m
 local pl=Instance.new('PointLight');pl.Color=Color3.fromRGB(255,170,160);pl.Range=12;pl.Brightness=1.4;pl.Shadows=false;pl.Parent=lp
 m.Parent=cam
 -- the head bone and the axis of his neck (turned about to creak the head round)
 local head,chest
 for _,b in m:GetDescendants() do if b:IsA('Bone') then if b.Name=='Head' then head=b elseif b.Name=='UpperTorso' then chest=b end end end
 local axis=Vector3.yAxis
 if head and chest then local w=(head.WorldPosition-chest.WorldPosition);if w.Magnitude>.1 then axis=head.WorldCFrame:VectorToObjectSpace(w.Unit) end end
 local gui=pg:FindFirstChild('MartyScare')
 local grade=Instance.new('ColorCorrectionEffect');grade.Name='MartyScareGrade';grade.Parent=Lighting
 local a={model=m,gui=gui,grade=grade,t0=os.clock(),camType=cam.CameraType,fov=cam.FieldOfView,hidden={},head=head,axis=axis,pivot=pivot,eye=eye,fired={}}
 active=a
 if gui then gui.Enabled=true;gui.Red.BackgroundTransparency=.35;gui.Black.BackgroundTransparency=1 end
 local function hideOthers()
  for _,g in pg:GetChildren() do if g:IsA('ScreenGui') and g.Enabled and g~=gui then g.Enabled=false;if not table.find(a.hidden,g) then table.insert(a.hidden,g) end end end
 end
 hideOthers()
 local reduced=Players.LocalPlayer:GetAttribute('EHReduceMotion')==true
 cam.CameraType=Enum.CameraType.Scriptable
 local function turn(f) return CFrame.fromAxisAngle(axis,math.rad(-TURN*(1-f))) end
 if head then head.Transform=turn(0) end -- starts facing the ceiling
 sound('hit');sound('sting');sound('static')
 a.heart=sound('heart');a.heart.Looped=true
 RunService:BindToRenderStep('MartyCeilingCam',Enum.RenderPriority.Last.Value,function()
  if active~=a then return end
  local t=os.clock()-a.t0
  local c=workspace.CurrentCamera
  hideOthers()
  -- head creak: holds still, then snaps a step round (a crack each time), shivering between snaps
  local f,last=0,-1
  for i,k in CREAKS do if t>=k[1] then f=k[2];last=i end end
  local prev=last>1 and CREAKS[last-1][2] or 0
  if last>=1 then local s=(t-CREAKS[last][1])/.07;if s<1 then f=prev+(f-prev)*s end end
  for i,k in CREAKS do if t>=k[1] and not a.fired['c'..i] then a.fired['c'..i]=true;sound(i%2==1 and 'crackA' or 'crackB',.9+i*.05) end end
  local shiver=t<LUNGE_AT and math.rad(math.noise(t*22,3)*2.2) or 0
  local tilt=0
  if t>=TILT_AT then tilt=math.rad(24)*math.min(1,(t-TILT_AT)/.06);if not a.fired.tilt then a.fired.tilt=true;sound('crackA',1.25,1) end end
  if a.head then a.head.Transform=turn(f)*CFrame.Angles(0,0,tilt+shiver) end
  -- red wash: steady, pulsing with the heartbeat; deeper on the lunge
  local pulse=.5+.5*math.sin(t*2*math.pi*1.9)
  local lunge=t>=LUNGE_AT and ease((t-LUNGE_AT)/LUNGE) or 0
  a.grade.TintColor=Color3.fromRGB(255,120,110):Lerp(Color3.fromRGB(255,60,50),lunge)
  a.grade.Contrast=.3+.2*lunge;a.grade.Saturation=.15;a.grade.Brightness=-.04+.03*pulse
  if a.gui then a.gui.Red.BackgroundTransparency=.42-.12*pulse-.2*lunge end
  -- the lunge: he lets go of the ceiling and flies at your face
  local face=a.head and a.head.WorldPosition or (a.pivot*Vector3.new(0,5.4,0))
  if t>=LUNGE_AT then
   if not a.fired.lunge then
    a.fired.lunge=true;a.face0=face
    sound('screech');sound('screech2');sound('lungeHit')
   end
   local target=a.eye+(a.face0-a.eye).Unit*.7
   local off=(target-a.face0)*(lunge^1.6)
   a.model:PivotTo(CFrame.new(off)*a.pivot)
  end
  -- camera: your eye, looking up at his face; a jolt on the cut-in and a violent shake on the lunge
  local look=a.face0 or face
  local cf=CFrame.lookAt(a.eye,look)
  if not reduced then
   local k=math.max(0,1-t/.4)*1.6+lunge*3
   cf*=CFrame.Angles(math.rad(math.noise(t*30,1)*k),math.rad(math.noise(t*30,2)*k),math.rad(math.noise(t*30,5)*k*.6))
  end
  c.FieldOfView=a.fov-6*ease(t/2.6)+(t>=LUNGE_AT and 14*lunge or 0)
  a.view=cf;c.CFrame=cf
  -- quick fade to black right as he reaches you, held a moment, then the cabin comes back - empty
  local tb=t-(LUNGE_AT+LUNGE-.04)
  if tb>=0 then
   if a.model.Parent and tb>=BLACK then a.model:Destroy();if a.heart then a.heart:Stop() end end
   local black
   if tb<BLACK then black=tb/BLACK elseif tb<BLACK+HOLD then black=1 else
    black=1-ease((tb-BLACK-HOLD)/UP)
    if a.gui then a.gui.Red.BackgroundTransparency=1 end
    a.grade.Enabled=false
    -- hand the camera back under the black
    if not a.released then a.released=true;c.CameraType=a.camType;c.FieldOfView=a.fov;RunService:UnbindFromRenderStep('MartyCeilingCam');if a.conn then a.conn:Disconnect();a.conn=nil end
     for _,g in a.hidden do if g.Parent then g.Enabled=true end end;a.hidden={}
     -- keep fading the black on its own
     local t1=os.clock()
     a.conn=RunService.RenderStepped:Connect(function()
      local u=(os.clock()-t1)/UP
      if a.gui then a.gui.Black.BackgroundTransparency=ease(u) end
      if u>=1 then cleanup(a) end
     end)
     return
    end
   end
   if a.gui then a.gui.Black.BackgroundTransparency=1-black end
  end
 end)
 -- (other camera code also writes the camera every frame; this has the last word while he is shown)
 a.conn=RunService.RenderStepped:Connect(function() if active==a and a.view and not a.released then local c=workspace.CurrentCamera;c.CameraType=Enum.CameraType.Scriptable;c.CFrame=a.view end end)
 task.delay(10,function() if active==a then cleanup(a) end end) -- safety net
end
return M
