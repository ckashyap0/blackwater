--!nonstrict
-- LEVEL 3: FILTRATION (R43 rebuild on the shared set-piece systems). Design: vault Floors/Floor 3.md and
-- repo tasks/R43_active_redesign_plan.md.
--   1  Leak     Walking into the dosing room splits drum 9 (beat DrumBurst: gas, beacons). Crank the drum's
--               valve shut in the bund, then pull the extract fan lever.
--   2  Isolate  Three valves on the dosing manifold; their tag colours are shuffled each run and the placard
--               says ferric = orange. The wrong valve gasses the room again (beat WrongLine).
--   3  Beds     The service board by the hall door lists the five running filters in a random order. Close
--               them in that order (each bed air-scours as it shuts). The wrong one makes every bed surge.
--   4  Filter4  Filter 4's console is dead. A cut shows it lift over its weir and the hall starts to flood
--               (Floors.RisingWater). Shut its hand wheel down in the pipe gallery. The black water on the
--               gallery floor sits on the valve unless someone draws it off with a light. If the flood gets too
--               high the crew is pushed back to the passage (Floors.PushBack) and the water drops a stage.
--   5  Bypass   THE SPLIT-UP. The key carrier goes down the one-person hatch and cranks the bypass wheel (three
--               turns); it only moves while the crew keep the header pumped (a Pump job that drains). The
--               intercoms speak under each other's names. When it opens: the grey face at the booth glass.
--   6  Lift     A cut: the clean channel in the office turns black and the panel shows the town main is next.
--               The hall lights die from the far end toward the lift. Marty waits at the passage end.
-- Black water, the light rule and the fumes live in BlackWaterReach. Everything the clients show is published as
-- attributes (floor: stage, timestamps, pressure, Beat_*; player: EHL3*, EHRadio*).
-- Marty: moves between stands only while nobody can see him, never touches the water, hurts nobody.
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level3)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Cinematic=require(game.ReplicatedStorage.Game.Shared.Utilities.Cinematic)
local BlackWater=require(script.Parent.BlackWaterReach)
local Beats=require(script.Parent.BeatRunner)
local Water=require(script.Parent.RisingWater)
local PushBack=require(script.Parent.PushBack)
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local function Ref(root,name)return Refs.Find(root,name)end
local function fx(name,fn)local ok,err=pcall(fn);if not ok then warn('[ElevatorHorror] Level 3 effect failed ('..name..'): '..tostring(err))end end
local Floor={};Floor.__index=Floor
local STAGES=Config.Stages
local H=Config.Holds
local W=Config.Work
local TAGS={{name='ORANGE',color=Color3.fromRGB(214,108,30)},{name='BLUE',color=Color3.fromRGB(46,92,170)},{name='GREEN',color=Color3.fromRGB(52,140,70)}}
function Floor.new(model,number)
 return setmetatable({Model=model,Number=number,_state='Inactive',_stage='Leak',_inlets={},_inletCount=0,_turns=0,
  _valveShut=false,_fanOn=false,_isolated=false,_order={},_orderIdx=1,_f4Shut=false,
  _said={},_queue=setmetatable({},{__mode='k'}),_scope=Scope.new(),_rng=Random.new(),_martyAt=nil},Floor)
end
function Floor:_Now()return workspace:GetServerTimeNow() end
function Floor:_Live()return self._state=='Active' and not self._context.IsSuspended() end
function Floor:_StageIndex()return table.find(STAGES,self._stage) or 1 end
function Floor:_Crew()
 local out={}
 for _,p in self._context.GetPlayers()do
  if typeof(p)=='Instance' and p:IsA('Player') and p:GetAttribute('EHLifeState')=='Alive' and p.Character and p.Character:FindFirstChild('HumanoidRootPart') then table.insert(out,p) end
 end
 return out
end
local function rootOf(p)return p.Character and p.Character:FindFirstChild('HumanoidRootPart')end
local function inside(zone,pos)
 if not zone or not pos then return false end
 local q=zone.CFrame:PointToObjectSpace(pos);local h=zone.Size/2
 return math.abs(q.X)<=h.X and math.abs(q.Y)<=h.Y and math.abs(q.Z)<=h.Z
end
function Floor:_Progress()self._progressAt=os.clock()end
function Floor:_Toast(player,text)
 if typeof(player)=='Instance' then player:SetAttribute('EHL3Toast',text);player:SetAttribute('EHL3ToastSerial',(player:GetAttribute('EHL3ToastSerial') or 0)+1) end
end
function Floor:_Work(id)
 local get=self._context.GetInteractionProgress
 if not get then return 0,1 end
 local p,w=get(id);return p or 0,w or 1
end
function Floor:_SetWork(id,v)local set=self._context.SetInteractionProgress;if set then set(id,v) end end
-- a beat that can play more than once (wrong valve, wrong bed)
function Floor:_Replay(name)if self._beats then self._beats:Reset({name});self._beats:Fire(name) end end
------------------------------------------------------------------ intercom lines
-- One line to one player: who (shown name), face (a user id for a headshot, 0 = none), kind
-- ('Marty' | 'Crew' | 'Old'). Lines to the same player never overlap: a second one waits its turn.
function Floor:_Line(player,who,face,kind,text)
 if self._state=='Stopped' or typeof(player)~='Instance' or not player.Parent then return end
 local t=os.clock();local free=self._queue[player] or 0
 local wait=math.max(0,free-t);local len=2.2+#text*.055
 self._queue[player]=t+wait+len+.4
 task.delay(wait,function()
  if self._state=='Stopped' or not player.Parent then return end
  player:SetAttribute('EHRadioLine',text);player:SetAttribute('EHRadioWho',who);player:SetAttribute('EHRadioFace',face or 0)
  player:SetAttribute('EHRadioKind',kind);player:SetAttribute('EHRadioSeconds',len);player:SetAttribute('EHRadioAt',self:_Now())
 end)
end
function Floor:_Say(targets,who,face,kind,text)for _,p in targets do self:_Line(p,who,face,kind,text) end end
-- Marty over the intercoms and PA (once per key). targets: nil = the whole crew
function Floor:_Marty(key,targets)
 if self._said[key] or self._state=='Stopped' then return end
 local entry=Config.Marty[key];if not entry then return end
 self._said[key]=true
 self.Model:SetAttribute('MartyLine',key);self.Model:SetAttribute('MartyLineAt',self:_Now())
 self:_Say(targets or self:_Crew(),'Marty',0,'Marty',entry.text)
