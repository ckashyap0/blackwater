--!nonstrict
-- LEVEL 4 (MAIN CONTROL ROOM) on this screen. Everything here is local presentation; the floor
-- (Level4Floor) owns the jobs and only publishes attributes:
--  * the living control room: blinking LEDs, animated screens (graphs, CCTV with timestamps and
--    the odd figure on CAM 03, TV static, alarms, the network mimic with the breaker order and
--    restart progress), the server room door sliding open, breaker levers, dial needles
--  * the radio calls: static + a garbled voice from the radios / PA, with a subtitle
--  * the Among Us style job list, the toast for mistakes, the restart progress bar
--  * the job windows (upload / wires / dials / radio), opened when the server sets EHL4Task
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level4)
local Controller={};Controller.__index=Controller
local SND={
 static='rbxassetid://9117060042',squelch='rbxassetid://9118023324',click='rbxassetid://9118026602',voices='rbxassetid://9120457641',
 beep='rbxassetid://9113880475',good='rbxassetid://9113867249',bad='rbxassetid://99071431420752',scroll='rbxassetid://9114647751',
 flip='rbxassetid://9120098454',trip='rbxassetid://87751901232664',door='rbxassetid://9119727134',
}
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local HudScale=require(game.ReplicatedStorage.Game.Shared.Utilities.HudScale)
-- Every on-screen piece of this floor is authored in StarterGui (ControlRoomHud: job list, restart
-- bar, toast, radio subtitle; ControlRoomTasks: the job window and its four job panels) in the
-- lobby's style. This file only fills them in, shows/hides them and moves them out of the way.
-- (FONT/MONO/make/label below are only for the in-world screens that draw live graphs.)
local FONT=Enum.Font.GothamMedium;local MONO=Enum.Font.Code
local CYAN=Color3.fromRGB(90,220,255);local GREEN=Color3.fromRGB(135,226,161);local AMBER=Color3.fromRGB(232,166,64);local RED=Color3.fromRGB(232,84,80)
local PANEL=Color3.fromRGB(8,9,10);local INK=Color3.fromHex('ebe8e1');local MUTED=Color3.fromHex('96928a');local GOLD=Color3.fromHex('d6ac3e')
local BREAKER_COLORS={Color3.fromRGB(196,72,60),Color3.fromRGB(214,172,62),Color3.fromRGB(96,170,110),Color3.fromRGB(80,130,200),Color3.fromRGB(214,210,200)}
local EASE=TweenInfo.new(.22,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
local EASE_IN=TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
function Controller.new(player,gui)return setmetatable({Name='ControlRoomController',Dependencies={'InputController'},_player=player,_gui=gui},Controller)end
local function ease(u)u=math.clamp(u,0,1);return u*u*(3-2*u) end
local function make(class,props,parent)local o=Instance.new(class);for k,v in props do o[k]=v end;o.Parent=parent;return o end
local function corner(o,r)make('UICorner',{CornerRadius=UDim.new(0,r or 8)},o);return o end
local function stroke(o,c,t)make('UIStroke',{Color=c or CYAN,Thickness=t or 1.5,Transparency=.2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},o);return o end
local function label(parent,text,props)
 local l=make('TextLabel',{BackgroundTransparency=1,Text=text,Font=FONT,TextColor3=INK,TextScaled=false,TextSize=18,TextWrapped=true,RichText=true,Size=UDim2.fromScale(1,1)},parent)
 for k,v in props or {} do l[k]=v end
 return l
end
function Controller:Init(deps)
 self._input=deps.InputController;self._scope=Scope.new()
 local hud=AuthoredGui.Get(self._gui,'ControlRoomHud');self._hud=hud
 self._list=hud:WaitForChild('JobList');self._restart=hud:WaitForChild('RestartBar')
 self._toast=hud:WaitForChild('Toast');self._sub=hud:WaitForChild('RadioSubtitle')
 for _,g in {self._list,self._restart,self._toast,self._sub} do
  g.Visible=false
  local _,release=HudScale.Attach(g,{referenceSize=Vector2.new(960,600),min=.62,max=1.1,consoleBoost=1.1});self._scope:Add(release)
 end
 self._listA,self._barA=0,0
 local head=self._list:WaitForChild('Header')
 self._listCount=head:WaitForChild('Count');self._listFill=self._list:WaitForChild('Progress'):WaitForChild('Fill')
 self._rows={}
 local rows=self._list:WaitForChild('Rows')
 for _,j in Config.Jobs do
  local r=rows:WaitForChild('Row_'..j.id)
  self._rows[j.id]={row=r,check=r.Box.Check,name=r:FindFirstChild('Name'),strike=r.Strike,done=false}
 end
 self._tasks=AuthoredGui.Get(self._gui,'ControlRoomTasks');self._tasks.Enabled=false
end
------------------------------------------------------------------ helpers
function Controller:_Floor()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 if not env then return nil end
 for _,m in env:GetChildren()do if m:GetAttribute('EncounterId')=='Level4' then return m,env end end
end
function Controller:_Sound(key,parent,volume,speed,keep)
 local s=Instance.new('Sound');s.SoundId=SND[key];s.Volume=volume or .5;s.PlaybackSpeed=speed or 1
 s.RollOffMinDistance=6;s.RollOffMaxDistance=70;s.Parent=parent or workspace.CurrentCamera
 s:Play();if not keep then game:GetService('Debris'):AddItem(s,20) end;return s
end
function Controller:_Cam()return workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero end
------------------------------------------------------------------ indexing a floor
function Controller:_Index(floor)
 local f={floor=floor,blink={},screens={},radios={},breakers={},lamps={},needles={},door={},sparks={}}
 for _,d in floor:GetDescendants()do
  if d:IsA('BasePart') then
   local b=d:GetAttribute('L4Blink')
   if b then table.insert(f.blink,{p=d,period=b,phase=math.random()*b,on=d.Color,off=d.Color:Lerp(Color3.new(0,0,0),.75),state=true}) end
   local kind=d:GetAttribute('L4Screen')
   if kind then
    local g=d:FindFirstChildWhichIsA('SurfaceGui')
    if g then table.insert(f.screens,{p=d,kind=kind,gui=g,seed=d:GetAttribute('Seed') or math.random(1,99),next=0}) end
   end
   if d:GetAttribute('L4Radio') then table.insert(f.radios,d) end
   if d:GetAttribute('SparkWire') then table.insert(f.sparks,{p=d,next=os.clock()+1+math.random()*4}) end
   local ref=d:GetAttribute('Ref')
   if ref then
    local bi=string.match(ref,'^Breaker(%d)$')
    if bi and d:GetAttribute('PivotFrame') then f.breakers[tonumber(bi)]={p=d,pivot=d:GetAttribute('PivotFrame'),home=d.CFrame,angle=0} end
    local li=string.match(ref,'^BreakerLamp(%d)$');if li then f.lamps[tonumber(li)]=d end
    local ni=string.match(ref,'^DialNeedle(%d)$')
    if ni and d:GetAttribute('PivotFrame') then f.needles[tonumber(ni)]={p=d,pivot=d:GetAttribute('PivotFrame'),angle=0,goal=0} end
    if ref=='ServerDoor' then f.doorLeaf=d end
   end
   if d:GetAttribute('SlidesWith')=='ServerDoor' then table.insert(f.door,d) end
  end
 end
 if f.doorLeaf then table.insert(f.door,f.doorLeaf) end
 -- where each door part sits now (closed, unless the door opened before this screen saw it)
 f.doorHome={};for _,p in f.door do f.doorHome[p]=p.CFrame end
 local openAt=floor:GetAttribute('ServerDoorOpenAt')
 if openAt and workspace:GetServerTimeNow()-openAt>1.6 then f.doorDone=true end
 f.indexedAt=os.clock();f.dirty=false
 return f
end
------------------------------------------------------------------ the living room
local function setBars(s,n,color)
 if not s.bars then
  s.bars={}
  local bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(4,10,16),BorderSizePixel=0},s.gui)
  bg:ClearAllChildren()
  s.title=label(bg,'',{Size=UDim2.fromScale(1,.18),TextScaled=true,TextColor3=color,Font=MONO,TextXAlignment=Enum.TextXAlignment.Left})
  for i=1,n do
   local b=make('Frame',{AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale((i-1)/n+.01,.96),Size=UDim2.fromScale(1/n-.02,.3),BackgroundColor3=color,BorderSizePixel=0,BackgroundTransparency=.15},bg)
   s.bars[i]={f=b,v=math.random()}
  end
  s.bg=bg
 end
