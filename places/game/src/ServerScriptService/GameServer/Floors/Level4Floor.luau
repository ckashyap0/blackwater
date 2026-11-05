--!nonstrict
-- LEVEL 4: MAIN CONTROL ROOM.
--   1  Find the keycard (Break Room - it turns up in one of a few places each round) and put it
--      in the reader by the Server Room door. The door slides open.
--   2  Five jobs, any order, shared by the whole crew (Among Us style list):
--        Upload the security logs (Server Room terminal, on-screen upload)
--        Fix the wiring (Wiring Room panel, drag the coloured wires)
--        Flip the breakers in the order on the screen (Control Room walkway, 3D levers)
--        Line up the pump dials (Control Room main desk, on-screen dials)
--        Tune the radio (Monitoring Room, on-screen tuner)
--   3  Restart the system in the Core Room: press the button, then stay close while it loads
--      (the bar only fills while someone is near it).
--   4  Get in the lift and go down.
-- Creepy radio calls (Marty, and a faint warning from B. Mercer) come over the radios and PA.
-- The on-screen job windows are opened by the server (EHL4Task) and finished through the
-- Level4Task remote, which the server checks (right job, same crew member, close by, right answer).
local Config=require(game.ReplicatedStorage.Game.Shared.Config.Level4)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Level5Floor=require(script.Parent.Level5Floor)
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local function Ref(root,name)return Refs.Find(root,name)end
local function fx(name,fn)local ok,err=pcall(fn);if not ok then warn('[ElevatorHorror] Level 4 effect failed ('..name..'): '..tostring(err))end end
local Floor={};Floor.__index=Floor
-- crawlable vents work exactly as on Level 5 (same routes, covers, screws and climb)
Floor._PrepareVents=Level5Floor._PrepareVents
Floor._DropCover=Level5Floor._DropCover
local STAGES={'Keycard','Jobs','Reboot','Lift'}
local JOB={};for _,j in Config.Jobs do JOB[j.id]=j end
function Floor.new(model,number)
 return setmetatable({Model=model,Number=number,_state='Inactive',_stage='Keycard',_done={},_locks={},_flipped={},_breakerProgress=0,
  _reboot=nil,_scope=Scope.new(),_serial=0,_rng=Random.new()},Floor)
end
function Floor:_Now()return workspace:GetServerTimeNow() end
function Floor:_Live()return self._state=='Active' and not self._context.IsSuspended() end
function Floor:_StageIndex()return table.find(STAGES,self._stage) or 1 end
function Floor:_DoneCount()local n=0;for _ in self._done do n+=1 end;return n end
------------------------------------------------------------------ radio calls
function Floor:_Radio(entry,source)
 if not entry or self._state=='Stopped' then return end
 local m=self.Model
 m:SetAttribute('RadioText',entry.text);m:SetAttribute('RadioWho',entry.who or 'Marty');m:SetAttribute('RadioStyle',entry.style or 'calm')
 m:SetAttribute('RadioSource',source or 'All');m:SetAttribute('RadioAt',self:_Now())
 self._lastRadio=os.clock()
end
function Floor:_Toast(player,text)
 if typeof(player)=='Instance' then player:SetAttribute('EHL4Toast',text);player:SetAttribute('EHL4ToastSerial',(player:GetAttribute('EHL4ToastSerial') or 0)+1) end