end
function Floor:_Hint(key)
 local text=Config.Hints[key];if not text then return end
 self:_Say(self:_Crew(),'Marty',0,'Marty',text)
end
function Floor:_Knock(refName)
 self.Model:SetAttribute('KnockRef',refName);self.Model:SetAttribute('KnockAt',self:_Now())
end
------------------------------------------------------------------ the key and who is sent
function Floor:_KeyState()
 local key=Ref(self.Model,'BypassKey');local stand=Ref(self.Model,'WheelStand')
 local installed=stand and stand:GetAttribute('EHInstalledItem')==Config.KeyItemId
 local state=key and key:GetAttribute('EHItemState') or 'AtSpawn'
 local carrier=nil
 for _,p in self._context.GetPlayers()do if typeof(p)=='Instance' and p:GetAttribute('EHCarriedItem')==Config.KeyItemId then carrier=p;break end end
 return installed,state,carrier,key
end
function Floor:_Sent()
 local id=self.Model:GetAttribute('SentUserId')
 return id and Players:GetPlayerByUserId(id) or nil
end
function Floor:_SetSent(player)
 local id=player and player.UserId or nil
 if self.Model:GetAttribute('SentUserId')==id then return end
 self.Model:SetAttribute('SentUserId',id)
 for _,p in self._context.GetPlayers()do if typeof(p)=='Instance' then p:SetAttribute('EHL3Sent',p==player and true or nil) end end
end
------------------------------------------------------------------ publish
function Floor:_Pressure()
 if not self._header then return 0 end
 return self._header.progress
