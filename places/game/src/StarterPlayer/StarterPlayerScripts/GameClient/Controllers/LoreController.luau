--!nonstrict
-- Paper reader (R32 rebuild, readable on every device). Authored in StarterGui.PocketRecords:
--   Backdrop, Paper (CanvasGroup) > Hole x3, Margin, Header > Eyebrow, Title, Rule,
--   Sheet (ScrollingFrame) > Body, Signature, Footer > Divider, Smaller, Larger, Close, Key
-- The whole page is shown at once in a clear serif in a scrolling sheet; there is no "read all"
-- step. The sheet is sized in screen points to fit the screen (never shrunk below a readable
-- size - long pages scroll instead), and A- / A+ change the text size for the rest of the session.
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local HudScale=require(Shared.Utilities.HudScale)
local TweenService=game:GetService('TweenService')
local CAS=game:GetService('ContextActionService')
local UIS=game:GetService('UserInputService')
local Controller={};Controller.__index=Controller
local MAX=Vector2.new(560,720) -- largest sheet (points)
local SIZES={17,19,21,23,26} -- body text sizes the A- / A+ buttons step through
local KIND={Paper='LOOSE PAPER',Record='MAINTENANCE RECORD'}
local EASE=TweenInfo.new(.24,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
function Controller.new(p,gui)return setmetatable({Name='LoreController',Dependencies={'InputController'},_player=p,_gui=gui},Controller)end
function Controller:Init(deps)
 self._scope=Scope.new();self._input=deps.InputController
 local gui=AuthoredGui.Get(self._gui,'PocketRecords');self._screen=gui
 local paper=gui:WaitForChild('Paper');paper.Visible=false;self._panel=paper
 self._backdrop=gui:WaitForChild('Backdrop');self._rustle=gui:FindFirstChild('PaperRustle')
 self._scale=paper:WaitForChild('ReaderScale')
 local head=paper:WaitForChild('Header');self._eyebrow=head:WaitForChild('Eyebrow');self._title=head:WaitForChild('Title')
 self._sheet=paper:WaitForChild('Sheet');self._body=self._sheet:WaitForChild('Body');self._signature=self._sheet:WaitForChild('Signature')
 local foot=paper:WaitForChild('Footer');self._close=foot:WaitForChild('Close');self._smaller=foot:WaitForChild('Smaller');self._larger=foot:WaitForChild('Larger');self._key=foot:FindFirstChild('Key')
 -- touch players get one size up by default; phones are held further from the eye than a monitor
 self._size=UIS.PreferredInput==Enum.PreferredInput.Touch and 3 or 2
 self._scope:Add(self._close.Activated:Connect(function()self:_Close()end))
 self._scope:Add(self._smaller.Activated:Connect(function()self:_Resize(-1)end))
 self._scope:Add(self._larger.Activated:Connect(function()self:_Resize(1)end))
 for _,b in {self._close,self._smaller,self._larger}do
  local function state()
   local s=b.GuiState;local on=s==Enum.GuiState.Hover or s==Enum.GuiState.Press or game.GuiService.SelectedObject==b
   TweenService:Create(b,TweenInfo.new(.12,Enum.EasingStyle.Quad),{BackgroundTransparency=s==Enum.GuiState.Press and .84 or on and .92 or 1}):Play()
   local o=b:FindFirstChild('Outline');if o then TweenService:Create(o,TweenInfo.new(.12,Enum.EasingStyle.Quad),{Transparency=on and .1 or .45}):Play() end
  end
  pcall(function()self._scope:Add(b:GetPropertyChangedSignal('GuiState'):Connect(state))end)
 end
 self._scope:Add(gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()if self._panel.Visible then self:_Fit() end end))
end
-- size the sheet to the screen in points; console gets a slightly larger page
function Controller:_Fit()
 local size=self._screen.AbsoluteSize;if size.X<=0 or size.Y<=0 then return end
 local s=HudScale.IsTenFoot() and 1.15 or 1
 local w=math.clamp(size.X/s-24,280,MAX.X);local h=math.clamp(size.Y/s-24,260,MAX.Y)
 self._scale.Scale=s;self._panel.Size=UDim2.fromOffset(w,h)
 -- the header grows with a long title; the scrolling sheet takes the space under it
 task.defer(function()
  local head=self._title.Parent
  local top=head.Position.Y.Offset+head.AbsoluteSize.Y/math.max(s,.01)+12
  self._sheet.Position=UDim2.new(0,60,0,top);self._sheet.Size=UDim2.new(1,-72,1,-(top+74))
 end)
 local touch=UIS.PreferredInput==Enum.PreferredInput.Touch
 if self._key then self._key.Visible=not touch;self._key.Text=UIS.PreferredInput==Enum.PreferredInput.Gamepad and '[B]' or '[E]' end
