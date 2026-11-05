--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- Client-side atmosphere transitions (presentation only; the server owns all state).
--  * Power restore: when a circuit comes back (server attribute Circuit<id>At), every light and
--    diffuser on that circuit fades in over FADE seconds on a slow, non-linear curve with a few
--    tube-strike flickers at the start, instead of snapping on.
--  * Facility ambience: a low machinery bed that plays on active floors.
--  * Elevator arrival: when the cabin doors open on a floor, an arrival clunk and the settling
--    cabin hum play. The moment you step out of the cabin they fade out logarithmically (linear in
--    dB, so the ear hears an even fade) while the ambience rises by the mirror curve and takes over.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local SoundService=game:GetService('SoundService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local FADE=3.8          -- light restore
local EXIT_FADE=2.8     -- arrival audio -> ambience crossfade
local SOUNDS={
 drone={'rbxassetid://9112839813',.16,.62,true},   -- distant plant machinery bed
 hum={'rbxassetid://9112889325',.07,.5,true},      -- electrical hum under it
 arrivalClunk={'rbxassetid://9114533169',.5,1,false},
 arrivalHum={'rbxassetid://127510969655408',.22,.45,true},
 outdoors={'rbxassetid://9113444476',.42,.82,true},      -- surface wind: the old outdoor bed with its mids/highs (birdsong) cut away
 surfaceDrone={'rbxassetid://9112839813',.1,.5,true},     -- the works humming in the dark around the yard
}
local function db(x)return 10^(x/20)end
function Controller.new(player)return setmetatable({Name='AtmosphereController',Dependencies={'InputController'},_player=player,_floors={},_ambDb=-60},Controller)end
function Controller:Init(deps)self._input=deps.InputController;self._scope=Scope.new();self._sounds={}end
function Controller:_Sound(key)
 local s=self._sounds[key]
 if not s then
  local d=SOUNDS[key];s=self._scope:Add(Instance.new('Sound'));s.Name='Atmosphere_'..key;s.SoundId=d[1];s.Volume=0;s.PlaybackSpeed=d[3];s.Looped=d[4];s.Parent=SoundService
  if key=='drone' then local eq=Instance.new('EqualizerSoundEffect',s);eq.HighGain=-12;eq.MidGain=-3;eq.LowGain=2 end
  if key=='outdoors' then local eq=Instance.new('EqualizerSoundEffect',s);eq.HighGain=-60;eq.MidGain=-24;eq.LowGain=6 end
  if key=='surfaceDrone' then local eq=Instance.new('EqualizerSoundEffect',s);eq.HighGain=-30;eq.MidGain=-10;eq.LowGain=4 end
  self._sounds[key]=s
 end
 return s
end
local function setVolume(s,v)
 if v>.0015 then if not s.IsPlaying then s:Play()end;s.Volume=v elseif s.IsPlaying then s:Stop();s.Volume=0 end
end
------------------------------------------------------------------ power restore fade
local function strikeCurve(u,seed)
 u=math.clamp(u,0,1)
 local k=u^2.4 -- slow start, accelerating: lamps warm up rather than snap
 if u<.3 then
  -- a few short tube-strike flashes while the ballasts catch
  local flash=math.max(0,math.sin(u*71+seed))^8*.5*(1-u/.3)
  k=math.max(k,flash)
 end
 return math.clamp(k,0,1)
end
function Controller:_Index(floor)
 local f=self._floors[floor]
 if f then return f end
 f={lights={},parts={}}
 for _,d in floor:GetDescendants()do
  local id=d:GetAttribute('Circuit')
  if id then
   if d:IsA('Light')then table.insert(f.lights,{obj=d,id=id,base=d.Brightness})
   elseif d:IsA('BasePart') and d:GetAttribute('Diffuser')then table.insert(f.parts,{obj=d,id=id,unlit=d.Color})end
  end
 end
 self._floors[floor]=f
 return f
end
function Controller:_Power(now)
 for floor,f in self._floors do
  if not floor.Parent then self._floors[floor]=nil;continue end
  local function progress(id)
   local at=floor:GetAttribute('Circuit'..id..'At');if type(at)~='number' then return nil end
   return (now-at)/FADE
  end
  for i,e in f.lights do
   local u=progress(e.id)
   if u and u<1 and e.obj.Parent then
    e.fading=true;e.obj.Brightness=e.base*strikeCurve(u,i*.37)
   elseif e.fading then e.fading=false;if e.obj.Parent then e.obj.Brightness=e.base end end
  end
  for i,e in f.parts do
   local u=progress(e.id)
   local p=e.obj
   if u and u<1 and p.Parent and p.Material==Enum.Material.Neon then
    e.lit=e.lit or p.Color;e.fading=true
    p.Color=e.unlit:Lerp(e.lit,strikeCurve(u,i*.37))
   elseif e.fading then e.fading=false;if p.Parent and e.lit then p.Color=e.lit end end
  end
 end
end
------------------------------------------------------------------ ambience + arrival
local function inCabin(root)
 local p=root.Position
 return math.abs(p.X)<8 and p.Z>-7 and p.Z<8 and p.Y>18 and p.Y<35
end
function Controller:_Audio(dt)
 local context=self._input:GetContext()
 local c=self._player.Character;local root=c and c:FindFirstChild('HumanoidRootPart')
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 local inside=root and inCabin(root) or false
 -- arrival: the doors start opening at a floor
 local doorState=cabin and cabin:GetAttribute('DoorState')
 if doorState~=self._lastDoor then
  if doorState=='Opening' and (context=='ActiveFloor' or context=='Transit' or context=='Intro') and inside then
   self._arrival={t0=os.clock()}
   local clunk=self:_Sound('arrivalClunk');clunk.TimePosition=0;clunk.Volume=SOUNDS.arrivalClunk[2];clunk:Play()
  end
  self._lastDoor=doorState
 end
 local a=self._arrival
 local ambientTarget
 local surface=cabin and (cabin:GetAttribute('Boarding')==true) or self._fade~=nil
 if context=='ActiveFloor' and not surface then ambientTarget=inside and -12 or 0
 elseif context=='Dead' or context=='Downed' then ambientTarget=-6
 else ambientTarget=-60 end
 if a then
  if not a.fadeAt and (not inside or os.clock()-a.t0>25 or context=='Results' or context=='Lobby') then a.fadeAt=os.clock();a.fromAmb=math.min(self._ambDb,-20)end
  local hum=self:_Sound('arrivalHum');local clunk=self:_Sound('arrivalClunk')
  if a.fadeAt then
   local u=math.clamp((os.clock()-a.fadeAt)/EXIT_FADE,0,1)
   -- logarithmic fade: straight line in decibels from 0 dB to -60 dB
   setVolume(hum,SOUNDS.arrivalHum[2]*db(-60*u))
   if clunk.IsPlaying then clunk.Volume=SOUNDS.arrivalClunk[2]*db(-60*u)end
   -- the ambience rises on the mirror curve and takes over seamlessly
   self._ambDb=a.fromAmb+(ambientTarget-a.fromAmb)*u
   if u>=1 then clunk:Stop();self._arrival=nil end
  else
   -- settling hum in the cabin; the plant is heard faintly through the open doors
   local rise=math.clamp((os.clock()-a.t0)/.6,0,1)
   setVolume(hum,SOUNDS.arrivalHum[2]*rise)
   self._ambDb+=(-24-self._ambDb)*(1-math.exp(-dt*3))
  end
 else
  -- outside an arrival: move toward the target at a steady rate in dB
  local step=12*dt
  self._ambDb=self._ambDb<ambientTarget and math.min(ambientTarget,self._ambDb+step) or math.max(ambientTarget,self._ambDb-step)
  setVolume(self:_Sound('arrivalHum'),0)
 end
 local g=self._ambDb<=-59 and 0 or db(self._ambDb)
 setVolume(self:_Sound('drone'),SOUNDS.drone[2]*g)
 setVolume(self:_Sound('hum'),SOUNDS.hum[2]*g)
end
------------------------------------------------------------------ lift ride crossfade
-- Floor to floor, nothing cuts and nothing goes black. Every sound that lives on a floor runs
-- through one SoundGroup (FloorFade): when the doors shut and the lift pulls away the floor you
-- are leaving fades out (its model lingers a few seconds as DepartingFloor for exactly this), the
-- light dips a little while you ride, and as the doors part on the next floor its sounds rise
-- out of silence and the light comes back up. The same rise plays when the intro ride first
-- opens onto Level 5.
local FADE_OUT,FADE_IN=2.2,2.6
local function floorOf(inst,env)
 local a=inst.Parent
 while a and a~=env do
  if a:IsA('Model') and (a:GetAttribute('EncounterId') or a:GetAttribute('DepartedEncounter')) then return a end
  a=a.Parent
 end
end
function Controller:_FloorSound(s,env)
 if s:IsA('Sound') and s.SoundGroup==nil and floorOf(s,env) then s.SoundGroup=self._fadeGroup end
end
function Controller:_LiftFade(dt)
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 if not env then return end
 if not self._fadeGroup then
  local g=Instance.new('SoundGroup');g.Name='FloorFade';g.Volume=1;g.Parent=SoundService;self._scope:Add(g);self._fadeGroup=g
  self._fadeP=1;self._dipQ=0
 end
 if self._fadeEnv~=env then
  self._fadeEnv=env
  for _,d in env:GetDescendants()do self:_FloorSound(d,env) end
  self._scope:Add(env.DescendantAdded:Connect(function(d)if d:IsA('Sound') then task.defer(function()if d.Parent then self:_FloorSound(d,env) end end) end end))
 end
 -- the floor being left is deleted by the server a moment after the doors shut: copy whatever it
 -- is still playing near you into local ghosts in the same spots, so its sound fades out with the
 -- group instead of cutting dead
 local dep=env:FindFirstChild('DepartingFloor')
 if dep and dep~=self._ghosted then
  self._ghosted=dep
  local cam=workspace.CurrentCamera;local eye=cam and cam.CFrame.Position or Vector3.zero
  local n=0
  for _,s in dep:GetDescendants()do
   if s:IsA('Sound') and s.IsPlaying and s.Volume>.01 and n<24 then
    local host=s.Parent;local pos=host and (host:IsA('BasePart') and host.Position or host:IsA('Attachment') and host.WorldPosition)
    if not pos or (pos-eye).Magnitude<s.RollOffMaxDistance+10 then
     n+=1
     local g=s:Clone();g.Name='Ghost_'..s.Name;g.SoundGroup=self._fadeGroup;g.TimePosition=s.TimePosition
     if pos then local a=Instance.new('Attachment');a.Name='SoundGhost';a.WorldPosition=pos;a.Parent=workspace.Terrain;g.Parent=a;game:GetService('Debris'):AddItem(a,FADE_OUT+.6)
     else g.Parent=SoundService;game:GetService('Debris'):AddItem(g,FADE_OUT+.6) end
     g:Play();s.Volume=0 -- (the original goes silent here so the two never double up)
    end
   end
  end
 end
 local cabin=env:FindFirstChild('Elevator')
 local ctx=self._player:GetAttribute('EHContext')
 local door=cabin and cabin:GetAttribute('DoorState')
 local travelling=cabin and cabin:GetAttribute('TravelStartedAt')~=nil
 local boarding=cabin and cabin:GetAttribute('Boarding')==true
 local want=1
 if boarding then want=1
 elseif travelling or ctx=='Transit' then want=0
 elseif ctx=='Intro' then want=(door=='Opening' or door=='Open') and 1 or 0 end
 -- once the doors are parting on a floor the new floor fades in, whatever the context says
 if not travelling and (door=='Opening' or door=='Open') and ctx~='Lobby' then want=1 end
 local p=self._fadeP
 if p<want then p=math.min(want,p+dt/FADE_IN) elseif p>want then p=math.max(want,p-dt/FADE_OUT) end
 self._fadeP=p
 local u=p*p*(3-2*p)
 self._fadeGroup.Volume=u
 -- the light dip: only while actually riding between floors
 local q=self._dipQ;local qw=travelling and 1 or 0
 if q<qw then q=math.min(1,q+dt/FADE_OUT) elseif q>qw then q=math.max(0,q-dt/FADE_IN) end
 self._dipQ=q
 local k=q*q*(3-2*q)
 local cc=self._dipGrade
 if k>.002 then
  if not cc or not cc.Parent then cc=Instance.new('ColorCorrectionEffect');cc.Name='LiftRideGrade';cc.Parent=game:GetService('Lighting');self._scope:Add(cc);self._dipGrade=cc end
  cc.Enabled=true;cc.Brightness=-.07*k;cc.Contrast=-.04*k;cc.Saturation=-.22*k;cc.TintColor=Color3.new(1,1,1):Lerp(Color3.fromRGB(226,232,240),k)
 elseif cc then cc.Enabled=false end
end
------------------------------------------------------------------ surface dusk
-- While the crew board at the surface (cabin attribute Boarding), this client swaps the pumping
-- station's grade for the works at late, overcast dusk: low cold light, a dense grey-green haze
-- (Atmosphere) that swallows the horizon, a full dark cloud deck, a desaturated grade, and the wind.
-- The yard's own lamps (harsh sodium floods, caged fluorescents) do the rest. Everything is put
-- back the moment the doors close (the yard is gone by then).
-- (the fog reaches far enough out to show the industrial skyline beyond the works as dark
-- shapes in the haze; the play area itself is fenced well inside that)
-- Surface at night, matched to the station below: deep darks under a heavy overcast, the yard lit
-- almost only by its own floodlights, lamps and the glowing pods. Ambient stays low (just enough to
-- read shapes), specular is high so wet concrete and metal pick up the lamps, and a dense haze
-- hangs in the air so every light carries a halo and a visible shaft.
-- (Oct 21: darker, so the street lamps and car lights carry the scene)
local DUSK={Ambient=Color3.fromRGB(9,10,12),OutdoorAmbient=Color3.fromRGB(21,24,28),Brightness=.3,ClockTime=21.3,FogStart=0,FogEnd=100000,
 FogColor=Color3.fromRGB(22,26,30),ExposureCompensation=-.3,EnvironmentDiffuseScale=.22,EnvironmentSpecularScale=.45,ShadowSoftness=.12} -- (specular .95 made metal edges flash white as the camera turned)
local SURFACE_GRADE={Brightness=0,Contrast=.2,Saturation=-.24,TintColor=Color3.fromRGB(206,222,230)}
local HAZE={Density=.44,Offset=.22,Color=Color3.fromRGB(38,44,48),Decay=Color3.fromRGB(15,18,21),Glare=.25,Haze=2.6}
-- {sound, volume, speed, treble cut dB}: every one of these is surface-only (see _SurfaceSky)
local SURFACE_AMBIENCE={
 {'rbxassetid://9112764573',.32},            -- crickets, a still night
 {'rbxassetid://9112777807',.2,1,-4},        -- air through the grass, very distant traffic
 {'rbxassetid://9112838931',.07,.85,-12},    -- the works: compressors and machine hum, far off
 {'rbxassetid://9112784654',.05,.9,-18},     -- the highway beyond the barriers, muffled
}
function Controller:_SurfaceSky(on)
 local L=game:GetService('Lighting')
 if on then
  local atm=Instance.new('Atmosphere');atm.Name='SurfaceHaze'
  for k,v in HAZE do atm[k]=v end
  atm.Parent=L;self._haze=atm
  local ok,clouds=pcall(function()local c=Instance.new('Clouds');c.Name='SurfaceOvercast';c.Cover=.92;c.Density=.8;c.Color=Color3.fromRGB(34,37,40);c.Parent=workspace.Terrain;return c end)
  if ok then self._clouds=clouds end
  -- (Oct 25) it rains over the whole surface, cutscenes included
  pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.Rain).Start()end)
  local sky=L:FindFirstChildOfClass('Sky')
  if sky then self._sky={sky=sky,stars=sky.StarCount,bodies=sky.CelestialBodiesShown};sky.StarCount=0;sky.CelestialBodiesShown=false end
   -- (Oct 23) the night outside: crickets, wind through the grass, the works humming, the highway far off
   self._amb={}
   for _,a in SURFACE_AMBIENCE do
    local snd=Instance.new('Sound');snd.Name='SurfaceAmbience';snd.SoundId=a[1];snd.Volume=a[2];snd.Looped=true;snd.PlaybackSpeed=a[3] or 1
    if a[4] then local eq=Instance.new('EqualizerSoundEffect');eq.HighGain=a[4];eq.MidGain=a[4]*.4;eq.LowGain=0;eq.Parent=snd end
    snd.Parent=game:GetService('SoundService');snd.TimePosition=math.random()*20;snd:Play();table.insert(self._amb,snd)
   end
 else
  pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.Rain).Stop()end)
  if self._amb then for _,a in self._amb do a:Destroy() end;self._amb=nil end
   if self._haze then self._haze:Destroy();self._haze=nil end
  if self._clouds then self._clouds:Destroy();self._clouds=nil end
  if self._sky then local s=self._sky;if s.sky.Parent then s.sky.StarCount=s.stars;s.sky.CelestialBodiesShown=s.bodies end;self._sky=nil end
 end
