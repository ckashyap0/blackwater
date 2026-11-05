--!strict
-- One uniform scale for HUD panels authored at a fixed design size.
-- Panels are laid out in offsets with fixed TextSize (no TextScaled), then a single
-- UIScale grows or shrinks everything together, so text, padding and spacing keep
-- identical proportions on PC, phone, tablet and console.
local UIS=game:GetService('UserInputService')
local GuiService=game:GetService('GuiService')
local Hud={}
export type Options={referenceSize:Vector2?,fit:Vector2?,fitMargin:number?,min:number?,max:number?,consoleBoost:number?}
function Hud.IsTenFoot():boolean
 local ok,tenFoot=pcall(function()return GuiService:IsTenFootInterface()end)
 return (ok and tenFoot==true)or UIS.PreferredInput==Enum.PreferredInput.Gamepad
end
function Hud.Factor(viewport:Vector2,options:Options?,tenFoot:boolean?):number
 local o:any=options or {}
 local lo,hi=o.min or .6,o.max or 1.15
 local s
 if o.fit then
  -- Whole panel must fit on screen with a margin (used for full-screen readers).
  local m=o.fitMargin or .9
  s=math.min(viewport.X*m/o.fit.X,viewport.Y*m/o.fit.Y)
  return math.clamp(s,.3,hi)
 end
 local ref=o.referenceSize or Vector2.new(960,600)
 s=math.clamp(math.min(viewport.X/ref.X,viewport.Y/ref.Y),lo,hi)
 -- phones/tablets: a landscape phone is only ~360-430 points tall, which drove the scale to the
 -- 0.6 floor and made prompts tiny. Touch screens get a boosted scale with a readable floor.
 if UIS.PreferredInput==Enum.PreferredInput.Touch then
  s=math.clamp(math.min(viewport.X/ref.X,viewport.Y/ref.Y)*(o.touchBoost or 1.35),o.touchMin or .82,1)
 end
 if tenFoot then s*=o.consoleBoost or 1.15 end -- couch distance: read from across the room
 return s
end
-- Adds a UIScale under target and keeps it current as the screen or input device changes.
function Hud.Attach(target:GuiObject,options:Options?):(UIScale,()->())
 local scale=Instance.new('UIScale');scale.Name='HudScale';scale.Parent=target
 local connections={}
 local function refresh()
  local screen=target:FindFirstAncestorWhichIsA('LayerCollector')
  local size=screen and (screen::any).AbsoluteSize or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize)
  if size and size.X>0 and size.Y>0 then scale.Scale=Hud.Factor(size,options,Hud.IsTenFoot())end
 end
 table.insert(connections,UIS:GetPropertyChangedSignal('PreferredInput'):Connect(refresh))
 table.insert(connections,target.AncestryChanged:Connect(function()
  refresh()
  local screen=target:FindFirstAncestorWhichIsA('LayerCollector')
  if screen and not connections.screen then connections.screen=screen:GetPropertyChangedSignal('AbsoluteSize'):Connect(refresh)end
 end))
 local screen=target:FindFirstAncestorWhichIsA('LayerCollector')
 if screen then connections.screen=screen:GetPropertyChangedSignal('AbsoluteSize'):Connect(refresh)end
 refresh()
 return scale,function()for _,c in connections do c:Disconnect()end;table.clear(connections)end
end
return table.freeze(Hud)
