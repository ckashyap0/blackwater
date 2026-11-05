--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Intro=require(Shared.Utilities.IntroTimeline)
local Refs=require(Shared.Utilities.FloorRefs)
local RunService=game:GetService('RunService')
local CAS=game:GetService('ContextActionService')
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)return setmetatable({Name='ArrivalController',Dependencies={'CameraController','StateController'},_player=player,_gui=gui,_seen={}},Controller)end
-- Intro UI. Everything is built once, in two ScreenGuis with one organised tree each, and every
-- element is reached through self._ui (no loose elements, no hand-placed pixel offsets):
--  IntroEyes  (whole physical screen) > Eyes > Closed, Lids > UpperLid1..6, LowerLid1..6
--  IntroHud   (device safe area)      > Root (padded) > Row (bottom-centred, side by side, HUD_H tall)
--                                        > Dialogue > Caption, Hint
--                      > Skip > Action, Tally   (bottom-right corner)
-- compact HUD: one slim strip, the skip button the same height as the dialogue beside it
local HUD_H=64
local function new(class,props,parent)
 local o=Instance.new(class);for k,v in props do o[k]=v end
 if parent then o.Parent=parent end
 return o
end
function Controller:_BuildUi()
 -- Both screens are authored in StarterGui (edit them there):
 --  IntroEyes > Eyes > Closed, Lids > UpperLid1..6, LowerLid1..6  (each lid: attributes Upper, Feather; its UIStroke
 --              transparency is how dark that layer is)
 --  IntroHud  > Root > Row > Dialogue (Caption, Hint); Root > Skip (Action, Tally) in the corner
 local ui={}
 local eyes=AuthoredGui.Get(self._gui,'IntroEyes');eyes.Enabled=false;ui.EyesGui=eyes
 local eyeRoot=eyes:WaitForChild('Eyes');ui.Eyes=eyeRoot
 ui.Closed=eyeRoot:WaitForChild('Closed')
 local lidRoot=eyeRoot:WaitForChild('Lids')
 ui.Lids={}
 for _,upper in {true,false}do for i=1,6 do
  local f=lidRoot:FindFirstChild((upper and 'Upper' or 'Lower')..'Lid'..i)
  if f then
   local stroke=f:FindFirstChildOfClass('UIStroke')
   table.insert(ui.Lids,{frame=f,stroke=stroke,upper=upper,feather=f:GetAttribute('Feather') or 0,alpha=stroke and stroke.Transparency or 0})
  end
 end end
 local hud=AuthoredGui.Get(self._gui,'IntroHud');hud.Enabled=false;ui.Hud=hud
 local root=hud:WaitForChild('Root');ui.Root=root
 local row=root:WaitForChild('Row');ui.Row=row
 ui.Dialogue=row:WaitForChild('Dialogue');ui.Dialogue.Visible=false
 ui.Caption=ui.Dialogue:WaitForChild('Caption');ui.Hint=ui.Dialogue:WaitForChild('Hint')
 -- (the skip button sits on its own in the bottom-right corner of the screen, on every device)
 ui.Skip=root:WaitForChild('Skip');ui.Skip.Visible=false
 ui.SkipAction=ui.Skip:WaitForChild('Action');ui.SkipTally=ui.Skip:WaitForChild('Tally')
 return ui
end
-- shows / hides the two HUD panels (the HUD ScreenGui is on only while one of them is)
function Controller:_ShowHud(dialogue,skip)
 local ui=self._ui
 if ui.Dialogue.Visible~=dialogue then ui.Dialogue.Visible=dialogue end
 if ui.Skip.Visible~=skip then ui.Skip.Visible=skip end
 local on=dialogue or skip
 if ui.Hud.Enabled~=on then ui.Hud.Enabled=on end
end
function Controller:Init(deps)
 self._scope=Scope.new();self._state=deps.StateController
 local ui=self:_BuildUi();self._ui=ui
 self._screen=ui.EyesGui;self._closed=ui.Closed;self._lids=ui.Lids
 self._box=ui.Dialogue;self._caption=ui.Caption;self._hint=ui.Hint
 self._skip=ui.Skip;self._skipKey=ui.SkipAction;self._skipCount=ui.SkipTally
 self._scope:Add(ui.Skip.Activated:Connect(function()self:_Skip()end))
 self._scope:Add(ui.Skip.MouseEnter:Connect(function()self._skipHover=true end))
 self._scope:Add(ui.Skip.MouseLeave:Connect(function()self._skipHover=false end))
 self._scope:Add(ui.Dialogue.Activated:Connect(function()self:_Advance()end))
end
-- Fades a whole GUI tree to alpha (1 = as designed, 0 = gone), remembering each element's own
-- transparencies so it can come back exactly.
function Controller:_FadeGui(root,alpha)
 self._fadeBase=self._fadeBase or setmetatable({},{__mode='k'})
 local function apply(o)
  local base=self._fadeBase[o]
  if not base then
   base={}
   if o:IsA('GuiObject') then base.bg=o.BackgroundTransparency end
   if o:IsA('TextLabel') or o:IsA('TextButton') then base.text=o.TextTransparency end
   if o:IsA('UIStroke') then base.stroke=o.Transparency end
   self._fadeBase[o]=base
  end
  local function f(b)return 1-(1-b)*alpha end
  if base.bg then o.BackgroundTransparency=f(base.bg) end
  if base.text then o.TextTransparency=f(base.text) end
  if base.stroke then o.Transparency=f(base.stroke) end
 end
 apply(root);for _,d in root:GetDescendants()do apply(d)end