end
function Controller:_Daylight()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 local on=cabin and cabin:GetAttribute('Boarding')==true or false
 local descendAt=cabin and cabin:GetAttribute('DescendAt')
 local L=game:GetService('Lighting')
 if on and not self._day and not descendAt then
  self._day={};self._fx={}
  -- (the station's darkness to return to comes from the runtime lighting config, not whatever the
  -- Lighting service happens to hold this frame - the place is saved bright for editing)
  local dark=require(Shared.Config.RuntimeLighting).Lighting
  for k,v in DUSK do local d=dark[k];if d==nil then d=L[k] end;self._day[k]=d;L[k]=v end
  for _,c in L:GetChildren()do
   if c:IsA('ColorCorrectionEffect') then self._fx[c]={c.Brightness,c.Contrast,c.Saturation,c.TintColor};for k,v in SURFACE_GRADE do c[k]=v end end
  end
  self:_SurfaceSky(true)
  self._fade=nil
 elseif self._day and not self._fade and (type(descendAt)=='number' or not on) then
  -- DESCEND was triggered (server time DescendAt): every client starts the same fade together
  self._fade=os.clock()-(type(descendAt)=='number' and math.clamp(workspace:GetServerTimeNow()-descendAt,0,1) or 0)
 end
 local outdoors=on and 1 or 0
 if self._fade then
  -- Cinematic descent: the view eases to black (1.4 s) while the doors close, holds while the yard
  -- is cleared and the crew line up, and fades back up (1.6 s) on the dim cabin as the cinematic
  -- begins. The lighting is blended from the surface dusk into the pumping station's darkness
  -- while the screen is black.
  local e=os.clock()-self._fade
  local k=math.clamp((e-1.2)/2.4,0,1);k=k*k*(3-2*k)
  for key,day in DUSK do
   local dark=self._day[key]
   if typeof(day)=='Color3' then L[key]=day:Lerp(dark,k) elseif type(day)=='number' then L[key]=day+(dark-day)*k end
  end
  for c,v in self._fx do if c.Parent then
   local g=SURFACE_GRADE
   c.Brightness=g.Brightness+(v[1]-g.Brightness)*k;c.Contrast=g.Contrast+(v[2]-g.Contrast)*k;c.Saturation=g.Saturation+(v[3]-g.Saturation)*k;c.TintColor=g.TintColor:Lerp(v[4],k)
  end end
  if self._haze then self._haze.Density=HAZE.Density*(1-k) end
  local black
  if e<1.4 then local u=e/1.4;black=u*u*(3-2*u) elseif e<4.4 then black=1 else black=1-math.clamp((e-4.4)/1.6,0,1)^.8 end
  self:_Black(black)
  outdoors=1-math.clamp(e/1.4,0,1)
  if e>=6 then
   for key,v in self._day do L[key]=v end
   for c,v in self._fx do if c.Parent then c.Brightness,c.Contrast,c.Saturation,c.TintColor=v[1],v[2],v[3],v[4] end end
   self:_SurfaceSky(false)
   self._day=nil;self._fx=nil;self._fade=nil;self:_Black(0)
  end
 end
 setVolume(self:_Sound('outdoors'),SOUNDS.outdoors[2]*outdoors)
 setVolume(self:_Sound('surfaceDrone'),SOUNDS.surfaceDrone[2]*outdoors)
 self._rainOut=outdoors
