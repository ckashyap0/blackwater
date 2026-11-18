--!nonstrict
-- LEVEL 3: FILTRATION, client side (presentation only; the server owns all state).
--  * BLACK WATER: each reach (a Folder tagged BlackWaterReach) publishes Head, its wet length. The film
--    parts up to Head fade in; the rest fade out. Nearby film ripples with nothing touching it.
--  * BEDS: a bed's water sinks when its inlet closes (Inlet<n>ClosedAt).
--  * FUMES: haze particles and a close ochre fog in the dosing room until the extract fan has run.
--  * HAZE: the player's own blur and grade from EHL3Haze (fumes or standing on film).
--  * HUD (authored in StarterGui.FiltrationHud): the header pressure column and the three wheel pips
--    during the bypass, a short toast, and TORCH OUT while black water holds the flashlight dead.
--  * LADDER: a short black fade while the server moves you up or down the hatch.
--  * KNOCKS: the knock signal from the floor (KnockAt / KnockRef) and on the cabin roof (RoofKnockAt).
--  * MONITOR: CAM 07 on the header console shows the booth glass, and the grey face when it comes.
-- Starts the intercom box (RadioLine) and the grey face (MartyGrey).
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local Lighting=game:GetService('Lighting')
local SoundService=game:GetService('SoundService')
local UIS=game:GetService('UserInputService')
local CS=game:GetService('CollectionService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local AuthoredGui=require(Shared.Utilities.AuthoredGui)
local HudScale=require(Shared.Utilities.HudScale)
local Refs=require(Shared.Utilities.FloorRefs)
local Config=require(Shared.Config.Level3)
local Knock=require(Shared.Utilities.KnockSignal)
local RadioLine=require(Shared.Utilities.RadioLine)
local MartyGrey=require(Shared.Utilities.MartyGrey)
local SetPieceFX=require(Shared.Utilities.SetPieceFX)
local Controller={};Controller.__index=Controller
local EASE=TweenInfo.new(.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
local L=Config.Light
function Controller.new(player,gui)return setmetatable({Name='FiltrationController',Dependencies={},_player=player,_gui=gui,_knocks={}},Controller)end
local function smooth(u)u=math.clamp(u,0,1);return u*u*(3-2*u)end
local function touch()return UIS.TouchEnabled and not UIS.KeyboardEnabled end
function Controller:Init()
 self._scope=Scope.new()
 local gui=AuthoredGui.Get(self._gui,'FiltrationHud');gui.Enabled=false;self._screen=gui
 local gauge=gui:WaitForChild('Gauge');self._gauge=gauge
 self._value=gauge:WaitForChild('Value');self._stateLabel=gauge:WaitForChild('State')
 local column=gauge:WaitForChild('Column')
 self._segs={}
 for _,s in column:GetChildren()do if s:IsA('Frame') and string.match(s.Name,'^Seg%d+$') then table.insert(self._segs,s) end end
 table.sort(self._segs,function(a,b)return tonumber(string.match(a.Name,'%d+'))<tonumber(string.match(b.Name,'%d+'))end)
 self._segOn={};self._segOff={}
 for i,s in self._segs do self._segOn[i]=s.BackgroundColor3;self._segOff[i]=s.BackgroundColor3:Lerp(Color3.fromRGB(16,17,16),.86) end
 local wheel=gauge:WaitForChild('Wheel')
 self._pips={wheel:WaitForChild('Pip1'),wheel:WaitForChild('Pip2'),wheel:WaitForChild('Pip3')}
 self._pipOn=self._pips[1].BackgroundColor3;self._pipOff=self._pipOn:Lerp(Color3.fromRGB(16,17,16),.86)
 self._toast=gui:WaitForChild('Toast');self._toastLabel=self._toast:WaitForChild('Label');self._toast.GroupTransparency=1
 self._torch=gui:WaitForChild('Torch');self._torch.GroupTransparency=1
 self._black=gui:WaitForChild('Black');self._black.BackgroundTransparency=1
 gauge.GroupTransparency=1
 self._fades={}
 for _,g in {gauge,self._toast,self._torch}do
  g.Visible=false;self._fades[g]=false
  local stroke=g:FindFirstChild('Outline');if stroke then stroke.Transparency=1 end
 end
 for _,f in {gauge,self._toast,self._torch}do
  local _,release=HudScale.Attach(f,{referenceSize=Vector2.new(960,600),min=.7,max=1.15,consoleBoost=1.15});self._scope:Add(release)
 end
end
function Controller:_Floor()
 local f=self._floor
 if f and f.Parent and f:GetAttribute('EncounterId')=='Level3' then return f end
 self._floor=nil
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 if env then for _,m in env:GetChildren()do if m:GetAttribute('EncounterId')=='Level3' then self._floor=m;self:_Bind(m);return m end end end
 return nil
end
------------------------------------------------------------------ bind a floor copy
function Controller:_Bind(floor)
 local b={reaches={},beds={},emitters={},seen={}}
 for _,f in CS:GetTagged('BlackWaterReach')do
  if f:IsDescendantOf(floor) then
   local segs={}
   for _,s in f:GetChildren()do local n=s:IsA('BasePart') and tonumber(string.match(s.Name,'^Seg(%d+)$'));if n then segs[n]=s end end
   local cum,total={},0
   for i,s in ipairs(segs)do total+=math.max(0,s.Size.Z-.9);cum[i]=total;s.LocalTransparencyModifier=0;s.Transparency=1 end
   table.insert(b.reaches,{folder=f,segs=segs,cum=cum,alpha=table.create(#segs,0),head=f:GetAttribute('Head') or 0})
  end
 end
 for i=1,6 do
  local w=Refs.Find(floor,'BedWater'..i)
  if w then b.beds[i]={part=w,base=w.CFrame} end
 end
 local zone=Refs.Find(floor,'FumeZone');b.fumeZone=zone
 for _,d in floor:GetDescendants()do
  if d:IsA('ParticleEmitter') and d:GetAttribute('Fume') then
   -- (R43) the dosing room's own fumes use the Blender gas sprite
   local gas=SetPieceFX.Presets.Gas;if gas then d.Texture=gas.Texture() end
   table.insert(b.emitters,{e=d,rate=d.Rate*(touch() and .5 or 1)})
  end
 end
 b.monitor=Refs.Find(floor,'ChamberMonitor')
 b.fan=Refs.Find(floor,'ExtractFanRotor')
 b.wheel=Refs.Find(floor,'BypassWheel');b.wheelBase=b.wheel and b.wheel.CFrame
 b.roarAt=Refs.Find(floor,'GalleryKnock')
 self._bound=b
end
------------------------------------------------------------------ black water film
function Controller:_Film(b,dt,eye)
 local range=touch() and L.RippleRangeTouch or L.RippleRange
 local budget=touch() and L.RipplePartsTouch or L.RippleParts
 local t=os.clock()
 for _,r in b.reaches do
  local target=r.folder:GetAttribute('Head') or 0
  r.head+=(target-r.head)*(1-math.exp(-dt*6))
  for i,s in ipairs(r.segs)do
   local start=(r.cum[i-1] or 0)
   local want=r.head>start+.4 and 1 or 0
   local a=r.alpha[i]
   if a~=want then
    a=want>a and math.min(1,a+dt/.6) or math.max(0,a-dt/.9)
    r.alpha[i]=a;s.Transparency=1-smooth(a)
   end
   -- ripples with nothing touching it: the film's ring texture drifts and pulses near you
   if a>.5 and budget>0 and (s.Position-eye).Magnitude<range then
    local tex=s:FindFirstChildOfClass('Texture')
    if tex then
     budget-=1
     tex.OffsetStudsU=(t*.35+i*1.7)%tex.StudsPerTileU
     tex.OffsetStudsV=math.sin(t*.6+i)*.4
     tex.Transparency=.55+.3*math.sin(t*1.3+i*2.1)
    end
   end
  end
 end
end
------------------------------------------------------------------ beds
function Controller:_Beds(b,floor,now)
 for i,bed in b.beds do
  local at=floor:GetAttribute('Inlet'..i..'ClosedAt')
  -- (R43) shutting a bed air-scours it: the surface boils white and roars, then it drains and its glow dies
  if type(at)=='number' and bed.scoured~=at then
   bed.scoured=at
   if now-at<3 then
    SetPieceFX.Burst(bed.part,'Boil',Config.Bed.ScourSeconds)
    SetPieceFX.Sound(Config.Sounds.scour,bed.part,.65,.9,Config.Bed.ScourSeconds+1)
    SetPieceFX.Sound('Gurgle',bed.part,.5,.8,6)
    SetPieceFX.Shake(.12,1.2,bed.part.Position)
   end
  end
  if not bed.glow then
   bed.glow={}
   for k=1,2 do local g=Refs.Find(floor,'BedGlow'..i..'_'..k);local l=g and g:FindFirstChildWhichIsA('Light');if l then table.insert(bed.glow,{l=l,b=l.Brightness}) end end
  end
  local dim=type(at)=='number' and smooth((now-at-1)/Config.Bed.DropSeconds) or 0
  for _,g in bed.glow do g.l.Brightness=g.b*(1-dim) end
  local u=type(at)=='number' and smooth((now-at)/Config.Bed.DropSeconds) or 0
  if bed.u~=u then
   bed.u=u;bed.part.CFrame=bed.base-Vector3.new(0,Config.Bed.DropStuds*u,0)
   -- a closed bed goes dark: it stops taking the light
   if not bed.color then bed.color=bed.part.Color end
   bed.part.Color=bed.color:Lerp(Color3.fromRGB(8,9,10),u)
  end
 end
end
------------------------------------------------------------------ the bypass wheel and main
-- Each finished turn swings the wheel round (WheelTurn<n>At); the bypass main along the gallery roof starts
-- to roar at the first turn and is at full flow by the third.
function Controller:_Bypass(b,floor,now)
 local angle,flow=0,0
 for i=1,Config.Wheel.Turns do
  local at=floor:GetAttribute('WheelTurn'..i..'At')
  if type(at)=='number' then local u=smooth((now-at+.2)/1.6);angle+=u*math.pi*1.5;flow+=u end
 end
 if b.wheel and b.wheelAngle~=angle then b.wheelAngle=angle;b.wheel.CFrame=b.wheelBase*CFrame.Angles(angle,0,0) end
 if flow>0 and b.roarAt then
  if not b.roar then
   local s=Instance.new('Sound');s.Name='BypassMainRoar';s.SoundId=Config.Sounds.drone;s.Looped=true;s.Volume=0;s.PlaybackSpeed=.42
   s.RollOffMinDistance=24;s.RollOffMaxDistance=170;s.Parent=b.roarAt;s:Play();b.roar=s
  end
  b.roar.Volume=(MartyGrey.Active and .04 or .16*flow)
 end
end
------------------------------------------------------------------ fumes and haze
function Controller:_Fumes(b,floor,now,dt,eye)
 local active=floor:GetAttribute('FumesActive')==true
 local fanAt=floor:GetAttribute('ExtractFanAt')
 local thin=1
 if type(fanAt)=='number' then thin=1-smooth((now-fanAt-Config.Fumes.FanSpinUp)/Config.Fumes.ThinSeconds) end
 if not active then thin=0 end
 if b.thin~=thin then
  b.thin=thin
  for _,e in b.emitters do e.e.Rate=e.rate*thin;e.e.Enabled=thin>.02 end
 end
 -- the fan turns once it is started
 if b.fan and type(fanAt)=='number' then
  local spin=smooth((now-fanAt)/Config.Fumes.FanSpinUp)
  b.fanAngle=((b.fanAngle or 0)+dt*spin*14)%(math.pi*2)
  if not b.fanBase then b.fanBase=b.fan.CFrame end
  b.fan.CFrame=b.fanBase*CFrame.Angles(0,0,b.fanAngle)
  -- and it roars: loud enough to hide footsteps
  if not b.fanSound then
   local s=Instance.new('Sound');s.Name='ExtractFanLoop';s.SoundId=Config.Sounds.fan~='' and Config.Sounds.fan or Config.Sounds.motor;s.Looped=true;s.Volume=0;s.PlaybackSpeed=1.5
   s.RollOffMinDistance=10;s.RollOffMaxDistance=90;s.Parent=b.fan;s:Play();b.fanSound=s
  end
  b.fanSound.Volume=.55*spin;b.fanSound.PlaybackSpeed=.6+.9*spin
 end
 -- close ochre fog while you stand in it
 local z=b.fumeZone;local inZone=false
 if z and thin>.02 then
  local p=z.CFrame:PointToObjectSpace(eye);local h=z.Size/2
  inZone=math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y and math.abs(p.Z)<=h.Z
 end
 local want=inZone and thin or 0
 self._fog=(self._fog or 0)+(want-(self._fog or 0))*(1-math.exp(-dt*2.5))
 -- (R43) the floor's own darker, longer fog (Config.Level3.Lighting), closing in to ochre in the fumes.
 -- The station's values are kept in _fogBase and put back when the floor is gone (Start).
 if not self._fogBase then self._fogBase={Lighting.FogEnd,Lighting.FogColor,Lighting.FogStart} end
 local F=Config.Lighting;local k=self._fog
 Lighting.FogEnd=F.FogEnd+(26-F.FogEnd)*k;Lighting.FogStart=F.FogStart*(1-k)
 Lighting.FogColor=F.FogColor:Lerp(Color3.fromRGB(92,84,52),k)
end
function Controller:_Haze(dt)
 local want=self._player:GetAttribute('EHL3Haze') or 0
 if self._player:GetAttribute('EHCinematic') then want=0 end -- (R43) a camera cut is never blurred by where you stand
 local kind=self._player:GetAttribute('EHL3HazeKind')
 local rate=want>(self._haze or 0) and 1/Config.Fumes.RiseSeconds or 1/Config.Fumes.ClearSeconds
 local h=self._haze or 0
 h=want>h and math.min(want,h+dt*rate) or math.max(want,h-dt*rate)
 self._haze=h
 if h>.005 then
  local cam=workspace.CurrentCamera
  if not self._blur or not self._blur.Parent then
   self._blur=Instance.new('BlurEffect');self._blur.Name='FiltrationHaze';self._blur.Parent=cam
   self._grade=Instance.new('ColorCorrectionEffect');self._grade.Name='FiltrationHazeGrade';self._grade.Parent=Lighting
  end
  if kind then self._hazeKind=kind end
  local fume=self._hazeKind=='Fume'
  self._blur.Size=(fume and 12 or 10)*h
  self._grade.Saturation=-.3*h;self._grade.Contrast=.06*h
  self._grade.TintColor=Color3.new(1,1,1):Lerp(fume and Color3.fromRGB(236,226,182) or Color3.fromRGB(196,206,208),h)
  -- fumes: a cough now and then
  if fume and want>.3 and os.clock()>(self._coughAt or 0) then
   self._coughAt=os.clock()+Config.Fumes.CoughMin+math.random()*(Config.Fumes.CoughMax-Config.Fumes.CoughMin)
   local id=Config.Sounds.cough~='' and Config.Sounds.cough or Config.Sounds.gasp
   local s=Instance.new('Sound');s.SoundId=id;s.Volume=.5;s.PlaybackSpeed=1.1+math.random()*.15;s.Parent=SoundService;s:Play();game:GetService('Debris'):AddItem(s,4)
  end
 elseif self._blur then
  self._blur:Destroy();self._blur=nil;self._grade:Destroy();self._grade=nil;self._hazeKind=nil
 end
end
------------------------------------------------------------------ HUD
function Controller:_Fade(group,shown)
 self._fades=self._fades or {}
 if self._fades[group]==shown then return end
 self._fades[group]=shown
 -- (a UIStroke does not follow GroupTransparency: fade the outline with the panel and hide it when gone)
 local stroke=group:FindFirstChild('Outline')
 if shown then group.Visible=true end
 local tween=TweenService:Create(group,EASE,{GroupTransparency=shown and 0 or 1});tween:Play()
 if stroke then TweenService:Create(stroke,EASE,{Transparency=shown and .35 or 1}):Play() end
 if not shown then tween.Completed:Connect(function()if self._fades[group]==false then group.Visible=false end end) end
end
function Controller:_Hud(floor,dt)
 local p=self._player
 local stage=floor and floor:GetAttribute('Stage')
 local onFloor=floor~=nil and p:GetAttribute('EHContext')=='ActiveFloor' and not p:GetAttribute('EHLoreOpen')
 local showGauge=onFloor and stage=='Bypass' and floor:GetAttribute('HeaderStartedAt')~=nil
 local blocked=p:GetAttribute('EHLightBlocked')==true
 local any=onFloor and (showGauge or blocked or (self._toastUntil or 0)>os.clock() or (self._blackA or 0)>0)
 if self._screen.Enabled~=(any or (self._hudLinger or 0)>os.clock()) then self._screen.Enabled=any or (self._hudLinger or 0)>os.clock() end
 if any then self._hudLinger=os.clock()+.6 end
 self:_Fade(self._gauge,showGauge==true)
 self:_Fade(self._torch,onFloor and blocked)
 if showGauge then
  local pressure=floor:GetAttribute('HeaderPressure') or 0
  self._shownP=(self._shownP or 0)+(pressure-(self._shownP or 0))*(1-math.exp(-dt*8))
  local n=#self._segs;local lit=self._shownP/100*n
  for i,s in self._segs do
   local on=i<=lit+.001
   if s:GetAttribute('On')~=on then s:SetAttribute('On',on);TweenService:Create(s,TweenInfo.new(.15,Enum.EasingStyle.Quart),{BackgroundColor3=on and self._segOn[i] or self._segOff[i]}):Play() end
  end
  self._value.Text=string.format('%d',math.floor(pressure+.5))
  local held=floor:GetAttribute('HeaderHeld')==true
  local latched=floor:GetAttribute('HeaderLatched')==true
  local sent=p:GetAttribute('EHL3Sent')==true
  local text=latched and 'LATCHED' or held and 'HOLDING' or 'DROPPING'
  if sent and pressure<Config.Header.WheelNeeds then text='NO PRESSURE' end
  if self._stateLabel.Text~=text then self._stateLabel.Text=text end
  local turns=floor:GetAttribute('WheelTurns') or 0
  for i,pip in self._pips do
   local on=i<=turns
   if pip:GetAttribute('On')~=on then pip:SetAttribute('On',on);TweenService:Create(pip,EASE,{BackgroundColor3=on and self._pipOn or self._pipOff}):Play() end
  end
 end
 self:_Fade(self._toast,(self._toastUntil or 0)>os.clock())
end
function Controller:_Toast(text)
 self._toastLabel.Text=text;self._toastUntil=os.clock()+3.2
end
------------------------------------------------------------------ ladder fade
function Controller:_LadderFade(now)
 local at=self._player:GetAttribute('EHL3LadderAt')
 local a=0
 if type(at)=='number' then
  local u=(now-at)/Config.Ladder.Seconds
  if u>=0 and u<1 then a=u<.35 and smooth(u/.35) or u>.65 and 1-smooth((u-.65)/.35) or 1 end
  if u>=0 and u<.1 and self._ladderFor~=at then
   self._ladderFor=at
   -- rungs under your hands
   for i=0,4 do task.delay(.15+i*.26,function()
    local s=Instance.new('Sound');s.SoundId=Config.Knock.Sound;s.Volume=.22;s.PlaybackSpeed=1.5+math.random()*.2;s.Parent=SoundService;s:Play();game:GetService('Debris'):AddItem(s,2)
   end) end
  end
 end
 if self._blackA~=a then self._blackA=a;self._black.BackgroundTransparency=1-a end
end
------------------------------------------------------------------ knocks
function Controller:_Knocks(floor)
 local at=floor:GetAttribute('KnockAt')
 if type(at)=='number' and self._knocks[floor]~=at then
  self._knocks[floor]=at
  local part=Refs.Find(floor,floor:GetAttribute('KnockRef') or '')
  Knock.At(part,at,.6)
 end
end
function Controller:_RoofKnock()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 local at=cabin and cabin:GetAttribute('RoofKnockAt')
 if type(at)=='number' and self._roofAt~=at then
  self._roofAt=at
  if self._player:GetAttribute('EHContext')~='Lobby' then Knock.At(nil,at,.55) end
 end
end
------------------------------------------------------------------ CAM 07 on the header console
function Controller:_Monitor(b,floor,now)
 local screen=b.monitor;local gui=screen and screen:FindFirstChildOfClass('SurfaceGui')
 if not gui then return end
 local dark,lit,eyes,empty,static=gui:FindFirstChild('Dark'),gui:FindFirstChild('Lit'),gui:FindFirstChild('Eyes'),gui:FindFirstChild('Empty'),gui:FindFirstChild('Static')
 local at=floor:GetAttribute('GreyFaceAt');local G=Config.Grey
 local state='Dark'
 if type(at)=='number' then
  local t=now-at
  if t>=0 and t<G.EyesAt then state='Lit'
  elseif t>=G.EyesAt and t<G.Hold then state='Eyes'
  elseif t>=G.Hold and t<G.Hold+G.Dark then state='Static'
  elseif t>=G.Hold+G.Dark and t<G.Hold+G.Dark+G.Empty then state='Empty' end
 end
 if b.monitorState~=state then
  b.monitorState=state
  if dark then dark.Visible=state=='Dark' or state=='Static' end
  if lit then lit.Visible=state=='Lit' end
  if eyes then eyes.Visible=state=='Eyes' end
  if empty then empty.Visible=state=='Empty' end
 end
 if static then
  -- crt snow: always a little, a lot on the cut
  static.ImageTransparency=state=='Static' and .15 or .82+.06*math.sin(now*31)
  static.Position=UDim2.fromScale(-math.random()*.2,-math.random()*.2)
 end
 local stamp=gui:FindFirstChild('Stamp')
 if stamp then stamp.Text=string.format('CAM 07  BYPASS BOOTH   03:12:%02d',math.floor(now)%60) end
end
function Controller:Start()
 if Shared.Parent:GetAttribute('PlaceRole')=='Lobby' then return end
 pcall(RadioLine.Start);pcall(MartyGrey.Start)
 self._scope:Add(self._player:GetAttributeChangedSignal('EHL3ToastSerial'):Connect(function()
  local t=self._player:GetAttribute('EHL3Toast');if t then self:_Toast(t) end
 end))
 -- a dead torch still clicks
 self._scope:Add(UIS.InputBegan:Connect(function(io,gp)
  if gp or io.KeyCode~=Enum.KeyCode.F or not self._player:GetAttribute('EHLightBlocked') then return end
  local s=Instance.new('Sound');s.SoundId=Config.Sounds.torchOn;s.Volume=.25;s.PlaybackSpeed=.8;s.Parent=SoundService;s:Play();game:GetService('Debris'):AddItem(s,2)
 end))
 -- the snuff: a short wet fizz as the beam dies
 self._scope:Add(self._player:GetAttributeChangedSignal('EHLightSnuffAt'):Connect(function()
  if type(self._player:GetAttribute('EHLightSnuffAt'))~='number' then return end
  local id=Config.Sounds.fizz~='' and Config.Sounds.fizz or Config.Sounds.crackle
  local s=Instance.new('Sound');s.SoundId=id;s.Volume=.3;s.PlaybackSpeed=1.3;s.Parent=SoundService;s:Play()
  task.delay(.8,function()s:Stop();s:Destroy();local c=Instance.new('Sound');c.SoundId=Config.Sounds.torchOff;c.Volume=.45;c.Parent=SoundService;c:Play();game:GetService('Debris'):AddItem(c,2)end)
 end))
 self._scope:Add(RunService.RenderStepped:Connect(function(dt)
  dt=math.min(dt,1/20)
  local now=workspace:GetServerTimeNow()
  local floor=self:_Floor()
  local cam=workspace.CurrentCamera;local eye=cam and cam.CFrame.Position or Vector3.zero
  local b=self._bound
  if floor and b then
   local ok,err=pcall(function()
    self:_Film(b,dt,eye);self:_Beds(b,floor,now);self:_Fumes(b,floor,now,dt,eye);self:_Bypass(b,floor,now);self:_Knocks(floor);self:_Monitor(b,floor,now)
   end)
   if not ok and not self._warned then self._warned=true;warn('[ElevatorHorror] Level 3 client: '..tostring(err)) end
  elseif self._fogBase then
   local base=self._fogBase;self._fogBase=nil;self._fog=0
   Lighting.FogEnd,Lighting.FogColor,Lighting.FogStart=base[1],base[2],base[3]
  end
  pcall(self._Haze,self,dt);pcall(self._LadderFade,self,now);pcall(self._RoofKnock,self)
  local okH,errH=pcall(self._Hud,self,floor,dt)
  if not okH and not self._warnedHud then self._warnedHud=true;warn('[ElevatorHorror] Level 3 HUD: '..tostring(errH)) end
 end))
end
function Controller:Destroy()
 if self._fogBase then local base=self._fogBase;Lighting.FogEnd,Lighting.FogColor,Lighting.FogStart=base[1],base[2],base[3] end
 if self._blur then self._blur:Destroy() end;if self._grade then self._grade:Destroy() end
 if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