end
function Controller:_Advance()
 if not self._sequenceId or self._skipped or self._uiLocked then return end
 if os.clock()-(self._lastAdvance or 0)<.15 then return end -- one press = one line, whichever input fired
 self._lastAdvance=os.clock()
 local current=math.max(self._cueIndex or 0,self._advanced or 0)
 self._advanced=math.min(#Intro.Captions-1,current+1)
 self._box:SetAttribute('AdvancedLine',self._advanced)
end
function Controller:_Doors(cabin)
 if not cabin then return end
 local state=cabin:GetAttribute('DoorState');local from=cabin:GetAttribute('DoorFromAlpha')or 0
 local started=cabin:GetAttribute('DoorStartedAt')
 local a
 if started and (state=='Opening'or state=='Closing')then
  -- The leaves run on a local clock that advances with real frame time and is only steered
  -- softly toward the shared server clock, so small server-time corrections never show up as
  -- jerks in the slide.
  local seconds=cabin:GetAttribute('DoorSeconds')or 2
  local serverDelta=math.max(0,workspace:GetServerTimeNow()-started)
  local key=state..tostring(started);local now=os.clock()
  if self._doorKey~=key then
   self._doorKey=key;self._doorLocal=serverDelta;self._doorClock=now
  else
   local dt=math.clamp(now-(self._doorClock or now),0,.1);self._doorClock=now
   local predicted=self._doorLocal+dt
   predicted+=(serverDelta-predicted)*(1-math.exp(-dt*1.5))
   self._doorLocal=math.max(self._doorLocal,predicted)
  end
  local delta=self._doorLocal/seconds
  a=math.clamp(from+(state=='Opening'and delta or -delta),0,1)
 else
  -- steady states: late joiners and every client agree with the server collision
  self._doorKey=nil
  a=state=='Open' and 1 or 0
 end
 -- smootherstep: the heavy leaves start and stop with no jolt (zero speed and acceleration)
 a=a*a*a*(a*(a*6-15)+10)
 if self._doorAlpha==a then return end
 self._doorAlpha=a
 for _,side in {-1,1}do
  local name=side<0 and 'LeftDoor'or 'RightDoor'
  local door=Refs.Find(cabin,name);local base=door and door:GetAttribute('ClosedFrame')
  local travel=door and door:GetAttribute('TravelDistance')or 7.8
  if base then door.CFrame=base*CFrame.new(side*travel*a,0,0)end
  -- painted leaves are presentation only and follow the same curve
  local visual=self._doorVisuals and self._doorVisuals[name]
  if not visual or not visual.Parent or not visual:IsDescendantOf(cabin)then
   visual=nil;for _,m in cabin:GetDescendants()do if m:IsA('Model')and m:GetAttribute('DoorVisual')==name then visual=m;break end end
   self._doorVisuals=self._doorVisuals or {};self._doorVisuals[name]=visual
  end
  local core=visual and visual.PrimaryPart;local closed=core and core:GetAttribute('ClosedFrame')
  if closed then visual:PivotTo(closed*CFrame.new(side*travel*a,0,0))end
 end

end
-- Crash audio (client-local, 2D): heavy heartbeat the instant the screen cuts to black, ear ringing
-- once the eyes groggily reopen. Nothing else - no buzz or crackle (its pulsing read as a ticking
-- clock). Both hold while you lie there and then fade out smoothly, as a straight line in dB, all the
-- way through getting up and the first seconds standing (CRASH_FADE), so there is no point where they
-- stop - and when the overlays finish at the doors they are released with a short fade, never cut.
-- heart: a single slow lub-dub (strong 'lub', softer 'dub' ~0.35 s later, then a long rest), looped,
-- slowed a touch so it lands as a heavy ~54 bpm resting cadence
-- pant: fast, shallow panic breathing (hyperventilating) from the moment the cabin starts to
-- strain, through the fall and the black; breath: heavy, ragged recovery breathing while you lie
-- on the floor. The panting slows and gives way to the heavy breaths as you come round, and both
-- ride the same long fade as the heartbeat and the ringing.
local CRASH={heart={'rbxassetid://176554627',1.3,.9},ring={'rbxassetid://105803704355846',.15,1},
 pant={'rbxassetid://94952921557556',.6,.95},breath={'rbxassetid://8258601662',.78,.84},
 -- the aftermath bed (dystopian): a deep, hollow drone of the dead shaft and the sick hum of failing
 -- electrics, rising out of the crash and hanging under everything until the doors open
 drone={'rbxassetid://9112795463',.75,.8},hum={'rbxassetid://5638169483',.07,.55}}
-- silent by here: the end of the doors' opening (the last of the breathing dies away as they open)
local CRASH_FADE_END=Intro.DoorsAt+Intro.DoorSeconds
local function db(x)return 10^(x/20)end
local function smoothIn(x)return x*x*(3-2*x)end
function Controller:_CrashSound(key)
 local s=self._crashSounds[key]
 if not s then local d=CRASH[key];s=Instance.new('Sound');s.Name='Crash_'..key;s.SoundId=d[1];s.Volume=0;s.PlaybackSpeed=d[3];s.Looped=true;s.Parent=game:GetService('SoundService');self._scope:Add(s);self._crashSounds[key]=s end
 return s
end
function Controller:_StopCrash()
 -- Released with a long, natural fade - never a cut: the breathing, the heartbeat and the ringing
 -- die away together (an exponential, i.e. even-in-decibels, decay) and reach silence exactly as
 -- the lift doors finish opening.
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 local seconds=2.5
 if cabin then
  local started=cabin:GetAttribute('DoorStartedAt');local length=cabin:GetAttribute('DoorSeconds')
  if type(started)=='number' and type(length)=='number' then seconds=started+length-workspace:GetServerTimeNow() end
 end
 -- (the aftermath lingers: it keeps dying away for a few seconds after the doors are open)
 seconds=math.clamp(seconds+3.5,4,13)
 for _,s in self._crashSounds or {}do
  if s.IsPlaying and s.Volume>.002 then
   -- a long, gradual fade (eases off quickest at the start and trails away slowly at the end):
   -- no step, no sudden dip, still audible well after the doors start moving
   local tw=game:GetService('TweenService'):Create(s,TweenInfo.new(seconds,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Volume=0})
   tw.Completed:Connect(function()if s.Volume<=.002 then s:Stop()end end);tw:Play()
  elseif s.IsPlaying then s.Volume=0;s:Stop() end
 end
end
function Controller:_CrashAudio(t)
 self._crashSounds=self._crashSounds or {}
 local function set(key,volume)
  local s=self:_CrashSound(key)
  if volume>.002 then if not s.IsPlaying then s:Play()end;s.Volume=volume elseif s.IsPlaying then s:Stop();s.Volume=0 end
 end
 local since=t-Intro.ImpactAt
 local panicFrom=Intro.StrainAt+1
 if t<panicFrom then set('heart',0);set('ring',0);set('pant',0);set('breath',0);set('drone',0);set('hum',0);return end
 -- full strength while you lie on the floor; as you get up they settle to a lower level and HOLD
 -- there - heartbeat, ringing and breathing alike - until the lift doors start to open. Then all of
 -- them fade out together over the doors' opening and are silent exactly as the doors finish
 -- (_StopCrash). Nothing drops out early or cuts.
 -- (only a slight settle as you get up - nothing suddenly drops away; the real fade is the long
 -- release once the doors open)
 local u=math.clamp((t-Intro.GetUpAt)/6,0,1)
 local fade=1-.18*smoothIn(u)
 -- breathing: panic builds gradually as the cabin strains, peaks through the drop and the black,
 -- then the panting slows (a little slower still as you calm) and hands over to heavy, ragged
 -- breaths while you lie there. Its strength rises and falls in slow waves, and it has its own,
 -- gentler fade: it eases away over the same span instead of dropping off at the start.
 local panic=smoothIn(math.clamp((t-panicFrom)/3,0,1))
 local calm=smoothIn(math.clamp((t-(Intro.RevealAt+1.5))/6,0,1))
 local swell=.8+.2*math.sin((t-panicFrom)*2*math.pi/5.5)
 local breathFade=fade
 local pant=self:_CrashSound('pant');pant.PlaybackSpeed=CRASH.pant[3]-.17*calm
 set('pant',CRASH.pant[2]*panic*(1-.75*calm)*swell*breathFade)
 set('breath',CRASH.breath[2]*smoothIn(math.clamp((since-1.2)/3.5,0,1))*(.6+.4*calm)*swell*breathFade)
 if since<0 then set('heart',0);set('ring',0);set('drone',0);set('hum',0);return end
 set('heart',CRASH.heart[2]*fade)
 -- the drone swells up out of the impact over a few seconds; the hum stutters like dying power
 set('drone',CRASH.drone[2]*smoothIn(math.clamp((since-.3)/3,0,1))*fade)
 local stutter=.65+.35*math.sin(since*7.3)*math.sin(since*2.1+.7)
 set('hum',CRASH.hum[2]*smoothIn(math.clamp((since-1)/2,0,1))*stutter*fade)
 if t>=Intro.RevealAt then
  local wake=t-Intro.RevealAt
  set('ring',CRASH.ring[2]*(.9+1.5*math.clamp(wake/.6,0,1))*fade)
 else
  -- the ringing starts in the black, right after the boom, and swells as the eyes open
  set('ring',CRASH.ring[2]*.9*math.clamp((since-.25)/.8,0,1)*fade)
 end
end
-- The heavy mechanical sounds right before the crash: the cable mechanism groans under the load,
-- the safety brake cranks in with a deep metal clunk, and the crash itself lands as a huge, deep
-- boom - the instant the lids slam shut (2D, client-local, never replayed after a skip).
local SFX={
 {key='groan',at=Intro.GroanAt,id='rbxassetid://9125690771',volume=.9,speed=.62},
 {key='crank',at=Intro.CrankAt,id='rbxassetid://9119630180',volume=1.2,speed=.55},
 {key='crankRattle',at=Intro.CrankAt+.05,id='rbxassetid://9125678301',volume=.6,speed=.7},
 -- the crash itself: a huge, weighty THUD with the low end pushed hard (three layers: the boom, the
 -- cabin's metal body, and the same boom pitched way down as a sub layer you feel more than hear)
 {key='boom',at=0,id='rbxassetid://9125484367',volume=2.6,speed=.78},
 {key='boomSub',at=0,id='rbxassetid://9125484367',volume=2.4,speed=.42},
 {key='boomBody',at=.02,id='rbxassetid://9119630548',volume=1.9,speed=.48},
 -- CRASH ... CRASH: the cabin first smashes into the brake rails (the big knock just before), then
 -- slams down for real - torn steel on both - and drops once more onto the buffers in the black,
 -- with loose metal rattling down the shaft after it
 {key='crash1',at=-.48,id='rbxassetid://9120188618',volume=1.7,speed=.72},
 {key='crash1Body',at=-.47,id='rbxassetid://9119630548',volume=1.3,speed=.56},
 {key='crash2',at=0,id='rbxassetid://9120188288',volume=2,speed=.62},
 {key='crash2Steel',at=.01,id='rbxassetid://9120187684',volume=1.5,speed=.5},
 {key='settle',at=.62,id='rbxassetid://9120187684',volume=1.3,speed=.42},
 {key='settleSub',at=.63,id='rbxassetid://9125484367',volume=1.4,speed=.4},
 {key='debris',at=.75,id='rbxassetid://9118064886',volume=.6,speed=.68},
 {key='creak',at=1.6,id='rbxassetid://9116795409',volume=.3,speed=.55},
 -- electrical failure: only a couple of faint, short buzzes now (no running crackle)
 {key='zap',at=-1.25,id='rbxassetid://9116278051',volume=.1,speed=1.08},
 {key='shock',at=Intro.BlackoutAt-Intro.ImpactAt-.06,id='rbxassetid://9116279560',volume=.22,speed=1},
 {key='zap2',at=2.6,id='rbxassetid://9116278051',volume=.06,speed=.9},
 -- coming round: a sharp gasp as you push yourself up off the cabin floor
 {key='gasp',at=Intro.GetUpAt-Intro.ImpactAt+.25,id='rbxassetid://9114555843',volume=.85,speed=.92},
}
function Controller:_CrashSfx(t)
 local fired=self._sfxFired or {};self._sfxFired=fired
 for _,s in SFX do
  local at=Intro.ImpactAt+s.at
  if not fired[s.key] and t>=at then
   fired[s.key]=true
   if t-at<.35 then
    local snd=Instance.new('Sound');snd.Name='Crash_'..s.key;snd.SoundId=s.id;snd.Volume=s.volume;snd.PlaybackSpeed=s.speed
    if s.key=='groan' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.HighGain=-14;eq.LowGain=4 end
    if s.key=='boom' or s.key=='boomBody' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.LowGain=10;eq.MidGain=1;eq.HighGain=-8 end
    if s.key=='crash1' or s.key=='crash2' or s.key=='crash2Steel' or s.key=='crash1Body' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.LowGain=8;eq.MidGain=2;eq.HighGain=-3 end
    if s.key=='settle' or s.key=='settleSub' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.LowGain=9;eq.MidGain=-4;eq.HighGain=-16 end
    if s.key=='debris' or s.key=='creak' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.LowGain=2;eq.MidGain=-2;eq.HighGain=-9;local rv=Instance.new('ReverbSoundEffect',snd);rv.DecayTime=2.2;rv.WetLevel=-6 end
    if s.key=='boomSub' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.LowGain=10;eq.MidGain=-8;eq.HighGain=-30 end
    if s.key=='zap' or s.key=='zap2' or s.key=='shock' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.HighGain=-10;eq.MidGain=-3;eq.LowGain=0 end
    if s.key=='gasp' then local eq=Instance.new('EqualizerSoundEffect',snd);eq.HighGain=-4;eq.LowGain=2 end
    snd.Parent=game:GetService('SoundService');snd:Play();game:GetService('Debris'):AddItem(snd,12)
   end
  end
 end
end
-- Seamless descent motor: the replicated DescentMotor loop is silenced locally and played as two
-- local voices that cross-fade (equal power) well before the end of the recording, so the loop
-- point can never be heard - no pop, stutter or repeating seam. They follow the server motor's
-- play state and pitch, and fade out briefly instead of cutting when it stops.
local XFADE=2.2
function Controller:_MotorLoop(dt)
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 local motor=cabin and cabin:FindFirstChild('DescentMotor',true)
 local m=self._motor
 if not motor then if m then for _,v in m.voices do v.s:Destroy()end;self._motor=nil end;return end
 if not m or m.src~=motor then
  if m then for _,v in m.voices do v.s:Destroy()end end
  local base=motor:GetAttribute('LoopVolume') or motor.Volume
  m={src=motor,base=base,voices={},gain=0,cur=nil}
  for i=1,2 do
   local s=Instance.new('Sound');s.Name='DescentMotorVoice'..i;s.SoundId=motor.SoundId;s.Looped=false;s.Volume=0
   s.RollOffMode=motor.RollOffMode;s.RollOffMinDistance=motor.RollOffMinDistance;s.RollOffMaxDistance=motor.RollOffMaxDistance
   for _,fx in motor:GetChildren()do if fx:IsA('SoundEffect')then fx:Clone().Parent=s end end
   s.Parent=motor.Parent;self._scope:Add(s)
   table.insert(m.voices,{s=s,w=0})
  end
  self._motor=m
 end
 motor:SetAttribute('LoopVolume',m.base);if motor.Volume~=0 then motor.Volume=0 end
 local playing=motor.IsPlaying
 local len=m.voices[1].s.TimeLength
 if len<=XFADE*2+.5 then return end
 local speed=motor.PlaybackSpeed
 for _,v in m.voices do v.s.PlaybackSpeed=speed end
 -- overall gain: quick fade in on start, short fade out on stop (no click either way)
 m.gain=playing and math.min(1,m.gain+dt/.35) or math.max(0,m.gain-dt/.3)
 if m.gain<=0 then for _,v in m.voices do if v.s.IsPlaying then v.s:Stop()end;v.w=0 end;m.cur=nil;m.xfade=nil;return end
 if not m.cur then m.cur=1;local v=m.voices[1];v.s.TimePosition=0;v.s:Play();v.w=1 end
 local cur=m.voices[m.cur];local nxt=m.voices[3-m.cur]
 -- start the other voice a cross-fade length before this one runs out
 if not m.xfade and cur.s.IsPlaying and cur.s.TimePosition>=len-XFADE then nxt.s.TimePosition=.15;nxt.s:Play();nxt.w=0;m.xfade=0 end
 if m.xfade then
  m.xfade+=dt*speed/(XFADE-.3)
  local u=math.clamp(m.xfade,0,1)
  cur.w=math.cos(u*math.pi/2);nxt.w=math.sin(u*math.pi/2)
  if u>=1 then cur.s:Stop();cur.w=0;m.cur=3-m.cur;m.xfade=nil end
 end
 if not m.voices[m.cur].s.IsPlaying and not m.xfade then local v=m.voices[m.cur];v.s.TimePosition=0;v.s:Play();v.w=1 end
 for _,v in m.voices do v.s.Volume=m.base*m.gain*v.w end
end
function Controller:_Lids(cover)
 local size=self._screen.AbsoluteSize;local W,H=math.max(size.X,1),math.max(size.Y,1)
 local open=math.clamp(1-cover,0,1)
 self._closed.Visible=open<.004
 if open<.004 then for _,lid in self._lids do lid.frame.Visible=false end;return end
 -- the upper lid lifts further than the lower one, and the corners widen as the eye opens
 local o=open^.75
 -- as the eye comes fully open the lids sweep right off every edge and corner (whatever the screen:
 -- phone landscape or portrait, tablet, ultrawide), so a fully open eye fills the whole screen and
 -- never leaves dark corners or a lid edge showing
 local clear=1+1.2*o^3
 local w=W*(.34+.92*o)*clear;local h=H*.74*o*clear;local cy=H*.5-H*.035*o
 -- the black beyond each lid edge is a stroke sized from this screen, so it always reaches past
 -- every corner (4K desktops, tablets, phones in either orientation)
 local reach=math.ceil((W+H)*1.5)
 for _,lid in self._lids do
  if lid.stroke.Thickness~=reach then lid.stroke.Thickness=reach end
  local rise=(lid.upper and 1.1 or .8)*h
  local R=math.min((w*w+rise*rise)/(2*rise),80000) -- circle through both eye corners and the lid apex
  local r=math.max(R-lid.feather*H*(.35+.65*o),1)
  local centre=lid.upper and (cy-rise+R) or (cy+rise-R)
  lid.frame.Position=UDim2.fromOffset(W/2,centre);lid.frame.Size=UDim2.fromOffset(2*r,2*r)
  lid.stroke.Transparency=lid.alpha+(1-lid.alpha)*(lid.feather>0 and o^3 or 0)
  lid.frame.Visible=true
 end
end
-- Build-up before the crash: escalating thuds through the cabin floor, the last one the violent drop.
function Controller:_Thuds(cabin,t)
 local fired=self._thudsFired or {};self._thudsFired=fired
 for i,th in Intro.Thuds do
  local at=Intro.ImpactAt-th[1]
  if not fired[i] and t>=at then
   fired[i]=true
   if t-at<.3 then -- never replay thuds that a skip jumped over
    local src=cabin and cabin:FindFirstChild('CabinImpact',true)
    local s=Instance.new('Sound');s.Name='DescentThud';s.SoundId=src and src.SoundId or 'rbxassetid://131524195375919'
    s.Volume=math.min(.25+.5*th[2],1.3);s.PlaybackSpeed=.6+.1*math.min(th[2],1)+(math.random()-.5)*.06
    s.Parent=game:GetService('SoundService');s:Play();game:GetService('Debris'):AddItem(s,5)
   end
  end
 end
end
-- strongest live thud envelope, its phase, and the summed vertical drop
local function thudShake(t)
 local e,phase,drop=0,0,0
 for _,th in Intro.Thuds do
  local s=t-(Intro.ImpactAt-th[1])
  if s>=0 and s<.75 then
   local k=(1-s/.75)^2*th[2];if k>e then e=k;phase=s end
   if s<.22 then drop+=math.sin(s/.22*math.pi)*.1*th[2] end
  end
 end
 return e,phase,drop
end
-- Roblox has no native motion blur, so a BlurEffect is driven by how violently the camera moves.
function Controller:_Blur(size,dt)
 local b=self._blur
 local current=self._blurSize or 0
 current=size>current and size or math.max(size,current-(dt or .016)*45)
 self._blurSize=current
 if current<=.05 then if b then b.Enabled=false end;return end
 if not b or not b.Parent then b=Instance.new('BlurEffect');b.Name='DescentMotionBlur';b.Parent=game:GetService('Lighting');self._scope:Add(b);self._blur=b end
 b.Enabled=true;b.Size=math.min(current,56)
end
-- The impact 'drop' (no colour flash): the picture is crushed dark, cold and colourless as the lids
-- slam shut, held through the blackout, and eased back to normal while the eyes groggily reopen.
-- Before it, the strain and the fall slowly drain the colour. Its own ColorCorrectionEffect, so the
-- level's grade is never touched.
local function gradeAt(t)
 local function ease(a)a=math.clamp(a,0,1);return a*a*(3-2*a)end
 if t<Intro.StrainAt then return 0,0,0,0 end
 if t<Intro.ImpactAt then local b=Intro.Shake(t);return -.06*b,.15*b,-.35*b,.3*b end
 -- crushed dark and colourless by the crash, eased to a dazed, washed-out grade as the eyes open,
 -- then back to normal as you come round
 local slam=ease((t-Intro.ImpactAt)/Intro.SlamSeconds)
 local release=t<Intro.RevealAt and 0 or ease((t-Intro.RevealAt)/(Intro.RevealEnd-Intro.RevealAt))
 local dz=Intro.Dazed(t)
 local hb,hc,hs,ht=-.1-.5*slam,.25+.3*slam,-.45-.5*slam,.4+.6*slam
 local db_,dc,ds,dt_=-.08*dz,.12*dz,-.4*dz,.35*dz
 return db_+(hb-db_)*(1-release),dc+(hc-dc)*(1-release),ds+(hs-ds)*(1-release),dt_+(ht-dt_)*(1-release)
end
function Controller:_Grade(t,reduced)
 local b,c,s,tint=gradeAt(t)
 local g=self._grade
 if math.abs(b)+math.abs(c)+math.abs(s)<.002 then if g then g.Enabled=false end;return end
 if not g or not g.Parent then g=Instance.new('ColorCorrectionEffect');g.Name='DescentImpactGrade';g.Parent=game:GetService('Lighting');self._scope:Add(g);self._grade=g end
 g.Enabled=true;g.Brightness=b;g.Contrast=reduced and c*.5 or c;g.Saturation=s;g.TintColor=Color3.new(1,1,1):Lerp(Color3.fromRGB(196,212,236),math.clamp(tint,0,1))
end
function Controller:_Fov(offset)
 local camera=workspace.CurrentCamera;if not camera then return end
 local applied=self._fovApplied or 0
 if math.abs(offset-applied)<1e-3 then return end
 camera.FieldOfView=math.clamp(camera.FieldOfView-applied+offset,1,120);self._fovApplied=offset
end
function Controller:_Finish()
 self:_StopCrash()
 self:_Fov(0);if self._grade then self._grade.Enabled=false end
 self._blurSize=0;if self._blur then self._blur.Enabled=false end
 self:_ShowHud(false,false)
 self._screen.Enabled=false;self._sequenceId=nil
 -- tear the intro's sounds and objects down on the next frame, so the frame the doors start
 -- moving never carries that cost
 if self._sequenceScope then local scope=self._sequenceScope;self._sequenceScope=nil;task.defer(function()scope:Destroy()end)end
end
function Controller:_Skip()
 if not self._sequenceId or self._skipped or self._voted or self._uiLocked or self._player:GetAttribute('EHContext')~='Intro' then return end
 -- A vote (the server decides: everyone voted = skip now; half or more = skip after a short
 -- countdown). One press is all it takes: from then on the button just shows the vote (it never
 -- asks again).
 -- (shown as voted straight away; if the request didn't go through it is quietly sent again)
 self._voted=true;self._votedAt=os.clock()
 self._voteSent=self._state:SendAction('SkipIntro',{characterEpoch=self._player:GetAttribute('EHCharacterEpoch'),runId=self._sequenceId})==true
end
function Controller:_Begin(id,cabin)
 self:_Finish();self._seen[id]=true;self._sequenceId=id;self._screen.Enabled=true;self._advanced=0;self._cueIndex=0;self._sequenceScope=Scope.new();self._elapsed=cabin:GetAttribute('IntroElapsed') or 0;self._sample=self._elapsed;self._sinceSample=0;self._skipped=cabin:GetAttribute('IntroSkipAt')~=nil;self._voted=false;self._voteSent=false;self._skipGoneAt=nil;self._speech=nil;self._skipSince=nil
 self._shaft=nil;self._thudsFired={};self._sfxFired={};self._shownText=nil;self._fadeKept=nil;self._uiLocked=false;self._box.Active=true;self._skip.Active=true
 -- (no PA voice or dialogue in the ride any more; Intro.NpcCues is the hook for a guide NPC later)
end
-- Shaft machinery seen through the inspection opening, driven only by the shared timeline.
function Controller:_Shaft(cabin,t)
 local s=self._shaft
 if not s or not s.cabin or s.cabin~=cabin then
  s={cabin=cabin,counterweight=Refs.Find(cabin,'Counterweight'),scroll=Refs.Find(cabin,'ShaftScroll'),needle=Refs.Find(cabin,'FloorDialNeedle')}
  s.cwBase=s.counterweight and s.counterweight:GetAttribute('BaseFrame');s.scrollBase=s.scroll and s.scroll:GetAttribute('BaseFrame')
  self._shaft=s
 end
 local travel=Intro.Travel(t)*Intro.ShaftSpeed
 local pass=Intro.Travel(Intro.CounterweightPassAt)*Intro.ShaftSpeed
 if s.counterweight and s.cwBase then
  -- the counterweight moves opposite the cabin, so relative to it at twice the speed
  s.counterweight:PivotTo(s.cwBase+Vector3.new(0,18.3+2*(travel-pass),0))
 end
 if s.scroll and s.scrollBase then
  local period=s.scroll:GetAttribute('Period')or 8
  s.scroll:PivotTo(s.scrollBase+Vector3.new(0,travel%period,0))
 end
 if s.needle then
  local pivot=s.needle:GetAttribute('PivotFrame');local from=s.needle:GetAttribute('SweepFrom')or 60;local to=s.needle:GetAttribute('SweepTo')or 36
  local total=Intro.Travel(Intro.Duration)
  if pivot then s.needle.CFrame=pivot*CFrame.Angles(0,0,math.rad(from+(to-from)*math.clamp(Intro.Travel(t)/total,0,1)))*CFrame.new(0,s.needle.Size.Y/2,0)end
 end
end
-- Floor-to-floor descent (five seconds): the shaft scrolls past the inspection opening, the
-- counterweight passes mid-travel and the floor hums; no screen fade, the doors simply open.
function Controller:_Travel(cabin,dt)
 local started=cabin and cabin:GetAttribute('TravelStartedAt')
 if not started then if self._wasTravelling then self._wasTravelling=false end;return end
 local dur=cabin:GetAttribute('TravelSeconds')or 5
 local e=math.clamp(workspace:GetServerTimeNow()-started,0,dur)
 self._wasTravelling=true
 -- ease in/out speed profile, integrated: distance in speed-seconds
 local u=e/dur;local travel=dur*(u*u*(3-2*u))*.75
 local s=self._shaft
 if not s or s.cabin~=cabin then self:_Shaft(cabin,0);s=self._shaft end
 if s then
  if s.scroll and s.scrollBase then local period=s.scroll:GetAttribute('Period')or 8;s.scroll:PivotTo(s.scrollBase+Vector3.new(0,(travel*Intro.ShaftSpeed*2)%period,0))end
  if s.counterweight and s.cwBase then s.counterweight:PivotTo(s.cwBase+Vector3.new(0,18.3+2*Intro.ShaftSpeed*2*(travel-dur*.375),0))end
 end
 local camera=workspace.CurrentCamera
 local reduced=self._player:GetAttribute('EHReduceMotion')==true
 -- brakes release: a heavy clunk and a short drop of the cabin just after the doors shut (the
 -- server swaps the floors out at this exact moment, so any hitch reads as the lift lurching)
 if self._lurchFor~=started then
  self._lurchFor=started
  task.delay(math.max(0,.28-e),function()
   local s=Instance.new('Sound');s.SoundId='rbxassetid://9114533169';s.Volume=.42;s.PlaybackSpeed=.78;s.Parent=game:GetService('SoundService');s:Play()
   game:GetService('Debris'):AddItem(s,4)
  end)
 end
 if camera and not reduced and e>.28 and e<.75 then
  local w=(e-.28)/.47;camera.CFrame*=CFrame.new(0,-math.sin(w*math.pi)*(1-w)*.22,0)
 end
 if camera and not reduced and e<dur then
  local k=math.sin(u*math.pi)*.006;local t=os.clock()
  camera.CFrame*=CFrame.new(math.sin(t*37)*k,math.sin(t*41+1.1)*k,0)
 end
end
function Controller:_Render(dt)
 local id=self._player:GetAttribute('EHRunId');local context=self._player:GetAttribute('EHContext')
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local cabin=env and env:FindFirstChild('Elevator')
 self:_Doors(cabin)
 pcall(function()self:_Travel(cabin,dt)end)
 if cabin and cabin:GetAttribute('Boarding') then self._screen.Enabled=false;self:_ShowHud(false,false);return end
 if id and context=='Intro' and cabin and cabin:GetAttribute('IntroRunId')==id and not self._seen[id] then self:_Begin(id,cabin)end
 if not self._sequenceId then return end
 if id~=self._sequenceId or context=='Dead' or context=='Results' or not cabin then self:_Finish();return end
 -- Hard guarantee: the moment the doors begin to open, every eye overlay, caption, skip panel,
 -- blur and grade is already gone.
 local doorState=cabin:GetAttribute('DoorState')
 if (doorState=='Opening' or doorState=='Open') and (self._elapsed or 0)>Intro.ImpactAt then self:_Finish();return end
 local sample=cabin:GetAttribute('IntroElapsed') or 0
 if sample~=self._sample then self._sample=sample;self._sinceSample=0 end
 self._sinceSample+=dt
 local paused=cabin:GetAttribute('IntroPaused')
 local predicted=sample+(paused and 0 or math.min(self._sinceSample,.2))
 -- Network samples correct clock speed without ever rewinding; a shared skip jumps forward once.
 if predicted-self._elapsed>1 then self._elapsed=predicted
 elseif not paused or context~='Intro' then self._elapsed=math.max(self._elapsed,self._elapsed+dt*math.clamp(1+(predicted-self._elapsed)*2,.8,1.2))end
 if cabin:GetAttribute('IntroSkipAt') and not self._skipped then self._skipped=true end
 local t=self._elapsed
 pcall(function()self:_Shaft(cabin,t)end)
 local cover=Intro.Cover(t)
 pcall(function()self:_CrashAudio(t)end)
 -- Captions: pre-fault exposition stops on skip; the post-fault instruction always shows.
 local cue=0;for i,v in Intro.Captions do if t>=v.start and (not self._skipped or v.afterFault)then cue=i end end
 self._cueIndex=cue
 local index=math.max(cue,self._skipped and 0 or (self._advanced or 0))
 local caption=Intro.Captions[index]
 -- Pre-jolt: the dialogue box and skip panel fade out over the UiFadeSeconds before the shake and
 -- stop taking input the moment the fade starts; they are completely gone when the shake begins.
 -- A successful skip lands right at the start of this fade, so it flows straight into the jolt.
 local fadeStart=Intro.StrainAt-Intro.UiFadeSeconds
 local preJolt=t<Intro.StrainAt
 local uiAlpha=t<fadeStart and 1 or math.clamp(1-(t-fadeStart)/Intro.UiFadeSeconds,0,1)
 local locked=preJolt and t>=fadeStart
 if locked~=self._uiLocked then self._uiLocked=locked;self._box.Active=not locked;self._skip.Active=not locked end
 local showing=caption~=nil and (t<caption.finish or index>cue) and cover<.6
 if showing and not (caption and caption.afterFault) then self._shownText=caption.text end
 if not (caption and caption.afterFault) then
  -- the line on screen when the fade starts (or when everyone skipped) fades out with the panel
  if showing and locked then self._fadeKept=true end
  local fading=locked and self._shownText~=nil and (self._skipped or self._fadeKept)
  if fading and not showing then showing=true;caption={text=self._shownText} end
  if showing then self:_FadeGui(self._box,uiAlpha) end
  if uiAlpha<=0 then showing=false end
 elseif showing then self:_FadeGui(self._box,1) end
 if not preJolt then self._fadeKept=nil end
 if showing then self._caption.Text=caption.text end
 -- live vote panel: fades out with the dialogue before the jolt (also right after a skip)
 -- The skip button: comes in two seconds after the ride starts, fading in softly. Asked once: after
 -- you vote it only shows the tally, and once the skip happens it fades away for good (it is never
 -- shown again, never asks again).
 if self._skipped and not self._skipGoneAt then self._skipGoneAt=os.clock() end
 local gone=self._skipGoneAt and math.clamp(1-(os.clock()-self._skipGoneAt)/.4,0,1) or 1
 local voteShown=context=='Intro' and preJolt and uiAlpha>0 and gone>0
 local skipAlpha=uiAlpha*gone
 if voteShown then
  self._skipSince=self._skipSince or os.clock()
  local k=math.clamp((os.clock()-self._skipSince-2)/.45,0,1)
  skipAlpha*=k*k*(3-2*k)
  if skipAlpha<=0 then voteShown=false end
 end
 -- (a vote that didn't reach the server is re-sent, at most once a second)
 if self._voted and not self._voteSent and not self._skipped and os.clock()-(self._votedAt or 0)>1 then
  self._votedAt=os.clock()
  self._voteSent=self._state:SendAction('SkipIntro',{characterEpoch=self._player:GetAttribute('EHCharacterEpoch'),runId=self._sequenceId})==true
 end
 self._skip.Active=voteShown and not locked
 self:_ShowHud(showing,voteShown)
 if voteShown then self:_FadeGui(self._skip,skipAlpha) end
 if voteShown then
  local votes,crew=cabin:GetAttribute('SkipVotes')or 0,math.max(1,cabin:GetAttribute('SkipCrew')or 1)
  -- once you have voted it stays that way (the server's record agrees; it is never asked twice)
  if self._player:GetAttribute('EHSkippedIntro')==self._sequenceId then self._voted=true end
  local deadline=cabin:GetAttribute('SkipDeadline')
  local label
  if type(deadline)=='number' then
   label='SKIPPING IN '..math.max(1,math.ceil(deadline-workspace:GetServerTimeNow()))
  elseif self._voted then label='VOTED'
  else label=self._skipPrompt or 'SKIP' end
  self._skipKey.Text=label
  if skipAlpha>=1 then self._skipKey.TextTransparency=(self._voted and type(deadline)~='number') and .35 or 0 end
  -- under the cursor / finger the text warms up and steps a pixel left (eased, never a jump)
  local hk=(self._skipHover and not self._voted) and 1 or 0
  self._skipHoverK=(self._skipHoverK or 0)+(hk-(self._skipHoverK or 0))*math.min(1,dt*14)
  self._skipKey.TextColor3=Color3.fromRGB(232,150,62):Lerp(Color3.fromRGB(255,200,120),self._skipHoverK)
  self._skipKey.Position=UDim2.fromOffset(-math.floor(3*self._skipHoverK+.5),0)
  self._skipCount.Text=string.format('%d/%d VOTED',math.min(votes,crew),crew)
 end
 self:_Lids(cover)
 self._screen.Enabled=cover>0
 local camera=workspace.CurrentCamera;local reduced=self._player:GetAttribute('EHReduceMotion')==true
 local ok,pref=pcall(function()return game.GuiService.ReducedMotionEnabled end);reduced=reduced or (ok and pref)
 local since=t-Intro.ImpactAt
 pcall(function()self:_Thuds(cabin,t)end)
 pcall(function()self:_CrashSfx(t)end)
 local blur,fov=0,0
 local sin=math.sin
 if camera and not reduced then
  local speed=math.min(Intro.Speed(t),1)
  -- running hum through the floor; then five seconds of shake whose intensity climbs
  -- exponentially (barely there at first, violent at the very end)
  local sh=Intro.Shake(t)
  local hum=speed*.006;local strain=.006+.15*sh
  local quake=sh>0 and strain or 0
  local x=sin(t*37)*hum+sin(t*9.3+sh*4)*quake+sin(t*23.1+.4)*quake*.6+sin(t*51)*quake*.5*sh
  local y=sin(t*41+1.1)*hum+sin(t*13.7)*quake*.8+sin(t*44.3+.3)*quake*.6*sh
  -- the knocks, each a hard jolt and a short drop
  local te,tp,tdrop=thudShake(t)
  local tj=sin(tp*44)*.24*te
  local lift=0
  -- the impact: a crushing downward lurch, a hard bounce and a long, heavy shudder (time-based,
  -- so it can never replay)
  local envelope=since>=0 and since<1.8 and (1-since/1.8)^2 or 0
  local strain,rattle=quake,0
  local j=sin(since*34)*.5*envelope
  local slam=0
  if since>=0 and since<.2 then slam=sin(since/.2*math.pi/2)*1.1
  elseif since>=.2 and since<.9 then local r=1-(since-.2)/.7;slam=1.1*r*r+sin((since-.2)*18)*.12*r end
  local nod=since>=0 and since<.6 and .22*sin(since/.6*math.pi) or 0
  camera.CFrame*=CFrame.new(x+sin(since*29)*envelope*.18+sin(tp*31+.7)*te*.12,y+j+tj+lift-slam-tdrop,0)
   *CFrame.Angles(j*.1+tj*.16+sin(t*17.3)*strain*.7+sin(t*29)*rattle*.5-nod,sin(t*11.1)*strain*.4+sin(tp*27)*te*.04+sin(t*33)*rattle*.3,j*.14+x*.45+tj*.14+sin(t*19)*rattle*.6)
  -- motion blur follows how violently the view moves
  blur=(sh>0 and 1+30*sh or 0)+te*14+envelope*40
  -- the view stretches with the shake, then punches in on the impact
  fov=6*sh+(since>=0 and since<1.2 and (since<.1 and 6-10*since/.1 or -4*(1-(since-.1)/1.1)^2) or 0)
 end
 -- dazed on the floor: heavy blur that clears as you come round (also with reduced motion)
 if since>=0 then blur=math.max(blur,22*Intro.Dazed(t)^1.3) end
 self:_Blur(blur,dt)
 self:_Fov(fov)
 self:_Grade(t,reduced)
 if context~='Intro' and t>=Intro.Duration then self:_Finish()end
end
function Controller:Start()
 CAS:BindActionAtPriority('BlackwaterSkip',function(_,state)
  if not self._sequenceId or self._uiLocked or not self._ui.Skip.Visible then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then self:_Skip()end
  return Enum.ContextActionResult.Sink
 end,false,3000,Enum.KeyCode.Space,Enum.KeyCode.ButtonB)
 self._scope:Add(function()CAS:UnbindAction('BlackwaterSkip')end)
 -- The cursor is locked in first person on PC, so the dialogue box can't be clicked: a click
 -- anywhere, Enter or E advances instead (A on gamepad); touch still taps the box.
 CAS:BindActionAtPriority('BlackwaterAdvance',function(_,state,input)
  if not self._sequenceId or self._skipped or self._uiLocked or not self._ui.Dialogue.Visible then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then self:_Advance()end
  return Enum.ContextActionResult.Sink
 end,false,3000,Enum.UserInputType.MouseButton1,Enum.KeyCode.Return,Enum.KeyCode.E,Enum.KeyCode.ButtonA)
 self._scope:Add(function()CAS:UnbindAction('BlackwaterAdvance')end)
 local uis=game:GetService('UserInputService')
 local function prompts()
  local input=uis.PreferredInput
  -- (Nov 3: orange typewriter text, no box - the key in brackets like the speaker tags of the check-in talk)
  self._skipPrompt=input==Enum.PreferredInput.Touch and '[TAP] SKIP' or (input==Enum.PreferredInput.Gamepad and '[B] SKIP' or '[SPACE] SKIP')
  self._hint.Text=input==Enum.PreferredInput.Touch and 'TAP TO CONTINUE' or (input==Enum.PreferredInput.Gamepad and 'A  CONTINUE' or 'CLICK OR ENTER TO CONTINUE')
 end
 prompts();self._scope:Add(uis:GetPropertyChangedSignal('PreferredInput'):Connect(prompts))
 RunService:BindToRenderStep('BlackwaterArrival',Enum.RenderPriority.Camera.Value+3,function(dt)self:_Render(dt)end)
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)pcall(self._MotorLoop,self,dt)end))
 self._scope:Add(function()RunService:UnbindFromRenderStep('BlackwaterArrival')end)
end
function Controller:Destroy()self:_Finish();if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
