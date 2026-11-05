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
local FONT=Enum.Font.GothamMedium;local MONO=Enum.Font.Code -- (no bold: it doesn't fit the game)
local CYAN=Color3.fromRGB(90,220,255);local GREEN=Color3.fromRGB(90,255,140);local AMBER=Color3.fromRGB(255,176,60);local RED=Color3.fromRGB(255,80,60)
local PANEL=Color3.fromRGB(14,20,24);local INK=Color3.fromRGB(226,232,230)
local WIRE_COLORS={Color3.fromRGB(230,60,50),Color3.fromRGB(60,120,240),Color3.fromRGB(245,205,50),Color3.fromRGB(235,95,205)}
local BREAKER_COLORS={Color3.fromRGB(220,60,50),Color3.fromRGB(240,190,50),Color3.fromRGB(80,200,100),Color3.fromRGB(70,140,230),Color3.fromRGB(220,220,210)}
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
 -- HUD: job list, restart bar, toast, radio subtitle (one ScreenGui)
 local sg=make('ScreenGui',{Name='ControlRoomHud',ResetOnSpawn=false,IgnoreGuiInset=true,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=4,Enabled=true},self._gui)
 self._hud=sg;self._scope:Add(sg)
 -- job list (left)
 local list=make('Frame',{Name='JobList',AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,-320,.42,0),Size=UDim2.fromOffset(300,232),BackgroundColor3=PANEL,BackgroundTransparency=.18,Visible=false},sg)
 corner(list,10);stroke(list,CYAN,1.2)
 label(list,'JOBS',{Size=UDim2.new(1,-24,0,26),Position=UDim2.fromOffset(14,8),TextXAlignment=Enum.TextXAlignment.Left,TextSize=17,TextColor3=CYAN,Font=Enum.Font.GothamBlack})
 self._listCount=label(list,'0/5',{Size=UDim2.new(0,60,0,26),Position=UDim2.new(1,-74,0,8),TextXAlignment=Enum.TextXAlignment.Right,TextSize=16,TextColor3=CYAN})
 local bar=make('Frame',{Position=UDim2.fromOffset(14,38),Size=UDim2.new(1,-28,0,4),BackgroundColor3=Color3.fromRGB(40,56,62),BorderSizePixel=0},list);corner(bar,2)
 self._listBar=make('Frame',{Size=UDim2.fromScale(0,1),BackgroundColor3=GREEN,BorderSizePixel=0},bar);corner(self._listBar,2)
 self._rows={}
 for i,j in Config.Jobs do
  local row=make('Frame',{Position=UDim2.fromOffset(12,48+(i-1)*36),Size=UDim2.new(1,-24,0,32),BackgroundTransparency=1},list)
  local box=make('Frame',{Size=UDim2.fromOffset(18,18),Position=UDim2.fromOffset(2,7),BackgroundColor3=Color3.fromRGB(30,40,44)},row);corner(box,4);stroke(box,Color3.fromRGB(120,140,140),1)
  local tick=label(box,'',{TextSize=14,TextColor3=Color3.fromRGB(10,20,14),Font=Enum.Font.GothamBlack})
  local t=label(row,j.room..':  '..j.name,{Position=UDim2.fromOffset(28,0),Size=UDim2.new(1,-28,1,0),TextXAlignment=Enum.TextXAlignment.Left,TextSize=14,Font=Enum.Font.Gotham})
  self._rows[j.id]={row=row,box=box,tick=tick,text=t,done=false}
 end
 self._list=list
 -- restart bar (bottom centre)
 local rb=make('Frame',{Name='RestartBar',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-110),Size=UDim2.fromOffset(460,58),BackgroundColor3=PANEL,BackgroundTransparency=.15,Visible=false},sg)
 corner(rb,10);stroke(rb,CYAN,1.5)
 self._rbTitle=label(rb,'SYSTEM RESTART',{Position=UDim2.fromOffset(14,6),Size=UDim2.new(1,-28,0,20),TextXAlignment=Enum.TextXAlignment.Left,TextSize=14,TextColor3=CYAN,Font=Enum.Font.GothamBlack})
 self._rbPct=label(rb,'0%',{Position=UDim2.new(1,-90,0,6),Size=UDim2.fromOffset(76,20),TextXAlignment=Enum.TextXAlignment.Right,TextSize=15,Font=MONO})
 local track=make('Frame',{Position=UDim2.fromOffset(14,32),Size=UDim2.new(1,-28,0,14),BackgroundColor3=Color3.fromRGB(30,40,46),BorderSizePixel=0},rb);corner(track,7)
 self._rbFill=make('Frame',{Size=UDim2.fromScale(0,1),BackgroundColor3=CYAN,BorderSizePixel=0},track);corner(self._rbFill,7)
 make('UIGradient',{Color=ColorSequence.new(Color3.new(1,1,1),Color3.fromRGB(170,200,210))},self._rbFill)
 self._restart=rb
 -- toast (top centre, under the task bar)
 local toast=make('TextLabel',{Name='Toast',AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,150),Size=UDim2.fromOffset(560,40),BackgroundColor3=Color3.fromRGB(60,16,14),BackgroundTransparency=.1,TextColor3=Color3.fromRGB(255,220,210),Font=FONT,TextSize=16,TextWrapped=true,Visible=false,Text=''},sg)
 corner(toast,8);stroke(toast,RED,1.2);self._toast=toast
 -- radio subtitle (bottom centre, above the controls)
 local sub=make('Frame',{Name='RadioSubtitle',AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-180),Size=UDim2.fromOffset(640,86),BackgroundColor3=Color3.fromRGB(8,10,10),BackgroundTransparency=.25,Visible=false},sg)
 corner(sub,10);stroke(sub,AMBER,1.2)
 self._subWho=label(sub,'RADIO',{Position=UDim2.fromOffset(16,8),Size=UDim2.new(1,-32,0,18),TextXAlignment=Enum.TextXAlignment.Left,TextSize=13,TextColor3=AMBER,Font=Enum.Font.GothamBlack})
 self._subText=label(sub,'',{Position=UDim2.fromOffset(16,28),Size=UDim2.new(1,-32,1,-36),TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextSize=18,Font=Enum.Font.Gotham})
 self._sub=sub
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
  if l then l.Text=state.done.Upload and 'DATA UPLOAD\n<font color="#5aff8c">LOGS SENT  [OK]</font>\n> _' or (state.stage=='Keycard' and 'DATA UPLOAD\nLOCKED\n> _' or 'DATA UPLOAD\nSECURITY LOGS: 3\n> PRESS E'..(math.floor(now*2)%2==0 and '_' or ' ')) end
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
 if not s.boxes then
  local bg=s.gui:FindFirstChildWhichIsA('Frame') or make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0},s.gui)
  bg:ClearAllChildren();bg.BackgroundColor3=Color3.fromRGB(10,8,4);s.bg=bg
  label(bg,'FLIP THE BREAKERS IN THIS ORDER',{Position=UDim2.fromScale(.02,.02),Size=UDim2.fromScale(.96,.26),TextScaled=true,TextColor3=AMBER,Font=Enum.Font.GothamBlack})
  s.boxes={}
  for k=1,5 do
   local b=make('Frame',{Position=UDim2.fromScale(.04+(k-1)*.192,.34),Size=UDim2.fromScale(.15,.6),BackgroundColor3=Color3.fromRGB(30,30,30),BorderSizePixel=0},bg);corner(b,6)
   local st=make('UIStroke',{Color=AMBER,Thickness=3},b)
   local t=label(b,'?',{TextScaled=true,Font=Enum.Font.GothamBlack,TextColor3=Color3.fromRGB(20,20,20)})
   if k<5 then label(bg,'>',{Position=UDim2.fromScale(.04+(k-1)*.192+.15,.4),Size=UDim2.fromScale(.042,.5),TextScaled=true,TextColor3=AMBER,Font=Enum.Font.GothamBlack}) end
   s.boxes[k]={f=b,s=st,t=t}
  end
 end
 local order=state.order or {}
 for k,box in s.boxes do
  local i=order[k]
  box.t.Text=i and tostring(i) or '?'
  box.f.BackgroundColor3=i and BREAKER_COLORS[i] or Color3.fromRGB(30,30,30)
  local done=state.done.Breakers or k<=state.breakerProgress
  box.s.Color=done and GREEN or (k==state.breakerProgress+1 and (math.floor(now*3)%2==0 and Color3.new(1,1,1) or AMBER) or AMBER)
  box.f.BackgroundTransparency=done and .5 or 0
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
 if not f then self._list.Visible=false;self._restart.Visible=false;self._listShown=nil;self._barShown=nil;return end
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
 local sub=self._sub
 sub.Visible=true;sub.BackgroundTransparency=1
 TweenService:Create(sub,TweenInfo.new(.25),{BackgroundTransparency=.25}):Play()
 self._subWho.Text=(who=='???' and 'RADIO  -  ???') or ('RADIO  -  '..string.upper(who))
 self._subWho.TextColor3=who=='Mercer' and Color3.fromRGB(150,200,255) or AMBER
 self._subText.TextTransparency=style=='faint' and .35 or 0
 self._subText.Font=style=='faint' and Enum.Font.GothamMedium or Enum.Font.Gotham
 task.spawn(function()
  local shown=0;local n=#text
  local t0=os.clock()
  while self._radioSerial==serial and shown<n do
   shown=math.min(n,math.floor((os.clock()-t0)*32))
   local s=string.sub(text,1,shown)
   if style=='glitch' then s=corrupt(s,.12);sub.Position=UDim2.new(.5,math.random(-4,4),1,-180+math.random(-2,2)) end
   self._subText.Text=s
   task.wait(.03)
  end
  if self._radioSerial~=serial then return end
  self._subText.Text=text;sub.Position=UDim2.new(.5,0,1,-180)
  task.wait(math.max(2.5,dur-n/32))
  if self._radioSerial~=serial then return end
  TweenService:Create(sub,TweenInfo.new(.4),{BackgroundTransparency=1}):Play()
  TweenService:Create(self._subText,TweenInfo.new(.4),{TextTransparency=1}):Play()
  task.wait(.42)
  if self._radioSerial==serial then sub.Visible=false;self._subText.TextTransparency=0 end
 end)
