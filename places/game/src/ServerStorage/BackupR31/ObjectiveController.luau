--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Visibility=require(game.ReplicatedStorage.Game.Shared.Utilities.ObjectiveVisibility)
local HudScale=require(game.ReplicatedStorage.Game.Shared.Utilities.HudScale)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Reveal=require(game.ReplicatedStorage.Game.Shared.Utilities.HudReveal)
local Level5=require(game.ReplicatedStorage.Game.Shared.Config.Level5)
-- The optional line under the main task while either spill is still on the floor
local MOP_LINE='Clean the Puddles (Optional)'
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)return setmetatable({Name='ObjectiveController',Dependencies={'InputController'},_player=player,_gui=gui,_refresh=0},Controller)end
function Controller:Init(deps)
 self._scope=Scope.new();self._input=deps.InputController
 -- CoreUISafeInsets keeps this clear of BOTH device notches and Roblox's own top-bar
 -- icons automatically, on every platform. This replaces a previous hand-rolled
 -- positioning scheme that mixed DeviceSafeInsets (for the GUI) with GuiService's
 -- classic GetGuiInset() (for the math) -- two different inset systems -- which is why
 -- it was landing off-center, especially on mobile.
 -- authored in StarterGui.MaintenanceTasks (TaskBar > Heading, Objective, SideTask)
 local gui=AuthoredGui.Get(self._gui,'MaintenanceTasks');gui.Enabled=false;self._screen=gui
 local frame=gui:WaitForChild('TaskBar')
 self._label=frame:WaitForChild('Objective');self._label.Text=''
 self._side=frame:WaitForChild('SideTask');self._side.Text='';self._side.Visible=false
 -- (TaskBar is a vertical list: each line sits under the one before it and grows with its own
 -- text, so a long objective can never run over the optional line)
 -- every text and panel in the task bar, with its authored transparency, for the HUD fade-in
 self._fadeParts={}
 for _,d in {frame,table.unpack(frame:GetDescendants())}do
  if d:IsA('TextLabel')then table.insert(self._fadeParts,{d,'TextTransparency',d.TextTransparency})end
  if d:IsA('GuiObject')then table.insert(self._fadeParts,{d,'BackgroundTransparency',d.BackgroundTransparency})end
  if d:IsA('UIStroke')then table.insert(self._fadeParts,{d,'Transparency',d.Transparency})end
 end
 local scale,releaseScale=HudScale.Attach(frame,{referenceSize=Vector2.new(960,600),min=.6,max=1.15,consoleBoost=1.15});self._scope:Add(releaseScale)
 -- (no on-screen pointer: the white outlines are the only task markers)
 self._marks={}
 self._scope:Add(game.GuiService.MenuOpened:Connect(function()self._menu=true end));self._scope:Add(game.GuiService.MenuClosed:Connect(function()self._menu=false end))
end
-- TASK OUTLINES: ONE thin white outline around ONE thing per target (the box, the wheel's case, the
-- fuse, the button panel) - never the pipes, signs, labels or stand around it - seen through walls.
-- The engine draws it (a Highlight, outline only), around a stand-in for the object: a local copy of
-- each of its solid, chunky parts, shrunk a hair so it sits hidden inside the real one. That way:
--  * the line follows the object's true silhouette exactly and moves naturally with the view;
--  * thin pipes, cables, wires and screws are left out, so there is one clean shape, not a tangle;
--  * the stand-in never streams in or out, changes or flickers, so the outline is rock steady.
-- Each object keeps its outline for as long as it is a target, fading in and out softly.
local RunService=game:GetService('RunService')
local OUTLINE_T=.22       -- outline transparency when fully shown (a lighter, finer-looking line)
local INSET=.012          -- studs: how far each stand-in face sits inside the real one (a fixed hair, not a
                          -- share of the size - scaling every piece about its own centre opened little gaps
                          -- between touching pieces, which showed as notches and steps in the line)
local MAX_OBJECT=16  -- studs: a model bigger than this (a room, the lift) is too big to outline whole
local holder
local function folder()
 if holder and holder.Parent then return holder end
 holder=Instance.new('Folder');holder.Name='EHTaskOutlines';holder.Parent=workspace
 return holder
