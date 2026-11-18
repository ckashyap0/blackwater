--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Visibility=require(game.ReplicatedStorage.Game.Shared.Utilities.ObjectiveVisibility)
local HudScale=require(game.ReplicatedStorage.Game.Shared.Utilities.HudScale)
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Reveal=require(game.ReplicatedStorage.Game.Shared.Utilities.HudReveal)
local Level5=require(game.ReplicatedStorage.Game.Shared.Config.Level5)
local Sources=require(game.ReplicatedStorage.Game.Shared.Utilities.ObjectiveSources)
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
 -- (R36) COLLAPSE: the chevron beside OBJECTIVE (authored TaskBar.Heading.Toggle) folds the objective lines
 -- away and brings them back; tap it on mobile, click it or press O on a computer. It starts open, and a
 -- player's choice holds for the rest of the session (player attribute EHObjectiveCollapsed).
 local toggle=frame:FindFirstChild('Heading') and frame.Heading:FindFirstChild('Toggle')
 self._toggle=toggle;self._chevron=toggle and toggle:FindFirstChild('Chevron')
 self._expand=self._player:GetAttribute('EHObjectiveCollapsed') and 0 or 1
 local function flip() self._player:SetAttribute('EHObjectiveCollapsed',not self._player:GetAttribute('EHObjectiveCollapsed') or nil) end
 if toggle then self._scope:Add(toggle.Activated:Connect(flip)) end
 self._scope:Add(game:GetService('UserInputService').InputBegan:Connect(function(io,gp)
  if gp or io.KeyCode~=Enum.KeyCode.O or not self._screen.Enabled then return end
  flip()
 end))
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
local OUTLINE_IN,OUTLINE_OUT=70,90 -- (Nov 13) studs: the outline comes on inside IN and stays until you are past OUT
local STANDIN_T=0 -- (Nov 13: a Highlight skips see-through parts, so the stand-in stays opaque; the z-fight at range is
                  -- handled by the larger INSET and the distance fade below)
local FAR_FULL,FAR_NONE,FAR_DEPTH=16,24,0 -- (Nov 13, later) the line only comes in once you are close enough to use the thing (full inside 16 studs, gone past 24), and never through walls -- (Nov 13, Ryan) full line inside 26 studs, fades out by 58; no through-wall line past 40
local OUTLINE_T=0 -- (Nov 15, Ryan: crisp, solid line) was .08
local FAR_SOFT={28,110,.6}
local NEAR_FADE={9,4.5} -- (Nov 17, Ryan) studs: walking up to a target (Marty, a machine) the line fades out - full beyond 9, gone inside 4.5 -- (Nov 16) studs where the line starts to soften, where it is softest, and how far it softens (0-1)
local function nearFade(d) local u=math.clamp((d-NEAR_FADE[2])/(NEAR_FADE[1]-NEAR_FADE[2]),0,1);return u*u*(3-2*u) end
local OUTLINE_ALWAYS=true -- (Nov 15, Ryan) no fade-in, no distance or close-up fade, visible through walls from anywhere
--      -- (R36) outline transparency when fully shown: a firm, clear line, through walls too
local INSET=.03           -- (Nov 13: was .012 - at range the stand-in z-fought the real face and the line crawled) studs: how far each stand-in face sits inside the real one (a fixed hair, not a
                          -- share of the size - scaling every piece about its own centre opened little gaps
                          -- between touching pieces, which showed as notches and steps in the line)
-- (Nov 13, later) OUTLINE STYLE. 'Shell' (default): no Highlight at all. Each stand-in becomes a thin glowing
-- shell (ForceField material) a hair larger than the real piece, so the glow follows the object's real shape,
-- is drawn as geometry (smooth at any distance, no jagged pixel line, no crawl) and never hits Roblox's limit on
-- how many Highlights can be on screen (going over it is what made outlines blink). It fades in from SHELL_FAR
-- studs and is full strength inside SHELL_NEAR. 'Highlight' brings back the old pixel line.
local OUTLINE_STYLE='Highlight' -- (Nov 13, later: Ryan prefers the white line back)
local SHELL_NEAR,SHELL_FAR=260,320 -- studs
local SHELL_T=.25 -- shell transparency when fully shown (0 = brightest)
local SHELL_PAD=.035 -- studs the shell sits outside each real face
local SHELL_COLOR=Color3.fromRGB(236,234,222)
local function shellify(list,grow)
 for _,pr in list do
  local c=pr.copy
  c.Material=Enum.Material.ForceField;c.Color=SHELL_COLOR;c.Transparency=1;c.Reflectance=0
  if c:IsA('MeshPart') then pcall(function()c.TextureID=''end) end
  c.Size=c.Size+Vector3.one*(grow or (INSET+SHELL_PAD*2))
 end
