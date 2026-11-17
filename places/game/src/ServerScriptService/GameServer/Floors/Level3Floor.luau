--!nonstrict
-- LEVEL 3: FILTRATION. Design guide: vault Floors/Floor 3.md.
--   1  Fumes    Start the extract fan in the dosing room (the room is full of ferric fumes).
--   2  Dosing   Shut off the two dosing pumps.
--   3  Inlets   Close the six filter inlets at the consoles on the centre deck (any order, any crew
--               member). Each closed bed lets its black water reach further along the deck drain.
--   4  Bypass   THE SPLIT-UP. One crew member takes the bypass key down the one-person hatch at the
--               end of the pipe gallery and turns the bypass wheel three times. The wheel only moves
--               while the rest of the crew hold header pressure at the console on the deck (the bar
--               only fills while someone stands by it; a solo player latches it). While they are
--               apart the intercoms speak under each other's names (Config.Level3.Radio).
--               When the wheel is open the booth bulb comes on: Marty at the glass, grey (MartyGrey).
--   5  Lift     Walk back through the dark hall and go down.
-- Black water, the light rule and the fumes live in BlackWaterReach. Everything the clients show is
-- published as attributes (floor model: stage, timestamps, pressure; player: EHL3*, EHRadio*).
-- Marty: one model in Level3.MartyMarkers, moved between its stands only while nobody can see him.
-- He never moves in view, never touches the water, hurts nobody, and tells the truth about the job.
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level3)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local BlackWater=require(script.Parent.BlackWaterReach)
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local function Ref(root,name)return Refs.Find(root,name)end
local function fx(name,fn)local ok,err=pcall(fn);if not ok then warn('[ElevatorHorror] Level 3 effect failed ('..name..'): '..tostring(err))end end
local Floor={};Floor.__index=Floor
local STAGES=Config.Stages
local H=Config.Holds
function Floor.new(model,number)
 return setmetatable({Model=model,Number=number,_state='Inactive',_stage='Fumes',_pumps={},_inlets={},_inletCount=0,_turns=0,
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
function Floor:_Publish()
 local m=self.Model;local active=self._state=='Active'
 local T=Config.Text
 local text,sentText,targets='','',{}
 if self._stage=='Fumes' then text=T.Fumes;targets={'FanStarter'}
 elseif self._stage=='Dosing' then
  local n=0;for _ in self._pumps do n+=1 end
  text=string.format(T.Dosing,n)
  for i=1,2 do if not self._pumps[i] then table.insert(targets,'DosingSwitch'..i) end end
 elseif self._stage=='Inlets' then
  text=string.format(T.Inlets,self._inletCount)
  for i=1,6 do if not self._inlets[i] then table.insert(targets,'FilterConsole'..i) end end
 elseif self._stage=='Bypass' then
  local installed,state,carrier=self:_KeyState()
  local h=self._header
  if not installed and not carrier then
   text=state=='Dropped' and T.KeyDropped or T.KeyOnHook;sentText=text;targets={'BypassKey'}
  else
   if not h then text=T.CrewStart
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
  enable('BW3Fan',active and self._stage=='Fumes')
  for i=1,2 do enable('BW3Pump'..i,active and self._stage=='Dosing' and not self._pumps[i]) end
  for i=1,6 do enable('BW3Inlet'..i,active and self._stage=='Inlets' and not self._inlets[i]) end
  enable('BW3Header',active and self._stage=='Bypass' and not self._header)
  enable('BW3Wheel',active and self._stage=='Bypass' and self._turns<Config.Wheel.Turns)
  enable('BW3HatchDown',(active or self._state=='Completed') and (self._stage=='Bypass' or self._stage=='Lift') and not self._occupant)
  enable('BW3HatchUp',self._occupant~=nil and not self._greyRunning)
  enable(Config.KeyItemId,active and self._stage=='Bypass')
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
 if stage=='Dosing' then self:_Marty('B1')
 elseif stage=='Inlets' then self:_Marty('C1')
 elseif stage=='Bypass' then self:_Marty('D1')
 elseif stage=='Lift' then
  -- every bed and the gallery rest further out for the walk back
  self._water:SetRestWhere(function(r)return r.folder:GetAttribute('Bed')~=nil end,Config.Light.LiftRestBed)
  self._water:SetRestWhere(function(r)return r.folder:GetAttribute('Zone')=='Gallery' end,Config.Light.LiftRestGallery)
  task.delay(3,function()if self._state~='Stopped' then self:_Marty('G1') end end)
 end
 if self._context.SetStatus then
  self._context.SetStatus(stage=='Lift' and 'GO DOWN' or 'LEVEL 3')
 end
 self:_Publish()
end
------------------------------------------------------------------ jobs
function Floor:_StartFan()
 local m=self.Model
 m:SetAttribute('ExtractFanAt',self:_Now())
 task.delay(Config.Fumes.FanSpinUp+Config.Fumes.ThinSeconds,function()if self._state~='Stopped' then m:SetAttribute('FumesActive',false) end end)
 self:_SetStage('Dosing')
end
function Floor:_StopPump(i)
 if self._pumps[i] then return end
 self._pumps[i]=true;self.Model:SetAttribute('Pump'..i..'OffAt',self:_Now());self:_Progress()
 local n=0;for _ in self._pumps do n+=1 end
 self.Model:SetAttribute('DosingPumpsOff',n)
 if n>=2 then self:_SetStage('Inlets') else self:_Publish() end
end
function Floor:_CloseInlet(i)
 if self._inlets[i] then return end
 self._inlets[i]=true;self._inletCount+=1;self:_Progress()
 self.Model:SetAttribute('Inlet'..i..'ClosedAt',self:_Now())
 self._water:SetRest(i,Config.Light.InletRest) -- every repair lets it go further
 if self._inletCount==3 then self:_Marty('C3') end
 if self._inletCount==4 then task.delay(1.5,function()if self._state~='Stopped' then self:_Knock('BedWater4') end end) end
 if self._inletCount>=6 then self:_SetStage('Bypass') else self:_Publish() end
end
function Floor:_HeaderStep(dt)
 local h=self._header;if not h or self._stage~='Bypass' then return end
 local zone=Ref(self.Model,'HeaderZone');local radius=Config.Header.Radius
 local near=false
 for _,p in self:_Crew()do
  local root=rootOf(p)
  if zone and root and p~=self._occupant and (root.Position-zone.Position).Magnitude<=radius then near=true;break end
 end
 local before,was=math.floor(h.progress),h.near
 h.near=near
 if near or h.latched then h.progress=math.min(100,h.progress+dt*Config.Header.FillPerSecond)
 else h.progress=math.max(0,h.progress-dt*Config.Header.DrainPerSecond) end
 local m=self.Model
 m:SetAttribute('HeaderPressure',math.floor(h.progress*10)/10);m:SetAttribute('HeaderHeld',near or h.latched==true)
 if math.floor(h.progress)~=before or was~=near then self:_Publish() end
end
function Floor:_Pressure()return self._header and self._header.progress or 0 end
function Floor:_TurnWheel(player)
 self._turns+=1;self:_Progress()
 local m=self.Model;local t=self:_Now()
 m:SetAttribute('WheelTurn'..self._turns..'At',t)
 if self._turns==2 then
  -- the chamber lamp and the hall's last bed lamp go out
  m:SetAttribute('ChamberLampOffAt',t+1.2);m:SetAttribute('HB3OffAt',t+1.2)
  fx('lamps',function()
   task.delay(1.2,function()
    for _,n in {'ChamberLamp','HB3'} do local lamp=Ref(m,n);local li=lamp and lamp:FindFirstChildWhichIsA('Light');if li then li.Enabled=false end end
   end)
  end)
 end
 if self._turns>=Config.Wheel.Turns then
  m:SetAttribute('BypassOpenAt',t);m:SetAttribute('GreyFaceAt',t+Config.Grey.Delay)
  self._greyRunning=true;self._greyFor=player
  -- his one line at the glass comes from the intercom behind the player; his mouth stays shut
  task.delay(Config.Grey.Delay+Config.Grey.LineAt,function()if self._state~='Stopped' and player.Parent then self:_Marty('F1',{player}) end end)
  task.delay(Config.Grey.Delay+Config.Grey.End,function()
   if self._state=='Stopped' then return end
   self._greyRunning=false
   local ok,code=self._context.CompleteObjective()
   if not ok then warn('[ElevatorHorror] Level 3 objective: '..tostring(code)) end
   if ok then self._state='Completed' end
   self:_SetStage('Lift');self:_Publish()
  end)
 end
 self:_Publish()
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
  local go=(self._inletCount>=1) or (entered and os.clock()-entered>40) or self._stage=='Bypass'
  if go and hidden('A') then self:_MartyTo(nil) end
 elseif where==nil and self._stage=='Bypass' and not self._martyDone then
  local _,_,carrier=self:_KeyState()
  if not carrier and hidden('B') then self:_MartyTo('B') end
 elseif where=='B' then
  local installed,_,carrier=self:_KeyState()
  if (carrier or installed) and hidden('B') then self._martyDone=true;self:_MartyTo(nil) end
 end
 -- TALK only at the hook
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
 m:SetAttribute('FumesActive',true);m:SetAttribute('HeaderPressure',0);m:SetAttribute('InletsClosed',0);m:SetAttribute('WheelTurns',0);m:SetAttribute('DosingPumpsOff',0)
 self._water=BlackWater.new(m);self._water:Prepare(context)
 self._markers=m:FindFirstChild('MartyMarkers')
 self._marty=self._markers and self._markers:FindFirstChild('Marty')
 if self._marty then self._marty:SetAttribute('TalkSets','L3');self._marty:SetAttribute('NoTurn',true);self:_MartyTo('A') end
 local function hold(id,refName,label,seconds,can,done,extra)
  local def={interactionId=id,target=Refs.Get(m,refName),interactionType='Panel',label=label,holdDuration=seconds,allowedRunPhases={FloorActive=true},
   canUse=function(player)
    if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
    return can(player)
   end,
   complete=function(player)
    if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
    local ok,why=can(player);if not ok then return false,why or 'Unavailable' end
    return done(player)
   end}
  for k,v in extra or {} do def[k]=v end
  context.RegisterInteraction(def)
 end
 local function live(stage)return self:_Live() and self._stage==stage end
 hold('BW3Fan','FanStarter','START FAN',H.Fan,function()return live('Fumes'),'Unavailable' end,function()self:_StartFan();return true,'Started' end)
 for i=1,2 do
  hold('BW3Pump'..i,'DosingSwitch'..i,'SHUT OFF',H.Pump,function()return live('Dosing') and not self._pumps[i],'Unavailable' end,function()self:_StopPump(i);return true,'Stopped' end)
 end
 for i=1,6 do
  hold('BW3Inlet'..i,'FilterConsole'..i,'CLOSE INLET',H.Inlet,function()return live('Inlets') and not self._inlets[i],'Unavailable' end,function()self:_CloseInlet(i);return true,'Closed' end)
 end
 hold('BW3Header','HeaderConsole','HOLD PRESSURE',H.Header,function()return live('Bypass') and not self._header,'Unavailable' end,function()
  local solo=#self:_Crew()<=1
  self._header={progress=0,near=true,latched=solo}
  m:SetAttribute('HeaderStartedAt',self:_Now());m:SetAttribute('HeaderLatched',solo);self:_Progress();self:_Publish()
  return true,'Started'
 end)
 hold('BW3Wheel','BypassWheel','TURN WHEEL',H.Wheel,function(player)
  if not live('Bypass') or self._turns>=Config.Wheel.Turns then return false,'Unavailable' end
  local installed=self:_KeyState()
  if not installed or player~=self._occupant then return false,'Unavailable' end
  if self:_Pressure()<Config.Header.WheelNeeds then return false,'NoPressure' end
  return true
 end,function(player)self:_TurnWheel(player);return true,'Turned' end)
 hold('BW3HatchDown','ChamberHatch','CLIMB DOWN',H.Hatch,function(player)
  if self._occupant or self._leaving then return false,'Busy' end
  if self._stage~='Bypass' and self._stage~='Lift' then return false,'Unavailable' end
  local installed,_,carrier,key=self:_KeyState()
  local keyBelow=key and inside(Ref(m,'ChamberZone'),key.Position)
  local sent=self:_Sent()
  if carrier==player then return true end
  if (installed or keyBelow) and (sent==nil or sent==player) then return true end
  return false,'NeedKey'
 end,function(player)return self:_Ladder(player,true) end)
 hold('BW3HatchUp','ChamberLadder','CLIMB UP',H.Hatch,function(player)
  return player==self._occupant and not self._greyRunning and not self._leaving,'Unavailable'
 end,function(player)return self:_Ladder(player,false) end,{requiresLineOfSight=false})
 -- the key and its socket on the wheel stand
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
  for _,p in Players:GetPlayers()do
   for _,a in {'EHL3Sent','EHL3InChamber','EHL3LadderAt','EHL3LadderDir','EHL3Toast','EHRadioLine','EHRadioWho','EHRadioFace','EHRadioKind','EHRadioAt','EHRadioSeconds','EHMartyTalkedL3'} do
    if p:GetAttribute(a)~=nil then p:SetAttribute(a,nil) end
   end
  end
 end)
end
function Floor:_Step(dt)
 if self._state~='Active' and self._state~='Completed' then return end
 local m=self.Model
 if not self._context.IsSuspended() then self._water:Step(dt) end
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
   -- (a moment's grace while the climb down is still in progress)
   local at=occ.Parent and occ:GetAttribute('EHL3LadderAt')
   if not at or self:_Now()-at>Config.Ladder.Seconds+1 then
    if occ.Parent then occ:SetAttribute('EHL3InChamber',nil) end
    self._occupant=nil
    if m:GetAttribute('BypassOpenAt') then self._exitAt=self._exitAt or os.clock() end
    self:_Publish()
   end
  end
 end
 if self._state=='Active' and not self._context.IsSuspended() then self:_HeaderStep(dt) end
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
  if e>=Config.Marty.A2.at and self._stage=='Fumes' then self:_Marty('A2') end
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
end
-- STUDIO ONLY (reached through ElevatorService's ElevatorDebug BindableFunction: "L3:<cmd>")
function Floor:Debug(cmd)
 if not RunService:IsStudio() then return 'StudioOnly' end
 local p=self:_Crew()[1]
 local k,v=string.match(cmd,'^(%w+)=(%w+)$')
 if k=='Stage' and table.find(STAGES,v) then
  if v~='Fumes' then self.Model:SetAttribute('FumesActive',false) end
  if table.find(STAGES,v)>3 then for i=1,6 do if not self._inlets[i] then self._inlets[i]=true;self._inletCount+=1;self.Model:SetAttribute('Inlet'..i..'ClosedAt',self:_Now()) end end end
  self:_SetStage(v);return 'Stage '..v
 elseif cmd=='Sent' and p then
  self:_SetStage('Bypass')
  local stand=Refs.Get(self.Model,'WheelStand');stand:SetAttribute('EHInstalledItem',Config.KeyItemId)
  self._header=self._header or {progress=100,near=true,latched=true}
  self:_Ladder(p,true);task.wait(1.2);self:_SetSent(p);return 'Sent '..p.Name
 elseif cmd=='Turn' and p then
  if self._turns<Config.Wheel.Turns then self:_TurnWheel(self._occupant or p) end;return 'Turns '..self._turns
 elseif cmd=='Snuff' and p then return tostring(self._water:Snuff(p))
 elseif cmd=='Reveal' and p then self._said.R1=nil;self:_Imitate('R1',p);return 'Reveal'
 elseif cmd=='State' then
  return string.format('stage=%s inlets=%d turns=%d pressure=%.0f occupant=%s marty=%s',self._stage,self._inletCount,self._turns,self:_Pressure(),tostring(self._occupant),tostring(self._martyAt))
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