end
local CAM_OFF={'NO SIGNAL','SIGNAL LOST','- - -'}
function Controller:_Screen(f,s,now,state)
 local kind=s.kind
 if kind=='Graph' then
  setBars(s,12,s.seed%2==0 and GREEN or CYAN)
  s.title.Text=(s.seed%2==0 and 'FLOW L/s ' or 'PRESSURE ')..(state.rebooted and 'NOMINAL' or 'NO DATA')
  for _,b in s.bars do b.v=math.clamp(b.v+(math.random()-.5)*.35,.05,1);if not state.rebooted then b.v*=.9 end;b.f.Size=UDim2.fromScale(b.f.Size.X.Scale,.05+b.v*.72) end
  s.next=now+.35
 elseif kind=='Cam' then
  if not s.bg then
   s.bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0},s.gui)
   s.bg:ClearAllChildren();s.bg.BackgroundColor3=Color3.fromRGB(14,18,16)
   -- a dim 'room' (floor shape) so a feed reads as a camera picture
   make('Frame',{Position=UDim2.fromScale(0,.62),Size=UDim2.fromScale(1,.38),BackgroundColor3=Color3.fromRGB(34,40,36),BorderSizePixel=0},s.bg)
   s.noise={}
   for i=1,6 do s.noise[i]=make('Frame',{Size=UDim2.fromScale(1,.03),BackgroundColor3=Color3.fromRGB(200,210,200),BackgroundTransparency=.8,BorderSizePixel=0},s.bg) end
   s.fig=make('Frame',{Position=UDim2.fromScale(.56,.26),Size=UDim2.fromScale(.08,.5),BackgroundColor3=Color3.fromRGB(4,6,6),BorderSizePixel=0,Visible=false},s.bg)
   make('Frame',{Position=UDim2.fromScale(.15,-.22),Size=UDim2.fromScale(.7,.22),BackgroundColor3=Color3.fromRGB(4,6,6),BorderSizePixel=0},s.fig)
   s.name=label(s.bg,'',{Position=UDim2.fromScale(.04,.02),Size=UDim2.fromScale(.92,.16),TextScaled=true,TextColor3=Color3.fromRGB(230,230,220),Font=MONO,TextXAlignment=Enum.TextXAlignment.Left})
   s.time=label(s.bg,'',{Position=UDim2.fromScale(.04,.84),Size=UDim2.fromScale(.92,.14),TextScaled=true,TextColor3=Color3.fromRGB(230,230,220),Font=MONO,TextXAlignment=Enum.TextXAlignment.Right})
   s.rec=make('Frame',{Position=UDim2.fromScale(.04,.86),Size=UDim2.fromScale(.05,.08),BackgroundColor3=RED,BorderSizePixel=0},s.bg);corner(s.rec,20)
   s.camName=s.p:GetAttribute('CamName') or 'CAM'
  end
  local dead=string.find(s.camName,'NO SIGNAL',1,true) or string.find(s.camName,'??',1,true)
  s.name.Text=dead and (s.camName..'  '..CAM_OFF[math.random(1,#CAM_OFF)]) or s.camName
  s.time.Text=string.format('03:12:%02d',os.time()%60)
  s.rec.Visible=math.floor(now*2)%2==0
  for _,n in s.noise do n.Position=UDim2.fromScale(0,math.random());n.BackgroundTransparency=dead and .3 or .85 end
  -- CAM 03 (the lift shaft): now and then a tall figure is standing there
  if string.find(s.camName,'CAM 03',1,true) then
   if not s.figUntil and math.random()<.025 then s.figUntil=now+1.2+math.random()*1.5 end
   s.fig.Visible=s.figUntil~=nil and now<s.figUntil
   if s.figUntil and now>s.figUntil then s.figUntil=nil end
  end
  s.next=now+.25
 elseif kind=='Static' then
  if not s.cells then
   s.bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0},s.gui)
   s.bg:ClearAllChildren();s.cells={}
   for y=0,5 do for x=0,7 do table.insert(s.cells,make('Frame',{Position=UDim2.fromScale(x/8,y/6),Size=UDim2.fromScale(1/8+.002,1/6+.002),BorderSizePixel=0},s.bg)) end end
  end
  for _,c in s.cells do local v=math.random(20,200);c.BackgroundColor3=Color3.fromRGB(v,v,v) end
  s.next=now+.08
 elseif kind=='Alert' then
  if not s.bg then
   s.bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0},s.gui)
   s.bg:ClearAllChildren()
   s.text=label(s.bg,'',{TextScaled=true,Font=Enum.Font.GothamBlack})
  end
  local on=math.floor(now*1.6)%2==0
  if state.rebooted then s.bg.BackgroundColor3=Color3.fromRGB(6,20,10);s.text.TextColor3=GREEN;s.text.Text='ALL SYSTEMS\nONLINE'
  else s.bg.BackgroundColor3=on and Color3.fromRGB(70,8,6) or Color3.fromRGB(16,4,4);s.text.TextColor3=on and Color3.fromRGB(255,220,200) or RED;s.text.Text=(s.seed%3==0 and 'CONTROL LINK\nLOST' or 'ALARM\nSYSTEM HALTED') end
  s.next=now+.3
 elseif kind=='Terminal' then
  local l=s.gui:FindFirstChildWhichIsA('TextLabel',true)
  if l then
   s.base=s.base or string.gsub(l.Text,'_$','')
   l.Text=s.base..(math.floor(now*2)%2==0 and '_' or ' ')
  end
  s.next=now+.5
 elseif kind=='Mimic' then self:_Mimic(f,s,now,state);s.next=now+.25
 elseif kind=='BreakerOrder' then self:_OrderScreen(f,s,now,state);s.next=now+.2
 elseif kind=='Upload' then
  local l=s.gui:FindFirstChildWhichIsA('TextLabel',true)
  if l then l.Text=state.done.Upload and 'SECNET v4.2\nnode4:~$ upload\n<font color="#9cf0b0">transfer complete</font>\nnode4:~$ _' or (state.stage=='Keycard' and 'SECNET v4.2\nACCESS LOCKED\nnode4:~$ _' or 'SECNET v4.2\nlogs waiting: 9\nnode4:~$ press E'..(math.floor(now*2)%2==0 and '_' or ' ')) end
  s.next=now+.5
 elseif kind=='Reboot' then
  local l=s.gui:FindFirstChildWhichIsA('TextLabel',true)
  if l then
   if state.rebooted then l.TextColor3=GREEN;l.Text='SYSTEM ONLINE\n100%'
   elseif state.rebootP then l.TextColor3=state.rebootNear and CYAN or RED;l.Text=(state.rebootNear and 'RESTARTING...' or 'STAY CLOSE!')..'\n'..string.format('%d%%',math.floor(state.rebootP))
   else l.TextColor3=Color3.fromRGB(255,90,70);l.Text=(state.stage=='Reboot' and 'PRESS THE BUTTON\nTO RESTART' or 'SYSTEM HALTED\nREBOOT REQUIRED') end
  end
  s.next=now+.15
 else s.next=now+5 end