end
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
local OUTLINE_AS={LinkSocket='DisconnectHousing',GateRelease='GateReleaseHousing',ValveWheel='WheelMesh',IsolationValve='WheelMesh',SwitchA='Brk_Housing',SwitchB='Brk_Housing',SwitchC='Brk_Housing'} -- (the wheel's hit box is invisible: outline the wheel itself)
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
 c.CFrame=p.CFrame*off;c.Transparency=STANDIN_T;c.LocalTransparencyModifier=0
 return c,off
end
-- (Nov 3) a hand wheel is outlined by its RIM only - a ring of thin segments laid along the rim, so the hub and
-- the spokes inside are never part of the line. The rim is a round tube: r = its centre radius, w = its
-- diameter (shares of the wheel's width), z = how far its plane sits off the part's centre (share of the depth).
-- Measured from the Floor 5 wheel's own mesh vertices: rim from radius 1.32 to 1.58 (of 1.58), its plane 0.05
-- in front of the part's centre; the tube is drawn a little thinner than the rim so it never shows.
-- (Nov 16, Ryan: the outline on the first Floor 5 task had gone - a Highlight draws nothing round a see-through part, so
-- the Nov 15 see-through disc showed no line) one very thin ring sitting INSIDE the rim's outer edge (hidden in the rim,
-- opaque, so the Highlight draws it): reads as a single circle round the outside of the wheel, no spokes or hub
local RING={WheelMesh={r=.475,w=.01,z=-.1,n=56}}
local CIRCLE_PX=4 -- (Nov 16) line width of the wheel's circle, in SurfaceGui pixels (100 per stud)
local function ringParts(obj,model)
 local spec=RING[obj.Name];if not spec then return nil end
 local R=math.min(obj.Size.X,obj.Size.Y)*spec.r;local seg=2*math.pi*R/spec.n*1.02
 local list={}
 for i=0,spec.n-1 do
  local a=(i+.5)/spec.n*2*math.pi
  local off=CFrame.new(0,0,obj.Size.Z*spec.z)*CFrame.Angles(0,0,a)*CFrame.new(R,0,0)*CFrame.Angles(0,0,math.pi/2) -- (a cylinder lies along its X: turned along the rim)
  local c=Instance.new('Part');c.Name='Rim';c.Shape=Enum.PartType.Cylinder;c.Anchored=true;c.CanCollide=false;c.CanQuery=false;c.CanTouch=false;c.CastShadow=false
  local dia=obj.Size.X*spec.w;c.Size=Vector3.new(seg,dia,dia);c.Transparency=STANDIN_T;c.Material=Enum.Material.SmoothPlastic
  c.CFrame=obj.CFrame*off;c.Parent=model
  table.insert(list,{src=obj,copy=c,cf=obj.CFrame,off=off})
 end
 return list
end
local function outline(model,depth)
 local h=Instance.new('Highlight');h.Name='Outline'
 h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(236,234,222);h.OutlineTransparency=1
 h.DepthMode=depth;h.Adornee=model;h.Parent=model
 return h
end
function Controller:_Mark(obj)
 local mk=self._marks[obj]
 if mk then mk.leaving=false;return end
 if RING[obj.Name] then
  -- the rim: full strength while you can see the wheel, softer while a wall is in the way (the full-strength
  -- line through walls read as a smeared shape)
  local model=Instance.new('Model');model.Name='Outline_'..obj.Name
  -- (Nov 16, Ryan: 'one outline round the wheel, seen through walls, like the other ones') a Highlight can't do a
  -- single circle round a spoked wheel (it also traces every gap between the spokes, and a hidden ring drew two
  -- lines and no line through walls). The wheel's outline is ONE white circle at the rim's outer edge, drawn by an
  -- always-on-top SurfaceGui on an invisible disc in the wheel's plane (both faces), so it shows through walls.
  local spec=RING[obj.Name]
  local D=math.min(obj.Size.X,obj.Size.Y)+.06
  local off=CFrame.new(0,0,obj.Size.Z*spec.z)
  local disc=Instance.new('Part');disc.Name='RimCircle';disc.Anchored=true;disc.CanCollide=false;disc.CanQuery=false;disc.CanTouch=false;disc.CastShadow=false
  disc.Transparency=1;disc.Size=Vector3.new(D,D,.05);disc.CFrame=obj.CFrame*off;disc.Parent=model
  local strokes={}
  for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
   local g=Instance.new('SurfaceGui');g.Face=face;g.AlwaysOnTop=true;g.LightInfluence=0;g.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud;g.PixelsPerStud=100;g.Adornee=disc;g.Parent=disc
   local f=Instance.new('Frame');f.BackgroundTransparency=1;f.AnchorPoint=Vector2.new(.5,.5);f.Position=UDim2.fromScale(.5,.5);f.Size=UDim2.new(1,-CIRCLE_PX,1,-CIRCLE_PX);f.Parent=g
   local c=Instance.new('UICorner');c.CornerRadius=UDim.new(.5,0);c.Parent=f
   local s=Instance.new('UIStroke');s.Color=Color3.fromRGB(236,234,222);s.Thickness=CIRCLE_PX;s.Transparency=1;s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border;s.Parent=f
   table.insert(strokes,s)
  end
  model.Parent=folder()
  self._marks[obj]={obj=obj,model=model,h=nil,circle=strokes,parts={{src=obj,copy=disc,cf=obj.CFrame,off=off}},alpha=0,leaving=false,ring=true,seen=1}
  return
 end
 if obj:IsA('BasePart') and obj:GetAttribute('EHItemState')~=nil and OUTLINE_STYLE=='Shell' then
  -- a pick-up: one shell around the item itself, following it if it moves
  local model=Instance.new('Model');model.Name='PickupOutline_'..obj.Name
  local pairs_={}
  for _,p in bodyParts(obj) do local c,off=standIn(p,obj);if c then c.Parent=model;table.insert(pairs_,{src=p,copy=c,cf=p.CFrame,off=off}) end end
  if #pairs_==0 then model:Destroy();return end
  shellify(pairs_);model.Parent=folder()
  self._marks[obj]={obj=obj,model=model,parts=pairs_,alpha=0,leaving=false,direct=true};return
 end
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
 local h=nil
 if OUTLINE_STYLE=='Shell' then shellify(pairs_)
 else
  h=Instance.new('Highlight');h.Name='Outline'
  h.FillTransparency=1;h.OutlineColor=Color3.fromRGB(236,234,222);h.OutlineTransparency=1
  h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop;h.Adornee=model;h.Parent=model
 end
 model.Parent=folder()
 self._marks[obj]={obj=obj,model=model,h=h,parts=pairs_,alpha=0,leaving=false}
end
function Controller:_Unmark(obj)
 local mk=self._marks[obj];if mk then mk.leaving=true end
end
-- every frame: fades, and the stand-in follows the object if it moves (a carried or dropped fuse)
function Controller:_DrawOutlines(dt)
 for obj,mk in self._marks do
  if OUTLINE_ALWAYS then mk.alpha=mk.leaving and 0 or 1 else mk.alpha+=((mk.leaving and 0 or 1)-mk.alpha)*(1-math.exp(-math.clamp(dt,0,.1)*9)) end
  -- the object itself has gone (picked up - even just predicted on this screen): its outline goes
  -- with it at once instead of fading out where the object used to be
  -- (Nov 13) a dropped item gets its outline only once it has landed and settled (it used to sit where the
  -- card would end up while the card was still falling)
  if mk.direct then local st=obj:GetAttribute('EHItemState');if st~=mk.lastState then mk.lastState=st;mk.stateAt=os.clock() end
   if st=='Dropped' and os.clock()-(mk.stateAt or 0)<1.4 then mk.alpha=0 end end
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
   -- (full strength from ~10 studs, fading to nothing within ~4)
   local cam=workspace.CurrentCamera;local near=1
   local ref=(mk.parts[1] and mk.parts[1].copy) or (obj:IsA('BasePart') and obj)
   -- (R36) only fades when you are right on it (full strength from 5 studs): the owner wants it clear
   if cam and ref then local u=math.clamp(((cam.CFrame.Position-ref.Position).Magnitude-2)/3,0,1);near=u*u*(3-2*u) end
   -- (R36) the wheel rim stays full strength through walls too (it used to dim to 45% behind a wall)
   -- (Nov 13) far away the line is only a few jagged pixels, so it is off until you are within OUTLINE_IN
   -- studs and then stays on until you are past OUTLINE_OUT (two distances, so it never flickers at the edge);
   -- it eases in and out, and the Highlight is switched off entirely while it is invisible
   local dist=(cam and ref) and (cam.CFrame.Position-ref.Position).Magnitude or 0
   -- (Nov 13, Ryan: 'the outlines glitch and look pixelated far away') a Highlight's line is a fixed
   -- pixel width, so on a small far-off shape it turns into a jagged, crawling smear. It now thins out
   -- smoothly with distance (full strength inside FAR_FULL, gone by FAR_NONE) instead of a hard switch
   -- at 70 studs, and past FAR_DEPTH it stops drawing through walls (the through-wall line is what
   -- shimmered most at range).
   local nearD,farD=FAR_FULL,FAR_NONE
   if not mk.h then nearD,farD=SHELL_NEAR,SHELL_FAR end
   local far=math.clamp((dist-nearD)/(farD-nearD),0,1);local farK=1-far*far*(3-2*far)
   if mk.rangeK==nil then mk.rangeK=farK end
   mk.rangeK+=(farK-mk.rangeK)*(1-math.exp(-math.clamp(dt,0,.1)*6))
   if mk.circle then
    -- the wheel's single circle (always on top): same strength rules as the other outlines
    local strength=mk.alpha
    if OUTLINE_ALWAYS then local u=math.clamp((dist-FAR_SOFT[1])/(FAR_SOFT[2]-FAR_SOFT[1]),0,1);u=u*u*(3-2*u);strength=mk.alpha*(1-FAR_SOFT[3]*u)*nearFade(dist) end
    local t=1-(1-OUTLINE_T)*strength
    for _,s in mk.circle do if math.abs(s.Transparency-t)>.002 then s.Transparency=t end end
   elseif mk.h then
    -- never through walls: the stand-in sits a hair inside the real object, so the Highlight stays AlwaysOnTop,
    -- and a ray from the camera decides whether the thing is actually in view (checked a few times a second,
    -- eased so it never blinks)
    if mk.h.DepthMode~=Enum.HighlightDepthMode.AlwaysOnTop then mk.h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop end
    if os.clock()>=(mk.losAt or 0) and cam and ref then
     mk.losAt=os.clock()+.12
     local o=cam.CFrame.Position;local d=ref.Position-o
     local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Exclude
     local ex={mk.model,self._player.Character,cam};if obj:IsA('Model') then table.insert(ex,obj) elseif obj.Parent and obj.Parent:IsA('Model') and obj.Parent~=workspace then table.insert(ex,obj.Parent) else table.insert(ex,obj) end
     for _,pr in mk.parts do if pr.src then table.insert(ex,pr.src) end end
     rp.FilterDescendantsInstances=ex
     local r=workspace:Raycast(o,d*.97,rp)
     mk.inView=(r==nil) or (r.Instance.Transparency>=.95) or (not r.Instance.CanCollide and r.Instance.Size.Magnitude<3)
    end
    mk.viewK=(mk.viewK or 0)+(((mk.inView~=false) and 1 or 0)-(mk.viewK or 0))*(1-math.exp(-math.clamp(dt,0,.1)*10))
    local strength=mk.alpha*near*mk.rangeK*mk.viewK
    if OUTLINE_ALWAYS then
     -- (Nov 16, Ryan: 'the outlines look weird from far away') still on everywhere and through walls, but a
     -- Highlight's line is a fixed pixel width, so on a small far-off shape it turned into a hard, jagged block.
     -- Past FAR_SOFT studs it eases to a softer, see-through line (never gone), and stays crisp up close.
     local u=math.clamp((dist-FAR_SOFT[1])/(FAR_SOFT[2]-FAR_SOFT[1]),0,1);u=u*u*(3-2*u)
     strength=mk.alpha*(1-FAR_SOFT[3]*u)*nearFade(dist)
    end
    local t=1-(1-OUTLINE_T)*strength
    if math.abs(mk.h.OutlineTransparency-t)>.002 then mk.h.OutlineTransparency=t end
    local on=strength>.01
    if mk.h.Enabled~=on then mk.h.Enabled=on end
   else
    -- the shell: no close-up fade (it is geometry, it stays clean up close)
    local strength=mk.alpha*mk.rangeK
    local t=strength>.01 and 1-(1-SHELL_T)*strength or 1
    if math.abs((mk.shownT or -1)-t)>.002 then mk.shownT=t;for _,pr in mk.parts do if pr.copy.Parent then pr.copy.Transparency=t end end end
   end
  end
 end
end
function Controller:_HideOutlines()
 for obj in self._marks do self:_Unmark(obj) end
end
function Controller:_Update()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment');local floor
 if env then for _,m in env:GetChildren()do local e=m:GetAttribute('EncounterId');if (e=='Level5' or e=='Level4' or e=='Level3') and m:GetAttribute('TaskActive')then floor=m;break end end end
 local src=(not floor) and Sources.Current(self._player) or nil -- (no floor task: a registered source, e.g. the surface keycard)
 if src then floor=src.key end
 local active=(src and not self._player:GetAttribute('EHCinematic') or self._input:GetContext()=='ActiveFloor') and not self._menu and not self._player:GetAttribute('EHLoreOpen') and floor~=nil
 -- (a single short gap while the floor republishes its attributes never blinks the bar off)
 local now=os.clock()
 if active then self._activeSince=self._activeSince or now;self._inactiveSince=nil else self._inactiveSince=self._inactiveSince or now;self._activeSince=nil end
 local shown=active or (self._screen.Enabled and now-(self._inactiveSince or now)<.45)
 if self._screen.Enabled~=shown then self._screen.Enabled=shown;if shown then self._shownAt=now end end
 -- after the lift the task bar fades in with the rest of the HUD
  -- (the fade-in with the HUD runs every frame in _FadeStep, not on this slower tick)



 -- (Nov 13) the same short grace as the bar: a brief gap never blinks the outlines off and on again
 if not active then if not shown then self:_HideOutlines() end;return end
 local message=src and src.text or floor:GetAttribute('TaskText')or ''
 -- (R41) Level 3 split-up: the crew member sent down the hatch reads their own line
 if not src and self._player:GetAttribute('EHL3Sent') then message=floor:GetAttribute('TaskTextSent') or message end
 local names={}
 for name in string.gmatch(floor:GetAttribute('TaskTargets')or floor:GetAttribute('TaskTarget')or '','[^,]+')do table.insert(names,name)end
 local targets={}
 for _,name in names do local part=Refs.Find(floor,name) or (env.Elevator and Refs.Find(env.Elevator,name));if part then table.insert(targets,part)end end
 if src then targets=src.targets or {} end
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
 if src then self._spillFloor=floor;self._spillZones={} elseif not self._spillZones or self._spillFloor~=floor then
  self._spillFloor=floor;self._spillZones={}
  for _,d in floor:GetDescendants()do if d:IsA('BasePart') and d:GetAttribute('SlipHazard') then table.insert(self._spillZones,d) end end
 end
 local wet=false
 for _,z in self._spillZones do if z.Parent and z:GetAttribute('SlipActive')==true then wet=true;break end end
 -- (the mop task is retired while MopSideTask is off, so the line follows that switch; floor pay borrows it for a moment)
 local side=(wet and Level5.MopSideTask) and MOP_LINE or ''
 if self._coinNote and now<(self._coinNoteUntil or 0) then side=self._coinNote end
 -- a new floor starts with a clean line: the last floor's objective is never shown on it, even for a frame
 if floor~=self._lastFloor then self._lastFloor=floor;self._shownState=nil;self._pending=nil;self._label.Text='';self._side.Text='';self._side.Visible=false end
 local composed=message..'\n'..side
 if composed~=self._pending then
  -- only a number changed (restart %, jobs done): no hold, no fade - the line just updates in place
  local sameShape=self._pending~=nil and (string.gsub(composed,'%d',''))==(string.gsub(self._pending,'%d',''))
  self._pending=composed;if not sameShape then self._pendingSince=now end
 end
 -- (Nov 16, Ryan: 'the objective fades out to a different one - this should NEVER occur') while the bar is
 -- hidden or still easing back in after a cutscene / black fade, a new objective is swapped in at once and with
 -- no fade of its own, so the bar only ever comes back already showing the right line
 local hidden=(self._cutK or 1)<.995 or (self._shownAt and now-self._shownAt<.3)
 if composed~=self._shownState and (self._shownState==nil or hidden or now-(self._pendingSince or now)>=.2) then
  self._shownState=composed
   if self._label.Text~=message then
    -- a number ticking over (restart %, jobs 2/5) updates the line in place; only a new objective fades in
    local same=(string.gsub(self._label.Text,'%d',''))==(string.gsub(message,'%d',''))
    self._label.Text=message;if not same and not hidden then self._textIn=os.clock() elseif hidden then self._textIn=nil end -- (fades in smoothly: _FadeStep)
   end
   if self._side.Text~=side then self._side.Text=side;if not hidden then self._textIn=os.clock() end end
  local showSide=side~='' and (self._expand or 1)>.02 -- (folded away: _FadeStep shows it again on opening)
  if self._side.Visible~=showSide then self._side.Visible=showSide end
 end
 -- Dropped items ALWAYS keep their white outline (through walls), whatever the current task is.
 if src then self._itemsFloor=floor;self._items={} elseif not self._items or self._itemsFloor~=floor or os.clock()>(self._itemsScan or 0) then
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
 -- (R36) folding the lines away and back: a short eased fade, then the lines leave the list so the bar shrinks
 local want=self._player:GetAttribute('EHObjectiveCollapsed') and 0 or 1
 local dt=math.min(1/20,os.clock()-(self._lastFold or os.clock()));self._lastFold=os.clock()
 self._expand=self._expand or want
 if self._expand~=want then
  local step=dt/.22;self._expand=want>self._expand and math.min(want,self._expand+step) or math.max(want,self._expand-step)
 end
 local open=self._expand>.02
 if self._label.Visible~=open then self._label.Visible=open end
 local sideOn=open and self._side.Text~=''
 if self._side.Visible~=sideOn then self._side.Visible=sideOn end
 local e=self._expand;e=e*e*(3-2*e) -- (eased both ways, no bounce)
 if self._chevron then local r=180*(1-e);if self._chevron.Rotation~=r then self._chevron.Rotation=r end end -- (points up when open, down when folded)
 local a=1
 if Reveal.Active() or self._revealing then a=Reveal.Alpha();self._revealing=Reveal.Active() end
 -- (Nov 13) the task bar eases out for every cutscene and transition (camera shots, the lift ride, the
 -- intro, a black fade) and back in after, instead of sitting over them
 local ctx=self._input and self._input:GetContext()
 local away=self._player:GetAttribute('EHCinematic')~=nil or (ctx~=nil and ctx~='ActiveFloor')
 -- (Nov 16) a line that is about to change is never shown fading back in: the bar waits until it is current
 if self._pending~=nil and self._pending~=self._shownState and (self._cutK or 1)<.995 then away=true end
 local pg=self._player:FindFirstChild('PlayerGui')
 if not away and pg then for _,n in {'ArrivalCover','DescentFade','WakeLids','ArrivalText','IntroHud'} do local g=pg:FindFirstChild(n);if g and g.Enabled then away=true;break end end end
 self._cutK=self._cutK or (away and 0 or 1)
 self._cutK+=((away and 0 or 1)-self._cutK)*math.min(1,dt*(away and 9 or 4))
 local ck=self._cutK*self._cutK*(3-2*self._cutK)
 a*=ck
 local k=1
 if self._textIn then
  local u=math.clamp((os.clock()-self._textIn)/.45,0,1);k=u*u*(3-2*u)
  if u>=1 then self._textIn=nil end
 end
 for _,f in self._fadeParts do
  local obj,prop,base=f[1],f[2],f[3]
  local w=a
  if prop=='TextTransparency' and (obj==self._label or obj==self._side) then w=a*k*e end
  -- (Nov 13) folding it away (the arrow, on every device) takes the OBJECTIVE heading with it; only the arrow stays
  if prop=='TextTransparency' and obj.Name=='Heading' and obj.Parent==self._label.Parent then w=a*e end
  local v=1-(1-base)*w
  if obj[prop]~=v then obj[prop]=v end
 end
end
function Controller:Start()
 task.spawn(function()
  local remote=game.ReplicatedStorage.Game:WaitForChild('Network'):WaitForChild('Coins',30)
  if remote then self._scope:Add(remote.OnClientEvent:Connect(function(kind,amount)
   if kind=='Earned' then self._coinNote='+'..tostring(amount)..' coins';self._coinNoteUntil=os.clock()+4 end
  end)) end
 end)
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