end
function Floor:_Publish()
 local m=self.Model;local active=self._state=='Active'
 local T=Config.Text
 local text,sentText,targets='','',{}
 if self._stage=='Leak' then
  if not self._valveShut then text=T.LeakValve;targets={'BundValve'} else text=T.LeakFan;targets={'FanStarter'} end
 elseif self._stage=='Isolate' then text=T.Isolate;targets={'IsoValve1','IsoValve2','IsoValve3'}
 elseif self._stage=='Beds' then
  text=string.format(T.Beds,self._orderIdx-1);targets={'ServiceBoard'}
  local nxt=self._order[self._orderIdx];if nxt then table.insert(targets,'FilterConsole'..nxt) end
 elseif self._stage=='Filter4' then text=T.Filter4;targets={'F4HandWheel'}
 elseif self._stage=='Bypass' then
  local installed,state,carrier=self:_KeyState()
  local h=self._header
  if not installed and not carrier then
   text=state=='Dropped' and T.KeyDropped or T.KeyOnHook;sentText=text;targets={'BypassKey'}
  else
   if not h or h.progress<=0 then text=T.CrewStart
   elseif h.near or h.latched then text=string.format(T.CrewHold,math.floor(h.progress))
   else text=string.format(T.CrewAway,math.floor(h.progress)) end
   if not installed then sentText=self._occupant and T.SentKey or T.SentAbove
   else sentText=string.format(T.SentWheel,self._turns) end
   targets={'HeaderConsole',installed and 'BypassWheel' or (self._occupant and 'WheelStand' or 'ChamberHatch')}
  end
 else text=T.Lift;sentText=T.Lift;targets={'ControlBox'} end
 if self._state=='Completed' then text=T.Lift;sentText=T.Lift;targets={'ControlBox'} end
 local enable=self._context.SetInteractionEnabled
 if enable then
  local st=self._stage
  enable('BW3BundValve',active and st=='Leak' and not self._valveShut)
  enable('BW3FanLever',active and st=='Leak' and self._valveShut and not self._fanOn)
  for i=1,3 do enable('BW3Iso'..i,active and st=='Isolate') end
  for _,i in Config.Beds.Running do enable('BW3Bed'..i,active and st=='Beds' and not self._inlets[i]) end
  enable('BW3F4Wheel',active and st=='Filter4' and not self._f4Shut)
  enable('BW3Header',active and st=='Bypass')
  enable('BW3Wheel',active and st=='Bypass' and self._turns<Config.Wheel.Turns)
  enable('BW3HatchDown',(active or self._state=='Completed') and (st=='Bypass' or st=='Lift') and not self._occupant)
  enable('BW3HatchUp',self._occupant~=nil and not self._greyRunning)
  enable(Config.KeyItemId,active and st=='Bypass')
 end
 m:SetAttribute('TaskText',text);m:SetAttribute('TaskTextSent',sentText~='' and sentText or text)
 m:SetAttribute('TaskTargets',table.concat(targets,','));m:SetAttribute('TaskTarget',targets[1] or '')
 m:SetAttribute('TaskCount',#STAGES);m:SetAttribute('TaskIndex',self:_StageIndex())
 m:SetAttribute('TaskActive',active or self._state=='Completed');m:SetAttribute('Stage',self._stage)
 m:SetAttribute('InletsClosed',self._inletCount);m:SetAttribute('WheelTurns',self._turns)
 m:SetAttribute('TaskRevision',(m:GetAttribute('TaskRevision') or 0)+1)
end
function Floor:_SetStage(stage)
 if self._stage==stage then return end
 self._stage=stage;self:_Progress();self._lastHint=nil
 local m=self.Model;m:SetAttribute('Stage'..stage..'At',self:_Now())
 if stage=='Isolate' then self:_Marty('B2')
 elseif stage=='Beds' then self:_Marty('C1')
 elseif stage=='Filter4' then self:_StartFlood()
 elseif stage=='Bypass' then self:_Marty('D1')
 elseif stage=='Lift' then
  -- every bed and the gallery rest further out for the walk back
  self._water:SetRestWhere(function(r)return r.folder:GetAttribute('Bed')~=nil end,Config.Light.LiftRestBed)
  self._water:SetRestWhere(function(r)return r.folder:GetAttribute('Zone')=='Gallery' end,Config.Light.LiftRestGallery)
 end
 if self._context.SetStatus then self._context.SetStatus(stage=='Lift' and 'GO DOWN' or 'LEVEL 3') end
 self:_Publish()
end
------------------------------------------------------------------ 1 leak
function Floor:_ShutBundValve()
 if self._valveShut then return end
 self._valveShut=true;self:_Progress()
 self.Model:SetAttribute('BundValveShutAt',self:_Now())
 self:_Marty('B1')
 self:_Publish()
end
function Floor:_StartFan()
 if self._fanOn then return end
 self._fanOn=true
 local m=self.Model
 m:SetAttribute('ExtractFanAt',self:_Now())
 task.delay(Config.Fumes.FanSpinUp+Config.Fumes.ThinSeconds*.6,function()if self._state~='Stopped' then m:SetAttribute('FumesActive',false) end end)
 fx('pilot',function()local pilot=Ref(m,'FanPilot');if pilot then pilot.Color=Color3.fromRGB(90,255,120);local li=pilot:FindFirstChildWhichIsA('Light');if li then li.Color=pilot.Color end end end)
 self:_SetStage('Isolate')
end
------------------------------------------------------------------ 2 isolate
function Floor:_Turned(i)
 if i==self._ferric then
  self._isolated=true;self.Model:SetAttribute('FerricShutAt',self:_Now())
  self:_SetStage('Beds')
  return
 end
 -- the wrong line: the valve springs back and the room fills again
 local m=self.Model
 self:_Replay('WrongLine')
 m:SetAttribute('FumesActive',true);m:SetAttribute('ExtractFanAt',self:_Now())
 for _,p in self:_Crew()do self:_Toast(p,Config.Text.WrongLine) end
 task.delay(.8,function()if self._state~='Stopped' then self:_SetWork('BW3Iso'..i,0) end end)
 task.delay(Config.Gas.WrongSurgeSeconds,function()if self._state~='Stopped' then m:SetAttribute('FumesActive',false) end end)
end
------------------------------------------------------------------ 3 beds
function Floor:_WriteBoard()
 local board=Ref(self.Model,'ServiceBoard');local label=board and board:FindFirstChild('Label',true)
 if not label then return end
 local th={'1st','2nd','3rd','4th','5th'}
 local lines={'<b>FILTERS - SHUTDOWN ORDER</b>',''}
 for k,i in self._order do table.insert(lines,th[k]..'   Filter '..i) end
 table.insert(lines,'');table.insert(lines,'F4 OUT OF SERVICE. DO NOT TOUCH.')
 label.Text=table.concat(lines,'\n')
end
function Floor:_CloseBed(i,player)
 if self._inlets[i] then return end
 if self._order[self._orderIdx]~=i then
  -- the wrong filter: every bed surges and the black water lunges up the drains for a while
  self:_Replay('BedSurge')
  self:_Toast(player,Config.Text.WrongBed)
  local surge=Config.Beds.Surge
  for b=1,6 do local r=self._water:Get(b);if r then self._water:SetRest(b,r.rest+surge) end end
  task.delay(Config.Beds.SurgeSeconds,function()
   if self._state=='Stopped' then return end
   for b=1,6 do local r=self._water:Get(b);if r then self._water:SetRest(b,math.max(0,r.rest-surge)) end end
  end)
  return
 end
 self._inlets[i]=true;self._inletCount+=1;self._orderIdx+=1;self:_Progress()
 self.Model:SetAttribute('Inlet'..i..'ClosedAt',self:_Now())
 self._water:SetRest(i,Config.Light.InletRest)
 fx('console',function()
  local m=self.Model
  local lever=Ref(m,'ConsoleLever'..i);local model=lever and lever.Parent
  if model and model:IsA('Model') then model:PivotTo(model:GetPivot()*CFrame.Angles(math.rad(-56),0,0)) end
  local pilot=Ref(m,'ConsolePilot'..i)
  if pilot then pilot.Color=Color3.fromRGB(255,60,50);local li=pilot:FindFirstChildWhichIsA('Light');if li then li.Color=pilot.Color end end
 end)
 if self._inletCount==3 then self:_Marty('C3') end
 if self._inletCount>=#Config.Beds.Running then self:_SetStage('Filter4') else self:_Publish() end
end
------------------------------------------------------------------ 4 filter 4 and the flood
function Floor:_StartFlood()
 local m=self.Model
 fx('console4',function()
  local c=Ref(m,'FilterConsole4');local label=c and c.Parent and c.Parent:FindFirstChild('Label',true)
  for _,d in m:GetDescendants() do
   if d:IsA('TextLabel') and d.Text:find('FILTER 4') and d.Parent and d.Parent:IsA('SurfaceGui') and d:FindFirstAncestor('FilterConsole4') then d.Text='FILTER 4  NO POWER';d.TextColor3=Color3.fromRGB(220,80,60) end
  end
 end)
 self._beats:Fire('Filter4Surge')
 task.delay(Cinematic.LEAD+5.5,function()if self._state~='Stopped' then self:_Marty('E1') end end)
 if self._flood then
  self._floodStage=2;self._flood:ToStage(2,Config.Flood.FirstSeconds)
  self._floodNext=os.clock()+Config.Flood.FirstSeconds+Config.Flood.StageSeconds
 end
end
function Floor:_FloodStep()
 local f=self._flood;if not f or self._stage~='Filter4' or self._f4Shut then return end
 if self._floodNext and os.clock()>=self._floodNext and not self._pushing then
  self._floodStage=math.min((self._floodStage or 1)+1,#f.Stages)
  f:ToStage(self._floodStage,Config.Flood.StageSeconds*.8)
  self._floodNext=os.clock()+Config.Flood.StageSeconds
 end
end
function Floor:_FloodFailed()
 if self._state=='Stopped' or self._pushing or self._f4Shut then return end
 self._pushing=true
 local cp=Ref(self.Model,'L3Checkpoint')
 PushBack.Run(self:_Crew(),cp,{onMoved=function()
  if self._state=='Stopped' then return end
  self._said.E2=nil;self:_Marty('E2')
  self._floodStage=Config.Flood.DropTo
  self._flood:ToStage(self._floodStage,3)
  self._floodNext=os.clock()+Config.Flood.StageSeconds
  self._pushing=false
 end})
end
-- the black water on the gallery floor sits on the Filter 4 valve unless something draws it away
local function headPoint(r)
 local s=math.clamp(r.folder:GetAttribute('Head') or 0,0,r.length)
 for i=2,#r.pts do
  if s<=r.cum[i] then local a,b=r.pts[i-1],r.pts[i];local seg=r.cum[i]-r.cum[i-1];return a:Lerp(b,seg>0 and (s-r.cum[i-1])/seg or 0) end
 end
 return r.pts[#r.pts]
end
function Floor:_F4Stalled()
 local wheel=Ref(self.Model,'F4HandWheel');if not wheel or not self._water then return false end
 for _,r in self._water._reaches do
  if r.folder:GetAttribute('Zone')=='Gallery' then
   local p=headPoint(r)
   -- the film covers everything from the drain to its head: near any part of it counts
   for k=0,8 do
    local q=r.pts[1]:Lerp(p,k/8)
    if (Vector3.new(q.X,0,q.Z)-Vector3.new(wheel.Position.X,0,wheel.Position.Z)).Magnitude<Config.Flood.StallDistance then return true end
   end
  end
 end
 return false
end
function Floor:_ShutF4()
 if self._f4Shut then return end
 self._f4Shut=true;self:_Progress()
 self.Model:SetAttribute('F4ShutAt',self:_Now())
 if self._flood then self._flood:ToStage(1,Config.Flood.DrainSeconds) end
 self:_Marty('E3')
 task.delay(4,function()if self._state~='Stopped' then self:_SetStage('Bypass') end end)
end
------------------------------------------------------------------ 5 bypass
function Floor:_HeaderStep(dt)
 if self._stage~='Bypass' then return end
 local p,w=self:_Work('BW3Header')
 local h=self._header or {progress=0,near=false,latched=false,last=0}
 self._header=h
 local before=math.floor(h.progress)
 local pct=math.clamp(p/w*100,0,100)
 -- a crew of one: once the header reaches what the wheel needs it stays there
 if not h.latched and #self:_Crew()<=1 and pct>=Config.Header.WheelNeeds then h.latched=true;self.Model:SetAttribute('HeaderLatched',true) end
 if h.latched and p<w then self:_SetWork('BW3Header',w);pct=100 end
 h.near=pct>h.progress+.05 or (h.near and pct>=h.progress-.01 and os.clock()-h.last<1.3)
 if pct>h.progress+.05 then h.last=os.clock() end
 h.progress=pct
 local m=self.Model
 if pct>0 and not m:GetAttribute('HeaderStartedAt') then m:SetAttribute('HeaderStartedAt',self:_Now()) end
 m:SetAttribute('HeaderPressure',math.floor(pct*10)/10);m:SetAttribute('HeaderHeld',h.near or h.latched==true)
 if math.floor(pct)~=before then self:_Publish() end
end
function Floor:_WheelStep()
 if self._stage~='Bypass' then return end
 local p=self:_Work('BW3Wheel')
 local turns=math.floor(p+1e-4)
 while self._turns<math.min(turns,Config.Wheel.Turns) do self:_TurnWheel(self._occupant or self:_Sent()) end
end
function Floor:_TurnWheel(player)
 self._turns+=1;self:_Progress()
 local m=self.Model;local t=self:_Now()
 m:SetAttribute('WheelTurn'..self._turns..'At',t)
 if self._turns==2 then
  m:SetAttribute('ChamberLampOffAt',t+1.2);m:SetAttribute('HB3OffAt',t+1.2)
  fx('lamps',function()
   task.delay(1.2,function()
    for _,n in {'ChamberLamp','HB3'} do
     local lamp=Ref(m,n);local li=lamp and lamp:FindFirstChildWhichIsA('Light');if li then li.Enabled=false end
     if lamp then lamp.Material=Enum.Material.Glass;lamp.Color=Color3.fromRGB(70,64,54) end
    end
   end)
  end)
 end
 if self._turns>=Config.Wheel.Turns and player then
  m:SetAttribute('BypassOpenAt',t);m:SetAttribute('GreyFaceAt',t+Config.Grey.Delay)
  self._greyRunning=true;self._greyFor=player
  task.delay(Config.Grey.Delay+Config.Grey.LineAt,function()if self._state~='Stopped' and player.Parent then self:_Marty('F1',{player}) end end)
  task.delay(Config.Grey.Delay+Config.Grey.End,function()
   if self._state=='Stopped' then return end
   self._greyRunning=false;self._greyDoneAt=os.clock()
   local ok,code=self._context.CompleteObjective()
   if not ok then warn('[ElevatorHorror] Level 3 objective: '..tostring(code)) end
   if ok then self._state='Completed' end
   self:_SetStage('Lift');self:_Publish()
  end)
 end
 self:_Publish()
end
------------------------------------------------------------------ 6 the payoff and the walk out
function Floor:_Payoff()
 if self._paid then return end
 self._paid=os.clock()
 self._beats:Fire('ClearWaterTurns')
 fx('mimic',function()
  local panel=Ref(self.Model,'MimicPanel');local g=panel and panel:FindFirstChild('Mimic')
  if not g then return end
  local function lamp(name,c)local f=g:FindFirstChild(name);local l=f and f:FindFirstChild('Lamp');if l then l.BackgroundColor3=c end end
  task.delay(Cinematic.LEAD+1.5,function()
   lamp('Filters',Color3.fromRGB(150,30,26));lamp('Bypass',Color3.fromRGB(230,150,40));lamp('Tank',Color3.fromRGB(230,150,40))
   local l1=g:FindFirstChild('Line1');if l1 then l1.BackgroundColor3=Color3.fromRGB(20,22,22) end
   local lb=g:FindFirstChild('LineBypass');if lb then lb.BackgroundColor3=Color3.fromRGB(20,22,22) end
   local l2=g:FindFirstChild('Line2');if l2 then l2.BackgroundColor3=Color3.fromRGB(20,22,22) end
   -- the route the water takes now: round the filters, through the bypass, into the clear water tank
   for _,nm in {'LineBypass','LineBypassTank','LineBypassTankUp'} do local f=g:FindFirstChild(nm);if f then f.BackgroundColor3=Color3.fromRGB(230,150,40) end end
  end)
 end)
 task.delay(Cinematic.LEAD+7.4,function()if self._state~='Stopped' then self:_Marty('G1') end end)
 task.delay(Cinematic.LEAD+12,function()if self._state~='Stopped' then self._beats:Fire('LightsDie') end end)
end
------------------------------------------------------------------ the hatch
function Floor:_Ladder(player,down)
 local m=self.Model
 local to=Ref(m,down and 'LadderBottom' or 'LadderTop');if not to then return false,'Unavailable' end
 player:SetAttribute('EHL3LadderDir',down and 'Down' or 'Up');player:SetAttribute('EHL3LadderAt',self:_Now())
 if down then self._occupant=player;player:SetAttribute('EHL3InChamber',true);if self._stage=='Bypass' then self._chamberAt=self._chamberAt or os.clock() end
 else self._leaving=player end
 self:_Publish()
 -- the screen is black for the middle of the climb (FiltrationController); move then
 task.delay(Config.Ladder.Seconds*.5,function()
  local ch=player.Character;local root=ch and ch:FindFirstChild('HumanoidRootPart')
  if root and self._state~='Stopped' then
   local yaw=down and CFrame.Angles(0,math.rad(-90),0) or CFrame.Angles(0,math.rad(180),0)
   ch:PivotTo(CFrame.new(to.Position)*yaw);root.AssemblyLinearVelocity=Vector3.zero
  end
  if not down then
   if self._occupant==player then self._occupant=nil end
   self._leaving=nil;player:SetAttribute('EHL3InChamber',nil)
   if self.Model:GetAttribute('BypassOpenAt') then self._exitAt=self._exitAt or os.clock() end
   self:_Publish()
  end
 end)
 return true,down and 'ClimbedDown' or 'ClimbedUp'
end
------------------------------------------------------------------ Marty
local VIEW_COS=math.cos(math.rad(65))
function Floor:_Seen(point,ignore)
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
 local list={ignore}
 for _,p in Players:GetPlayers()do if p.Character then table.insert(list,p.Character) end end
 params.FilterDescendantsInstances=list;params.RespectCanCollide=true
 for _,p in self:_Crew()do
  local head=p.Character:FindFirstChild('Head');local root=rootOf(p)
  if head and root then
   local d=point-head.Position;local flat=Vector3.new(d.X,0,d.Z);local look=root.CFrame.LookVector
   local inView=flat.Magnitude<4 or Vector3.new(look.X,0,look.Z).Unit:Dot(flat.Unit)>VIEW_COS
   if d.Magnitude<140 and inView then
    local hit=workspace:Raycast(head.Position,d,params)
    if not hit or (hit.Position-point).Magnitude<1 then return true end
   end
  end
 end
 return false
end
function Floor:_StandFrame(name)
 local mk=self._markers and self._markers:FindFirstChild(name);local stand=mk and mk:FindFirstChild('MartyStand')
 if not stand then return nil end
 local look=stand.CFrame.LookVector*Vector3.new(1,0,1)
 local p=Vector3.new(stand.Position.X,stand.Position.Y-stand.Size.Y/2,stand.Position.Z)
 return CFrame.lookAt(p,p+look.Unit),stand
end
function Floor:_MartyTo(where)
 local marty=self._marty;if not marty then return end
 if where==nil then marty.Parent=nil;self._martyAt=nil;return end
 local f=self:_StandFrame(Config.Stands[where]);if not f or not marty.PrimaryPart then return end
 marty:PivotTo(f*marty.PrimaryPart.CFrame:ToObjectSpace(marty:GetPivot()))
 marty:SetAttribute('SpotSerial',(marty:GetAttribute('SpotSerial') or 0)+1)
 marty.Parent=self._markers;self._martyAt=where
end
function Floor:_MartyStep()
 local marty=self._marty;if not marty then return end
 local where=self._martyAt
 local function hidden(standKey)
  local f=self:_StandFrame(Config.Stands[standKey]);if not f then return true end
  return not self:_Seen(f.Position+Vector3.new(0,5.2,0),marty) and not self:_Seen(f.Position+Vector3.new(0,2,0),marty)
 end
 if where=='A' then
  -- he leaves the cross walk once the crew has seen the hall and nobody is looking
  local entered=self._hallAt
  local go=(self._inletCount>=1) or (entered and os.clock()-entered>40) or self:_StageIndex()>=table.find(STAGES,'Filter4')
  if go and hidden('A') then self:_MartyTo(nil) end
 elseif where==nil and self._stage=='Bypass' and not self._martyDone then
  local _,_,carrier=self:_KeyState()
  if not carrier and hidden('B') then self:_MartyTo('B') end
 elseif where=='B' then
  local installed,_,carrier=self:_KeyState()
  if (carrier or installed) and hidden('B') then self._martyDone=true;self:_MartyTo(nil) end
 elseif where==nil and self._stage=='Lift' and self._paid and hidden('D') then
  -- the walk out: he is at the end of the passage, between the crew and the lift
  self:_MartyTo('D')
 end
 local talk=marty:FindFirstChild('MartyTalk')
 if talk then
  local on=self._martyAt=='B' and self._stage=='Bypass'
  if talk:GetAttribute('EHInteractionEnabled')~=on then talk:SetAttribute('EHInteractionEnabled',on) end
 end
end
------------------------------------------------------------------ the imitation
function Floor:_Others(sent)
 local out={};for _,p in self:_Crew()do if p~=sent then table.insert(out,p) end end;return out
end
function Floor:_Imitate(key,sent)
 if self._said[key] or not sent or not sent.Parent then return end
 self._said[key]=true
 local R=Config.Radio
 local others=self:_Others(sent)
 local solo=#others==0
 if not self._voices then
  local a=others[1] and others[self._rng:NextInteger(1,#others)] or sent
  local b=a
  if #others>1 then repeat b=others[self._rng:NextInteger(1,#others)] until b~=a end
  self._voices={a,b}
 end
 local v1,v2=self._voices[1],self._voices[2]
 if not v1.Parent then v1=sent end;if not v2.Parent then v2=v1 end
 local function crew(p,entry)self:_Line(sent,p.DisplayName,p.UserId,'Crew',entry.text)end
 if key=='S1' then if solo then crew(sent,R.SoloS1) else crew(v1,R.S1) end
 elseif key=='S2' then if solo then self:_Line(sent,R.SoloS2.who,0,'Old',R.SoloS2.text) else crew(v2,R.S2) end
 elseif key=='S3' then if solo then self:_Line(sent,R.SoloS3.who,0,'Old',R.SoloS3.text) else crew(v1,R.S3) end
 elseif key=='S4' then crew(solo and sent or v1,R.S4)
 elseif key=='K1' or key=='K2' or key=='K3' then
  if not solo then self:_Say(others,sent.DisplayName,sent.UserId,'Crew',R[key].text) end
 elseif key=='R1' then
  self:_Say(self:_Crew(),sent.DisplayName,sent.UserId,'Crew',R.R1.text)
  task.delay(4,function()if self._state~='Stopped' then self:_Knock('GalleryKnock') end end)
 end
end
function Floor:_RadioStep()
 local m=self.Model;local t=os.clock()
 local sent=self._greyFor or self._occupant or self:_Sent()
 if self._chamberAt and self._occupant then
  local e=t-self._chamberAt
  if e>=10 then self:_Imitate('S1',self._occupant) end
  if e>=14 then self:_Imitate('K1',self._occupant) end
 end
 local function since(attr)local at=m:GetAttribute(attr);return at and (self:_Now()-at) or nil end
 local t1,t2,g=since('WheelTurn1At'),since('WheelTurn2At'),since('GreyFaceAt')
 if sent then
  if t1 and t1>=2 then self:_Imitate('S2',sent) end
  if t1 and t1>=6 then self:_Imitate('K2',sent) end
  if t2 and t2>=2 then self:_Imitate('S3',sent) end
  if t2 and t2>=6 then self:_Imitate('K3',sent) end
  local G=Config.Grey
  if g and g>=G.Hold+G.Dark+G.Empty+.5 then self:_Imitate('S4',sent) end
  -- the reveal: the sent player is back with the crew and the intercom still begs in their name
  if self._exitAt and not self._said.R1 then
   local root=rootOf(sent);local ready=t-self._exitAt>25
   if root and root.Position.Y>18 then
    local others=self:_Others(sent)
    if #others==0 then ready=true end
    for _,p in others do local r=rootOf(p);if r and (r.Position-root.Position).Magnitude<=20 then ready=true end end
   end
   if ready then self:_Imitate('R1',sent) end
  end
 end
end
------------------------------------------------------------------ prepare
function Floor:Prepare(context)
 assert(not self._context,'Already prepared');self._context=context
 local m=self.Model
 m:SetAttribute('FumesActive',false);m:SetAttribute('HeaderPressure',0);m:SetAttribute('InletsClosed',0);m:SetAttribute('WheelTurns',0)
 self._water=BlackWater.new(m);self._water:Prepare(context)
 self._markers=m:FindFirstChild('MartyMarkers')
 self._marty=self._markers and self._markers:FindFirstChild('Marty')
 if self._marty then self._marty:SetAttribute('TalkSets','L3');self._marty:SetAttribute('NoTurn',true);self:_MartyTo('A') end
 -- this run's puzzles: which valve tag is ferric, and the order the board gives
 local tags={1,2,3}
 for i=3,2,-1 do local j=self._rng:NextInteger(1,i);tags[i],tags[j]=tags[j],tags[i] end
 for i=1,3 do
  local tag=Ref(m,'ValveTag'..i);local t=TAGS[tags[i]]
  if tag then tag.Color=t.color end
  if t.name=='ORANGE' then self._ferric=i end
 end
 self._order=table.clone(Config.Beds.Running)
 for i=#self._order,2,-1 do local j=self._rng:NextInteger(1,i);self._order[i],self._order[j]=self._order[j],self._order[i] end
 self:_WriteBoard()
 -- the flood over the hall
 local zone=Water.All(m)[1]
 if zone then
  self._flood=Water.new(zone,{crew=function()return self:_Crew()end,
   drain=function(p,amount)context.DrainStamina(p,amount)end,
   slow=function(p,mult)context.SetSpeedModifier(p,'L3Flood',mult)end,
   onFail=function()self:_FloodFailed()end})
 end
 -- beats
 self._beats=Beats.new(m,{
  DrumBurst={when={zone='FumeZone'},run=function()
   m:SetAttribute('FumesActive',true)
   task.delay(2.2,function()if self._state~='Stopped' then self:_Marty('B0') end end)
  end},
  WrongLine={when={manual=true}},
  BedSurge={when={manual=true}},
  Filter4Surge={when={manual=true},cinematic='Filter4'},
  ClearWaterTurns={when={manual=true},cinematic='Payoff'},
  LightsDie={when={manual=true}},
 },{crew=function()return self:_Crew()end})
 local function job(id,refName,label,def,can,done)
  def.interactionId=id;def.target=Refs.Get(m,refName);def.label=label;def.allowedRunPhases={FloorActive=true}
  def.canUse=function(player)
   if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
   return can(player)
  end
  def.complete=function(player)
   if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
   local ok,why=can(player);if not ok then return false,why or 'Unavailable' end
   return done(player)
  end
  context.RegisterInteraction(def)
 end
 local function live(stage)return self:_Live() and self._stage==stage end
 -- 1 leak
 job('BW3BundValve','BundValve','SHUT VALVE',{mode='Crank',work=W.BundValve},
  function()return live('Leak') and not self._valveShut,'Unavailable' end,function()self:_ShutBundValve();return true,'Shut' end)
 local starter=Refs.Get(m,'FanStarter')
 starter:SetAttribute('LeverRef','FanLever');starter:SetAttribute('LeverAxis','Z');starter:SetAttribute('LeverDeg',-110)
 job('BW3FanLever','FanStarter','PULL LEVER',{mode='Lever',work=W.FanLever,persist=false},
  function()
   if not live('Leak') or self._fanOn then return false,'Unavailable' end
   if not self._valveShut then return false,'ValveFirst' end
   return true
  end,function()self:_StartFan();return true,'Started' end)
 -- 2 isolate
 for i=1,3 do
  job('BW3Iso'..i,'IsoValve'..i,'CLOSE VALVE',{mode='Crank',work=W.IsoValve},
   function()return live('Isolate'),'Unavailable' end,function()self:_Turned(i);return true,'Turned' end)
 end
 -- 3 beds (Filter 4's console has no power)
 for _,i in Config.Beds.Running do
  job('BW3Bed'..i,'FilterConsole'..i,'CLOSE INLET',{holdDuration=H.Bed},
   function()return live('Beds') and not self._inlets[i],'Unavailable' end,function(p)self:_CloseBed(i,p);return true,'Closed' end)
 end
 -- 4 filter 4 by hand
 job('BW3F4Wheel','F4HandWheel','SHUT FILTER 4',{mode='Crank',work=W.F4Wheel,rate=function()return self:_F4Stalled() and 0 or 1 end},
  function()return live('Filter4') and not self._f4Shut,'Unavailable' end,function()self:_ShutF4();return true,'Shut' end)
 -- 5 bypass: the header pump and the wheel
 job('BW3Header','HeaderConsole','PUMP',{mode='Pump',work=W.Header,sustain=true,decay=Config.Header.Decay,pumpGap=Config.Header.PumpGap,exclusive=false},
  function(player)return live('Bypass') and player~=self._occupant,'Unavailable' end,function()return true,'Pumping' end)
 job('BW3Wheel','BypassWheel','TURN WHEEL',{mode='Crank',work=W.BypassWheel,
   rate=function(player)return (player==self._occupant and self:_Pressure()>=Config.Header.WheelNeeds) and 1 or 0 end},
  function(player)
   if not live('Bypass') or self._turns>=Config.Wheel.Turns then return false,'Unavailable' end
   local installed=self:_KeyState()
   if not installed or player~=self._occupant then return false,'Unavailable' end
   return true
  end,function(player)self:_WheelStep();return true,'Turned' end)
 job('BW3HatchDown','ChamberHatch','CLIMB DOWN',{holdDuration=H.Hatch},function(player)
  if self._occupant or self._leaving then return false,'Busy' end
  if self._stage~='Bypass' and self._stage~='Lift' then return false,'Unavailable' end
  local installed,_,carrier,key=self:_KeyState()
  local keyBelow=key and inside(Ref(m,'ChamberZone'),key.Position)
  local sent=self:_Sent()
  if carrier==player then return true end
  if (installed or keyBelow) and (sent==nil or sent==player) then return true end
  return false,'NeedKey'
 end,function(player)return self:_Ladder(player,true) end)
 job('BW3HatchUp','ChamberLadder','CLIMB UP',{holdDuration=H.Hatch,requiresLineOfSight=false},function(player)
  return player==self._occupant and not self._greyRunning and not self._leaving,'Unavailable'
 end,function(player)return self:_Ladder(player,false) end)
 local key=Refs.Get(m,'BypassKey');local stand=Refs.Get(m,'WheelStand')
 context.RegisterItem(Config.KeyItemId,Config.KeyKind,key,{hold=H.Key,label='TAKE KEY'})
 context.RegisterSocket(Config.KeySocketId,Config.KeyKind,stand,{hold=H.Socket,label='PUT IN KEY'})
 key:SetAttribute('EHInteractionLabel','TAKE KEY');stand:SetAttribute('EHInteractionLabel','PUT IN KEY')
 self._scope:Add(stand:GetAttributeChangedSignal('EHInstalledItem'):Connect(function()
  if stand:GetAttribute('EHInstalledItem')==Config.KeyItemId then
   if self._occupant then self:_SetSent(self._occupant) end
   self:_Progress();self:_Marty('D8',self._occupant and {self._occupant} or nil);self:_Publish()
  end
 end))
 -- readable papers (same reader as the other floors)
 for _,part in m:GetDescendants()do
  local excerpt=part:GetAttribute('LoreExcerpt');local id=part:GetAttribute('LoreId')
  if part:IsA('BasePart') and type(excerpt)=='string' and type(id)=='string' then
   context.RegisterInteraction({interactionId=id,target=part,interactionType='Paper',label='READ PAPER',holdDuration=.3,allowedRunPhases={FloorActive=true},
    canUse=function()return self._state~='Stopped' and not context.IsSuspended(),'Unavailable'end,
    complete=function(player)
     if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
     player:SetAttribute('EHLoreLevel',3)
     player:SetAttribute('EHLoreTitle',part:GetAttribute('LoreTitle') or 'Note');player:SetAttribute('EHLoreAuthor',part:GetAttribute('LoreAuthor') or '')
     player:SetAttribute('EHLoreExcerpt',excerpt);player:SetAttribute('EHLoreBody',part:GetAttribute('LoreBody') or excerpt);player:SetAttribute('EHLoreKind',part:GetAttribute('LoreKind') or 'Paper')
     player:SetAttribute('EHLoreSerial',(player:GetAttribute('EHLoreSerial') or 0)+1);return true,'Read'
    end})
  end
 end
 self:_Publish()
 local acc,slow=0,0
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)
  acc+=dt
  if acc>=Config.Light.Step then
   local step=acc;acc=0;slow+=step
   local ok,err=pcall(self._Step,self,step);if not ok then warn('[ElevatorHorror] Level 3 step: '..tostring(err)) end
   if slow>=.5 then slow=0;local ok2,err2=pcall(self._MartyStep,self);if not ok2 then warn('[ElevatorHorror] Level 3 Marty: '..tostring(err2)) end end
  end
 end))
 self._scope:Add(function()
  if self._flood then self._flood:Stop() end
  for _,p in Players:GetPlayers()do
   for _,a in {'EHL3Sent','EHL3InChamber','EHL3LadderAt','EHL3LadderDir','EHL3Toast','EHRadioLine','EHRadioWho','EHRadioFace','EHRadioKind','EHRadioAt','EHRadioSeconds','EHMartyTalkedL3','EHPushBackAt','EHWading'} do
    if p:GetAttribute(a)~=nil then p:SetAttribute(a,nil) end
   end
  end
 end)
end
function Floor:_Step(dt)
 if self._state~='Active' and self._state~='Completed' then return end
 local m=self.Model
 local live=not self._context.IsSuspended()
 if live then self._water:Step(dt) end
 if self._beats and live then self._beats:Step() end
 if self._flood and live then self._flood:Step(dt);self:_FloodStep() end
 -- who carries the key is the one who is sent (until it sits in the stand)
 if self._stage=='Bypass' then
  local installed,state,carrier=self:_KeyState()
  if not installed then self:_SetSent(carrier or (self._occupant) or nil) end
  local sent=self:_Sent()
  if installed and self.Model:GetAttribute('SentUserId') and not sent then self:_SetSent(nil) end
  local sig=tostring(installed)..state..tostring(carrier and carrier.UserId)..tostring(self._occupant and self._occupant.UserId)
  if sig~=self._keySig then
   if carrier and not self._said.D7 then self:_Marty('D7') end
   self._keySig=sig;self:_Progress();self:_Publish()
  end
 end
 -- the occupant left the chamber some other way (left the game, died)
 local occ=self._occupant
 if occ and not self._leaving then
  local root=occ.Parent and rootOf(occ)
  if not root or occ:GetAttribute('EHLifeState')~='Alive' or not inside(Ref(m,'ChamberZone'),root.Position) then
   local at=occ.Parent and occ:GetAttribute('EHL3LadderAt')
   if not at or self:_Now()-at>Config.Ladder.Seconds+1 then
    if occ.Parent then occ:SetAttribute('EHL3InChamber',nil) end
    self._occupant=nil
    if m:GetAttribute('BypassOpenAt') then self._exitAt=self._exitAt or os.clock() end
    self:_Publish()
   end
  end
 end
 if self._state=='Active' and live then self:_HeaderStep(dt);self:_WheelStep() end
 -- the Filter 4 valve: say why it will not turn
 if self._stage=='Filter4' and not self._f4Shut then
  for _,p in self:_Crew()do
   if p:GetAttribute('EHActiveInteraction')=='BW3F4Wheel' and self:_F4Stalled() and os.clock()-(self._stallToast or 0)>6 then
    self._stallToast=os.clock();self:_Toast(p,Config.Text.Stalled)
    if not self._said.StallHint then self._said.StallHint=true;self:_Hint('Stalled') end
   end
  end
 end
 -- the payoff: once the sent player is back up, or a while after the face
 if self._stage=='Lift' and not self._paid and ((self._exitAt and os.clock()-self._exitAt>1.5) or (self._greyDoneAt and os.clock()-self._greyDoneAt>20)) then self:_Payoff() end
 -- first look at the hall
 if not self._hallAt then
  local zone=Ref(m,'HallEntryZone')
  for _,p in self:_Crew()do local r=rootOf(p);if r and inside(zone,r.Position) then self._hallAt=os.clock();m:SetAttribute('HallEnteredAt',self:_Now());break end end
 end
 if m:GetAttribute('FirstSnuffAt') and not self._said.C2 then self:_Marty('C2') end
 -- arrival lines
 if self._activeAt and self._state=='Active' then
  local e=os.clock()-self._activeAt
  if e>=Config.Marty.A1.at then self:_Marty('A1') end
  if e>=Config.Marty.A2.at and self._stage=='Leak' and not m:GetAttribute('Beat_DrumBurst') then self:_Marty('A2') end
 end
 pcall(self._RadioStep,self)
 -- last line: the first crew member back in the cabin
 if self._stage=='Lift' and not self._said.G2 then
  for _,p in self:_Crew()do
   local r=rootOf(p)
   if r and math.abs(r.Position.X)<8 and r.Position.Z>-7 and r.Position.Z<8 and r.Position.Y>18 and r.Position.Y<35 then self:_Marty('G2');break end
  end
 end
 -- stuck hints
 if self._state=='Active' and self._progressAt and os.clock()-self._progressAt>Config.HintSeconds and os.clock()-(self._lastHint or 0)>Config.HintSeconds then
  self._lastHint=os.clock()
  local key=self._stage
  if key=='Leak' and self._valveShut then key='LeakFan' end
  if key=='Bypass' then
   local installed,_,carrier=self:_KeyState()
   key=(not installed and not carrier) and 'BypassKey' or 'BypassPressure'
   if key=='BypassPressure' and self:_Pressure()>=Config.Header.WheelNeeds then key=nil end
  end
  if key then self:_Hint(key) end
 end
end
function Floor:Activate()
 assert(self._context);self._state='Active';self._activeAt=os.clock();self:_Progress()
 self:_Publish()
 if self._context.SetStatus then self._context.SetStatus('LEVEL 3') end
 -- the doors open onto the landing: a short look out over the filter hall first
 task.delay(.8,function()if self._state=='Active' then Cinematic.Play(self.Model,'Arrival') end end)
end
-- STUDIO ONLY (reached through ElevatorService's ElevatorDebug BindableFunction: "L3:<cmd>")
function Floor:Debug(cmd)
 if not RunService:IsStudio() then return 'StudioOnly' end
 local p=self:_Crew()[1]
 local k,v=string.match(cmd,'^(%w+)=(%w+)$')
 if k=='Stage' and table.find(STAGES,v) then
  local idx=table.find(STAGES,v)
  if idx>1 then self._valveShut=true;self._fanOn=true;self.Model:SetAttribute('FumesActive',false) end
  if idx>2 then self._isolated=true end
  if idx>3 then for _,i in Config.Beds.Running do if not self._inlets[i] then self._inlets[i]=true;self._inletCount+=1;self.Model:SetAttribute('Inlet'..i..'ClosedAt',self:_Now()) end end;self._orderIdx=#self._order+1 end
  if idx>4 then self._f4Shut=true;if self._flood then self._flood:ToStage(1,1) end end
  self:_SetStage(v);return 'Stage '..v
 elseif cmd=='Order' then return table.concat(self._order,',')..' ferric=V'..tostring(self._ferric)
 elseif cmd=='Flood' then if self._flood then self._flood:ToStage(#self._flood.Stages,3) end;return 'Flooding'
 elseif cmd=='F4' then self:_ShutF4();return 'F4 shut'
 elseif cmd=='Payoff' then self:_Payoff();return 'Payoff'
 elseif cmd=='Sent' and p then
  self:_SetStage('Bypass')
  local stand=Refs.Get(self.Model,'WheelStand');stand:SetAttribute('EHInstalledItem',Config.KeyItemId)
  self._header=self._header or {progress=100,near=true,latched=true,last=0};self._header.latched=true
  self:_Ladder(p,true);task.wait(1.2);self:_SetSent(p);return 'Sent '..p.Name
 elseif cmd=='Turn' and p then
  if self._turns<Config.Wheel.Turns then self:_SetWork('BW3Wheel',self._turns+1);self:_WheelStep() end;return 'Turns '..self._turns
 elseif cmd=='Snuff' and p then return tostring(self._water:Snuff(p))
 elseif cmd=='Reveal' and p then self._said.R1=nil;self:_Imitate('R1',p);return 'Reveal'
 elseif cmd=='State' then
  return string.format('stage=%s beds=%d/%s turns=%d pressure=%.0f flood=%s occupant=%s marty=%s',self._stage,self._inletCount,table.concat(self._order,','),self._turns,self:_Pressure(),
   self._flood and string.format('%.1f',self._flood:Rise()) or '-',tostring(self._occupant),tostring(self._martyAt))
 end
 return 'Unknown'
end
function Floor:GetObjectiveSnapshot()return {status=self._state,progress=self:_StageIndex()-1}end
function Floor:OnParticipantStateChanged(snapshot)self._participants=snapshot.participants end
function Floor:Stop()
 self._state='Stopped';self.Model:SetAttribute('TaskActive',false)
 if self._water then pcall(function()self._water:Stop()end) end
 self._scope:Destroy()
end
function Floor:Destroy()self:Stop();self.Model:Destroy()end
return table.freeze(Floor)