end
------------------------------------------------------------------ surface rain
-- It is raining up at the works: a curtain of thin, cold streaks falls around you (a box of rain that
-- follows the camera, this screen only) with the steady hiss of a downpour. Under a roof - the lift
-- cabin, a canopy, a doorway - the rain stops falling in front of you and its sound turns to a dull
-- drumming overhead. It comes and goes with the surface itself (outdoors: 0..1).
local RAIN_SOUND,RAIN_VOLUME='rbxassetid://9112856553',.35
local RAIN_RATE=0 -- (Oct 18, Ryan: no visible rain - just its sound, plus the lightning)
local RAIN_PARAMS=RaycastParams.new();RAIN_PARAMS.FilterType=Enum.RaycastFilterType.Exclude
function Controller:_Rain(outdoors,dt)
 local camera=workspace.CurrentCamera
 local r=self._rain
 if outdoors<=.001 or not camera then
  if r then r.box:Destroy();r.sound:Destroy();self._rain=nil end
  return
 end
 if not r then
  local box=Instance.new('Part');box.Name='SurfaceRain';box.Anchored=true;box.CanCollide=false;box.CanQuery=false;box.CanTouch=false
  box.Transparency=1;box.Size=Vector3.new(70,1,70);box.CastShadow=false
  local e=Instance.new('ParticleEmitter');e.Name='Rain'
  e.Texture='rbxasset://textures/particles/smoke_main.dds'
  e.Shape=Enum.ParticleEmitterShape.Box;e.ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume
  e.EmissionDirection=Enum.NormalId.Bottom;e.Orientation=Enum.ParticleOrientation.VelocityParallel
  e.Speed=NumberRange.new(80,92);e.SpreadAngle=Vector2.new(.5,.5);e.Acceleration=Vector3.zero -- (falls straight down)
  e.Lifetime=NumberRange.new(.42,.5)
  e.Size=NumberSequence.new(.17);e.Squash=NumberSequence.new(3) -- (longer streaks)
  e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(.06,.2),NumberSequenceKeypoint.new(.92,.25),NumberSequenceKeypoint.new(1,1)})
  e.Color=ColorSequence.new(Color3.fromRGB(150,182,226));e.LightEmission=.6;e.LightInfluence=.25;e.Brightness=2.4
  e.Rate=0;e.Parent=box
  box.Parent=camera
  local s=Instance.new('Sound');s.Name='SurfaceRainSound';s.SoundId=RAIN_SOUND;s.Looped=true;s.Volume=0
  local eq=Instance.new('EqualizerSoundEffect');eq.Name='Roof';eq.LowGain=0;eq.MidGain=0;eq.HighGain=0;eq.Parent=s
  s.Parent=game:GetService('SoundService');s:Play()
  r={box=box,emitter=e,sound=s,eq=eq,cover=0};self._rain=r
 end
 local eye=camera.CFrame.Position
 -- under a roof? (anything solid overhead within 40 studs)
 local c=self._player.Character
 RAIN_PARAMS.FilterDescendantsInstances={camera,c}
 local roof=workspace:Raycast(eye,Vector3.new(0,40,0),RAIN_PARAMS)~=nil
 r.cover+=((roof and 1 or 0)-r.cover)*(1-math.exp(-dt*4))
 -- the box rides above you, a little ahead of where you look, so you always walk into falling rain
 local look=camera.CFrame.LookVector;local ahead=Vector3.new(look.X,0,look.Z)*10
 r.box.CFrame=CFrame.new(eye+ahead+Vector3.new(0,22,0))
 r.emitter.Rate=RAIN_RATE*outdoors*(1-r.cover)
 r.sound.Volume=RAIN_VOLUME*outdoors*(1-.45*r.cover)
 r.eq.HighGain=-16*r.cover;r.eq.MidGain=-5*r.cover;r.eq.LowGain=3*r.cover