end
------------------------------------------------------------------ publish
function Floor:_Publish()
 local m=self.Model;local active=self._state=='Active'
 local enable=self._context.SetInteractionEnabled
 local text,targets='',{}
 local card=Ref(m,'Keycard')
 if self._stage=='Keycard' then
  local carried=card and card:GetAttribute('EHItemState')=='Carried'
  text=carried and Config.Text.KeycardCarried or Config.Text.Keycard
  targets={carried and 'CardReader' or 'Keycard'}
 elseif self._stage=='Jobs' then
  text=string.format(Config.Text.Jobs,self:_DoneCount(),#Config.Jobs)
  for _,j in Config.Jobs do
   if not self._done[j.id] then
    if j.id=='Breakers' then for i=1,5 do if not self._flipped[i] then table.insert(targets,'BreakerHit'..i) end end
    else table.insert(targets,j.target) end
   end
  end
 elseif self._stage=='Reboot' then
  local r=self._reboot
  if not r then text=Config.Text.Reboot;targets={'RebootButton'}
  else text=string.format(r.near and Config.Text.Rebooting or Config.Text.RebootAlone,math.floor(r.progress));targets={'RebootScreen'} end
 else text=Config.Text.Lift;targets={'ControlBox'} end
 if self._state=='Completed' then text=Config.Text.Lift;targets={'ControlBox'} end
 if enable then
  for _,j in Config.Jobs do
   if j.id=='Breakers' then for i=1,5 do enable('BW4Breaker'..i,active and self._stage=='Jobs' and not self._done.Breakers and not self._flipped[i]) end
   else enable('BW4Job'..j.id,active and self._stage=='Jobs' and not self._done[j.id]) end
  end
  enable('BW4Reboot',active and self._stage=='Reboot' and not self._reboot)
 end
 m:SetAttribute('TaskText',text)
 m:SetAttribute('TaskTargets',table.concat(targets,','));m:SetAttribute('TaskTarget',targets[1] or '')
 m:SetAttribute('TaskCount',#STAGES);m:SetAttribute('TaskIndex',self:_StageIndex())
 m:SetAttribute('TaskActive',active or self._state=='Completed');m:SetAttribute('Stage',self._stage)
 local done={};for _,j in Config.Jobs do if self._done[j.id] then table.insert(done,j.id) end end
 m:SetAttribute('JobsDone',table.concat(done,','))
 m:SetAttribute('TaskRevision',(m:GetAttribute('TaskRevision') or 0)+1)
end
------------------------------------------------------------------ keycard door
function Floor:_OpenDoor()
 if self._stage~='Keycard' then return end
 self._stage='Jobs';self:_Publish()
 local m=self.Model;local now=self:_Now()
 m:SetAttribute('ServerDoorOpenAt',now)
 fx('reader',function()local lamp=Ref(m,'ReaderLamp');if lamp then lamp.Color=Color3.fromRGB(90,255,120) end end)
 if self._context.SetStatus then self._context.SetStatus('SERVER ROOM OPEN') end
 -- every client slides the door from ServerDoorOpenAt; the server sets the final pose after
 task.delay(1.9,function()
  if self._state=='Stopped' then return end
  fx('door',function()
   local leaf=Ref(m,'ServerDoor');if not leaf then return end
   local off=leaf:GetAttribute('SlideOffset') or Vector3.new(0,0,8.3)
   for _,p in leaf.Parent:GetDescendants()do
    if p:IsA('BasePart') and (p==leaf or p:GetAttribute('SlidesWith')=='ServerDoor') then p.CFrame=p.CFrame+off end
   end
   leaf.CanCollide=false
  end)
 end)
 task.delay(3.5,function()if self._state=='Active' then self:_Radio(Config.Radio.DoorOpen,'GuardDeskRadio') end end)
end
------------------------------------------------------------------ jobs
function Floor:_FinishJob(id,player)
 if self._done[id] then return end
 self._done[id]=true;self._locks[id]=nil
 if player then player:SetAttribute('EHL4Task',nil) end
 local m=self.Model;m:SetAttribute('Job'..id..'At',self:_Now())
 if id=='Radio' then task.delay(1.2,function()if self._state=='Active' then self:_Radio(Config.Radio.Tuned,'Monitoring') end end) end
 if self:_DoneCount()>=#Config.Jobs then
  self._stage='Reboot'
  if self._context.SetStatus then self._context.SetStatus('RESTART THE CORE') end
 end
 self:_Publish()
end
function Floor:_ReleaseLock(id)
 local l=self._locks[id];if not l then return end
 self._locks[id]=nil
 if l.player and l.player.Parent and l.player:GetAttribute('EHL4Task')==id then l.player:SetAttribute('EHL4Task',nil) end
end
function Floor:_Breaker(i,player)
 local m=self.Model
 local expected=self._order[self._breakerProgress+1]
 if i==expected then
  self._flipped[i]=true;self._breakerProgress+=1
  m:SetAttribute('Breaker'..i..'At',self:_Now())
  if self._breakerProgress>=5 then self:_FinishJob('Breakers',nil) else self:_Publish() end
  return true,'Flipped'
 end
 -- wrong order: the whole bank trips back
 self._flipped={};self._breakerProgress=0
 for k=1,5 do m:SetAttribute('Breaker'..k..'At',nil) end
 m:SetAttribute('BreakerTripAt',self:_Now())
 self:_Toast(player,'Wrong order! The breakers tripped. Check the screen and start again.')
 self:_Publish()
 return true,'Tripped'
end
local function near(player,part,range)
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 return root and part and (root.Position-part.Position).Magnitude<=range
end
function Floor:_OnTask(player,action,id,serial,answer)
 if type(action)~='string' or type(id)~='string' or not JOB[id] then return end
 local lock=self._locks[id]
 if action=='Cancel' then
  if lock and lock.player==player then self:_ReleaseLock(id) end
  return
 end
 if action~='Done' or not self:_Live() or self._stage~='Jobs' or self._done[id] then return end
 if not lock or lock.player~=player or lock.serial~=serial then return end
 if not near(player,Ref(self.Model,JOB[id].target),18) then return end
 local ok=false
 if id=='Upload' then ok=os.clock()-lock.at>=Config.UploadSeconds*.8
 elseif id=='Wires' then
  if type(answer)=='table' then
   ok=true
   for i=1,4 do local j=answer[i];if type(j)~='number' or self._wireOrder[j]~=i then ok=false end end
  end
 elseif id=='Dials' then
  if type(answer)=='table' then
   ok=true
   for k=1,3 do local v=answer[k];if type(v)~='number' or v~=v or math.abs(v-self._dials[k])>Config.DialTolerance then ok=false end end
  end
 elseif id=='Radio' then ok=type(answer)=='number' and answer==answer and math.abs(answer-self._freq)<=.25 end
 if ok then self:_FinishJob(id,player) else self:_Toast(player,"That's not quite right. Try again.") end
end
------------------------------------------------------------------ reboot
function Floor:_RebootStep(dt)
 local r=self._reboot;if not r or self._stage~='Reboot' then return end
 local zone=Ref(self.Model,'RebootZone');local radius=Config.RebootRadius
 local anyone=false
 for _,p in self._context.GetPlayers()do
  local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart');local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid')
  if root and h and h.Health>0 and zone and (root.Position-zone.Position).Magnitude<=radius then anyone=true;break end
 end
 local before=math.floor(r.progress);local wasNear=r.near
 r.near=anyone
 if anyone then r.progress=math.min(100,r.progress+dt*100/Config.RebootSeconds) else r.progress=math.max(0,r.progress-dt*Config.RebootDrain) end
 local m=self.Model
 m:SetAttribute('RebootProgress',math.floor(r.progress*10)/10);m:SetAttribute('RebootNear',anyone)
 if r.progress>=50 and not r.half then
  r.half=true;self:_Radio(Config.Radio.RebootHalf,'All');m:SetAttribute('FlickerAt',self:_Now())
 end
 if r.progress>=100 then self:_RebootDone();return end
 if math.floor(r.progress)~=before or wasNear~=anyone then self:_Publish() end
end
function Floor:_RebootDone()
 local m=self.Model
 self._reboot.progress=100;m:SetAttribute('RebootProgress',100)
 local ok,code=self._context.CompleteObjective()
 if not ok then warn('[ElevatorHorror] Level 4 objective: '..tostring(code)) end
 self._stage='Lift';if ok then self._state='Completed' end
 m:SetAttribute('CircuitCoreAt',self:_Now());m:SetAttribute('Circuit'..'Core',true)
 fx('core lights',function()
  for _,v in m:GetDescendants()do
   if v:GetAttribute('Circuit')=='Core' then
    if v:IsA('Light') then v.Enabled=true
    elseif v:IsA('BasePart') then v.Material=Enum.Material.Neon;v.Color=v:GetAttribute('LitColor') or Color3.fromRGB(181,194,162) end
   end
  end
 end)
 if self._context.SetStatus then self._context.SetStatus('GO DOWN') end
 self:_Publish()
 task.delay(2.5,function()if self._state~='Stopped' then self:_Radio(Config.Radio.RebootDone,'All') end end)
end
------------------------------------------------------------------ prepare
function Floor:Prepare(context)
 assert(not self._context,'Already prepared');self._context=context
 local m=self.Model;local rng=self._rng
 -- this round's puzzle values
 local order={1,2,3,4,5};for i=5,2,-1 do local j=rng:NextInteger(1,i);order[i],order[j]=order[j],order[i] end
 self._order=order;m:SetAttribute('BreakerOrder',table.concat(order,','))
 local wires={1,2,3,4};for i=4,2,-1 do local j=rng:NextInteger(1,i);wires[i],wires[j]=wires[j],wires[i] end
 self._wireOrder=wires;m:SetAttribute('WireOrder',table.concat(wires,','))
 self._dials={};for k=1,3 do self._dials[k]=rng:NextInteger(3,17)*5 end
 m:SetAttribute('DialTargets',table.concat(self._dials,','))
 self._freq=Config.RadioFrequencies[rng:NextInteger(1,#Config.RadioFrequencies)];m:SetAttribute('RadioFrequency',self._freq)
 -- the keycard turns up in one of its spots
 local card=Refs.Get(m,'Keycard')
 local spots={};for i=1,8 do local s=Ref(m,'KeycardSpot'..i);if s then table.insert(spots,s) end end
 if #spots>0 and context.RunId~='HorrorFixture' then card.CFrame=spots[rng:NextInteger(1,#spots)].CFrame end
 context.RegisterItem(Config.KeycardItemId,Config.KeycardKind,card)
 context.RegisterSocket(Config.KeycardSocketId,Config.KeycardKind,Refs.Get(m,'CardReader'))
 card:SetAttribute('EHInteractionLabel','TAKE KEYCARD')
 Refs.Get(m,'CardReader'):SetAttribute('EHInteractionLabel','USE KEYCARD')
 self._scope:Add(Refs.Get(m,'CardReader'):GetAttributeChangedSignal('EHInstalledItem'):Connect(function()
  if self._state=='Active' and Refs.Get(m,'CardReader'):GetAttribute('EHInstalledItem')==Config.KeycardItemId then self:_OpenDoor() end
 end))
 -- the four on-screen jobs
 for _,j in Config.Jobs do
  if j.id~='Breakers' then
   context.RegisterInteraction({interactionId='BW4Job'..j.id,target=Refs.Get(m,j.target),interactionType='Panel',label=j.label,holdDuration=.35,allowedRunPhases={FloorActive=true},
    canUse=function(player)
     if not self:_Live() or self._stage~='Jobs' or self._done[j.id] then return false,'Unavailable' end
     local l=self._locks[j.id];if l and l.player~=player and l.player.Parent then return false,'Busy' end
     if player:GetAttribute('EHL4Task') and player:GetAttribute('EHL4Task')~=j.id then return false,'Busy' end
     return true
    end,
    complete=function(player)
     if not self:_Live() or self._stage~='Jobs' or self._done[j.id] then return false,'Unavailable' end
     local l=self._locks[j.id];if l and l.player~=player and l.player.Parent then return false,'Busy' end
     self._serial+=1
     self._locks[j.id]={player=player,serial=self._serial,at=os.clock()}
     player:SetAttribute('EHL4TaskSerial',self._serial);player:SetAttribute('EHL4Task',j.id)
     return true,'Opened'
    end})
  end
 end
 -- the breakers
 for i=1,5 do
  context.RegisterInteraction({interactionId='BW4Breaker'..i,target=Refs.Get(m,'BreakerHit'..i),interactionType='Panel',label='FLIP '..i,holdDuration=.3,quick=true,allowedRunPhases={FloorActive=true},
   canUse=function()if not self:_Live() or self._stage~='Jobs' or self._done.Breakers or self._flipped[i] then return false,'Unavailable' end;return true end,
   complete=function(player)if not self:_Live() or self._stage~='Jobs' or self._done.Breakers or self._flipped[i] then return false,'Unavailable' end;return self:_Breaker(i,player) end})
 end
 -- the reboot button
 context.RegisterInteraction({interactionId='BW4Reboot',target=Refs.Get(m,'RebootButton'),interactionType='Panel',label='RESTART',holdDuration=1.2,allowedRunPhases={FloorActive=true},
  canUse=function()if not self:_Live() or self._stage~='Reboot' or self._reboot then return false,'Unavailable' end;return true end,
  complete=function()
   if not self:_Live() or self._stage~='Reboot' or self._reboot then return false,'Unavailable' end
   self._reboot={progress=0,near=true,started=os.clock()}
   m:SetAttribute('RebootStartedAt',self:_Now());m:SetAttribute('RebootProgress',0)
   if self._context.SetStatus then self._context.SetStatus('RESTARTING...') end
   self:_Publish();return true,'Started'
  end})
 -- readable papers (same reader as Level 5)
 for _,part in m:GetDescendants()do
  local excerpt=part:GetAttribute('LoreExcerpt');local id=part:GetAttribute('LoreId')
  if part:IsA('BasePart') and type(excerpt)=='string' and type(id)=='string' then
   context.RegisterInteraction({interactionId=id,target=part,interactionType='Paper',label='READ PAPER',holdDuration=.3,allowedRunPhases={FloorActive=true},
    canUse=function()return self._state~='Stopped' and not context.IsSuspended(),'Unavailable'end,
    complete=function(player)
     if self._state=='Stopped' or context.IsSuspended() then return false,'Unavailable' end
     player:SetAttribute('EHLoreLevel',4)
     player:SetAttribute('EHLoreTitle',part:GetAttribute('LoreTitle') or 'Note');player:SetAttribute('EHLoreAuthor',part:GetAttribute('LoreAuthor') or '')
     player:SetAttribute('EHLoreExcerpt',excerpt);player:SetAttribute('EHLoreBody',part:GetAttribute('LoreBody') or excerpt);player:SetAttribute('EHLoreKind',part:GetAttribute('LoreKind') or 'Paper')
     player:SetAttribute('EHLoreSerial',(player:GetAttribute('EHLoreSerial') or 0)+1);return true,'Read'
    end})
  end
 end
 -- the job windows report back through this remote
 local network=game.ReplicatedStorage.Game:FindFirstChild('Network')
 if network then
  local remote=network:FindFirstChild('Level4Task')
  if not remote then remote=Instance.new('RemoteEvent');remote.Name='Level4Task';remote.Parent=network end
  local last=setmetatable({},{__mode='k'})
  self._scope:Add(remote.OnServerEvent:Connect(function(player,action,id,serial,answer)
   if os.clock()-(last[player] or 0)<.15 then return end;last[player]=os.clock()
   local ok,err=pcall(self._OnTask,self,player,action,id,serial,answer)
   if not ok then warn('[ElevatorHorror] Level 4 task: '..tostring(err)) end
  end))
 end
 -- vents
 local okVents,errVents=pcall(function()self:_PrepareVents(context)end)
 if not okVents then warn('[ElevatorHorror] Level 4 vents unavailable: '..tostring(errVents)) end
 self:_Publish()
 local acc=0
 self._scope:Add(RunService.Heartbeat:Connect(function(dt)acc+=dt;if acc>=.2 then local step=acc;acc=0;local ok,err=pcall(self._Step,self,step);if not ok then warn('[ElevatorHorror] Level 4 step: '..tostring(err)) end end end))
 self._scope:Add(function()for _,p in Players:GetPlayers()do if p:GetAttribute('EHL4Task') then p:SetAttribute('EHL4Task',nil) end end end)
end
function Floor:_Step(dt)
 if self._state~='Active' and self._state~='Completed' then return end
 -- the keycard changing hands changes the objective line
 local card=Ref(self.Model,'Keycard');local carried=card and card:GetAttribute('EHItemState')=='Carried'
 if self._stage=='Keycard' and carried~=self._cardCarried then self._cardCarried=carried;self:_Publish() end
 -- job windows close if their crew member walks away or leaves
 for id,l in self._locks do
  local target=Ref(self.Model,JOB[id].target)
  if not l.player.Parent or not near(l.player,target,20) or os.clock()-l.at>120 then self:_ReleaseLock(id) end
 end
 if self._state=='Active' and not self._context.IsSuspended() then self:_RebootStep(dt) end
 -- now and then a radio crackles into life
 if self._state=='Active' and self._activeAt and os.clock()-self._activeAt>40 and os.clock()>(self._nextAmbient or 0) then
  self._nextAmbient=os.clock()+self._rng:NextNumber(70,120)
  if os.clock()-(self._lastRadio or 0)>25 then
   local list=Config.Radio.Ambient
   local radios={'BreakRoomRadio','GuardDeskRadio','SupervisorRadio','WiringRadio','Monitoring'}
   self:_Radio(list[self._rng:NextInteger(1,#list)],radios[self._rng:NextInteger(1,#radios)])
  end
 end
end
function Floor:Activate()
 assert(self._context);self._state='Active';self._activeAt=os.clock();self._nextAmbient=os.clock()+60
 self:_Publish()
 if self._context.SetStatus then self._context.SetStatus('LEVEL 4') end
 task.delay(Config.Radio.Arrival.delay or 10,function()if self._state=='Active' then self:_Radio(Config.Radio.Arrival,'All') end end)
end
function Floor:GetObjectiveSnapshot()return {status=self._state,progress=self:_StageIndex()-1}end
function Floor:OnParticipantStateChanged(snapshot)self._participants=snapshot.participants end
function Floor:Stop()self._state='Stopped';self.Model:SetAttribute('TaskActive',false);self._scope:Destroy()end
function Floor:Destroy()self:Stop();self.Model:Destroy()end
return table.freeze(Floor)