end
------------------------------------------------------------------ HUD
function Controller:_Hud(floor,state,dt)
 local context=self._input:GetContext()
 local onFloor=context=='ActiveFloor' and not self._window
 -- job list: slides in during the jobs stage
 local showList=onFloor and state.stage=='Jobs'
 if showList~=self._listShown then
  self._listShown=showList
  if showList then self._list.Visible=true end
  local tw=TweenService:Create(self._list,TweenInfo.new(.45,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=showList and UDim2.new(0,18,.42,0) or UDim2.new(0,-320,.42,0)})
  tw.Completed:Connect(function()if not self._listShown then self._list.Visible=false end end)
  tw:Play()
 end
 self._listCount.Text=state.doneCount..'/'..#Config.Jobs
 self._listBar.Size=self._listBar.Size:Lerp(UDim2.fromScale(state.doneCount/#Config.Jobs,1),math.clamp(dt*8,0,1))
 for id,r in self._rows do
  local done=state.done[id]==true
  if done~=r.done then
   r.done=done
   r.box.BackgroundColor3=done and GREEN or Color3.fromRGB(30,40,44);r.tick.Text=done and '✓' or ''
   r.text.TextColor3=done and Color3.fromRGB(120,200,140) or INK
   if done then
    local flash=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=GREEN,BackgroundTransparency=.4,BorderSizePixel=0},r.row);corner(flash,6)
    TweenService:Create(flash,TweenInfo.new(.7),{BackgroundTransparency=1}):Play();game:GetService('Debris'):AddItem(flash,.8)
    self:_Sound('good',nil,.5)
   end
  end
 end
 -- restart bar
 local showBar=onFloor and state.rebootP~=nil
 if showBar~=self._barShown then self._barShown=showBar;self._restart.Visible=showBar end
 if showBar then
  local p=state.rebootP/100
  self._rbFill.Size=self._rbFill.Size:Lerp(UDim2.fromScale(p,1),math.clamp(dt*6,0,1))
  self._rbPct.Text=string.format('%d%%',math.floor(state.rebootP))
  local col=state.rebootNear and CYAN or RED
  self._rbFill.BackgroundColor3=col;self._rbTitle.TextColor3=col
  self._rbTitle.Text=state.rebootNear and 'SYSTEM RESTART  -  STAY CLOSE' or 'SYSTEM RESTART  -  GET BACK TO THE CORE!'
  local s=self._restart:FindFirstChildWhichIsA('UIStroke');if s then s.Color=col end
 end
