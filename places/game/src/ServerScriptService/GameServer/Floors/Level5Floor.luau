--!nonstrict
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level5)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local TweenService=game:GetService('TweenService')
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Hazards=require(script.Parent.SlipHazards)
-- Operable parts are found by their Ref attribute, never by where they sit in Explorer.
local function Ref(root,name)return Refs.Find(root,name)end
local Floor={};Floor.__index=Floor
-- Gauge readings are re-rolled every round and never repeat the previous round's values on this
-- server (the first round also avoids the old fixed defaults: 50 PSI tank, 122 PSI line).
local lastTankStart,lastLinePressure,lastTankTarget=5,122,30
local function text(part,value)local label=part and part:FindFirstChildWhichIsA('TextLabel',true);if label then label.Text=value end end
-- Cosmetic effects (tweens, sounds, readouts) must never be able to abort a task: progress is
-- committed and published first, then effects run protected.
local function fx(name,fn)local ok,err=pcall(fn);if not ok then warn('[ElevatorHorror] Level 5 effect failed ('..name..'): '..tostring(err))end end
function Floor.new(model,number)return setmetatable({Model=model,Number=number,_state='Inactive',_stage=1,_circuits={},_count=0,_pressure=5,_target=3,_compressor=false,_verified=false,_verifying=false,_scope=Scope.new()},Floor)end
------------------------------------------------------------------ air receiver control module
-- The lift brakes' air receiver is run from a wall-mounted control module beside the old cabinet:
--   1 START COMPRESSOR (heavy toggle switch, amber RUN lamp)
--   2 SET PSI with FILL / RELEASE on the cabinet
--   3 SEAL CHECK (key switch): three status lamps - PRESSURE, VALVES, SEAL - go amber, then green,
--     one after another; changing the pressure afterwards voids the check
--   4 LOCK
-- A green phosphor readout shows the state of every step. (The dev-check fixture keeps the old
-- three-button flow it asserts against: _simplePanel.)
local LAMP_OFF,LAMP_AMBER,LAMP_GREEN,LAMP_RED=Color3.fromRGB(46,24,18),Color3.fromRGB(255,176,60),Color3.fromRGB(90,255,120),Color3.fromRGB(255,70,50)
function Floor:_Lamp(name,color,glow)
 local lamp=Ref(self.Model,name);if not lamp then return end
 lamp.Color=color;lamp.Material=glow and Enum.Material.Neon or Enum.Material.Glass
 local light=lamp:FindFirstChild('Glow');if light then light.Enabled=glow==true;light.Color=color end
end
function Floor:_AirReadout()
 local screen=Ref(self.Model,'AirReadout');local label=screen and screen:FindFirstChildWhichIsA('TextLabel',true)
 if not label then return end
 local function c(t,col)return '<font color="'..col..'">'..t..'</font>' end
 local G,A,R,D='#78E68C','#FFB13C','#FF5A46','#3E7A4C'
 local bar=string.rep('#',self._pressure)..string.rep('.',6-self._pressure)
 local seal=self._verified and c('PASS',G) or self._verifying and c('RUNNING',A) or c('---',D)
 local nextStep
 if self._stage~=4 then nextStep=self._stage>4 and c('RECEIVER LOCKED',G) or c('STANDBY - NO SUPPLY',D)
 elseif not self._compressor then nextStep=c('START COMPRESSOR',A)
 elseif self._pressure~=self._target then nextStep=c('SET RECEIVER TO '..(self._target*10)..' PSI',A)
 elseif not self._verified then nextStep=c(self._verifying and 'CHECKING SEALS...' or 'RUN SEAL CHECK',A)
 else nextStep=c('LOCK RECEIVER',G) end
 label.Text=table.concat({
  'AIR RECEIVER R-2  //  LIFT BRAKES',
  'COMPRESSOR   '..(self._compressor and c('RUNNING',G) or c('OFF',R)),
  'RECEIVER     '..string.format('%3d',self._pressure*10)..' PSI  ['..bar..']',
  'SEAL CHECK   '..seal,
  '> '..nextStep..'_',
 },'\n')
end
function Floor:_ResetSeal()
 self._verified=false;self._verifying=false;self._sealSerial=(self._sealSerial or 0)+1
 self.Model:SetAttribute('SealVerified',false)
 fx('seal reset',function()for _,n in {'LampPressure','LampValves','LampSeal'}do self:_Lamp(n,LAMP_OFF,false)end end)
