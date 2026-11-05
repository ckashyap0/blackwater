--!nonstrict
-- How black the screen is right now (0 = clear .. 1 = solid black), read from the game's own
-- full-screen covers: the join cover, the descent fade, the wake-up lids and the lift's eyelids.
-- First-person view models (hands, flashlight, carried items, mop) multiply their visibility by
-- 1 - Black(), so they come up exactly with the picture instead of popping in, and are never
-- drawn as dark shapes over a black screen.
local Players=game:GetService('Players')
local Fade={}
local COVERS={{'ArrivalCover','Black'},{'DescentFade','Black'},{'WakeLids','Shut'},{'IntroEyes','Eyes','Closed'}}
local cache={}
local function frame(gui,path)
 local f=gui
 for i=2,#path do f=f and f:FindFirstChild(path[i]) end
 return f
end
local lastClock,lastValue=0,0
function Fade.Black():number
 local now=os.clock()
 if now==lastClock then return lastValue end
 lastClock=now
 local player=Players.LocalPlayer;local pg=player and player:FindFirstChildOfClass('PlayerGui')
 if not pg then lastValue=1;return 1 end
 local black=0
 for i,path in COVERS do
  local e=cache[i]
  if not e or not e.gui.Parent or not e.f or not e.f.Parent then
   local gui=pg:FindFirstChild(path[1]);e=gui and {gui=gui,f=frame(gui,path)} or nil;cache[i]=e
  end
  if e and e.f and e.gui:IsA('ScreenGui') and e.gui.Enabled and e.f:IsA('GuiObject') and e.f.Visible then
   black=math.max(black,1-e.f.BackgroundTransparency)
  end
 end
 lastValue=math.clamp(black,0,1)
 return lastValue
end
-- How visible first-person view models (hands, flashlight, carried items, mop) should be: they
-- come up with the HUD after a cutscene (HudReveal) and never show over a black screen.
local Reveal
function Fade.ViewAlpha():number
 Reveal=Reveal or require(script.Parent:WaitForChild('HudReveal'))
 return math.clamp(math.min(Reveal.Alpha(),1-Fade.Black()),0,1)
end
-- Apply a visibility (0..1) to every part of a view model as LocalTransparencyModifier, on top of
-- a per-model base hide (e.g. stowed against a wall). Cheap: skips parts already at the value.
function Fade.ApplyToModel(model:Instance?,alpha:number,baseHide:number?)
 if not model then return end
 local hide=math.max(baseHide or 0,1-alpha)
 for _,d in model:GetDescendants()do
  if d:IsA('BasePart') and math.abs(d.LocalTransparencyModifier-hide)>.004 then d.LocalTransparencyModifier=hide end
 end
 if model:IsA('BasePart') and math.abs(model.LocalTransparencyModifier-hide)>.004 then model.LocalTransparencyModifier=hide end
end
return Fade