end
-- the parts drawn for one outlined thing: the part itself plus anything built onto it (a fuse's
-- end caps and blade tags), so the line goes round the whole object in 3D
local function bodyParts(obj)
 local list={}
 if obj:IsA('BasePart') then
  if obj.Transparency<.95 then table.insert(list,obj) end
  for _,d in obj:GetDescendants()do if d:IsA('BasePart') and d.Transparency<.95 then table.insert(list,d) end end
  -- an invisible hit box (most Floor 4 targets): outline the visible parts of its machine that sit
  -- inside the box - one breaker's lever, the card slot - or, failing that, the whole small machine
  if #list==0 and obj.Parent and obj.Parent:IsA('Model') then
   local cf,hs=obj.CFrame,obj.Size/2+Vector3.new(.3,.3,.3)
   local all={}
   for _,d in obj.Parent:GetDescendants()do
    if d:IsA('BasePart') and d~=obj and d.Transparency<.95 then
     local l=cf:PointToObjectSpace(d.Position)
     if math.abs(l.X)<=hs.X and math.abs(l.Y)<=hs.Y and math.abs(l.Z)<=hs.Z then table.insert(list,d) end
     local z=d.Size;local thin=math.min(z.X,z.Y,z.Z)<.12 and math.max(z.X,z.Y,z.Z)<3
     if not thin and z.X*z.Y*z.Z>.01 then table.insert(all,d) end
    end
   end
   -- (a busy panel - wires, screws, labels - would turn the line into a tangle: keep its solid body)
   if #list>12 then local solid={} for _,d in list do local z=d.Size;if not(math.min(z.X,z.Y,z.Z)<.12 and math.max(z.X,z.Y,z.Z)<3) and z.X*z.Y*z.Z>.01 then table.insert(solid,d) end end;if #solid>0 then list=solid end end
   if #list==0 and #all<=80 then list=all end
  end
 else
  -- a whole small machine (OutlineGroup): its solid body only - cables, screws, labels and thin
  -- trim would turn the line into a tangle
  for _,d in obj:GetDescendants()do
   if d:IsA('BasePart') and d.Transparency<.95 then
    local s=d.Size;local thin=math.min(s.X,s.Y,s.Z)<.12 and math.max(s.X,s.Y,s.Z)<3
    if not thin and s.X*s.Y*s.Z>.01 then table.insert(list,d) end
   end
  end
 end
 return list