end
function Controller:_ShowToast(text)
 local t=self._toast;t.Text=text;t.Visible=true;t.BackgroundTransparency=1;t.TextTransparency=1
 TweenService:Create(t,TweenInfo.new(.2),{BackgroundTransparency=.1,TextTransparency=0}):Play()
 self:_Sound('bad',nil,.4,1.1)
 self._toastSerial=(self._toastSerial or 0)+1;local serial=self._toastSerial
 task.delay(3.2,function()if self._toastSerial==serial then local tw=TweenService:Create(t,TweenInfo.new(.35),{BackgroundTransparency=1,TextTransparency=1});tw:Play();tw.Completed:Wait();if self._toastSerial==serial then t.Visible=false end end end)
end
------------------------------------------------------------------ job windows
function Controller:_Remote()
 local net=game.ReplicatedStorage.Game:FindFirstChild('Network')
 return net and net:FindFirstChild('Level4Task')
end
function Controller:_OpenWindow(id)
 if self._window then self:_CloseWindow(false) end
 local job;for _,j in Config.Jobs do if j.id==id then job=j end end
 if not job then return end
 local serial=self._player:GetAttribute('EHL4TaskSerial')
 local w={id=id,serial=serial,scope=Scope.new(),done=false}
 self._window=w
 -- freeze the view and free the pointer while the window is up (same as reading a paper)
 self._player:SetAttribute('EHLoreOpen',true);self._input:SetBlocked('L4Task',true)
 if self._controls then pcall(function()self._controls:Disable() end) end
 local sg=make('ScreenGui',{Name='L4TaskWindow',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=20,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},self._gui)
 w.scope:Add(sg);w.gui=sg
 local dim=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,BorderSizePixel=0},sg)
 TweenService:Create(dim,TweenInfo.new(.25),{BackgroundTransparency=.45}):Play()
 local panel=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.53),Size=UDim2.fromOffset(620,420),BackgroundColor3=PANEL,BackgroundTransparency=.04},sg)
 corner(panel,14);stroke(panel,CYAN,2)
 local vp=workspace.CurrentCamera.ViewportSize
 local target=math.clamp(math.min(vp.X/900,vp.Y/620),.55,1.25)
 local sc=make('UIScale',{Scale=target*.92},panel)
 TweenService:Create(sc,TweenInfo.new(.32,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=target}):Play()
 TweenService:Create(panel,TweenInfo.new(.3,Enum.EasingStyle.Quart),{Position=UDim2.fromScale(.5,.5)}):Play()
 w.panel=panel
 label(panel,string.upper(job.name),{Position=UDim2.fromOffset(22,14),Size=UDim2.new(1,-90,0,28),TextXAlignment=Enum.TextXAlignment.Left,TextSize=22,Font=Enum.Font.GothamBlack,TextColor3=CYAN})
 w.hint=label(panel,'',{Position=UDim2.fromOffset(22,44),Size=UDim2.new(1,-44,0,20),TextXAlignment=Enum.TextXAlignment.Left,TextSize=15,Font=Enum.Font.Gotham,TextColor3=Color3.fromRGB(170,190,190)})
 local close=make('TextButton',{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-14,0,14),Size=UDim2.fromOffset(40,40),BackgroundColor3=Color3.fromRGB(60,24,22),Text='X',Font=Enum.Font.GothamBlack,TextSize=18,TextColor3=Color3.fromRGB(255,200,190),AutoButtonColor=true},panel)
 corner(close,8)
 w.scope:Add(close.Activated:Connect(function()self:_CloseWindow(true) end))
 local body=make('Frame',{Position=UDim2.fromOffset(22,74),Size=UDim2.new(1,-44,1,-96),BackgroundColor3=Color3.fromRGB(8,12,16)},panel)
 corner(body,10);w.body=body
 local build=self['_Job'..id]
 if build then local ok,err=pcall(build,self,w,body);if not ok then warn('[ElevatorHorror] job window: '..tostring(err)) end end
 self:_Sound('beep',nil,.5,1.3)
