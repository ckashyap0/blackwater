--!nonstrict
-- Rain over the surface yard (client only). A sheet of emitters rides above (and a little ahead of) the
-- camera wherever it goes - cutscene cameras included - throwing fast streaks down past it, with small
-- splashes on whatever is below the camera and a looped rain bed. Under a roof (anything solid straight
-- above the camera) the streaks stop and the sound goes dull, so it never rains inside the stall or a
-- building. (Box-volume emission and >400/s rates on one emitter do not render reliably, so the density
-- comes from several surface emitters on one sheet.)
local RunService=game:GetService('RunService')
local SoundService=game:GetService('SoundService')
local M={}
local conn,sheet,floor,snd,eq
local streaks,splashes={},{}
local STREAK_RATE,SPLASH_RATE,LAYERS=400,300,7
local function part(name,size)
 local p=Instance.new('Part');p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.CastShadow=false
 p.Transparency=1;p.Size=size;p.Parent=workspace;return p
end
function M.Start()
 if conn then return end
 sheet=part('LocalRainSheet',Vector3.new(44,1,44))
 for i=1,LAYERS do
  local em=Instance.new('ParticleEmitter');em.Name='Rain'..i
  em.Color=ColorSequence.new(Color3.fromRGB(186,196,208));em.LightEmission=.5;em.LightInfluence=.35
  em.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.7),NumberSequenceKeypoint.new(.2,.38),NumberSequenceKeypoint.new(1,.45)})
  em.Size=NumberSequence.new(({.3,.26,.22,.2,.18,.24,.2})[i] or .2);em.Squash=NumberSequence.new(-2.9)
  em.Orientation=Enum.ParticleOrientation.VelocityParallel;em.EmissionDirection=Enum.NormalId.Bottom
  em.Speed=NumberRange.new(70,95);em.SpreadAngle=Vector2.new(3,3);em.Acceleration=Vector3.new(7,0,3)
  em.Lifetime=NumberRange.new(.5,.6);em.Rate=STREAK_RATE;em.Parent=sheet;streaks[i]=em
 end
 floor=part('LocalRainSplash',Vector3.new(50,.2,50))
 for i=1,2 do
  local sp=Instance.new('ParticleEmitter');sp.Name='Splash'..i
  sp.Color=ColorSequence.new(Color3.fromRGB(205,214,222));sp.LightEmission=.3;sp.LightInfluence=.6
  sp.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.4),NumberSequenceKeypoint.new(1,1)})
  sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.06),NumberSequenceKeypoint.new(1,.18)})
  sp.EmissionDirection=Enum.NormalId.Top;sp.Speed=NumberRange.new(1,3);sp.SpreadAngle=Vector2.new(60,60)
  sp.Acceleration=Vector3.new(0,-30,0);sp.Lifetime=NumberRange.new(.12,.2);sp.Rate=SPLASH_RATE;sp.Parent=floor;splashes[i]=sp
 end
 snd=Instance.new('Sound');snd.Name='SurfaceRain';snd.SoundId='rbxassetid://1516791621';snd.Looped=true;snd.Volume=.55
 eq=Instance.new('EqualizerSoundEffect');eq.Parent=snd
 snd.Parent=SoundService;snd:Play()
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local cover,ground,t,on=0,nil,0,nil
  local entry,deep,outside=nil,0,nil
  M.Level=function()return cover end -- (Oct 25) in the lift building the rain fades further the deeper in you walk
 conn=RunService.RenderStepped:Connect(function(dt)
  local cam=workspace.CurrentCamera;if not cam then return end
  local p=cam.CFrame.Position;local look=cam.CFrame.LookVector
  local ahead=Vector3.new(look.X,0,look.Z);ahead=ahead.Magnitude>.05 and ahead.Unit*16 or Vector3.zero
  sheet.CFrame=CFrame.new(((cover==2 and outside) or (p+ahead))+Vector3.new(0,24,0)) -- (inside the lift building the sheet sits outside, past the roof, where you look)
  t+=dt
  if t>.12 then t=0
   -- (Oct 25) the fade to black into the lift scene: the rain is gone while the screen is black, before the cutscene fades in
   local pg=game:GetService('Players').LocalPlayer:FindFirstChild('PlayerGui');local df=pg and pg:FindFirstChild('DescentFade');local bk=df and df.Enabled and df:FindFirstChild('Black',true)
   if bk and bk.Visible and bk.BackgroundTransparency<.05 then M.Stop();return end
   local ex={cam,sheet,floor};local pl=game:GetService('Players').LocalPlayer;if pl and pl.Character then table.insert(ex,pl.Character) end
   local f=workspace:FindFirstChild('ArrivalDriveLocal');if f then table.insert(ex,f) end
   params.FilterDescendantsInstances=ex
   local roof=workspace:Raycast(p,Vector3.new(0,60,0),params)
   local sides=0
   if roof then for k=0,7 do local a=k*math.pi/4;if workspace:Raycast(p,Vector3.new(math.cos(a),0,math.sin(a))*32,params) then sides+=1 end end end
   -- (Oct 25) only the lift building muffles the rain; small roofs (the check-in shed) never dim it
    local env=workspace:FindFirstChild('Runtime') and workspace.Runtime:FindFirstChild('DescentEnvironment');local lift=env and env:FindFirstChild('Elevator');local car=lift and lift:FindFirstChild('Cabin')
    local hall=roof and (roof.Instance:FindFirstAncestor('15_ShaftHall') or roof.Instance:FindFirstAncestor('02_ShaftHeadHouse') or (lift and roof.Instance:IsDescendantOf(lift)))
    cover=not roof and 0 or (hall and 2 or 1)
    -- (Oct 25) standing in the lift car itself: no rain at all - not overhead and not the "rain seen outside"
    -- sheet either (that sheet is wide and its drops fall straight through roofs, so from the car it rained
    -- inside). Decided by the car's own box, so it holds whatever the roof ray happens to hit.
    local inCar=false
    if car then local okB,cf,sz=pcall(function()return car:GetBoundingBox()end);if okB and cf then local l=cf:PointToObjectSpace(p);inCar=math.abs(l.X)<=sz.X/2+.5 and math.abs(l.Y)<=sz.Y/2+.5 and math.abs(l.Z)<=sz.Z/2+.5 end end
    if inCar then cover=2 end
    if cover==2 and inCar then outside=nil elseif cover==2 then local f=Vector3.new(look.X,0,look.Z);f=f.Magnitude>.05 and f.Unit or Vector3.zAxis;outside=nil;for d=4,64,4 do local q=p+f*d;if not workspace:Raycast(q,Vector3.new(0,60,0),params) then outside=q+f*22;break end end else outside=nil end
    if hall then entry=entry or p;local h=Vector3.new(p.X-entry.X,0,p.Z-entry.Z).Magnitude;deep=math.clamp(h/28,0,1) else entry=nil;deep=0 end
   local dn=workspace:Raycast(p+Vector3.new(0,1,0),Vector3.new(0,-60,0),params)
   ground=dn and dn.Position.Y or nil
  end
  local want=(cover==2 and outside) and 3 or cover
  if want~=on then on=want;for k,e in streaks do e.Enabled=(want==0) or (want==1 and k<=6) or (want==3 and k<=4) end end -- (open: all; a small roof: barely lighter; an enclosed hall: much lighter)
  for _,e in splashes do local w=want<2 and ground~=nil;if e.Enabled~=w then e.Enabled=w end end
  if ground then floor.CFrame=CFrame.new(p.X+ahead.X*.3,ground+.12,p.Z+ahead.Z*.3) end
  local wantVol=want>=2 and (.38-.34*deep) or .55;snd.Volume+=(wantVol-snd.Volume)*math.min(1,dt*3)
  local wantHi=want>=2 and (-10-16*deep) or 0;eq.HighGain+=(wantHi-eq.HighGain)*math.min(1,dt*3)
 end)
end
function M.Stop()
 if conn then conn:Disconnect();conn=nil end
 for _,o in {sheet,floor,snd} do if o then o:Destroy() end end
 sheet,floor,snd,eq=nil,nil,nil,nil;table.clear(streaks);table.clear(splashes)
end
return M