end
function Controller:_Mimic(f,s,now,state)
 if not s.nodes then
  local bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0},s.gui)
  bg:ClearAllChildren();bg.BackgroundColor3=Color3.fromRGB(4,10,18);s.bg=bg
  label(bg,'WATER NETWORK  //  LIVE',{Position=UDim2.fromScale(.03,.02),Size=UDim2.fromScale(.94,.08),TextScaled=true,TextColor3=CYAN,Font=MONO,TextXAlignment=Enum.TextXAlignment.Left})
  local pts={{'RESERVOIR',.12,.3},{'PUMP 1',.35,.2},{'PUMP 2',.35,.4},{'PUMP 3',.35,.6},{'TREATMENT',.6,.4},{'CITY',.86,.4}}
  local links={{1,2},{1,3},{1,4},{2,5},{3,5},{4,5},{5,6}}
  s.lines={}
  for _,l in links do
   local a,b=pts[l[1]],pts[l[2]]
   local dx,dy=(b[2]-a[2]),(b[3]-a[3])*.56
   local len=math.sqrt(dx*dx+dy*dy)
   local fr=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale((a[2]+b[2])/2,(a[3]+b[3])/2),Size=UDim2.new(len,0,0,6),Rotation=math.deg(math.atan2(dy,dx)),BackgroundColor3=Color3.fromRGB(60,70,80),BorderSizePixel=0},bg)
   table.insert(s.lines,fr)
  end
  s.nodes={}
  for _,p in pts do
   local n=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(p[2],p[3]),Size=UDim2.fromScale(.1,.11),BackgroundColor3=Color3.fromRGB(30,36,44),BorderSizePixel=0},bg);corner(n,6)
   local st=make('UIStroke',{Color=RED,Thickness=3},n)
   label(n,p[1],{TextScaled=true,Font=MONO})
   table.insert(s.nodes,{f=n,s=st})
  end
  s.order=label(bg,'',{Position=UDim2.fromScale(.03,.74),Size=UDim2.fromScale(.94,.12),TextScaled=true,Font=Enum.Font.GothamBlack,TextColor3=AMBER})
  s.status=label(bg,'',{Position=UDim2.fromScale(.03,.87),Size=UDim2.fromScale(.94,.1),TextScaled=true,Font=MONO,TextColor3=INK})
 end
 local blink=math.floor(now*2)%2==0
 for i,n in s.nodes do
  local ok=state.rebooted or (i==1) or (i>=2 and i<=4 and state.done.Dials) or (i==5 and state.done.Upload)
  n.s.Color=ok and GREEN or (blink and RED or Color3.fromRGB(90,20,16))
 end
 for _,l in s.lines do l.BackgroundColor3=state.rebooted and Color3.fromRGB(60,200,255) or Color3.fromRGB(60,70,80) end
 local parts={}
 for k,i in state.order or {} do
  local col=k<=state.breakerProgress and '#5aff8c' or '#ffb13c'
  table.insert(parts,string.format('<font color="%s">%d</font>',col,i))
 end
 s.order.Text=state.done.Breakers and '<font color="#5aff8c">MAIN BREAKERS: ON</font>' or ('BREAKER ORDER:  '..table.concat(parts,'  >  '))
 if state.rebooted then s.status.Text='CORE ONLINE  //  ALL PUMPS NOMINAL'
 elseif state.rebootP then s.status.Text=string.format('CORE RESTART %d%%  //  STAY WITH THE CORE',math.floor(state.rebootP))
 else s.status.Text=string.format('JOBS DONE %d/5  //  CORE OFFLINE',state.doneCount) end
end
function Controller:_OrderScreen(f,s,now,state)
 -- authored in the breaker bank's screen (Bg > Title, Status, Cell1..5 > Num, Strip, Ring)
 local bg=s.gui:FindFirstChild('Bg');if not bg then return end
 local order=state.order or {}
 local tripped=f.tripFlash~=nil and now<f.tripFlash
 local blink=math.floor(now*2.5)%2==0
 for k=1,5 do
  local c=bg:FindFirstChild('Cell'..k)
  if c then
   local i=order[k]
   local done=state.done.Breakers or k<=state.breakerProgress
   local cur=not state.done.Breakers and k==state.breakerProgress+1
   c.Num.Text=i and tostring(i) or '-'
   c.Num.TextTransparency=done and .55 or 0
   c.Strip.BackgroundColor3=i and BREAKER_COLORS[i] or Color3.fromRGB(51,51,51)
   c.Ring.Color=tripped and RED or (done and GREEN or ((cur and blink) and INK or AMBER))
   c.Ring.Transparency=(done or cur or tripped) and 0 or .55
  end
 end
 local st=bg:FindFirstChild('Status')
 if st then
  st.Text=state.done.Breakers and 'COMPLETE' or (tripped and 'TRIPPED - START AGAIN' or string.format('STEP %d / 5',math.min(5,state.breakerProgress+1)))
  st.TextColor3=state.done.Breakers and GREEN or (tripped and RED or AMBER)
 end
end
------------------------------------------------------------------ floor state each frame
function Controller:_State(floor)
 local st={stage=floor:GetAttribute('Stage') or 'Keycard',done={},doneCount=0}
 for id in string.gmatch(floor:GetAttribute('JobsDone') or '','[^,]+')do st.done[id]=true;st.doneCount+=1 end
 st.order={};for n in string.gmatch(floor:GetAttribute('BreakerOrder') or '','%d+')do table.insert(st.order,tonumber(n)) end
 st.breakerProgress=0
 for k,i in st.order do if floor:GetAttribute('Breaker'..i..'At') then st.breakerProgress=k else break end end
 if st.done.Breakers then st.breakerProgress=5 end
 st.rebooted=floor:GetAttribute('CircuitCoreAt')~=nil
 if floor:GetAttribute('RebootStartedAt') and not st.rebooted then st.rebootP=floor:GetAttribute('RebootProgress') or 0;st.rebootNear=floor:GetAttribute('RebootNear')~=false end
 return st