end
function Controller:_CloseWindow(cancel)
 local w=self._window;if not w then return end
 self._window=nil
 if cancel and not w.done then local r=self:_Remote();if r then r:FireServer('Cancel',w.id,w.serial) end end
 self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('L4Task',false)
 if self._controls then pcall(function()self._controls:Enable() end) end
 local sc=w.panel and w.panel:FindFirstChildWhichIsA('UIScale')
 if sc then TweenService:Create(sc,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=sc.Scale*.9}):Play() end
 task.delay(.2,function()w.scope:Destroy() end)
end
function Controller:_Success(w,answer)
 if w.done then return end
 w.done=true
 local r=self:_Remote();if r then r:FireServer('Done',w.id,w.serial,answer) end
 self:_Sound('good',nil,.6,1)
 local ok=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(10,10),BackgroundColor3=Color3.fromRGB(20,80,40),BackgroundTransparency=.05,ZIndex=50},w.panel)
 corner(ok,14);stroke(ok,GREEN,2)
 label(ok,'✓  DONE',{TextSize=34,Font=Enum.Font.GothamBlack,TextColor3=GREEN,ZIndex=51})
 TweenService:Create(ok,TweenInfo.new(.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(300,110)}):Play()
 task.delay(1,function()if self._window==w then self:_CloseWindow(false) end end)