end
function Controller:_Resize(step)
 local n=math.clamp(self._size+step,1,#SIZES)
 if n==self._size then return end
 self._size=n;self._body.TextSize=SIZES[n];self._signature.TextSize=SIZES[n]+5
 self._smaller.TextTransparency=n==1 and .6 or 0;self._larger.TextTransparency=n==#SIZES and .6 or 0
 self:_Rustle(.18,1.4)
end
function Controller:_Rustle(volume,pitch)
 local r=self._rustle;if not r then return end
 r.Volume=volume;r.PlaybackSpeed=pitch+math.random(-4,4)/100;r.TimePosition=0;r:Play()
end
function Controller:_Close()
 if not self._panel.Visible or self._closing then return end
 self._closing=true;self._origin=nil;self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('Lore',false)
 if self._controls then self._controls:Enable() end
 if game.GuiService.SelectedObject and game.GuiService.SelectedObject:IsDescendantOf(self._panel) then game.GuiService.SelectedObject=nil end
 self:_Rustle(.35,1.12)
 local bd=self._backdrop
 TweenService:Create(bd,TweenInfo.new(.2,Enum.EasingStyle.Quad),{BackgroundTransparency=1}):Play()
 if self._tween then self._tween:Cancel() end
 self._tween=TweenService:Create(self._panel,TweenInfo.new(.18,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{GroupTransparency=1,Position=UDim2.new(.5,0,.5,14)})
 self._tween.Completed:Connect(function(st)
  if st==Enum.PlaybackState.Completed then self._panel.Visible=false;bd.Visible=false end
  self._closing=false
 end)
 self._tween:Play()
end
function Controller:_Open()
 self._closing=false
 local kind=KIND[self._player:GetAttribute('EHLoreKind') or 'Record'] or 'RECORD'
 self._eyebrow.Text=kind..'  ·  LEVEL '..tostring(self._player:GetAttribute('EHLoreLevel') or 5)
 self._title.Text=self._player:GetAttribute('EHLoreTitle') or 'Maintenance record'
 local body=self._player:GetAttribute('EHLoreBody') or ''
 if body=='' then body=self._player:GetAttribute('EHLoreExcerpt') or '' end
 self._body.Text=body;self._body.TextSize=SIZES[self._size];self._signature.TextSize=SIZES[self._size]+5
 local author=self._player:GetAttribute('EHLoreAuthor') or ''
 self._signature.Text=author~='' and ('— '..author) or '';self._signature.Visible=author~=''
 self._sheet.CanvasPosition=Vector2.zero
 self:_Fit()
 -- pick the sheet up: a short fade and lift, no spin
 local bd=self._backdrop;bd.Visible=true;bd.BackgroundTransparency=1
 TweenService:Create(bd,EASE,{BackgroundTransparency=.5}):Play()
 if self._tween then self._tween:Cancel() end
 self._panel.GroupTransparency=1;self._panel.Position=UDim2.new(.5,0,.5,16);self._panel.Visible=true
 self._tween=TweenService:Create(self._panel,EASE,{GroupTransparency=0,Position=UDim2.fromScale(.5,.5)});self._tween:Play()
 self:_Rustle(.55,1)
 self._player:SetAttribute('EHLoreOpen',true);self._input:SetBlocked('Lore',true);if self._controls then self._controls:Disable() end
 if UIS.PreferredInput==Enum.PreferredInput.Gamepad then game.GuiService.SelectedObject=self._close end
 local root=self._player.Character and self._player.Character:FindFirstChild('HumanoidRootPart');self._origin=root and root.Position
end
function Controller:Start()
 task.spawn(function()
  local scripts=self._player:WaitForChild('PlayerScripts');local module=scripts:WaitForChild('PlayerModule',10)
  if module then local ok,controls=pcall(function()return require(module):GetControls()end);if ok then self._controls=controls;if self._panel.Visible then controls:Disable() end end end
 end)
 self._scope:Add(self._player:GetAttributeChangedSignal('EHLoreSerial'):Connect(function()self:_Open()end))
 -- E / Backspace / B put it down; + and - (and the shoulder buttons) change the text size;
 -- the right stick / mouse wheel / finger scroll the sheet
 CAS:BindAction('BlackwaterLore',function(_,state,input)
  if not self._panel.Visible or self._closing then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then
   local k=input.KeyCode
   if k==Enum.KeyCode.Equals or k==Enum.KeyCode.KeypadPlus or k==Enum.KeyCode.ButtonR1 then self:_Resize(1)
   elseif k==Enum.KeyCode.Minus or k==Enum.KeyCode.KeypadMinus or k==Enum.KeyCode.ButtonL1 then self:_Resize(-1)
   else self:_Close() end
  end
  return Enum.ContextActionResult.Sink
 end,false,Enum.KeyCode.E,Enum.KeyCode.Backspace,Enum.KeyCode.ButtonB,Enum.KeyCode.Equals,Enum.KeyCode.Minus,Enum.KeyCode.KeypadPlus,Enum.KeyCode.KeypadMinus,Enum.KeyCode.ButtonR1,Enum.KeyCode.ButtonL1)
 self._scope:Add(function()CAS:UnbindAction('BlackwaterLore')end)
 self._scope:Add(game:GetService('RunService').Heartbeat:Connect(function(dt)
  if not self._panel.Visible or self._closing then return end
  -- gamepad: right stick scrolls the page
  local pad=UIS:GetGamepadState(Enum.UserInputType.Gamepad1)
  for _,i in pad do if i.KeyCode==Enum.KeyCode.Thumbstick2 and math.abs(i.Position.Y)>.2 then self._sheet.CanvasPosition-=Vector2.new(0,i.Position.Y*dt*600) end end
  local root=self._player.Character and self._player.Character:FindFirstChild('HumanoidRootPart')
  if self._player:GetAttribute('EHContext')~='ActiveFloor' or not root or (self._origin and (root.Position-self._origin).Magnitude>10) then self:_Close() end
 end))
end
function Controller:Destroy()
 if self._tween then self._tween:Cancel() end
 if self._panel.Visible then self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('Lore',false);if self._controls then self._controls:Enable() end end
 if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