end
-- The text of task i as players read it (the air tank task names this round's random target).
function Floor:_TaskText(i)
 local step=Config.Tasks[i];if not step then return nil end
 return (string.gsub(step.text,'%%d',tostring(self._target*10)))
end
-- Mechanisms move about their authored pivots (hinges, stems, dial centres) and always make a sound.
local SOUNDS={valve={'rbxassetid://9116644054',.7,.55},lever={'rbxassetid://9119727134',.9,.6},fit={'rbxassetid://9120089122',1,.6}}
function Floor:_Sound(part,key)
 if not part then return end
 local d=SOUNDS[key];local s=part:FindFirstChild('Mechanism_'..key)
 if not s then s=Instance.new('Sound');s.Name='Mechanism_'..key;s.SoundId=d[1];s.PlaybackSpeed=d[2];s.Volume=d[3];s.RollOffMaxDistance=50;s.RollOffMinDistance=6;s.Parent=part end
 s:Play()
end
function Floor:_Swing(part,degrees,seconds,axis)
 if not part then return end
 local pivot=part:GetAttribute('PivotFrame')
 if not pivot then self:_Tween(part,{CFrame=part.CFrame*(axis=='x' and CFrame.Angles(math.rad(degrees),0,0) or CFrame.Angles(0,0,math.rad(degrees)))},seconds);return end
 local offset=pivot:ToObjectSpace(part.CFrame)
 local turn=axis=='x' and CFrame.Angles(math.rad(degrees),0,0) or CFrame.Angles(0,0,math.rad(degrees))
 local target=pivot*turn*offset
 self:_Tween(part,{CFrame=target},seconds)
 -- detail parts riding on the lever (LeverOf = its Ref) swing with it
 local ref=part:GetAttribute('Ref')
 if ref and part.Parent then
  for _,p in part.Parent:GetDescendants()do
   if p:IsA('BasePart') and p~=part and p:GetAttribute('LeverOf')==ref then self:_Tween(p,{CFrame=target*part.CFrame:ToObjectSpace(p.CFrame)},seconds) end
  end
 end
end
-- Needles pivot at the dial centre: angle 0 points straight up.
function Floor:_Needle(needle,degrees,seconds)
 if not needle then return end
 local pivot=needle:GetAttribute('PivotFrame')
 local target=pivot and pivot*CFrame.Angles(0,0,math.rad(degrees))*CFrame.new(0,needle.Size.Y/2,0) or CFrame.new(needle.Position)*CFrame.Angles(0,0,math.rad(degrees))
 self:_Tween(needle,{CFrame=target},seconds)
end
function Floor:_Linkage(name)
 for _,p in self.Model:GetDescendants()do
  local offset=p:IsA('BasePart') and p:GetAttribute('MechanismOf')==name and p:GetAttribute('MoveOffset')
  if offset then self:_Tween(p,{CFrame=p.CFrame+offset},.45)end
 end
end
function Floor:_Available(stage)return self._state=='Active' and self._stage==stage and not self._context.IsSuspended(),'Unavailable'end
function Floor:_Tween(part,properties,seconds)
 if not part then return end
 local tween=TweenService:Create(part,TweenInfo.new(seconds,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),properties)
 self._scope:Add(function()tween:Cancel()end);tween:Play()
end
function Floor:_Target()
 local step=Config.Tasks[self._stage];local target=step and step.target or 'ReturnGuide'
 local targets={target}
 if self._stage==2 then
  local link=Ref(self.Model,'ReplacementLink')
  if link and link:GetAttribute('EHItemState')=='Carried' then target='LinkSocket';targets={target} end
 elseif self._stage==3 then
  -- Outline every circuit still to reset, not just the next one.
  targets={}
  for _,id in Config.SwitchIds do if not self._circuits[id] then table.insert(targets,'Switch'..id)end end
  target=targets[1]or target
 elseif self._stage==4 then
  -- all three panel buttons are outlined for the whole step
  if self._simplePanel then targets={'TankFill','TankBleed','TankLock'}
  elseif not self._compressor then targets={'CompressorSwitch'}
  elseif self._pressure~=self._target then targets={'TankFill','TankBleed'}
  elseif not self._verified then targets={'SealCheck'}
  else targets={'TankLock'} end
  target=targets[1]
 end
 if self.Model:GetAttribute('TaskTarget')~=target then self.Model:SetAttribute('TaskTarget',target)end
 local list=table.concat(targets,',')
 if self.Model:GetAttribute('TaskTargets')~=list then self.Model:SetAttribute('TaskTargets',list)end
end
function Floor:_Publish()
 local step=Config.Tasks[self._stage];local active=self._state=='Active'
 local enable=self._context.SetInteractionEnabled
 if enable then
  enable('BW5Isolation',active and self._stage==1)
  enable('BW5GateRelease',active and self._stage==5)
  for _,id in {'BW5TankFill','BW5TankBleed','BW5TankConfirm'}do enable(id,active and self._stage==4)end
  if not self._simplePanel then
   enable('BW5SealCheck',active and self._stage==4)
   enable('BW5Compressor',active and self._stage==4 and not self._compressor)
  end
  enable(Config.LinkSocketId,active and self._stage==2)
  for _,id in Config.SwitchIds do enable('BW5Switch'..id,active and self._stage==3 and not self._circuits[id])end
 end
 local taskText=step and self:_TaskText(self._stage) or 'Going down to Level 4'
 local link=Ref(self.Model,'ReplacementLink')
 if self._stage==2 and link and link:GetAttribute('EHItemState')=='Carried'then taskText='Put the fuse in the fuse box'end
 self.Model:SetAttribute('TaskText',taskText)
 self.Model:SetAttribute('TaskCount',#Config.Tasks);self.Model:SetAttribute('TaskIndex',self._stage);self.Model:SetAttribute('TaskActive',active or self._state=='Completed');self.Model:SetAttribute('BreakerProgress',self._count)
 self.Model:SetAttribute('TaskRevision',(self.Model:GetAttribute('TaskRevision') or 0)+1);self:_Target()
 fx('terminals',function()self:_Terminals()end)
end
-- The SCADA outstation screens double as the crew's live task list: every finished objective as
-- "[DONE] <task>" and the current one as "[NOW] <task>" (nothing past it is shown).
function Floor:_Terminals()
 local lines={}
 local finished=self._state=='Completed' and #Config.Tasks or math.min(self._stage-1,#Config.Tasks)
 for i=1,finished do table.insert(lines,'> [DONE] '..self:_TaskText(i)) end
 if self._state=='Active' and Config.Tasks[self._stage] then table.insert(lines,'> [NOW] '..self:_TaskText(self._stage)) end
 -- the optional side protocol, filed under the job list in the same flat terminal voice
 local total=self.Model:GetAttribute('SpillsTotal')
 if Config.SideQuest and type(total)=='number' and total>0 then
  local cleared=total-(self.Model:GetAttribute('SpillsRemaining') or total)
  table.insert(lines,'OPTIONAL: PROTOCOL 04 (EFFLUENT ABATEMENT)')
  table.insert(lines,'> '..string.upper(string.format(Config.SideQuest.Counter,cleared,total)))
 end
 self._terminals=self._terminals or {}
 if not self._terminalsScanned then
  self._terminalsScanned=true
  for _,d in self.Model:GetDescendants()do
   if d:IsA('BasePart') and d.Name=='Screen' and d.Parent and d.Parent.Name=='DiagnosticTerminal' then
    local label=d:FindFirstChildWhichIsA('TextLabel',true)
    if label then table.insert(self._terminals,{label=label,header=(label.Text:match('^[^\n]*') or 'BLACKWATER WATER WORKS  LEVEL 5')}) end
   end
  end
 end
 for _,t in self._terminals do
  if t.label.Parent then t.label.Text=t.header..'\nJOBS\n'..table.concat(lines,'\n')..(self._state=='Active' and '\n> _' or '') end
 end
end
function Floor:_Power(id)
 self._circuits[id]=true;self._count+=1;self.Model:SetAttribute('Circuit'..id..'At',workspace:GetServerTimeNow());self.Model:SetAttribute('Circuit'..id,true)
 if self._count==3 then self.Model:SetAttribute('PowerRestored',true);self._stage=4 end
 self:_Publish()
 fx('circuit',function()
  local index=table.find(Config.SwitchIds,id)
  local color=Color3.fromRGB(134,171,117)
  for _,lamp in {Ref(self.Model,'Indicator'..index),self._context.Cabin and Ref(self._context.Cabin,'BreakerIndicator'..index)}do if lamp then lamp.Color=color end end
  -- the breaker handle itself is animated by every client from Circuit<id>At (MechanismController),
   -- so the heavy pull is perfectly smooth instead of stepping along with network updates
  for _,v in self.Model:GetDescendants()do
   if v:GetAttribute('Circuit')==id then
    if v:IsA('Light')then v.Enabled=true
    elseif v:IsA('BasePart')and v:GetAttribute('Diffuser')then v.Material=Enum.Material.Neon;v.Color=Color3.fromRGB(173,187,162)end
   end
  end
  local switch=Ref(self.Model,'Switch'..id);local sound=switch and switch:FindFirstChild('Contactor');if sound then sound:Play()end
 end)
 if self._count==3 then
  fx('supply',function()
   if self._context.RestoreCabinSupply then self._context.RestoreCabinSupply()end
   if self._context.SetStatus then self._context.SetStatus('NEXT: AIR TANK TO '..(self._target*10)..' PSI')end
   self:_AirReadout()
  end)
 end
end
function Floor:TestLift()
 if not self:_Available(6)then return false,'ObjectiveIncomplete'end
 local ok,reason=self._context.CompleteObjective();if not ok then return false,reason end
 self._state='Completed';self._stage=7
 self:_Publish()
 fx('lift',function()
  text(Ref(self.Model,'PanelReadout'),'POWER ON')
  if self._context.SetStatus then self._context.SetStatus('GOING DOWN')end
 end)
 return true,'LiftTested'
end
function Floor:Prepare(context)
 assert(not self._context,'Already prepared');self._context=context
 text(Ref(self.Model,'PanelReadout'),'NO POWER')
 context.RegisterInteraction({interactionId='BW5Isolation',target=Refs.Get(self.Model,'IsolationValve'),interactionType='Panel',label='CLOSE VALVE',holdDuration=2.5,allowedRunPhases={FloorActive=true},
  canUse=function()return self:_Available(1)end,
  complete=function()
   if not self:_Available(1)then return false,'Unavailable'end
   self.Model:SetAttribute('LineIsolated',true);self._stage=2;self:_Publish()
   fx('isolation',function()
    local wheel=Ref(self.Model,'ValveWheel')
    if wheel then
     -- the whole hand wheel (rim and spokes) turns about the stem axis
     local pivot=wheel.CFrame;local turn=CFrame.Angles(0,0,math.rad(165))
     self:_Tween(wheel,{CFrame=pivot*turn},1)
     for _,p in self.Model:GetDescendants()do if p:IsA('BasePart')and p:GetAttribute('RotatesWith')=='ValveWheel'then self:_Tween(p,{CFrame=pivot*turn*pivot:ToObjectSpace(p.CFrame)},1)end end
     self:_Sound(wheel,'valve')
    end
    self:_Needle(Ref(self.Model,'GaugeNeedle'),70,1.4)
    local hiss=Refs.Get(self.Model,'IsolationValve'):FindFirstChild('Pressure');if hiss then self:_Tween(hiss,{Volume=.025},1.2)end
    text(Ref(self.Model,'PressureGauge'),'3 PSI')
   end)
   return true,'Isolated'
  end})
 context.RegisterInteraction({interactionId='BW5GateRelease',target=Refs.Get(self.Model,'GateRelease'),interactionType='Panel',label='OPEN GATE',holdDuration=2,allowedRunPhases={FloorActive=true},
  canUse=function()return self:_Available(5)end,
  complete=function()
   if not self:_Available(5)then return false,'Unavailable'end
   self._stage=6;self.Model:SetAttribute('GateReleased',true);self:_Publish()
   fx('gate',function()
    local gate=Ref(self.Model,'ReturnGate')
    if gate then
     -- Every client slides the gate leaf up into its header from this shared timestamp
     -- (Exponential in/out, 2.4 s, full travel). The server only owns the collision, which
     -- clears once the leaf is above head height.
     self.Model:SetAttribute('ReturnGateOpenedAt',workspace:GetServerTimeNow())
     local motor=self.Model:FindFirstChild('GateMotor',true);if motor then motor:Play()end
     task.delay(1.1,function()if self._state~='Stopped' and gate.Parent then gate.CanCollide=false end end)
    end
    local release=Refs.Get(self.Model,'GateRelease')
    -- (every client animates the pull itself from this timestamp - MechanismController - so it is
    -- frame-smooth; tweening it here only reached players in network-sized steps)
    self.Model:SetAttribute('GateReleaseAt',workspace:GetServerTimeNow());self:_Sound(release,'lever')
    if self._context.SetStatus then self._context.SetStatus('LIFT READY')end
   end)
   return true,'GateReleased'
  end})
 -- The air task is the plain three-button panel again (FILL / RELEASE to the PSI on the task,
 -- then LOCK): no compressor or seal-check steps. The panel itself carries the extra detail.
 -- (The compressor / seal-check code below only runs if a map still has that module.)
 self._simplePanel=true
 local function pressureDisplay()
  self.Model:SetAttribute('TankPressure',self._pressure*10)
  fx('air readout',function()self:_AirReadout()end)
  -- one slim gold plate shows the reading; the target lives only in the objective text
  text(Refs.Get(self.Model,'TankGauge'),tostring(self._pressure*10)..' PSI')
  local reading=Refs.Get(self.Model,'TankGauge'):FindFirstChildWhichIsA('TextLabel',true)
  if reading then reading.TextColor3=self._pressure==self._target and Color3.fromRGB(110,235,120) or Color3.fromRGB(255,176,64) end
  local needle=Ref(self.Model,'TankNeedle')
  self:_Needle(needle,90-self._pressure*30,.35)
 end
 for _,entry in {{'BW5TankFill','TankFill',1,'FILL +10 PSI'},{'BW5TankBleed','TankBleed',-1,'RELEASE -10 PSI'}}do
  context.RegisterInteraction({interactionId=entry[1],target=Refs.Get(self.Model,entry[2]),interactionType='Panel',label=entry[4],holdDuration=.52,quick=true,allowedRunPhases={FloorActive=true}, -- (FILL / RELEASE are quick taps; LOCK stays a deliberate hold)
   canUse=function()
    local ok,r=self:_Available(4);if not ok then return false,r end
    if not self._simplePanel and not self._compressor then return false,'CompressorOff' end
    if self._verifying then return false,'Busy' end
    return true
   end,
   complete=function()
    if not self:_Available(4)then return false,'Unavailable'end
    if not self._simplePanel and not self._compressor then return false,'CompressorOff' end
    self._pressure=math.clamp(self._pressure+entry[3],0,6)
    -- any change after a passed seal check voids it
    if self._verified or self._verifying then self:_ResetSeal() end
    fx('pressure',function()pressureDisplay();local hiss=Refs.Get(self.Model,entry[2]):FindFirstChild('Air');if hiss then hiss:Play()end end)
    fx('pressure lamp',function()self:_Lamp('LampPressure',self._pressure==self._target and LAMP_AMBER or LAMP_OFF,self._pressure==self._target)end)
    self:_Target()
    return true,'Adjusted'
   end})
 end
 -- step 1: the compressor (heavy toggle)
 local compressor=not self._simplePanel and Ref(self.Model,'CompressorSwitch')
 if compressor then
  context.RegisterInteraction({interactionId='BW5Compressor',target=compressor,interactionType='Panel',label='START COMPRESSOR',holdDuration=1,allowedRunPhases={FloorActive=true},
   canUse=function()local ok,r=self:_Available(4);if not ok then return false,r end;if self._compressor then return false,'Unavailable' end;return true end,
   complete=function()
    if not self:_Available(4) or self._compressor then return false,'Unavailable' end
    self._compressor=true;self.Model:SetAttribute('CompressorOn',true)
    if self._context.SetInteractionEnabled then self._context.SetInteractionEnabled('BW5Compressor',false) end
    fx('compressor',function()
     local lever=Ref(self.Model,'CompressorLever');self:_Swing(lever,60,.35,'x');self:_Sound(lever,'lever')
     self:_Lamp('LampCompressor',LAMP_AMBER,true)
     local hum=compressor:FindFirstChild('CompressorRun')
     if not hum then hum=Instance.new('Sound');hum.Name='CompressorRun';hum.SoundId='rbxassetid://127510969655408';hum.Looped=true;hum.Volume=.18;hum.PlaybackSpeed=1.35;hum.RollOffMinDistance=5;hum.RollOffMaxDistance=40;hum.Parent=compressor end
     hum:Play()
     self:_AirReadout()
    end)
    self:_Target();self:_Publish()
    return true,'CompressorStarted'
   end})
 end
 -- step 3: seal check (key switch) - three lamps light in turn, then the receiver can be locked
 local seal=not self._simplePanel and Ref(self.Model,'SealCheck')
 if seal then
  context.RegisterInteraction({interactionId='BW5SealCheck',target=seal,interactionType='Panel',label='RUN SEAL CHECK',holdDuration=1.5,allowedRunPhases={FloorActive=true},
   canUse=function()
    local ok,r=self:_Available(4);if not ok then return false,r end
    if not self._compressor then return false,'CompressorOff' end
    if self._pressure~=self._target then return false,'PressureUnbalanced' end
    if self._verified or self._verifying then return false,'Busy' end
    return true
   end,
   complete=function()
    if not self:_Available(4) or not self._compressor or self._pressure~=self._target or self._verified or self._verifying then return false,'Unavailable' end
    self._verifying=true;self._sealSerial=(self._sealSerial or 0)+1;local serial=self._sealSerial
    fx('seal start',function()
     local key=Ref(self.Model,'VerifyKey');self:_Swing(key,90,.25,'z');self:_Sound(seal,'fit')
     self:_AirReadout()
    end)
    -- PRESSURE, VALVES, SEAL: each goes amber, then green, one after another
    for i,n in {'LampPressure','LampValves','LampSeal'}do
     task.delay(.15+(i-1)*.55,function()if self._sealSerial==serial and self._state=='Active' then fx('seal lamp',function()self:_Lamp(n,LAMP_AMBER,true)end) end end)
     task.delay(.45+(i-1)*.55,function()if self._sealSerial==serial and self._state=='Active' then fx('seal lamp',function()self:_Lamp(n,LAMP_GREEN,true)end) end end)
    end
    task.delay(1.9,function()
     if self._sealSerial~=serial or self._state~='Active' then return end
     self._verifying=false;self._verified=true;self.Model:SetAttribute('SealVerified',true)
     fx('seal done',function()self:_AirReadout();local key=Ref(self.Model,'VerifyKey');self:_Swing(key,-90,.25,'z')end)
     self:_Target();self:_Publish()
    end)
    self:_Target()
    return true,'SealCheckStarted'
   end})
 end
 context.RegisterInteraction({interactionId='BW5TankConfirm',target=Refs.Get(self.Model,'TankLock'),interactionType='Panel',label='LOCK',holdDuration=.55,allowedRunPhases={FloorActive=true},
  canUse=function()return self:_Available(4)end,
  complete=function()
   if not self:_Available(4)then return false,'Unavailable'end
   if self._pressure~=self._target then return false,'PressureUnbalanced'end
   if not self._simplePanel and not self._verified then return false,'SealCheck' end
   fx('lock readout',function()self._stage=5;self:_AirReadout();self:_Lamp('LampSeal',LAMP_GREEN,true)end)
   fx('lock',function()local clunk=Refs.Get(self.Model,'TankLock'):FindFirstChildWhichIsA('Sound');if clunk then clunk.PlaybackSpeed=.6;clunk:Play()end end)
   self.Model:SetAttribute('TankBalanced',true);self._stage=5;self:_Publish();return true,'PressureLocked'
  end})
 if context.RunId~='HorrorFixture' then -- the dev checks keep the fixed 50 PSI start they assert against
  local rng=Random.new()
  -- a new target every round (never the same as last round), and a start reading that is never
  -- already on it
  local targets={}
  for _,psi in Config.TankTargets do if psi~=lastTankTarget then table.insert(targets,psi)end end
  self._target=targets[rng:NextInteger(1,#targets)]//10;lastTankTarget=self._target*10
  local options={}
  for p=0,6 do if p~=self._target and p~=lastTankStart then table.insert(options,p)end end
  self._pressure=options[rng:NextInteger(1,#options)];lastTankStart=self._pressure
  local line;repeat line=rng:NextInteger(96,138) until math.abs(line-lastLinePressure)>=4
  lastLinePressure=line;self.Model:SetAttribute('LinePressure',line);self.Model:SetAttribute('TankStartPressure',self._pressure*10)
  fx('gauges',function()
   text(Ref(self.Model,'PressureGauge'),line..' PSI')
   -- line gauge dial: 3 PSI sits at +70 degrees, 122 PSI at -40 degrees
   local needle=Ref(self.Model,'GaugeNeedle');if needle then self:_Needle(needle,70-(line-3)*110/119,.05)end
  end)
 end
 pressureDisplay()
 context.RegisterItem(Config.LinkItemId,Config.LinkKind,Refs.Get(self.Model,'ReplacementLink'),{hold=.68}) -- (Oct 25: taking the fuse is half a second slower)
 context.RegisterSocket(Config.LinkSocketId,Config.LinkKind,Refs.Get(self.Model,'LinkSocket'))
 Refs.Get(self.Model,'ReplacementLink'):SetAttribute('EHInteractionLabel','TAKE FUSE')
 Refs.Get(self.Model,'LinkSocket'):SetAttribute('EHInteractionLabel','PUT IN FUSE')
 self._scope:Add(Refs.Get(self.Model,'LinkSocket'):GetAttributeChangedSignal('EHInstalledItem'):Connect(function()
  if self._state=='Active' and self._stage==2 and Refs.Get(self.Model,'LinkSocket'):GetAttribute('EHInstalledItem')==Config.LinkItemId then self._stage=3;self:_Publish();text(Ref(self.Model,'PanelReadout'),'TURN ON ALL 3 SWITCHES');fx('fit',function()self:_Sound(Refs.Get(self.Model,'LinkSocket'),'fit')end)end
 end))
 for _,id in Config.SwitchIds do
  context.RegisterInteraction({interactionId='BW5Switch'..id,target=Refs.Get(self.Model,'Switch'..id),interactionType='Panel',label='TURN ON',holdDuration=Config.SwitchHoldSeconds,allowedRunPhases={FloorActive=true},
   canUse=function()return self:_Available(3) and not self._circuits[id],'Unavailable'end,
   complete=function()if not self:_Available(3) or self._circuits[id]then return false,'Unavailable'end;self:_Power(id);return true,'Powered'end})
 end
 for _,part in self.Model:GetDescendants()do
  local excerpt=part:GetAttribute('LoreExcerpt');local id=part:GetAttribute('LoreId')
  if part:IsA('BasePart')and type(excerpt)=='string' and type(id)=='string'then
   -- Loose papers are their own interaction class so prompts, audio and the reader all treat them as paper.
   local paper=part:GetAttribute('LoreKind')=='Paper'
   context.RegisterInteraction({interactionId=id,target=part,interactionType=paper and 'Paper' or 'Panel',label=paper and 'READ PAPER' or 'READ',holdDuration=.3,allowedRunPhases={FloorActive=true},
    canUse=function()return self._state~='Stopped' and not context.IsSuspended(),'Unavailable'end,
    complete=function(player)
     if self._state=='Stopped' or context.IsSuspended()then return false,'Unavailable'end
     player:SetAttribute('EHLoreLevel',5);player:SetAttribute('EHLoreTitle',part:GetAttribute('LoreTitle')or 'Maintenance record');player:SetAttribute('EHLoreAuthor',part:GetAttribute('LoreAuthor')or 'Station maintenance');player:SetAttribute('EHLoreExcerpt',excerpt);player:SetAttribute('EHLoreBody',part:GetAttribute('LoreBody')or excerpt);player:SetAttribute('EHLoreKind',part:GetAttribute('LoreKind')or 'Record')
     player:SetAttribute('EHLoreSerial',(player:GetAttribute('EHLoreSerial')or 0)+1);return true,'Read'
    end})
  end
 end
 -- Side task: wet-floor slips and the Janitor Closet mops (never blocks the main objective chain).
 local okHazards,errHazards=pcall(function()self._hazards=Hazards.new(self.Model);self._hazards:Prepare(context)end)
 if not okHazards then warn('[ElevatorHorror] slip hazards unavailable: '..tostring(errHazards))end
 -- keep the Protocol 04 counter on the job terminals current (silently)
 self._scope:Add(self.Model:GetAttributeChangedSignal('SpillsRemaining'):Connect(function()fx('terminals',function()self:_Terminals()end)end))
 -- Side routes: crawlable vents (never part of the objective chain).
 local okVents,errVents=pcall(function()self:_PrepareVents(context)end)
 if not okVents then warn('[ElevatorHorror] vents unavailable: '..tostring(errVents))end
 self:_Publish()
 local elapsed=0;self._scope:Add(game:GetService('RunService').Heartbeat:Connect(function(dt)elapsed+=dt;if elapsed>=.2 then elapsed=0;self:_Step()end end))
end
------------------------------------------------------------------ vents
-- Each VentRoute (Workspace.BlackwaterAuthoring.Level5.Ventilation) is a duct between two rooms,
-- with a louvred cover above head height at BOTH ends (EndA / EndB). Either cover can be opened -
-- from the room (hold E / tap: OPEN VENT) or from inside the duct once you reach it - and it comes
-- loose and drops to the floor. Wherever a cover is open you can CLIMB IN. While inside (player
-- attributes EHInVent = route, EHVentEnd = the end you came in by) you are locked crouched; it
-- clears the moment you drop out of either open end (or otherwise leave the duct).
local function inside(volume,pos)
 local p=volume.CFrame:PointToObjectSpace(pos);local h=volume.Size/2
 return math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y and math.abs(p.Z)<=h.Z
end
local CLIMB_SECONDS=1.05 -- the climb-in (matches the clients' HazardController CLIMB_SECONDS)
local ventSeen=setmetatable({},{__mode='k'}) -- player -> has been seen inside the duct since climbing in
local ventOut=setmetatable({},{__mode='k'})  -- player -> seconds spent outside the duct after that
local function clearVent(p)ventSeen[p]=nil;ventOut[p]=nil;p:SetAttribute('EHInVent',nil);p:SetAttribute('EHVentAt',nil);p:SetAttribute('EHVentEnd',nil)end
function Floor:_PrepareVents(context)
 self._vents={}
 local root=self.Model:FindFirstChild('Ventilation');if not root then return end
 for _,route in root:GetChildren()do
  local id=route:GetAttribute('VentId');local volume=id and Ref(route,'VentVolume'..id)
  if volume then
   local v={id=id,route=route,volume=volume,ends={}}
   self._vents[id]=v
   for _,E in {'A','B'}do
    local cover=Ref(route,'VentCover'..id..E);local mouth=Ref(route,'VentMouth'..id..E)
    if cover and mouth then
     local e={key=id..E,side=E,cover=cover,mouth=mouth,open=false}
     v.ends[E]=e
     context.RegisterInteraction({interactionId='BW5VentCover'..e.key,target=cover,interactionType='Panel',label='OPEN VENT',holdDuration=1.85,allowedRunPhases={FloorActive=true},lineOfSightModel=cover.Parent and cover.Parent.Parent,
      canUse=function(player)
       if self._state~='Active' or e.open or context.IsSuspended() then return false,'Unavailable'end
       -- from inside, only the duct you are crawling through
       local inVent=player:GetAttribute('EHInVent');if inVent and inVent~=id then return false,'Unavailable'end
       return true
      end,
      complete=function()
       if e.open or self._state~='Active' then return false,'Unavailable'end
       e.open=true;route:SetAttribute('Cover'..E..'OpenAt',workspace:GetServerTimeNow())
       context.SetInteractionEnabled('BW5VentCover'..e.key,false);context.SetInteractionEnabled('BW5VentEnter'..e.key,true)
       -- any screws still in go down with the cover (no UNSCREW prompt on a falling plate)
       for n in e.screws or {} do context.SetInteractionEnabled('BW5Screw'..e.key..n,false) end
       fx('vent cover',function()self:_DropCover(e)end)
       return true,'Opened'
      end})
     -- Four corner screws on the room side. Each one comes out with a quick twist (UNSCREW); with
     -- all four out the cover pulls free 25% faster. It can still be forced with them in, and from
     -- inside the duct (where the screw heads cannot be reached) it is always the full hold.
     e.screws={};e.screwsOut=0
     for n=1,4 do
      local hit=Ref(route,'VentScrew'..e.key..n)
      if hit then
       local sid='BW5Screw'..e.key..n
       local s={hit=hit,model=hit.Parent,out=false}
       e.screws[n]=s
       context.RegisterInteraction({interactionId=sid,target=hit,interactionType='Panel',label='UNSCREW',holdDuration=.3,quick=true,allowedRunPhases={FloorActive=true},lineOfSightModel=cover.Parent and cover.Parent.Parent,
        canUse=function(player)
         if self._state~='Active' or e.open or s.out or context.IsSuspended() then return false,'Unavailable'end
         if player:GetAttribute('EHInVent') then return false,'Unavailable'end
         return true
        end,
        complete=function()
         if s.out or e.open or self._state~='Active' then return false,'Unavailable'end
         s.out=true;e.screwsOut+=1
         context.SetInteractionEnabled(sid,false)
         -- every client spins its own copy out of the hole the moment this arrives
         s.model:SetAttribute('UnscrewedAt',workspace:GetServerTimeNow())
         task.delay(.6,function()if s.model.Parent and not e.open then s.model:Destroy()end end)
         if e.screwsOut>=4 and context.SetInteractionHoldScale then
          context.SetInteractionHoldScale('BW5VentCover'..e.key,.75)
          route:SetAttribute('Cover'..E..'Loose',true)
         end
         return true,'Unscrewed'
        end})
      end
     end
     context.RegisterInteraction({interactionId='BW5VentEnter'..e.key,target=mouth,interactionType='Panel',label='CLIMB IN',holdDuration=.25,enabled=false,requiresLineOfSight=false,allowedRunPhases={FloorActive=true},
      canUse=function(player)
       if not e.open or self._state~='Active' then return false,'Unavailable'end
       if player:GetAttribute('EHInVent') then return false,'Unavailable'end
       if (player:GetAttribute('EHKnockedUntil')or 0)>workspace:GetServerTimeNow() then return false,'Knocked'end
       return true
      end,
      complete=function(player)
       if not e.open or player:GetAttribute('EHInVent') then return false,'Unavailable'end
       player:SetAttribute('EHVentAt',workspace:GetServerTimeNow());player:SetAttribute('EHVentEnd',E);player:SetAttribute('EHInVent',id)
       return true,'Entered'
      end})
    end
   end
  end
 end
 local elapsed=0
 self._scope:Add(game:GetService('RunService').Heartbeat:Connect(function(dt)
  elapsed+=dt;if elapsed<.1 then return end;local step=elapsed;elapsed=0
  for _,p in game:GetService('Players'):GetPlayers()do
   local id=p:GetAttribute('EHInVent')
   if id then
    local v=self._vents[id];local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart');local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
    local since=workspace:GetServerTimeNow()-(p:GetAttribute('EHVentAt')or 0)
    local dead=not v or not root or not h or h.Health<=0
    local isIn=not dead and inside(v.volume,root.Position)
    -- The climb is driven by the climber's own client and reaches the server over the network, so
    -- nothing is judged until the body has actually arrived inside the duct (a slow connection can
    -- never drop you out mid-climb and stand you up inside it). After that, being out of the duct
    -- for a beat means you have climbed out of an open end.
    if isIn then ventSeen[p]=true end
    if dead then clearVent(p)
    elseif not ventSeen[p] then
     if since>CLIMB_SECONDS+4 then clearVent(p) end -- the climb never arrived: give up cleanly
    else
     ventOut[p]=isIn and 0 or (ventOut[p] or 0)+step
     if ventOut[p]>=.35 or since>600 then clearVent(p) end
    end
   end
  end
 end))
 self._scope:Add(function()for _,p in game:GetService('Players'):GetPlayers()do if p:GetAttribute('EHInVent')then clearVent(p)end end end)
end
-- The cover comes free: every piece is welded to the plate, unanchored, pushed off the wall into
-- the room (whichever side it was opened from) and left to fall and clatter on the floor.
function Floor:_DropCover(e)
 local plate=e.cover;local model=plate.Parent
 local s=Instance.new('Sound');s.Name='VentClatter';s.SoundId='rbxassetid://9116643017';s.Volume=.8;s.PlaybackSpeed=1.1;s.RollOffMaxDistance=60;s.Parent=plate
 for _,p in model:GetDescendants()do if p:IsA('BasePart')then p.Anchored=false;p.CollisionGroup='Default' end end
 plate.CanCollide=true
 local away=(plate.Position-e.mouth.Position);away=Vector3.new(away.X,0,away.Z)
 away=away.Magnitude>.01 and away.Unit or -e.mouth.CFrame.LookVector
 pcall(function()plate:SetNetworkOwner(nil)end)
 plate.AssemblyLinearVelocity=away*4+Vector3.new(0,1.5,0)
 plate.AssemblyAngularVelocity=Vector3.new(math.random()-.5,0,math.random()-.5)*4+plate.CFrame.RightVector*3
 s:Play()
 task.delay(.9,function()if plate.Parent then local t=Instance.new('Sound');t.SoundId='rbxassetid://9116642648';t.Volume=.9;t.RollOffMaxDistance=60;t.Parent=plate;t:Play();game:GetService('Debris'):AddItem(t,4)end end)
 -- once it has come to rest it is fixed where it lies and stops colliding, so a crew member
 -- climbing in or dropping out never steps on a loose plate (no tripping, no physics jitter)
 local t0=os.clock()
 task.spawn(function()
  repeat task.wait(.2) until not plate.Parent or os.clock()-t0>4 or (os.clock()-t0>1.2 and plate.AssemblyLinearVelocity.Magnitude<.3)
  if not plate.Parent then return end
  for _,p in model:GetDescendants()do if p:IsA('BasePart')then p.Anchored=true;p.CanCollide=false;p.CanQuery=false end end
 end)
 -- the duct exhales as the cover comes away: a stronger gust of dust and air that settles back
 local exhaust=e.mouth.Parent and e.mouth.Parent:FindFirstChild('ExhaustSource')
 if exhaust then exhaust:SetAttribute('GustAt',workspace:GetServerTimeNow()) end
end
function Floor:_Step()
 if self._state~='Active' or self._context.IsSuspended()then return end
 local link=Ref(self.Model,'ReplacementLink');local carried=link and link:GetAttribute('EHItemState')=='Carried'
 if self._stage==2 and carried~=self._linkCarried then self._linkCarried=carried;self:_Publish()else self:_Target()end
end
function Floor:Activate()assert(self._context);self._state='Active';self:_Publish();if self._context.SetStatus then self._context.SetStatus(Config.TrippedMessage)end end
function Floor:GetObjectiveSnapshot()return {status=self._state,progress=self._stage-1}end
function Floor:OnParticipantStateChanged(snapshot)self._participants=snapshot.participants end
function Floor:Stop()if self._hazards then pcall(function()self._hazards:Stop()end)end;self._state='Stopped';self.Model:SetAttribute('TaskActive',false);pcall(function()self:_Publish()end);self._scope:Destroy()end
function Floor:Destroy()self:Stop();self.Model:Destroy()end
return table.freeze(Floor)
--Make the floor 