end
-- some controls are outlined by the box they sit in (one clean rectangle instead of a thin lever,
-- a slot or three separate buttons)
-- (the three air-brake buttons each keep their own round outline)
local OUTLINE_AS={LinkSocket='DisconnectHousing',GateRelease='GateReleaseHousing',ValveWheel='WheelMesh'} -- (the wheel's hit box is invisible: outline the wheel itself)
local function objectOf(part)
 local swap=OUTLINE_AS[part:GetAttribute('Ref') or '']
 if swap and part.Parent then
  local found=part.Parent:FindFirstChild(swap,true)
  if found and found:IsA('BasePart') then return found end
 end
 return part
end
-- the part of an upright block that is sunk into the floor is left out of its stand-in, so the
-- outline (which shows through walls and floors) stops at the floor like the object you can see
local CLIP_PARAMS=RaycastParams.new();CLIP_PARAMS.FilterType=Enum.RaycastFilterType.Exclude;CLIP_PARAMS.RespectCanCollide=false
local function floorClip(p,obj)
 if not p:IsA('Part') or p.Shape~=Enum.PartType.Block or p.CFrame.UpVector.Y<.995 then return nil end
 local top=p.Position.Y+p.Size.Y/2;local bottom=p.Position.Y-p.Size.Y/2
 CLIP_PARAMS.FilterDescendantsInstances={obj,folder()}
 local hit=workspace:Raycast(Vector3.new(p.Position.X,top-.05,p.Position.Z),Vector3.new(0,-(p.Size.Y+.1),0),CLIP_PARAMS)
 if not hit or hit.Normal.Y<.9 or hit.Instance.Transparency>=.95 then return nil end
 -- (only a real floor or counter: something wider than the object itself, not a ledge or button on it)
 local hs=hit.Instance.Size
 if not hit.Instance:IsA('BasePart') or math.max(hs.X,hs.Z)<math.max(p.Size.X,p.Size.Z)*1.5 then return nil end
 local y=hit.Position.Y
 if y<=bottom+.05 or y>=top-.2 then return nil end
 return top-y,(y-bottom)/2
end
local function standIn(p,obj)
 local ok,c=pcall(function()return p:Clone() end)
 if not ok or not c then return nil end
 c:ClearAllChildren()
 -- (a plain copy: no tags or attributes, so nothing else in the game ever treats it as the real thing)
 for _,t in c:GetTags() do c:RemoveTag(t) end
 for k in c:GetAttributes() do c:SetAttribute(k,nil) end
 c.Anchored=true;c.CanCollide=false;c.CanQuery=false;c.CanTouch=false;c.CastShadow=false;c.Massless=true
 local off=CFrame.identity
 local h,lift=nil,nil
 if p.Anchored then h,lift=floorClip(p,obj) end
 local function inset(v)return Vector3.new(math.max(.004,v.X-INSET),math.max(.004,v.Y-INSET),math.max(.004,v.Z-INSET))end
 if h then c.Size=inset(Vector3.new(p.Size.X,h,p.Size.Z));off=CFrame.new(0,lift,0) else c.Size=inset(p.Size) end
 c.CFrame=p.CFrame*off;c.Transparency=0;c.LocalTransparencyModifier=0
 return c,off
end
function Controller:_Mark(obj)
 local mk=self._marks[obj]
 if mk then mk.leaving=false;return end
 if obj:IsA('BasePart') and obj:GetAttribute('EHItemState')~=nil then
  local model=Instance.new('Folder');model.Name='PickupOutline_'..obj.Name;model.Parent=folder()
  local h=Instance.new('Highlight');h.Name='Outline';h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(236,234,222);h.OutlineTransparency=1;h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.Adornee=obj;h.Parent=model
  self._marks[obj]={obj=obj,model=model,h=h,parts={},alpha=0,leaving=false,direct=true};return
 end
 local model=Instance.new('Model');model.Name='Outline_'..obj.Name
 local pairs_={}
 for _,p in bodyParts(obj) do
  local c,off=standIn(p,obj)
  if c then c.Parent=model;table.insert(pairs_,{src=p,copy=c,cf=p.CFrame,off=off}) end
 end
 if #pairs_==0 then model:Destroy();return end
 local h=Instance.new('Highlight');h.Name='Outline'
 h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(236,234,222);h.OutlineTransparency=1
 h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.Adornee=model;h.Parent=model
 model.Parent=folder()
 self._marks[obj]={obj=obj,model=model,h=h,parts=pairs_,alpha=0,leaving=false}
end
function Controller:_Unmark(obj)
 local mk=self._marks[obj];if mk then mk.leaving=true end
end
-- every frame: fades, and the stand-in follows the object if it moves (a carried or dropped fuse)
function Controller:_DrawOutlines(dt)
 for obj,mk in self._marks do
  mk.alpha+=((mk.leaving and 0 or 1)-mk.alpha)*(1-math.exp(-math.clamp(dt,0,.1)*9))
  -- the object itself has gone (picked up - even just predicted on this screen): its outline goes
  -- with it at once instead of fading out where the object used to be
  local gone=mk.direct and (obj.Transparency>=.99 or obj.LocalTransparencyModifier>=.99 or obj:GetAttribute('EHItemState')=='Carried' or obj:GetAttribute('EHItemState')=='Installed') or false
  for _,pr in mk.parts do local s=pr.src;if s and s.Parent and (s.Transparency>=.99 or s.LocalTransparencyModifier>=.99) then gone=true;break end end
  if gone or (mk.leaving and mk.alpha<.01) or not obj.Parent then
   mk.model:Destroy()
   self._marks[obj]=nil
  else
   for _,pr in mk.parts do
    local src=pr.src
    if src.Parent then
     local cf=src.CFrame
     if cf~=pr.cf then pr.cf=cf;pr.copy.CFrame=cf*pr.off end
    elseif pr.copy.Parent then pr.copy:Destroy() end
   end
   -- up close the outline's pixel edge reads as hard and jagged, so it fades as you approach
   -- (full strength from ~10 studs, about a third at arm's length)
   local cam=workspace.CurrentCamera;local near=1
   local ref=(mk.parts[1] and mk.parts[1].copy) or (obj:IsA('BasePart') and obj)
   if cam and ref then near=math.clamp(((cam.CFrame.Position-ref.Position).Magnitude-2.5)/7.5,.35,1) end
   local t=1-(1-OUTLINE_T)*mk.alpha*near
   if math.abs(mk.h.OutlineTransparency-t)>.002 then mk.h.OutlineTransparency=t end
  end
 end
end
function Controller:_HideOutlines()
 for obj in self._marks do self:_Unmark(obj) end
end
function Controller:_Update()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local floor
 if env then for _,m in env:GetChildren()do local e=m:GetAttribute('EncounterId');if (e=='Level5' or e=='Level4') and m:GetAttribute('TaskActive')then floor=m;break end end end
 local active=self._input:GetContext()=='ActiveFloor' and not self._menu and not self._player:GetAttribute('EHLoreOpen') and floor~=nil
 -- (a single short gap while the floor republishes its attributes never blinks the bar off)
 local now=os.clock()
 if active then self._activeSince=self._activeSince or now;self._inactiveSince=nil else self._inactiveSince=self._inactiveSince or now;self._activeSince=nil end
 local shown=active or (self._screen.Enabled and now-(self._inactiveSince or now)<.45)
 if self._screen.Enabled~=shown then self._screen.Enabled=shown end
 -- after the lift the task bar fades in with the rest of the HUD
  -- (the fade-in with the HUD runs every frame in _FadeStep, not on this slower tick)



 if not active then self:_HideOutlines();return end
 local message=floor:GetAttribute('TaskText')or ''
 local names={}
 for name in string.gmatch(floor:GetAttribute('TaskTargets')or floor:GetAttribute('TaskTarget')or '','[^,]+')do table.insert(names,name)end
 local targets={}
 for _,name in names do local part=Refs.Find(floor,name) or (env.Elevator and Refs.Find(env.Elevator,name));if part then table.insert(targets,part)end end
 local stage=floor:GetAttribute('TaskIndex')
 if floor:GetAttribute('EncounterId')~='Level5' then stage=nil end -- (the stage tweaks below are Level 5's)
 if stage==2 then
  local link=Refs.Find(floor,'ReplacementLink')
  -- (a pick-up predicted on this screen counts straight away: no waiting for the server)
  local predicted=link and self._player:GetAttribute('EHPredictCarry')~=nil and self._player:GetAttribute('EHPredictCarry')==link:GetAttribute('EHInteractionId')
  if link and (predicted or link:GetAttribute('EHItemState')=='Carried') then
   message=(predicted or link:GetAttribute('EHItemOwner')==self._player.UserId) and 'Put the fuse in the fuse box' or 'Help your teammate reach the fuse box'
   targets={Refs.Find(floor,'LinkSocket')}
  end
 elseif stage==3 then message..='  ('..tostring(floor:GetAttribute('BreakerProgress')or 0)..'/3)'
 elseif stage==6 and env.Elevator then targets={Refs.Find(env.Elevator,'ControlBox')} end
 -- ONE source of truth: the lines are composed here and written once, only when the composed
 -- state really changes, and only after it has held for a moment - so a burst of attribute
 -- updates (stage, target, fuse state) never flickers or stacks two objectives on screen.
 if not self._spillZones or self._spillFloor~=floor then
  self._spillFloor=floor;self._spillZones={}
  for _,d in floor:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('SlipHazard') then table.insert(self._spillZones,d) end end
 end
 local wet=false
 for _,z in self._spillZones do if z.Parent and z:GetAttribute('SlipActive')==true then wet=true;break end end
 local side=wet and MOP_LINE or ''
 local composed=message..'\n'..side
 if composed~=self._pending then self._pending=composed;self._pendingSince=now end
 if composed~=self._shownState and (self._shownState==nil or now-(self._pendingSince or now)>=.2) then
  self._shownState=composed
   if self._label.Text~=message then self._label.Text=message;self._textIn=os.clock() end -- (fades in smoothly: _FadeStep)
   if self._side.Text~=side then self._side.Text=side;self._textIn=os.clock() end
  local showSide=side~=''
  if self._side.Visible~=showSide then self._side.Visible=showSide end
 end
 -- Dropped items ALWAYS keep their white outline (through walls), whatever the current task is.
 if not self._items or self._itemsFloor~=floor or os.clock()>(self._itemsScan or 0) then
  self._itemsFloor=floor;self._itemsScan=os.clock()+20;self._items={} -- (per floor, slow re-sweep: the item parts never change)
  for _,d in floor:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('EHItemState')~=nil then table.insert(self._items,d)end end
 end
 for _,item in self._items do
  if item.Parent and item:GetAttribute('EHItemState')=='Dropped' and not table.find(targets,item) then table.insert(targets,item)end
 end
 -- an invisible hit box stands in for the visible control inside it: outline what you can see
 local expanded={}
 for _,target in targets do
  if target and target:IsA('BasePart') and OUTLINE_AS[target:GetAttribute('Ref') or ''] then
   -- (an authored swap: e.g. the valve's invisible hit box -> the wheel mesh, resolved in objectOf)
   table.insert(expanded,target)
  elseif target and target:IsA('BasePart') and target:GetAttribute('OutlineGroup') and target.Parent and target.Parent:IsA('Model') then
   -- the hit box marks a whole small machine: outline the machine as one shape
   table.insert(expanded,target.Parent)
  elseif target and target:IsA('BasePart') and target.Transparency>=.95 and target.Parent then
   local box=target.CFrame;local half=target.Size/2+Vector3.new(.15,.15,.15)
   local reach=math.max(target.Size.X,target.Size.Y,target.Size.Z)+.4
   local best,bestV
   for _,p in target.Parent:GetChildren()do
    if p:IsA('BasePart') and p~=target and p.Transparency<.95 then
     local l=box:PointToObjectSpace(p.Position)
     local v=p.Size.X*p.Size.Y*p.Size.Z
     -- (it has to actually fit in the hit box: a big shared backing panel behind several
     -- controls is never mistaken for the one control being asked for)
     local fits=math.max(p.Size.X,p.Size.Y,p.Size.Z)<=reach
     if fits and math.abs(l.X)<=half.X and math.abs(l.Y)<=half.Y and math.abs(l.Z)<=half.Z and (not best or v>bestV) then best,bestV=p,v end
    end
   end
   -- (no single visible part beside it - Floor 4's machines nest theirs one level down: keep the hit
   -- box, and bodyParts outlines the visible parts inside it / its machine instead of dropping it)
   table.insert(expanded,best or target)
  else table.insert(expanded,target) end
 end
 targets=expanded
 -- one outline per whole object (several parts of the same object share it)
 local want={}
 for _,target in targets do
  if target and target:IsA('BasePart') and target.Parent then want[objectOf(target)]=true
  elseif target and target:IsA('Model') and target.Parent then want[target]=true end
 end
 for obj in want do if obj.Parent then self:_Mark(obj) end end
 for obj,mk in self._marks do if not want[obj] or not obj.Parent then self:_Unmark(obj) end end
end
-- every frame: the task bar's fade-in with the rest of the HUD, and a new objective's own fade
function Controller:_FadeStep()
 if not self._fadeParts then return end
 local a=1
 if Reveal.Active() or self._revealing then a=Reveal.Alpha();self._revealing=Reveal.Active() end
 local k=1
 if self._textIn then
  local u=math.clamp((os.clock()-self._textIn)/.45,0,1);k=u*u*(3-2*u)
  if u>=1 then self._textIn=nil end
 end
 for _,f in self._fadeParts do
  local obj,prop,base=f[1],f[2],f[3]
  local w=a
  if prop=='TextTransparency' and (obj==self._label or obj==self._side) then w=a*k end
  local v=1-(1-base)*w
  if obj[prop]~=v then obj[prop]=v end
 end
end
function Controller:Start()
 self._scope:Add(RunService.RenderStepped:Connect(function()local ok,err=pcall(self._FadeStep,self);if not ok then warn(err) end end))
 self._scope:Add(game.RunService.Heartbeat:Connect(function(dt)self._refresh+=dt;if self._refresh>=.15 then self._refresh=0;self:_Update()end end))
 -- (before the frame is drawn, so a moving object's outline is always exactly on it)
 RunService:BindToRenderStep('EHTaskOutlines',Enum.RenderPriority.Last.Value,function(dt)local ok,err=pcall(self._DrawOutlines,self,dt);if not ok then warn(err) end end)
 self._scope:Add(function()RunService:UnbindFromRenderStep('EHTaskOutlines')end)
end
function Controller:Destroy()
 for _,mk in self._marks or {} do mk.model:Destroy() end
 if self._fade then self._fade:Cancel()end;if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