end
-- a pressable button in the window
local function button(parent,text,pos,size,color)
 local b=make('TextButton',{Position=pos,Size=size,BackgroundColor3=color or Color3.fromRGB(24,70,90),Text=text,Font=Enum.Font.GothamBlack,TextSize=18,TextColor3=INK,AutoButtonColor=true},parent)
 corner(b,8);stroke(b,CYAN,1.2)
 return b
end
-- pointer position in screen pixels (the job window ignores the top-bar inset, so these match its
-- AbsolutePosition)
function Controller:_Pointer()
 local p=UIS:GetMouseLocation();return Vector2.new(p.X,p.Y)
end
------------------------------------------------ UPLOAD
local FILES={'access_log_0412.dat','door_events.csv','cam03_0312.mp4','staff_list.csv','shift_rota.txt','alarm_history.log','VOSS_M.rec','pump_trend_week.csv','mercer_b_notes.txt'}
function Controller:_JobUpload(w,body)
 w.hint.Text='Send the security logs up to the surface. Keep this open until it finishes.'
 local function folder(x,name)
  local f=make('Frame',{Position=UDim2.new(x,-60,0,26),Size=UDim2.fromOffset(120,96),BackgroundTransparency=1},body)
  local ic=make('Frame',{Position=UDim2.fromOffset(20,6),Size=UDim2.fromOffset(80,60),BackgroundColor3=Color3.fromRGB(230,180,70)},f);corner(ic,6)
  make('Frame',{Position=UDim2.fromOffset(20,0),Size=UDim2.fromOffset(36,12),BackgroundColor3=Color3.fromRGB(230,180,70)},f)
  label(f,name,{Position=UDim2.fromOffset(0,70),Size=UDim2.new(1,0,0,22),TextSize=14,Font=MONO})
  return ic
 end
 folder(.2,'LEVEL 4');folder(.8,'SURFACE')
 local lane=make('Frame',{Position=UDim2.new(.2,60,0,58),Size=UDim2.new(.6,-120,0,4),BackgroundColor3=Color3.fromRGB(40,60,70),BorderSizePixel=0},body)
 local file=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(0,.5),Size=UDim2.fromOffset(26,32),BackgroundColor3=INK,Visible=false},lane);corner(file,3)
 local track=make('Frame',{Position=UDim2.new(.08,0,0,150),Size=UDim2.new(.84,0,0,22),BackgroundColor3=Color3.fromRGB(26,36,42)},body);corner(track,11)
 local fill=make('Frame',{Size=UDim2.fromScale(0,1),BackgroundColor3=CYAN},track);corner(fill,11)
 local pct=label(body,'0%',{Position=UDim2.new(.08,0,0,176),Size=UDim2.new(.84,0,0,22),TextSize=16,Font=MONO,TextXAlignment=Enum.TextXAlignment.Right})
 local line=label(body,'Ready.',{Position=UDim2.new(.08,0,0,176),Size=UDim2.new(.7,0,0,22),TextSize=15,Font=MONO,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.fromRGB(150,200,210)})
 local go=button(body,'UPLOAD',UDim2.new(.5,-90,1,-62),UDim2.fromOffset(180,46))
 local running=false
 w.scope:Add(go.Activated:Connect(function()
  if running then return end;running=true;go.Visible=false;file.Visible=true
  local snd=self:_Sound('scroll',nil,.18,1.1,true)
  w.scope:Add(function()if snd.Parent then snd:Destroy() end end)
  local t0=os.clock();local dur=Config.UploadSeconds;local fi=1;local stall=false
  w.scope:Add(RunService.RenderStepped:Connect(function()
   if w.done then return end
   local u=math.clamp((os.clock()-t0)/dur,0,1)
   -- the upload chokes on one file for a moment
   if u>.62 and u<.7 and not stall then stall=true;t0+=1.1;line.Text='<font color="#ff5a46">VOSS_M.rec - FILE NOT FOUND (retrying)</font>';self:_Sound('bad',nil,.35,1.2) end
   fill.Size=UDim2.fromScale(u,1);pct.Text=string.format('%d%%',math.floor(u*100))
   file.Position=UDim2.fromScale((os.clock()*1.4)%1,.5)
   local idx=math.clamp(math.floor(u*#FILES)+1,1,#FILES)
   if idx~=fi and not (u>.62 and u<.72) then fi=idx;line.Text='sending '..FILES[idx]..'...' end
   if u>=1 then line.Text='All logs sent.';if snd.Parent then snd:Stop() end;self:_Success(w,true) end
  end))
 end))
end
------------------------------------------------ WIRES
function Controller:_JobWires(w,body)
 w.hint.Text='Drag each wire on the left to the plug of the same colour.'
 local order={};for n in string.gmatch((self._f and self._f.floor:GetAttribute('WireOrder')) or '1,2,3,4','%d+')do table.insert(order,tonumber(n)) end
 local lefts,rights={},{}
 for i=1,4 do
  local y=24+(i-1)*62
  local l=make('Frame',{Position=UDim2.fromOffset(18,y),Size=UDim2.fromOffset(54,30),BackgroundColor3=WIRE_COLORS[i]},body);corner(l,6);stroke(l,Color3.new(1,1,1),1)
  local r=make('Frame',{AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,y),Size=UDim2.fromOffset(54,30),BackgroundColor3=WIRE_COLORS[order[i]]},body);corner(r,6);stroke(r,Color3.new(1,1,1),1)
  lefts[i]={f=l,linked=nil};rights[i]={f=r,color=order[i]}
 end
 local wires={}
 local function wireFrame(color)
  local f=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(0,10),BackgroundColor3=color,BorderSizePixel=0,ZIndex=5},w.gui);corner(f,5)
  return f
 end
 local function place(f,a,b)
  local d=b-a;f.Position=UDim2.fromOffset((a.X+b.X)/2,(a.Y+b.Y)/2);f.Size=UDim2.fromOffset(d.Magnitude,10);f.Rotation=math.deg(math.atan2(d.Y,d.X))
 end
 local function centre(g,right)return g.AbsolutePosition+Vector2.new(right and 0 or g.AbsoluteSize.X,g.AbsoluteSize.Y/2) end
 local drag
 local answer={}
 for i,l in lefts do
  w.scope:Add(l.f.InputBegan:Connect(function(input)
   if l.linked or w.done then return end
   if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
    drag={i=i,f=wireFrame(WIRE_COLORS[i])};self:_Sound('beep',nil,.3,1.6)
   end
  end))
 end
 w.scope:Add(RunService.RenderStepped:Connect(function()
  if drag then place(drag.f,centre(lefts[drag.i].f,false),self:_Pointer()) end
  for i,wf in wires do place(wf,centre(lefts[i].f,false),centre(rights[lefts[i].linked].f,true)) end
 end))
 w.scope:Add(UIS.InputEnded:Connect(function(input)
  if not drag then return end
  if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
  local p=self:_Pointer();local hitJ
  for j,r in rights do local a,s=r.f.AbsolutePosition,r.f.AbsoluteSize;if p.X>=a.X-14 and p.X<=a.X+s.X+14 and p.Y>=a.Y-14 and p.Y<=a.Y+s.Y+14 then hitJ=j end end
  local d=drag;drag=nil
  if hitJ and rights[hitJ].color==d.i then
   lefts[d.i].linked=hitJ;answer[d.i]=hitJ;wires[d.i]=d.f
   self:_Sound('flip',nil,.4,1.3)
   local n=0;for _ in answer do n+=1 end
   if n>=4 then self:_Success(w,answer) end
  else
   d.f:Destroy();if hitJ then self:_Sound('bad',nil,.3,1.4) end
  end
 end))