end
function Controller:_Living(dt)
 local floor=self:_Floor()
 if floor~=(self._f and self._f.floor) then
  if self._fConn then self._fConn:Disconnect();self._fConn=nil end
  self._f=floor and self:_Index(floor) or nil
  self._lastRadio=floor and floor:GetAttribute('RadioAt') or nil
  self._lastFlicker=floor and floor:GetAttribute('FlickerAt') or nil
  self._lastTrip=floor and floor:GetAttribute('BreakerTripAt') or nil
  -- the floor streams in bit by bit: anything that arrives later is picked up by a re-index
  if floor then self._fConn=floor.DescendantAdded:Connect(function()if self._f then self._f.dirty=true end end) end
 elseif self._f and self._f.dirty and os.clock()-(self._f.indexedAt or 0)>1.5 then
  local old=self._f
  local f=self:_Index(floor)
  -- keep what has already happened on this screen
  f.doorDone=old.doorDone or f.doorDone;f.doorSound=old.doorSound
  for p,c in old.doorHome do f.doorHome[p]=c end
  for i,b in old.breakers do if f.breakers[i] then f.breakers[i]=b end end
  for i,n in old.needles do if f.needles[i] then f.needles[i]=n end end
  for _,s in f.sparks do for _,o in old.sparks do if o.p==s.p then s.next=o.next;s.fx=o.fx end end end
  self._f=f
 end
 local f=self._f
 -- the control room is far bigger than Level 5's corridors: let the haze reach further while
 -- this floor is up (the station's own fog comes back the moment it is gone)
 local Lighting=game:GetService('Lighting')
 -- (eased both ways over a couple of seconds, so arriving or leaving never pops the haze)
 if f and not self._fog then self._fog={Lighting.FogStart,Lighting.FogEnd} end
 local goal=f and {10,175} or self._fog
 if goal then
  local k=1-math.exp(-(dt or 1/60)*1.4)
  Lighting.FogStart+=(goal[1]-Lighting.FogStart)*k;Lighting.FogEnd+=(goal[2]-Lighting.FogEnd)*k
  if not f and math.abs(Lighting.FogEnd-goal[2])<.5 then Lighting.FogStart=goal[1];Lighting.FogEnd=goal[2];self._fog=nil end
 end
 if not f then self._listA=0;self._barA=0;self._list.Visible=false;self._restart.Visible=false;return end
 local now=os.clock();local cam=self:_Cam()
 local state=self:_State(floor);self._st=state
 -- LEDs (only near ones, only when they change)
 for _,b in f.blink do
  if b.p.Parent and (b.p.Position-cam).Magnitude<90 then
   local on=((now+b.phase)%b.period)<b.period*.55
   if on~=b.state then b.state=on;b.p.Color=on and b.on or b.off end
  end
 end
 -- screens (near ones, each at its own rate)
 for _,s in f.screens do
  if now>=s.next and s.p.Parent then
   if (s.p.Position-cam).Magnitude<110 then local ok,err=pcall(self._Screen,self,f,s,now,state);if not ok then s.next=now+5;warn(err) end
   else s.next=now+1 end
  end
 end
 -- torn live wires: a quiet buzz, then every few seconds a burst of sparks, a flash and a crackle
 for _,s in f.sparks do
  if s.p.Parent and (s.p.Position-cam).Magnitude<140 then
   if not s.fx then pcall(self._SparkFx,self,s) end
   if s.fx and now>=s.next then
    s.next=now+1.6+math.random()*4.5
    pcall(self._SparkBurst,self,s)
   end
  end
 end
 -- door
 local openAt=floor:GetAttribute('ServerDoorOpenAt')
 if openAt and not f.doorDone and f.doorLeaf then
  local u=(workspace:GetServerTimeNow()-openAt)/1.7
  local off=f.doorLeaf:GetAttribute('SlideOffset') or Vector3.new(0,0,8.3)
  if not f.doorSound then f.doorSound=true;if u<1 then self:_Sound('door',f.doorLeaf,.8,.7);self:_Sound('beep',f.doorLeaf,.6,1.2) end end
  if u>=1 then f.doorDone=true end
  local k=ease(u)
  for _,p in f.door do if p.Parent then local c=f.doorHome[p];if c then p.CFrame=c+off*k end end end
 end
 -- breaker levers
 local trip=floor:GetAttribute('BreakerTripAt')
 if trip~=self._lastTrip then
  self._lastTrip=trip
  if trip then
   local bank=f.breakers[3] and f.breakers[3].p
   if bank then self:_Sound('trip',bank,.9,1.4);self:_Sound('bad',bank,.7,.8);self:_Sparks(bank) end
   f.tripFlash=now+1.2
  end
 end
 for i,b in f.breakers do
  local down=floor:GetAttribute('Breaker'..i..'At')~=nil or state.done.Breakers
  local goal=down and -94 or 0 -- (past ~95 the handle sinks into the breaker body)
  if down and not b.wasDown then self:_Sound('flip',b.p,.8) end
  b.wasDown=down
  local rate=(goal<b.angle) and 520 or 300
  if b.angle~=goal then
   b.angle=b.angle<goal and math.min(goal,b.angle+rate*dt) or math.max(goal,b.angle-rate*dt)
   if b.p.Parent then b.p.CFrame=b.pivot*CFrame.Angles(math.rad(b.angle),0,0)*b.pivot:ToObjectSpace(b.home) end
  end
  local lamp=f.lamps[i]
  if lamp then
   local lit=down or (f.tripFlash and now<f.tripFlash and math.floor(now*8)%2==0)
   local col=down and Color3.fromRGB(90,255,120) or (lit and RED or Color3.fromRGB(60,20,16))
   if lamp.Color~=col then lamp.Color=col;lamp.Material=lit and Enum.Material.Neon or Enum.Material.Glass end
  end
 end
 -- dial needles: restless until the dials are set, then they settle on their marks
 local targets={};for n in string.gmatch(floor:GetAttribute('DialTargets') or '','%d+')do table.insert(targets,tonumber(n)) end
 for i,n in f.needles do
  if state.done.Dials and targets[i] then n.goal=-120+targets[i]*2.4
  else n.t=(n.t or 0)-dt;if n.t<=0 then n.t=.4+math.random();n.goal=(math.random()-.5)*220 end end
  n.angle+=(n.goal-n.angle)*(1-math.exp(-dt*(state.done.Dials and 4 or 2.5)))
  if n.p.Parent then n.p.CFrame=n.pivot*CFrame.Angles(0,0,math.rad(-n.angle))*CFrame.new(0,n.p.Size.Y*.4,0) end
 end
 -- radio calls
 local at=floor:GetAttribute('RadioAt')
 if at and at~=self._lastRadio then self._lastRadio=at;if workspace:GetServerTimeNow()-at<10 then self:_RadioCall(f,floor) end end
 -- lights flicker
 local fl=floor:GetAttribute('FlickerAt')
 if fl and fl~=self._lastFlicker then self._lastFlicker=fl;if workspace:GetServerTimeNow()-fl<5 then self:_Flicker(floor) end end
 -- HUD: job list / restart bar
 self:_Hud(floor,state,dt)
end
function Controller:_Sparks(part)
 local a=Instance.new('Attachment');a.Parent=part
 local pe=Instance.new('ParticleEmitter');pe.Texture='rbxasset://textures/particles/sparkles_main.dds';pe.Color=ColorSequence.new(Color3.fromRGB(255,220,140))
 pe.LightEmission=1;pe.Size=NumberSequence.new(.25,0);pe.Speed=NumberRange.new(8,16);pe.SpreadAngle=Vector2.new(60,60);pe.Lifetime=NumberRange.new(.2,.5);pe.Acceleration=Vector3.new(0,-30,0);pe.Rate=0;pe.Parent=a
 pe:Emit(40);game:GetService('Debris'):AddItem(a,2)
 local l=Instance.new('PointLight');l.Color=Color3.fromRGB(255,200,120);l.Brightness=4;l.Range=14;l.Parent=part;game:GetService('Debris'):AddItem(l,.25)
end
local ZAPS={'rbxassetid://9116279560','rbxassetid://9116275293','rbxassetid://9116278051'}
function Controller:_SparkFx(s)
 local a=Instance.new('Attachment');a.Name='SparkPoint';a.Position=Vector3.new(0,-.2,0);a.Parent=s.p
 local pe=Instance.new('ParticleEmitter');pe.Name='Sparks';pe.Texture='rbxasset://textures/particles/sparkles_main.dds'
 pe.Color=ColorSequence.new(Color3.fromRGB(255,240,190),Color3.fromRGB(255,150,60));pe.LightEmission=1;pe.LightInfluence=0
 pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.22),NumberSequenceKeypoint.new(1,0)})
 pe.Speed=NumberRange.new(6,14);pe.SpreadAngle=Vector2.new(70,70);pe.Lifetime=NumberRange.new(.25,.7)
 pe.Acceleration=Vector3.new(0,-40,0);pe.Drag=1.5;pe.Rate=0;pe.EmissionDirection=Enum.NormalId.Bottom;pe.Parent=a
 local l=Instance.new('PointLight');l.Name='SparkFlash';l.Color=Color3.fromRGB(190,215,255);l.Range=16;l.Brightness=0;l.Shadows=false;l.Parent=a
 local hum=Instance.new('Sound');hum.Name='LiveWireBuzz';hum.SoundId='rbxassetid://9112889325';hum.Looped=true;hum.Volume=.12;hum.PlaybackSpeed=1.9
 hum.RollOffMinDistance=3;hum.RollOffMaxDistance=26;hum.Parent=s.p;hum:Play()
 s.fx={pe=pe,light=l,hum=hum}