end
------------------------------------------------------------------ surface storm
-- A thunderstorm far off over the works (Oct 18): a low rolling rumble under the rain, and every
-- 9-20 s a distant lightning flash - the whole sky flickers cold white for a split second (a screen
-- grade pulse, two or three quick flickers) and the thunder arrives 1.5-4 s later, like a strike
-- miles away. Under a roof the flash is dimmer. Comes and goes with the surface (outdoors 0..1).
local THUNDER={'rbxassetid://9120018172','rbxassetid://9120018216','rbxassetid://9120018050'}
local RUMBLE='rbxassetid://9120018695'
function Controller:_Storm(outdoors,dt)
 local st=self._storm
 if outdoors<=.001 then
  if st then st.cc:Destroy();st.rumble:Destroy();for _,s in st.claps do s:Destroy() end;if st.shakeBound then pcall(function()game:GetService('RunService'):UnbindFromRenderStep('StormRumble')end) end;self._storm=nil end
  return
 end
 if not st then
  local cc=Instance.new('ColorCorrectionEffect');cc.Name='StormFlash';cc.Brightness=0;cc.TintColor=Color3.fromRGB(214,226,255);cc.Enabled=true;cc.Parent=game:GetService('Lighting')
  local rumble=Instance.new('Sound');rumble.Name='StormRumble';rumble.SoundId=RUMBLE;rumble.Looped=true;rumble.Volume=0;rumble.Parent=SoundService;rumble:Play()
  local claps={}
  for i,id in THUNDER do local s=Instance.new('Sound');s.Name='Thunder'..i;s.SoundId=id;s.Volume=0;local eq=Instance.new('EqualizerSoundEffect');eq.LowGain=7;eq.MidGain=1;eq.HighGain=-2;eq.Parent=s;s.Parent=SoundService;claps[i]=s end
  st={cc=cc,rumble=rumble,claps=claps,next=os.clock()+4+math.random()*5,flash=nil};self._storm=st
 end
 local cover=self._rain and self._rain.cover or 0
 st.rumble.Volume=.5*outdoors
 local now=os.clock()
 if now>=st.next and not st.flash then
  -- a strike: 2-3 flickers over ~0.45 s, then the thunder after a distance delay
  local pulses={} local t=0
  -- (Oct 25) every so often a CLOSE strike: blinding flash, near-instant crack, a much heavier and longer shake
   local big=now>=(st.nextBig or now+20) and math.random()<.75
   if big then st.nextBig=now+22+math.random()*18 elseif not st.nextBig then st.nextBig=now+20 end
   for _=1,math.random(2,3) do table.insert(pulses,{t,.08+math.random()*.07,big and (1+math.random()*.3) or (.26+math.random()*.24)});t+=.1+math.random()*.12 end
  st.flash={start=now,pulses=pulses,len=t+.25}
  local clap=st.claps[math.random(1,#st.claps)]
  local delay=big and (.2+math.random()*.3) or (1.5+math.random()*2.5)
  task.delay(delay,function()if clap.Parent then clap.PlaybackSpeed=.88+math.random()*.16;clap.Volume=(big and 4 or (1.7+math.random()*.6))*(self._rainOut or outdoors);if big then clap.PlaybackSpeed=.8+math.random()*.08 end;clap.TimePosition=0;clap:Play();st.shakeAt=os.clock();st.shakeAmp=big and (3.45+math.random()*.75) or (2.1+math.random()*.57);st.shakeLen=big and 5 or 3 end end)
  st.next=now+9+math.random()*11
 end
 local b=0
 if st.flash then
  local u=now-st.flash.start
  for _,p in st.flash.pulses do local x=(u-p[1])/p[2];if x>=0 and x<=1 then b=math.max(b,p[3]*math.sin(x*math.pi)) end end
  if u>st.flash.len then st.flash=nil end
 end
 do local okR,R=pcall(require,game.ReplicatedStorage.Game.Shared.Utilities.Rain);if okR and R.Level and R.Level()==2 then b=0 end end -- (no lightning flash inside the lift building; the rumble stays)
  st.cc.Brightness=b*outdoors*(1-.6*cover)
 -- the thunder's rumble: a low, rolling shake of the view that swells in and dies away over ~2 s
 if not st.shakeBound then
  st.shakeBound=true
  game:GetService('RunService'):BindToRenderStep('StormRumble',Enum.RenderPriority.Camera.Value+2,function()
   local s2=self._storm;local cam=workspace.CurrentCamera
   if not s2 or not s2.shakeAt or not cam then return end
   local L=s2.shakeLen or 3;local u=os.clock()-s2.shakeAt;if u>(L>3 and L-.3 or L) then s2.shakeAt=nil;return end
   local env=math.min(1,u/(L>3 and .08 or .25))*(1-u/L)^2*(s2.shakeAmp or 1)*(self._rainOut or 1)
   local t=os.clock()
   local rx=(math.noise(t*9,1.3)*.6+math.noise(t*23,7.1)*.4)*math.rad(.55)*env
   local ry=(math.noise(t*8,4.2)*.6+math.noise(t*21,2.9)*.4)*math.rad(.45)*env
   cam.CFrame=cam.CFrame*CFrame.Angles(rx,ry,0)
  end)
 end
end
------------------------------------------------------------------ yard signals
-- The yard's indicator lamps, beacons and one failing tube are animated here (client-local, no
-- scripts inside the yard): parts tagged BlinkRate (Hz) / BlinkPhase blink on and off (BlinkSoft =
-- a slow pulse, for the aviation beacons); parts tagged Flicker drop out at random like a dying tube.
function Controller:_YardSignals()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 -- (the cabin carries the flag: the yard model itself may still be streaming in at this moment)
 if not yard then self._signals=nil;return end
 local s=self._signals
 if not s or s.yard~=yard then
  s={yard=yard,blink={},flicker={},rotors={}}
  for _,d in yard:GetDescendants()do
   if d:IsA('Model') and d:GetAttribute('RotateRPM') and d.PrimaryPart then
    table.insert(s.rotors,{m=d,base=d:GetPivot(),rpm=d:GetAttribute('RotateRPM'),phase=d:GetAttribute('RotatePhase') or 0})
   elseif d:IsA('BasePart') then
    if d:GetAttribute('BlinkRate') then table.insert(s.blink,{p=d,rate=d:GetAttribute('BlinkRate'),phase=d:GetAttribute('BlinkPhase')or 0,soft=d:GetAttribute('BlinkSoft')==true,color=d.Color,light=d:FindFirstChildOfClass('Light')})
    elseif d:GetAttribute('Flicker') then table.insert(s.flicker,{p=d,color=d.Color,light=d:FindFirstChildOfClass('Light'),next=0,on=true}) end
   end
  end
  for _,b in s.blink do b.base=b.light and b.light.Brightness end
  for _,f in s.flicker do f.base=f.light and f.light.Brightness end
  self._signals=s
 end
 local t=os.clock()
 -- clarifier scraper bridges creep round on the shared server clock (same angle on every screen)
 local now=workspace:GetServerTimeNow()
 for _,r in s.rotors do
  if r.m.Parent then r.m:PivotTo(r.base*CFrame.Angles(0,((now*r.rpm/60)+r.phase)%1*math.pi*2,0)) end
 end
 for _,b in s.blink do
  local u=(t*b.rate+b.phase)%1
  local k
  if b.soft then k=math.max(0,math.sin(u*math.pi*2))^2 else k=u<.5 and 1 or 0 end
  local tr=.82*(1-k)
  if math.abs(b.p.Transparency-tr)>.01 then b.p.Transparency=tr end
  if b.light then b.light.Brightness=b.base*k end
 end
 for _,f in s.flicker do
  if t>=f.next then
   -- mostly on, with bursts of short dropouts
   if f.on then f.on=false;f.next=t+math.random()*.12+.03 else f.on=true;f.next=t+(math.random()<.3 and math.random()*.15 or math.random()*3+.6) end
   f.p.Transparency=f.on and 0 or .75
   if f.light then f.light.Brightness=f.on and f.base or f.base*.08 end
  end
 end
end
function Controller:_Black(a)
 if not self._blackGui then
  -- authored in StarterGui.DescentFade (Black)
  self._blackGui=AuthoredGui.Get(self._player:WaitForChild('PlayerGui'),'DescentFade')
 end
 self._blackGui.Enabled=a>.002
 self._blackGui.Black.BackgroundTransparency=1-math.clamp(a,0,1)
end
------------------------------------------------------------------ arrival cover
-- From the moment the game place loads, the screen is solid black (every edge, every device) until
-- your character is standing where the run starts - on the surface apron while the crew board, or
-- in place for a rejoin - and only then fades up. You never see the lift interior (or a teleport)
-- before the surface. (inCabin: see the arrival audio above)
local JOIN_BLACK=.35 -- seconds of black after the loading screen before the eyes start to open
function Controller:_SpawnCover(dt)
 local c=self._cover;if not c then return end
 if not c.revealAt then
  local ch=self._player.Character;local root=ch and ch:FindFirstChild('HumanoidRootPart')
  local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
  local context=self._player:GetAttribute('EHContext')
  local ready=false
  if root and cabin then
   if cabin:GetAttribute('Boarding')==true then ready=not inCabin(root) -- placed out on the apron
   elseif context and context~='Lobby' then ready=true end           -- a run already under way
  end
  if ready then c.stable+=dt else c.stable=0 end
  -- safety reveal: 15 s after your character exists (never while there is no character yet - the
  -- crew may still be loading in, and lifting the cover then only showed an empty, dark world)
  if root then c.rootSince=c.rootSince or os.clock() else c.rootSince=nil end
  -- (a run already under way is only trusted after a few settled seconds: at the start of a run the
   -- character and context can arrive a moment before the cabin's Boarding flag, which would skip
   -- the arrival drive and wake-up)
   local need=(cabin and cabin:GetAttribute('Boarding')==true) and .1 or 3
   if c.stable>=need or (c.rootSince and os.clock()-c.rootSince>15) or os.clock()-c.start>90 then
   c.revealAt=os.clock()
   -- the loading screen (ReplicatedFirst) fades its words out over the black now
   self._player:SetAttribute('EHArrivalReady',true)
   -- first time on the surface: you wake up instead of the screen simply fading in
   if ready and cabin and cabin:GetAttribute('Boarding')==true and not self._woke then
    self._woke=true
    -- the black screen after joining lasts exactly JOIN_BLACK seconds before the eyes start to
    -- open (if your character is ready sooner, the rest of that second is held black here)
    self._wakeBlack=math.max(0,JOIN_BLACK-(os.clock()-c.start))
    -- (Oct 21) the arrival drive plays first when the yard has the crew's car: typed lines over
    -- black, the drive up to the closed barrier, then the picture fades up beside the car (the
    -- wake-up comes later, after the drive through the gate into the car park: see Start)
    local yard=env and env:FindFirstChild('SurfaceYard')
    if cabin:GetAttribute('ArrivalCar') then
     local okD=pcall(function()
      require(game.ReplicatedStorage.Game.Shared.Utilities.ArrivalDrive).Play({player=self._player,env=env,cover=c.gui,fadeIn=true,
       onDone=function()self._player:SetAttribute('EHSpawnHold',nil);self._player:SetAttribute('EHCinematic',nil) end})
     end)
     if okD then self._cover=nil;return end
    end
    local ok=pcall(self._StartWake,self)
    if ok then c.gui:Destroy();self._cover=nil;return end
   end
  end
 end
 local a=c.revealAt and 1-math.clamp((os.clock()-c.revealAt)/1.2,0,1) or 1
 a=a*a*(3-2*a)
 c.frame.BackgroundTransparency=1-a
 -- (no wake-up this time - a rejoin mid-run: the control lock ends once the picture is fully up)
 if a<=0 then c.gui:Destroy();self._cover=nil;self._player:SetAttribute('EHSpawnHold',nil) end
end
------------------------------------------------------------------ waking up on the approach road
-- The first time you appear on the surface you wake up rather than fading in: black, then a heavy
-- double blink (the lids part, sag shut again, then open for good) while blur, depth of field and
-- a too-wide field of view clear. Your gaze rests on the lit treatment pods looming over the wall,
-- then eases down to the road ahead and control is handed back. Purely local presentation.
-- natural double blink: the lids part a little and heavily, sink shut again, then open for good
local WAKE={black=0,open1=1.9,droop=.5,shut=.35,open2=1.8,settle=1.9}
-- the view starts a step behind and a little above your eyes for a clean look at the glowing pods,
-- and drifts into your own eyes as you come round
local WAKE_PULLBACK,WAKE_LIFT=2.6,.6
local LID_SLICES=40
local WAKE_PAN=-24 -- degrees the view starts off the tanks before panning onto them
local function smooth(u)u=math.clamp(u,0,1);return u*u*(3-2*u)end
local function wakeCurve(t,black) -- lid closure 0..1, haze 0..1
 local w=WAKE
 local a=black or w.black;local b=a+w.open1;local c=b+w.droop;local d=c+w.shut;local e=d+w.open2
 if t<a then return 1,1 end
 if t<b then local u=smooth((t-a)/w.open1);return 1-.4*u^1.3,1-.3*u end
 if t<c then local u=smooth((t-b)/w.droop);return .6+.4*u,.7+.15*u end
 if t<d then return 1,.85 end
 if t<e then local u=smooth((t-d)/w.open2);return 1-u^.85,.85*(1-u) end
 return 0,0
end
function Controller:_StartWake()
 local p=self._player
 local ch=p.Character;local root=ch and ch:FindFirstChild('HumanoidRootPart');local head=ch and ch:FindFirstChild('Head')
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 local yard=env and env:FindFirstChild('SurfaceYard')
 local pods=yard and yard:FindFirstChild('TreatmentPods',true)
 assert(root and head and pods,'nothing to wake up to')
 local cf,size=pods:GetBoundingBox()
 local target=cf.Position+Vector3.new(0,size.Y*.22,0)
 local camera=workspace.CurrentCamera
 -- authored in StarterGui.WakeLids: Shut (full black). The eye opening itself is an almond: the overlap
 -- of two huge circles (one per lid), each painted black everywhere outside its edge by a very thick
 -- stroke - smooth curved lids that meet in points at the corners, like a real eye. Two fainter copies
 -- just inside soften the edge (a lash shadow). (The old strip templates are left hidden.)
 local g=AuthoredGui.Fresh(p:WaitForChild('PlayerGui'),'WakeLids');g.Enabled=false
 local shut=g:WaitForChild('Shut')
 for _,n in {'UpperLidTemplate','LowerLidTemplate'} do local t=g:FindFirstChild(n);if t then t.Visible=false end end
 local lids={}
 local function lidCircle(alpha)
  local f=Instance.new('Frame');f.Name='Lid';f.BackgroundTransparency=1;f.AnchorPoint=Vector2.new(.5,.5);f.BorderSizePixel=0;f.ZIndex=2
  local c=Instance.new('UICorner');c.CornerRadius=UDim.new(.5,0);c.Parent=f
  local st=Instance.new('UIStroke');st.Color=Color3.new(0,0,0);st.Thickness=4000;st.Transparency=alpha;st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;st.Parent=f
  f.Parent=g;return f
 end
 for _,layer in {{0,0}} do -- {inset as a fraction of screen height, transparency}
  table.insert(lids,{up=lidCircle(layer[2]),lo=lidCircle(layer[2]),inset=layer[1]})
 end
 -- open = 0 (shut) .. 1 (wide)
 local function setLids(open)
  local S=g.AbsoluteSize;local W,H=math.max(S.X,1),math.max(S.Y,1)
  local R=.95*W -- (smaller circles: the eye's pointed corners show while it is half open)
  local full=R+H/2-math.sqrt(math.max(R*R-W*W/4,0))+.1*H -- half-height at which the lids clear every corner
  local e=math.clamp(open,0,1)^1.25
  for _,l in lids do
   local hu=math.max(0,e*full-l.inset*H)
   local hl=math.max(0,e*full*(.8+.2*e)-l.inset*H) -- the lower lid opens a little less
   l.up.Size=UDim2.fromOffset(2*R,2*R);l.up.Position=UDim2.fromOffset(W/2,H/2-hu+R)
   l.lo.Size=UDim2.fromOffset(2*R,2*R);l.lo.Position=UDim2.fromOffset(W/2,H/2+hl-R)
  end
 end
 setLids(0)
 g.Enabled=true
 local blur=Instance.new('BlurEffect');blur.Name='WakeBlur';blur.Size=24;blur.Parent=camera
 local dof=Instance.new('DepthOfFieldEffect');dof.Name='WakeFocus';dof.FarIntensity=.55;dof.NearIntensity=.9;dof.InFocusRadius=18;dof.FocusDistance=(target-head.Position).Magnitude;dof.Parent=camera
 local controls
 pcall(function()local pm=p.PlayerScripts:FindFirstChild('PlayerModule');if pm then controls=require(pm):GetControls();controls:Disable() end end)
 local fov0=camera.FieldOfView
 p:SetAttribute('EHCinematic',true)
 local t0=os.clock()
 local black=self._wakeBlack or WAKE.black
 local total=black+WAKE.open1+WAKE.droop+WAKE.shut+WAKE.open2
 -- the one fixed way you face when you come round: the facing the server spawned you with
 local facing=ch:GetAttribute('EHFacing')
 local Lock=require(game.ReplicatedStorage.Game.Shared.Utilities.ControlLock)
 local function finish()
  RunService:UnbindFromRenderStep('BlackwaterWake')
  p:SetAttribute('EHCinematic',nil)
  p:SetAttribute('EHSpawnHold',nil) -- (InputController still waits for the camera to be home)
  g:Destroy();blur:Destroy();dof:Destroy()
  camera.FieldOfView=fov0
  if controls then pcall(function()controls:Enable()end)end
  self._wakeFinish=nil
 end
 self._wakeFinish=finish
 RunService:BindToRenderStep('BlackwaterWake',Enum.RenderPriority.Camera.Value+3,function()
  local t=os.clock()-t0
  if not root.Parent or not head.Parent then finish();return end
  -- once the eyes are fully open the first-person camera runs again underneath ('Return' keeps the
  -- controls locked) and the view settles into it, so control comes back without any jump
  local want=t>=total and 'Return' or true
  if p:GetAttribute('EHCinematic')~=want then p:SetAttribute('EHCinematic',want) end
  if want=='Return' and camera.CameraType~=Enum.CameraType.Custom then camera.CameraType=Enum.CameraType.Custom end
  local lid,haze=wakeCurve(t,black)
  setLids(1-lid)
  shut.BackgroundTransparency=1-smooth((lid-.9)/.1)
  blur.Size=3+21*haze
  if t>total then blur.Size=3*(1-smooth((t-total)/WAKE.settle)) end
  dof.NearIntensity=.9*math.max(haze,1-smooth(t/(total+WAKE.settle)));dof.FarIntensity=.55*dof.NearIntensity
  -- gaze: on the pods while you come round, then down to the road ahead
  local k=smooth((t-total)/WAKE.settle)
  -- a clean, slightly set-back view of the glowing pods that drifts forward into your own eyes
  local head0=head.Position+Vector3.new(0,.35,0)
  local flatPod=Vector3.new(target.X-head0.X,0,target.Z-head0.Z).Unit
  local back=1-smooth(t/(total+WAKE.settle*.6))
  local eye=head0-flatPod*WAKE_PULLBACK*back+Vector3.new(0,WAKE_LIFT*back,0)
  -- a slow, locked pan: the eyes first open a little off to the side and drift across onto the
  -- big blue-lit tanks, where the gaze settles while you come round
  local pan=math.rad(WAKE_PAN)*(1-smooth(t/(total*.85)))
  local podDir=CFrame.Angles(0,pan,0)*(target-eye).Unit
  if want=='Return' then eye=eye:Lerp(camera.CFrame.Position,k) end
  local fwd=typeof(facing)=='Vector3' and facing or root.CFrame.LookVector;fwd=Vector3.new(fwd.X,0,fwd.Z).Unit
  local dir=podDir:Lerp(fwd,k);if dir.Magnitude<1e-3 then dir=fwd end
  local daze=1-smooth(t/(total+WAKE.settle))
  -- (Oct 23) once the eyes are open: a short shake of the head to clear it (three quick turns that die away)
   local sk=t-total-.1;local shake=0
   if sk>0 and sk<1.4 then shake=math.sin(sk*2*math.pi*2.2)*.12*math.sin(math.pi*sk/1.4) end
   camera.CFrame=CFrame.lookAt(eye,eye+dir.Unit)*CFrame.Angles(math.sin(t*.8)*.012*daze,math.sin(t*.55)*.018*daze+shake,.07*daze+shake*.22)
  -- (the control lock holds the view at exactly what is drawn here, so nothing turns on its own
  -- when the wake-up lets go)
  if want=='Return' then Lock.heldRot=camera.CFrame.Rotation end
  camera.FieldOfView=fov0+14*daze
  if t>=total+WAKE.settle then finish() end
 end)
end
function Controller:Start()
 local role=Shared.Parent:GetAttribute('PlaceRole')or require(Shared.Config.PlaceConfig).Resolve(game.PlaceId,RunService:IsStudio(),workspace:GetAttribute('EHStudioPlaceRole'))
 if role~='Game' then return end
 -- locked from the very first frame (released by the cover / wake-up below)
 self._player:SetAttribute('EHSpawnHold',true)
 do
  -- authored in StarterGui.ArrivalCover (Black); up from the very first frame
  local g=AuthoredGui.Fresh(self._player:WaitForChild('PlayerGui'),'ArrivalCover');g.Enabled=true
  local f=g:WaitForChild('Black');self._scope:Add(g)
  self._cover={gui=g,frame=f,start=os.clock(),stable=0}
  self._scope:Add(RunService.RenderStepped:Connect(function(dt)if self._cover then pcall(self._SpawnCover,self,math.min(dt,.1))end end))
 end
 -- Spawn guard: a new character is held still (on this client, which simulates it) until the
 -- ground under it has actually streamed in, so it can never drop through a floor that is not
 -- there yet - no falling through the apron or the lift floor, no lost health at the start.
 -- Every new character starts under the control lock (EHSpawnHold, see InputController). The
 -- first one is released by the join cover / wake-up; any later one as soon as it stands on solid
 -- ground.
 local function guard(ch)
  self._player:SetAttribute('EHSpawnHold',true)
  task.spawn(function()
   local function done()
    task.wait(.3)
    if self._player.Character==ch and not self._cover and not self._wakeFinish then self._player:SetAttribute('EHSpawnHold',nil) end
   end
   local root=ch:WaitForChild('HumanoidRootPart',10);if not root then done();return end
   local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={ch}
   -- (anything solid anywhere below counts: a character spawned or dropped above a real floor
   -- simply falls onto it - it is only ever held while the floor itself has not streamed in yet,
   -- and never for long, so nobody hangs in the air)
   local function grounded()return workspace:Raycast(root.Position,Vector3.new(0,-120,0),params)~=nil end
   if grounded() then done();return end
   root.Anchored=true
   local t0=os.clock()
   while ch.Parent and root.Parent and not grounded() and os.clock()-t0<4 do task.wait(.05) end
   if root.Parent then root.AssemblyLinearVelocity=Vector3.zero;root.Anchored=false end
   done()
  end)
 end
 if self._player.Character then guard(self._player.Character) end
 self._scope:Add(self._player.CharacterAdded:Connect(guard))
 local acc=0
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)
  dt=math.clamp(dt,0,.1)
  pcall(self._Daylight,self)
  local okR,errR=pcall(self._Rain,self,self._rainOut or 0,dt);if not okR then warn('[ElevatorHorror] rain: '..tostring(errR)) end
  local okS,errS=pcall(self._Storm,self,self._rainOut or 0,dt);if not okS then warn('[ElevatorHorror] storm: '..tostring(errS)) end
  pcall(self._YardSignals,self)
  local okF,errF=pcall(self._LiftFade,self,dt);if not okF and not self._fadeWarned then self._fadeWarned=true;warn('[ElevatorHorror] lift fade: '..tostring(errF)) end
  local ok,err=pcall(self._Audio,self,dt);if not ok then warn('[ElevatorHorror] atmosphere audio: '..tostring(err))end
  acc+=dt
  if acc>=.5 then
   acc=0
   local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
   if env then for _,m in env:GetChildren()do if m:GetAttribute('EncounterId') and not self._floors[m]then self:_Index(m)end end end
  end
 end))
 self._scope:Add(RunService.RenderStepped:Connect(function()pcall(self._Power,self,workspace:GetServerTimeNow())end))
  -- (Oct 23) the checkpoint: characters in the car are hidden; the drive in starts from GateDriveAt
  local AD=require(game.ReplicatedStorage.Game.Shared.Utilities.ArrivalDrive)
  pcall(AD.WatchCar,self._player)
  pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.KeycardSwipe).Watch()end)
 pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.LiftLampFlicker).Start()end)
 pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.CrtStatic).Start()end) -- (Oct 26) gatehouse CRT snow
 pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.FrontDeskNPC).Start()end) -- (Oct 26) gatehouse attendant: breathing, head sway, head follow after check-in
 pcall(function()require(game.ReplicatedStorage.Game.Shared.Utilities.CheckInTalk).Start()end) -- (Nov 2) check-in conversation box (StarterGui.CheckInTalk)
  task.spawn(function()
   while self._scope do
    local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
    local yard=env and env:FindFirstChild('SurfaceYard')
    local at=yard and yard:GetAttribute('GateDriveAt')
    if type(at)=='number' and at~=self._gateFor then
     self._gateFor=at
     if workspace:GetServerTimeNow()-at<AD.GateTotal-1 then
      local okG,errG=pcall(AD.PlayGate,{player=self._player,yard=yard,onDone=function()
       self._wakeBlack=.35
       local okW=pcall(self._StartWake,self)
       if not okW then self._player:SetAttribute('EHSpawnHold',nil);self._player:SetAttribute('EHCinematic',nil) end
      end})
      if not okG then warn('[ElevatorHorror] gate drive: '..tostring(errG));self._player:SetAttribute('EHCinematic',nil) end
     end
    end
    task.wait(.15)
   end
  end)
end
function Controller:Destroy()
 if self._wakeFinish then pcall(self._wakeFinish) end
 pcall(function()self._player:SetAttribute('EHSpawnHold',nil)end)
 local runtime=nil
 if self._day then local L=game:GetService('Lighting');for k,v in self._day do if type(k)=='string' then L[k]=v end end;self._day=nil end
 pcall(self._SurfaceSky,self,false)
 pcall(self._Rain,self,0,0)
 pcall(self._Storm,self,0,0)
 if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