end
------------------------------------------------ DIALS
function Controller:_JobDials(w,body)
 w.hint.Text='Drag each pump dial into its green zone, then press LOCK.'
 local targets={};for n in string.gmatch((self._f and self._f.floor:GetAttribute('DialTargets')) or '50,50,50','%d+')do table.insert(targets,tonumber(n)) end
 local tol=Config.DialTolerance
 local vals={}
 local lock=button(body,'LOCK',UDim2.new(.5,-80,1,-58),UDim2.fromOffset(160,44),Color3.fromRGB(40,40,40))
 local function inZone()for k=1,3 do if math.abs(vals[k]-targets[k])>tol-1 then return false end end;return true end
 for k=1,3 do
  vals[k]=(targets[k]+50+math.random(15,30))%100
  local x=.2+(k-1)*.3
  local col=make('Frame',{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(x,0,0,22),Size=UDim2.fromOffset(70,190),BackgroundColor3=Color3.fromRGB(22,30,34)},body);corner(col,10)
  make('Frame',{AnchorPoint=Vector2.new(0,.5),Position=UDim2.fromScale(0,1-targets[k]/100),Size=UDim2.new(1,0,tol*2/100,0),BackgroundColor3=GREEN,BackgroundTransparency=.55,BorderSizePixel=0},col)
  local needle=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,1-vals[k]/100),Size=UDim2.new(1,14,0,6),BackgroundColor3=RED,BorderSizePixel=0,ZIndex=3},col);corner(needle,3)
  local num=label(body,'',{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(x,0,0,216),Size=UDim2.fromOffset(120,20),TextSize=16,Font=MONO})
  label(body,'PUMP '..k,{AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(x,0,0,2),Size=UDim2.fromOffset(120,16),TextSize=13,Font=Enum.Font.GothamBlack,TextColor3=CYAN})
  local dragging=false
  w.scope:Add(col.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true end end))
  w.scope:Add(UIS.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end))
  w.scope:Add(RunService.RenderStepped:Connect(function()
   if dragging and not w.done then
    local p=self:_Pointer();local a,s=col.AbsolutePosition,col.AbsoluteSize
    vals[k]=math.clamp((1-(p.Y-a.Y)/s.Y)*100,0,100)
   end
   needle.Position=needle.Position:Lerp(UDim2.fromScale(.5,1-vals[k]/100),.35)
   local good=math.abs(vals[k]-targets[k])<=tol-1
   needle.BackgroundColor3=good and GREEN or RED
   num.Text=string.format('%d PSI',math.floor(vals[k]*1.2))
  end))
 end
 w.scope:Add(RunService.RenderStepped:Connect(function()
  local ok=inZone();lock.BackgroundColor3=ok and Color3.fromRGB(30,120,60) or Color3.fromRGB(40,40,40)
 end))
 w.scope:Add(lock.Activated:Connect(function()
  if w.done then return end
  if inZone() then self:_Success(w,{vals[1],vals[2],vals[3]}) else self:_Sound('bad',nil,.35,1.3) end
 end))