end
function Controller:_SparkBurst(s)
 local fx=s.fx;if not fx or not fx.pe.Parent then return end
 local z=Instance.new('Sound');z.SoundId=ZAPS[math.random(1,#ZAPS)];z.Volume=.55+math.random()*.25;z.PlaybackSpeed=.9+math.random()*.25
 z.RollOffMinDistance=5;z.RollOffMaxDistance=60;z.Parent=s.p;z:Play();game:GetService('Debris'):AddItem(z,3)
 task.spawn(function()
  -- two or three quick spits, each with a blue-white flash
  for i=1,math.random(2,3) do
   if not fx.pe.Parent then return end
   fx.pe:Emit(math.random(10,22));fx.light.Brightness=3+math.random()*2
   if fx.hum.Parent then fx.hum.Volume=.3 end
   task.wait(.05+math.random()*.06);fx.light.Brightness=0
   task.wait(.04+math.random()*.12)
  end
  if fx.hum.Parent then fx.hum.Volume=.12 end
 end)
end
function Controller:_Flicker(floor)
 local lights={}
 for _,d in floor:GetDescendants()do if d:IsA('Light') and d.Enabled then table.insert(lights,d) end end
 task.spawn(function()
  local t0=os.clock()
  while os.clock()-t0<2.4 do
   for _,l in lights do if l.Parent then l.Enabled=math.random()<.35 end end
   task.wait(.06+math.random()*.1)
  end
  for _,l in lights do if l.Parent then l.Enabled=true end end
 end)
end
------------------------------------------------------------------ radio calls
local function corrupt(text,amount)
 local out={}
 local glyphs={'#','%','?','/','_','~','!'}
 for c in string.gmatch(text,'.')do if c~=' ' and math.random()<amount then table.insert(out,glyphs[math.random(1,#glyphs)]) else table.insert(out,c) end end
 return table.concat(out)
end
function Controller:_RadioCall(f,floor)
 local text=floor:GetAttribute('RadioText') or '';local who=floor:GetAttribute('RadioWho') or 'Marty';local style=floor:GetAttribute('RadioStyle') or 'calm'
 local source=floor:GetAttribute('RadioSource') or 'All'
 self._radioSerial=(self._radioSerial or 0)+1;local serial=self._radioSerial
 -- sound from the radios (and the PA for whole-floor calls)
 local speed=style=='glitch' and .6 or style=='creepy' and .78 or style=='faint' and .9 or .95
 local dur=3+#text*.055
 for _,r in f.radios do
  if r.Parent and (source=='All' or r:GetAttribute('L4Radio')==source) then
   self:_Sound('squelch',r,style=='faint' and .35 or .7,1)
   local v=self:_Sound('voices',r,style=='faint' and .12 or .32,speed)
   if style=='glitch' then local ps=Instance.new('DistortionSoundEffect');ps.Level=.6;ps.Parent=v end
   task.delay(dur,function()if v.Parent then TweenService:Create(v,TweenInfo.new(.4),{Volume=0}):Play() end;if r.Parent then self:_Sound('static',r,.5,1) end end)
   local lamp=r.Parent and r.Parent:FindFirstChild('Lamp')
   if lamp then local c=lamp.Color;lamp.Color=Color3.fromRGB(255,60,40);task.delay(dur,function()if lamp.Parent then lamp.Color=c end end) end
  end
 end
 -- a quiet copy on this screen so the words always come with sound
 self:_Sound('static',nil,.12,1)
 -- subtitle (switched off for now: Config.Level4.ShowRadioSubtitles; the box and typing code
 -- below stay as scaffolding for the improved version)
 if Config.ShowRadioSubtitles~=true then return end
 local sub=self._sub;local who_=sub:FindFirstChild('Who');local line=sub:FindFirstChild('Text')
 sub.Visible=true;sub.GroupTransparency=1
 TweenService:Create(sub,EASE,{GroupTransparency=0}):Play()
 who_.Text=(who=='???' and 'RADIO  -  ???') or ('RADIO  -  '..string.upper(who))
 who_.TextColor3=who=='Mercer' and Color3.fromRGB(150,200,255) or GOLD
 line.TextTransparency=style=='faint' and .35 or 0
 task.spawn(function()
  local shown=0;local n=#text
  local t0=os.clock()
  while self._radioSerial==serial and shown<n do
   shown=math.min(n,math.floor((os.clock()-t0)*32))
   local s=string.sub(text,1,shown)
   if style=='glitch' then s=corrupt(s,.12) end
   line.Text=s
   task.wait(.03)
  end
  if self._radioSerial~=serial then return end
  line.Text=text
  task.wait(math.max(2.5,dur-n/32))
  if self._radioSerial~=serial then return end
  TweenService:Create(sub,TweenInfo.new(.4),{GroupTransparency=1}):Play()
  task.wait(.42)
  if self._radioSerial==serial then sub.Visible=false end
 end)
end
------------------------------------------------------------------ HUD
-- keeps the job list and the toast clear of the objective bar on every screen size: the list sits
-- top-right, and drops below the bar whenever the bar is wide enough to reach it (phones, small
-- windows); the toast always sits just under the bar
function Controller:_Layout()
 local bar=self._taskBar
 if not (bar and bar.Parent) then local g=self._gui:FindFirstChild('MaintenanceTasks');bar=g and g:FindFirstChild('TaskBar');self._taskBar=bar end
 local screen=bar and bar:FindFirstAncestorWhichIsA('ScreenGui')
 local bottom,right=0,0
 if screen and screen.Enabled and bar.AbsoluteSize.Y>1 then bottom=bar.AbsolutePosition.Y+bar.AbsoluteSize.Y;right=bar.AbsolutePosition.X+bar.AbsoluteSize.X end
 local width=self._hud.AbsoluteSize.X
 local listLeft=width-16-self._list.AbsoluteSize.X
 local y=(bottom>0 and right>listLeft-12) and bottom+14 or 16
 self._list.Position=UDim2.new(1,-16,0,y+(1-self._listA)*-8)
 self._toast.Position=UDim2.new(.5,0,0,math.max(bottom,60)+12)
end
function Controller:_Hud(floor,state,dt)
 local context=self._input:GetContext()
 local onFloor=context=='ActiveFloor' and not self._window and not self._player:GetAttribute('EHLoreOpen')
 local k=1-math.exp(-math.clamp(dt or 1/60,0,.1)*10)
 -- job list: fades in during the jobs stage
 local showList=onFloor and state.stage=='Jobs'
 self._listA+=((showList and 1 or 0)-self._listA)*k
 if math.abs(self._listA-(showList and 1 or 0))<.004 then self._listA=showList and 1 or 0 end
 self._list.AnchorPoint=Vector2.new(1,0)
 self._list.Visible=self._listA>0
 self._list.GroupTransparency=1-self._listA
 self:_Layout()
 self._listCount.Text=state.doneCount..' / '..#Config.Jobs
 self._listFill.Size=self._listFill.Size:Lerp(UDim2.fromScale(state.doneCount/#Config.Jobs,1),k)
 for id,r in self._rows do
  local done=state.done[id]==true
  if done~=r.done then
   r.done=done
   r.check.Visible=done
   r.name.TextColor3=done and MUTED or INK
   local sc=self._list:FindFirstChild('HudScale');sc=sc and sc.Scale or 1
   local w=done and math.min(r.name.TextBounds.X/math.max(sc,.01),r.name.AbsoluteSize.X/math.max(sc,.01)) or 0
   TweenService:Create(r.strike,TweenInfo.new(.35,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.new(0,w,0,1)}):Play()
   if done and self._listA>.5 then self:_Sound('good',nil,.45) end
  end
 end
 -- restart bar
 local showBar=onFloor and state.rebootP~=nil
 self._barA+=((showBar and 1 or 0)-self._barA)*k
 if math.abs(self._barA-(showBar and 1 or 0))<.004 then self._barA=showBar and 1 or 0 end
 self._restart.Visible=self._barA>0;self._restart.GroupTransparency=1-self._barA
 self._restart.Position=UDim2.new(.5,0,1,-150+(1-self._barA)*8)
 if state.rebootP then
  local p=state.rebootP/100
  local fill=self._restart.Track.Fill
  fill.Size=fill.Size:Lerp(UDim2.fromScale(p,1),k)
  self._restart.Percent.Text=string.format('%d%%',math.floor(state.rebootP))
  local col=state.rebootNear and GOLD or RED
  fill.BackgroundColor3=col
  self._restart.Hint.Text=state.rebootNear and 'Stay close to the core' or 'Get back to the core - it stops without you'
  self._restart.Hint.TextColor3=state.rebootNear and MUTED or RED
 end
end
function Controller:_ShowToast(text)
 local t=self._toast;t:FindFirstChild('Text').Text=text
 t.Visible=true;t.GroupTransparency=1
 TweenService:Create(t,EASE,{GroupTransparency=0}):Play()
 self:_Sound('bad',nil,.4,1.1)
 self._toastSerial=(self._toastSerial or 0)+1;local serial=self._toastSerial
 task.delay(3.2,function()
  if self._toastSerial~=serial then return end
  local tw=TweenService:Create(t,TweenInfo.new(.35),{GroupTransparency=1});tw:Play();tw.Completed:Wait()
  if self._toastSerial==serial then t.Visible=false end
 end)
end
------------------------------------------------------------------ job windows
function Controller:_Remote()
 local net=game.ReplicatedStorage.Game:FindFirstChild('Network')
 return net and net:FindFirstChild('Level4Task')
end
local function pressed(input)return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch end
function Controller:_OpenWindow(id)
 if self._window then self:_CloseWindow(false,true) end
 local job;for _,j in Config.Jobs do if j.id==id then job=j end end
 if not job then return end
 local g=self._tasks;local win=g:FindFirstChild('Window');if not win then return end
 local serial=self._player:GetAttribute('EHL4TaskSerial')
 local w={id=id,serial=serial,scope=Scope.new(),done=false,gui=g,win=win,body=win.Body}
 self._window=w
 -- freeze the view and free the pointer while the window is up (same as reading a paper)
 self._player:SetAttribute('EHLoreOpen',true);self._input:SetBlocked('L4Task',true)
 if self._controls then pcall(function()self._controls:Disable() end) end
 for _,c in w.body:GetChildren()do if c:IsA('GuiObject') then c.Visible=false end end
 win:FindFirstChild('Title').Text=job.name
 w.hint=win:FindFirstChild('Hint');w.hint.Text=''
 local done=win.Done;done.Visible=false;done.GroupTransparency=1
 -- one uniform scale so the whole window fits any screen
 local vp=workspace.CurrentCamera.ViewportSize
 win.WindowScale.Scale=math.clamp(math.min(vp.X*.94/win.Size.X.Offset,vp.Y*.9/win.Size.Y.Offset),.45,1.25)
 g.Enabled=true
 win.GroupTransparency=1;win.Position=UDim2.new(.5,0,.5,10);g.Dim.BackgroundTransparency=1
 TweenService:Create(win,EASE,{GroupTransparency=0,Position=UDim2.fromScale(.5,.5)}):Play()
 TweenService:Create(g.Dim,EASE,{BackgroundTransparency=.4}):Play()
 w.scope:Add(win.Close.Activated:Connect(function()self:_CloseWindow(true) end))
 local build=self['_Job'..id]
 if build then local ok,err=pcall(build,self,w,w.body);if not ok then warn('[ElevatorHorror] job window: '..tostring(err)) end end
 -- gamepad: start with a control selected so the D-pad / stick can move between them
 if UIS.PreferredInput==Enum.PreferredInput.Gamepad then
  local first={Upload=w.body.Upload.Run,Wires=w.body.Wires.L1,Dials=w.body.Dials.Dial1.Up,Radio=w.body.Radio.Right}
  task.defer(function()if self._window==w then game:GetService('GuiService').SelectedObject=first[id] or win.Close end end)
  w.scope:Add(function()local gs=game:GetService('GuiService');if gs.SelectedObject and gs.SelectedObject:IsDescendantOf(win) then gs.SelectedObject=nil end end)
 end
 self:_Sound('beep',nil,.4,1.3)
end
function Controller:_CloseWindow(cancel,instant)
 local w=self._window;if not w then return end
 self._window=nil
 if cancel and not w.done then local r=self:_Remote();if r then r:FireServer('Cancel',w.id,w.serial) end end
 self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('L4Task',false)
 if self._controls then pcall(function()self._controls:Enable() end) end
 w.scope:Destroy()
 local g=w.gui;local win=w.win
 if instant then g.Enabled=false;return end
 self._closeSerial=(self._closeSerial or 0)+1;local s=self._closeSerial
 TweenService:Create(win,EASE_IN,{GroupTransparency=1,Position=UDim2.new(.5,0,.5,8)}):Play()
 TweenService:Create(g.Dim,EASE_IN,{BackgroundTransparency=1}):Play()
 task.delay(.18,function()if self._closeSerial==s and not self._window then g.Enabled=false end end)
end
function Controller:_Success(w,answer)
 if w.done then return end
 w.done=true
 local r=self:_Remote();if r then r:FireServer('Done',w.id,w.serial,answer) end
 self:_Sound('good',nil,.55,1)
 local d=w.win.Done;d.Visible=true;d.GroupTransparency=1
 TweenService:Create(d,EASE,{GroupTransparency=0}):Play()
 task.delay(1,function()if self._window==w then self:_CloseWindow(false) end end)
end
-- a button that repeats while held (the +/- and < > buttons)
local function repeater(w,b,step)
 local holding=false
 w.scope:Add(b.MouseButton1Down:Connect(function()
  holding=true;step()
  task.delay(.35,function()while holding and not w.done and b.Parent do step();task.wait(.06) end end)
 end))
 w.scope:Add(b.MouseButton1Up:Connect(function()holding=false end))
 w.scope:Add(b.MouseLeave:Connect(function()holding=false end))
 w.scope:Add(function()holding=false end)
end
-- relative drags: only the movement of the pointer/finger is used, never its absolute position, so
-- the controls track exactly on every device and inset (notches, top bar, scaled windows)
local function dragger(w,target,onDelta)
 local active=nil;local last=nil
 w.scope:Add(target.InputBegan:Connect(function(input)
  if pressed(input) and not w.done then active=input;last=input.Position end
 end))
 w.scope:Add(UIS.InputChanged:Connect(function(input)
  if not active then return end
  if input.UserInputType==Enum.UserInputType.MouseMovement or (input.UserInputType==Enum.UserInputType.Touch and input==active) then
   local d=input.Position-last;last=input.Position
   if d.Magnitude>0 then onDelta(Vector2.new(d.X,d.Y)) end
  end
 end))
 w.scope:Add(UIS.InputEnded:Connect(function(input)
  if active and (input==active or input.UserInputType==Enum.UserInputType.MouseButton1) then active=nil end
 end))
end
------------------------------------------------ UPLOAD (a terminal session)
local FILES={'access_log_0412.dat','door_events.csv','cam03_0312.mp4','staff_list.csv','shift_rota.txt','alarm_history.log','VOSS_M.rec','pump_trend_week.csv','mercer_b_notes.txt'}
local BOOT={'BWWA SECNET v4.2   (c) 1987 Blackwater Water Authority','login: maint','password: ********','last login: Tue 03:12 on tty3','',
 'maint@node4:~$ ls /sec/logs','access_log_0412.dat   door_events.csv   cam03_0312.mp4','staff_list.csv   shift_rota.txt   alarm_history.log','VOSS_M.rec   pump_trend_week.csv   mercer_b_notes.txt',''}
local CMD='upload --all /sec/logs surface'
function Controller:_JobUpload(w,body)
 local up=body.Upload;up.Visible=true
 w.hint.Text='Send the security logs to the surface. Keep this window open until it finishes.'
 local out,prog,prompt,run=up.Output,up.Progress,up.Prompt,up.Run
 local lines={}
 local function push(s)table.insert(lines,s);while #lines>12 do table.remove(lines,1) end;out.Text=table.concat(lines,'\n') end
 out.Text='';prog.Text='';run.Visible=false
 local typed='';local stage='boot'
 w.scope:Add(RunService.RenderStepped:Connect(function()
  local blink=math.floor(os.clock()*2)%2==0
  prompt.Text=(stage=='sending' or stage=='done') and '' or ('maint@node4:~$ '..typed..(blink and '_' or ' '))
 end))
 local function alive()return self._window==w and not w.done end
 task.spawn(function()
  for _,l in BOOT do if not alive() then return end;push(l);task.wait(l=='' and .05 or .09) end
  if alive() then stage='ready';run.Visible=true;if UIS.PreferredInput==Enum.PreferredInput.Gamepad then game:GetService('GuiService').SelectedObject=run end end
 end)
 local started=false
 local function start()
  if started or stage~='ready' or not alive() then return end
  started=true;run.Visible=false;stage='typing'
  task.spawn(function()
   for i=1,#CMD do if not alive() then return end;typed=string.sub(CMD,1,i);if i%3==0 then self:_Sound('click',nil,.12,1.6) end;task.wait(.028) end
   push('maint@node4:~$ '..CMD);typed='';stage='sending'
   push('connecting to surface relay 10.4.0.1 ... ok')
   local snd=self:_Sound('scroll',nil,.14,1.1,true)
   w.scope:Add(function()if snd.Parent then snd:Destroy() end end)
   local t0=os.clock();local dur=Config.UploadSeconds;local fi=0;local stalled=false
   while alive() do
    local u=math.clamp((os.clock()-t0)/dur,0,1)
    -- the upload chokes on one file for a moment
    if u>.62 and not stalled then
     stalled=true;push('<font color="#e85450">VOSS_M.rec   ERR 0x2F  file not found - retrying</font>');self:_Sound('bad',nil,.3,1.2)
     task.wait(1.1);t0+=1.1;u=math.clamp((os.clock()-t0)/dur,0,1)
    end
    local idx=math.clamp(math.floor(u*#FILES)+1,1,#FILES)
    if idx~=fi then fi=idx;push('sending '..FILES[idx]..' ...') end
    local n=math.floor(u*28+.5)
    prog.Text=string.format('[%s%s] %3d%%   %.1f KB/s',string.rep('#',n),string.rep('.',28-n),math.floor(u*100),2+math.sin(os.clock()*3)*.4)
    if u>=1 then
     push('transfer complete: '..#FILES..' files, 0 errors');stage='done'
     if snd.Parent then snd:Stop() end
     self:_Success(w,true);return
    end
    task.wait(.05)
   end
  end)
 end
 w.scope:Add(run.Activated:Connect(start))
 CAS:BindActionAtPriority('BlackwaterL4Run',function(_,st)if st==Enum.UserInputState.Begin then start() end;return Enum.ContextActionResult.Sink end,false,3000,Enum.KeyCode.Return,Enum.KeyCode.KeypadEnter) -- (a pad presses the selected RUN button with A)
 w.scope:Add(function()CAS:UnbindAction('BlackwaterL4Run') end)
end
------------------------------------------------ WIRES
local WIRE_NAMES={'RED','BLUE','YELLOW','WHITE'}
function Controller:_JobWires(w,body)
 local wi=body.Wires;wi.Visible=true
 w.hint.Text='Pick a wire on the left, then the plug of the same colour.'
 local order={};for n in string.gmatch((self._f and self._f.floor:GetAttribute('WireOrder')) or '1,2,3,4','%d+')do table.insert(order,tonumber(n)) end
 local L,R,W={},{},{}
 for i=1,4 do
  L[i]=wi['L'..i];R[i]=wi['R'..i];W[i]=wi['Wire'..i]
  W[i].Visible=false
 end
 for i=1,4 do
  -- the right-hand plugs are shuffled each round
  local c=order[i]
  R[i].Plug.BackgroundColor3=L[c].Plug.BackgroundColor3;R[i].Label.Text=WIRE_NAMES[c]
  for _,s in {L[i],R[i]} do s.Plug.Ring.Color=INK;s.Plug.Ring.Transparency=.7;s.Plug.Ring.Thickness=1 end
 end
 local drag=wi.DragWire;drag.Visible=false
 local status=wi.Status
 local linked,answer,sel,dragging={},{},nil,false
 local function count()local n=0;for _ in answer do n+=1 end;return n end
 status.Text='0 / 4 connected'
 local function ring(s,col,t,th)s.Plug.Ring.Color=col;s.Plug.Ring.Transparency=t;s.Plug.Ring.Thickness=th or 1 end
 local function select(i)
  if sel then ring(L[sel],INK,.7) end
  sel=i
  if i then ring(L[i],GOLD,0,2);self:_Sound('beep',nil,.25,1.6) end
 end
 local function endPoint(s,left)
  local p=s.Plug;local a=p.AbsolutePosition;local z=p.AbsoluteSize
  return Vector2.new(left and a.X+z.X+4 or a.X-4,a.Y+z.Y/2)
 end
 local function place(f,a,b)
  -- (in the window's own units: absolute pixels back through its one UIScale)
  local sc=math.max(.01,w.win.WindowScale.Scale);local o=wi.AbsolutePosition
  a=(a-o)/sc;b=(b-o)/sc
  local d=b-a;f.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2);f.Size=UDim2.fromOffset(d.Magnitude,f.Size.Y.Offset);f.Rotation=math.deg(math.atan2(d.Y,d.X))
 end
 local function connect(i,j)
  if w.done or linked[i] then return end
  for _,v in linked do if v==j then return end end
  if order[j]~=i then
   self:_Sound('bad',nil,.3,1.4);ring(R[j],RED,0,2)
   task.delay(.35,function()if R[j].Parent then ring(R[j],INK,.7) end end)
   return
  end
  linked[i]=j;answer[i]=j;select(nil);dragging=false;drag.Visible=false
  ring(L[i],INK,.4);ring(R[j],INK,.4)
  W[i].Visible=true
  self:_Sound('flip',nil,.4,1.3)
  status.Text=count()..' / 4 connected'
  if count()>=4 then self:_Success(w,answer) end
 end
 for i=1,4 do
  w.scope:Add(L[i].InputBegan:Connect(function(input)
   if not pressed(input) or w.done or linked[i] then return end
   select(i);dragging=input.UserInputType==Enum.UserInputType.MouseButton1
  end))
  w.scope:Add(R[i].Activated:Connect(function()if sel then connect(sel,i) end end))
  w.scope:Add(R[i].MouseButton1Up:Connect(function()if sel and dragging then connect(sel,i) end end))
 end
 -- let go anywhere else: the wire stays picked, so a tap on its plug still finishes it
 w.scope:Add(UIS.InputEnded:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 then task.defer(function()dragging=false;drag.Visible=false end) end
 end))
 w.scope:Add(RunService.RenderStepped:Connect(function()
  for i,j in linked do place(W[i],endPoint(L[i],true),endPoint(R[j],false)) end
  if sel and dragging then
   drag.Visible=true;drag.BackgroundColor3=L[sel].Plug.BackgroundColor3
   -- (the mouse is in whole-screen pixels; GUI pixels start under the top bar, and the screen's own
   -- AbsolutePosition is exactly that offset, so adding it lines the two up on every device)
   local m=UIS:GetMouseLocation()+w.gui.AbsolutePosition
   place(drag,endPoint(L[sel],true),Vector2.new(m.X,m.Y))
  elseif drag.Visible then drag.Visible=false end
 end))
end
------------------------------------------------ DIALS
function Controller:_JobDials(w,body)
 local di=body.Dials;di.Visible=true
 w.hint.Text='Bring each pump needle into its green band, then lock the settings.'
 local targets={};for n in string.gmatch((self._f and self._f.floor:GetAttribute('DialTargets')) or '50,50,50','%d+')do table.insert(targets,tonumber(n)) end
 local tol=Config.DialTolerance
 local vals={}
 local lock=di.Lock
 local function inZone()for k=1,3 do if math.abs(vals[k]-targets[k])>tol-1 then return false end end;return true end
 for k=1,3 do
  local col=di['Dial'..k];local g=col.Gauge;local needle=g.Needle;local num=col.Value
  vals[k]=(targets[k]+50+math.random(15,30))%100
  g.Zone.Position=UDim2.fromScale(0,1-targets[k]/100);g.Zone.Size=UDim2.new(1,0,tol*2/100,0)
  needle.Position=UDim2.fromScale(.5,1-vals[k]/100)
  dragger(w,g,function(d)vals[k]=math.clamp(vals[k]-d.Y/math.max(1,g.AbsoluteSize.Y)*100,0,100) end)
  repeater(w,col.Up,function()vals[k]=math.clamp(vals[k]+1,0,100) end)
  repeater(w,col.Down,function()vals[k]=math.clamp(vals[k]-1,0,100) end)
  w.scope:Add(RunService.RenderStepped:Connect(function(dt)
   needle.Position=needle.Position:Lerp(UDim2.fromScale(.5,1-vals[k]/100),1-math.exp(-math.min(dt,.1)*18))
   local good=math.abs(vals[k]-targets[k])<=tol-1
   needle.BackgroundColor3=good and GREEN or INK
   num.Text=string.format('%d PSI',math.floor(vals[k]*1.2))
   num.TextColor3=good and GREEN or INK
  end))
 end
 w.scope:Add(RunService.RenderStepped:Connect(function()
  local ok=inZone();lock.TextColor3=ok and GREEN or MUTED;lock.UIStroke.Color=ok and GREEN or INK
 end))
 w.scope:Add(lock.Activated:Connect(function()
  if w.done then return end
  if inZone() then self:_Success(w,{vals[1],vals[2],vals[3]}) else self:_Sound('bad',nil,.35,1.3) end
 end))
end
------------------------------------------------ RADIO
function Controller:_JobRadio(w,body)
 local ra=body.Radio;ra.Visible=true
 local target=(self._f and self._f.floor:GetAttribute('RadioFrequency')) or 104.7
 w.hint.Text=string.format('Tune to %.1f FM and hold it there.',target)
 local disp,band,cursor,meter,holdLbl=ra.Display,ra.Band,ra.Band.Cursor,ra.Signal,ra.Hold
 local bars={};for i=1,32 do bars[i]=ra.Wave['Bar'..i] end
 disp.TextColor3=GOLD;holdLbl.Text=''
 local freq=92+math.random()*4
 local held=0
 local hum=self:_Sound('static',nil,0,1,true);hum.Looped=true
 w.scope:Add(function()if hum.Parent then hum:Destroy() end end)
 dragger(w,band,function(d)freq=math.clamp(freq+d.X/math.max(1,band.AbsoluteSize.X)*20,88,108) end)
 repeater(w,ra.Left,function()freq=math.clamp(freq-.1,88,108) end)
 repeater(w,ra.Right,function()freq=math.clamp(freq+.1,88,108) end)
 w.scope:Add(RunService.RenderStepped:Connect(function(dt)
  if w.done then return end
  cursor.Position=UDim2.fromScale((freq-88)/20,.5)
  disp.Text=string.format('%.1f FM',freq)
  local off=math.abs(freq-target)
  local sig=math.clamp(1-off/3,0,1)
  meter.Text='SIGNAL  '..string.rep('|',math.floor(sig*16))
  hum.Volume=.05+.22*(1-sig)
  local t=os.clock()
  for i,b in bars do
   local clean=math.sin(t*9+i*.5)*.5+.5
   local v=clean*sig+math.random()*(1-sig)
   b.Size=UDim2.new(b.Size.X.Scale,0,0,3+v*58)
   b.BackgroundColor3=sig>.93 and GREEN or INK
   b.BackgroundTransparency=.15+(1-sig)*.45
  end
  if off<=.2 then held+=dt;cursor.BackgroundColor3=GREEN;holdLbl.Text=string.format('hold  %d%%',math.floor(math.min(1,held/1.2)*100)) else held=0;cursor.BackgroundColor3=RED;holdLbl.Text='' end
  if held>=1.2 then disp.TextColor3=GREEN;self:_Success(w,freq) end
 end))
end
------------------------------------------------------------------ lifecycle
function Controller:Start()
 task.spawn(function()
  local scripts=self._player:WaitForChild('PlayerScripts');local module=scripts:WaitForChild('PlayerModule',10)
  if module then local ok,controls=pcall(function()return require(module):GetControls()end);if ok then self._controls=controls end end
 end)
 self._scope:Add(RunService.RenderStepped:Connect(function(dt)local ok,err=pcall(self._Living,self,dt);if not ok and not self._warned then self._warned=true;warn('[ElevatorHorror] Control room: '..tostring(err)) end end))
 -- job windows open when the server hands this crew member a job
 self._scope:Add(self._player:GetAttributeChangedSignal('EHL4Task'):Connect(function()
  local id=self._player:GetAttribute('EHL4Task')
  if id then self:_OpenWindow(id) elseif self._window and not self._window.done then self:_CloseWindow(false) end
 end))
 self._scope:Add(self._player:GetAttributeChangedSignal('EHL4ToastSerial'):Connect(function()
  local t=self._player:GetAttribute('EHL4Toast');if t then self:_ShowToast(t) end
 end))
 CAS:BindAction('BlackwaterL4Task',function(_,state)
  if not self._window then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then self:_CloseWindow(true) end
  return Enum.ContextActionResult.Sink
 end,false,Enum.KeyCode.Backspace,Enum.KeyCode.ButtonB)
 self._scope:Add(function()CAS:UnbindAction('BlackwaterL4Task')end)
 -- leaving the floor (death, results, the lift) closes any open window
 self._scope:Add(RunService.Heartbeat:Connect(function()
  if self._window and self._input:GetContext()~='ActiveFloor' then self:_CloseWindow(true) end
 end))
end
function Controller:Destroy()
 if self._window then self:_CloseWindow(true) end
 if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