end
------------------------------------------------ RADIO
function Controller:_JobRadio(w,body)
 local target=(self._f and self._f.floor:GetAttribute('RadioFrequency')) or 104.7
 w.hint.Text=string.format('Slide the tuner to %.1f FM and hold it there.',target)
 local disp=label(body,'',{Position=UDim2.new(.5,-110,0,14),Size=UDim2.fromOffset(220,46),TextSize=34,Font=MONO,TextColor3=AMBER})
 local band=make('Frame',{Position=UDim2.new(.06,0,0,150),Size=UDim2.new(.88,0,0,44),BackgroundColor3=Color3.fromRGB(40,30,14)},body);corner(band,8);stroke(band,AMBER,1)
 for fq=88,108,2 do
  local x=(fq-88)/20
  make('Frame',{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(x,0),Size=UDim2.new(0,2,.4,0),BackgroundColor3=AMBER,BorderSizePixel=0},band)
  label(band,tostring(fq),{AnchorPoint=Vector2.new(.5,0),Position=UDim2.fromScale(x,.45),Size=UDim2.fromOffset(40,18),TextSize=12,Font=MONO,TextColor3=AMBER})
 end
 local cursor=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.1,.5),Size=UDim2.new(0,6,1.4,0),BackgroundColor3=RED,BorderSizePixel=0,ZIndex=3},band);corner(cursor,3)
 -- waveform + signal meter
 local wave={}
 for i=1,28 do wave[i]=make('Frame',{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(.06+.88*(i-.5)/28,0,0,100),Size=UDim2.new(.88/28*.6,0,0,4),BackgroundColor3=GREEN,BorderSizePixel=0},body) end
 local meter=label(body,'SIGNAL',{Position=UDim2.new(.06,0,0,64),Size=UDim2.fromOffset(200,18),TextSize=13,Font=Enum.Font.GothamBlack,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=GREEN})
 local freq=92+math.random()*4
 local dragging=false;local held=0
 local hum=self:_Sound('static',nil,0,1,true);hum.Looped=true
 w.scope:Add(function()if hum.Parent then hum:Destroy() end end)
 w.scope:Add(band.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true end end))
 w.scope:Add(UIS.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end))
 w.scope:Add(RunService.RenderStepped:Connect(function(dt)
  if w.done then return end
  if dragging then local p=self:_Pointer();local a,s=band.AbsolutePosition,band.AbsoluteSize;freq=88+math.clamp((p.X-a.X)/s.X,0,1)*20 end
  cursor.Position=UDim2.fromScale((freq-88)/20,.5)
  disp.Text=string.format('%.1f FM',freq)
  local off=math.abs(freq-target)
  local sig=math.clamp(1-off/3,0,1)
  meter.Text='SIGNAL '..string.rep('|',math.floor(sig*12))
  hum.Volume=.06+.25*(1-sig)
  local t=os.clock()
  for i,b in wave do
   local clean=math.sin(t*9+i*.55)*.5+.5
   local v=clean*sig+math.random()*(1-sig)
   b.Size=UDim2.new(b.Size.X.Scale,0,0,4+v*60)
   b.BackgroundColor3=sig>.93 and GREEN or (sig>.6 and AMBER or Color3.fromRGB(150,160,150))
  end
  if off<=.2 then held+=dt;cursor.BackgroundColor3=GREEN else held=0;cursor.BackgroundColor3=RED end
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
