--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- Loose lined paper reader. Records in the world are loose sheets of lined white paper;
-- reading one lifts that sheet into view (with a paper rustle) and "PUT DOWN" lays it back.
-- Authored at a fixed design size and scaled uniformly by HudScale for every device.
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local HudScale=require(Shared.Utilities.HudScale)
local TextService=game:GetService('TextService')
local TweenService=game:GetService('TweenService')
local CAS=game:GetService('ContextActionService')
local Controller={};Controller.__index=Controller
local PAPER=Vector2.new(460,600) -- design size of the sheet (px, before HudScale)
local FOOTER=66 -- button strip at the bottom of the sheet
local RULE=26 -- ruled-line pitch; handwriting sits on these lines
local TOP=78 -- y of the first rule
local TEXT_X=70 -- right of the red margin
local TEXT_W=PAPER.X-TEXT_X-24
function Controller.new(p,gui)return setmetatable({Name='LoreController',Dependencies={'InputController'},_player=p,_gui=gui,_rules={}},Controller)end
function Controller:Init(deps)
 self._scope=Scope.new();self._input=deps.InputController
 -- The sheet is authored in StarterGui.PocketRecords (edit it there):
 --   Backdrop (dims the world behind the sheet)
 --   Paper > Hole x3, Sheet (Margin, Eyebrow, PaperTitle, Handwriting > LineTemplate, RuleTemplate, Signature),
 --           Footer (Divider, ReadAll / PutDown > Outline, KeyChip > Key, Label, Selection)
 -- LineTemplate / RuleTemplate are copied for each line of writing and each ruled line.
 local gui=AuthoredGui.Get(self._gui,'PocketRecords')
 local panel=gui:WaitForChild('Paper');panel.Visible=false;self._panel=panel
 local aspect=panel:FindFirstChildOfClass('UIAspectRatioConstraint');self._aspect=aspect
 -- One uniform scale, but never below a readable size: on short (landscape phone) screens the
 -- sheet gets shorter instead of smaller, and the handwriting scrolls.
 local scale=panel:FindFirstChild('HudScale') or Instance.new('UIScale',panel);self._scale=scale
 self._height=PAPER.Y
 local function fit()
  local size=gui.AbsoluteSize;if size.X<=0 or size.Y<=0 then return end
  local s=math.clamp(math.min(size.X*.9/PAPER.X,size.Y*.92/PAPER.Y),.8,1.25)
  if HudScale.IsTenFoot()then s=math.max(s,1)end
  local height=math.clamp(math.floor(size.Y*.92/s),360,PAPER.Y)
  scale.Scale=s;self._height=height
  panel.Size=UDim2.fromOffset(PAPER.X,height);if aspect then aspect.AspectRatio=PAPER.X/height end
  if panel.Visible then self:_Layout()end
 end
 self._scope:Add(gui:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit));self._fit=fit
 local sheet=panel:WaitForChild('Sheet');self._sheet=sheet
 self._title=sheet:WaitForChild('PaperTitle')
 self._writing=sheet:WaitForChild('Handwriting');self._lines={};self._text=''
 self._lineTemplate=self._writing:WaitForChild('LineTemplate');self._lineTemplate.Visible=false
 self._ruleTemplate=sheet:WaitForChild('RuleTemplate');self._ruleTemplate.Visible=false
 self._signature=sheet:WaitForChild('Signature')
 local footer=panel:WaitForChild('Footer')
 self._readButton=footer:WaitForChild('ReadAll');self._putButton=footer:WaitForChild('PutDown')
 self._scope:Add(self._readButton.Activated:Connect(function()self:_Expand()end))
 self._scope:Add(self._putButton.Activated:Connect(function()self:_Close()end))
 self._rustle=gui:FindFirstChild('PaperRustle')
 self._backdrop=gui:FindFirstChild('Backdrop');self._eyebrow=sheet:FindFirstChild('Eyebrow')
 -- Button states: idle = outline only; hover = faint ink wash; pressed = deeper wash; gamepad
 -- selection = amber ring. All eased, nothing snaps.
 for _,b in {self._readButton,self._putButton}do
  local function state()
   local s=b.GuiState;local hover=s==Enum.GuiState.Hover;local press=s==Enum.GuiState.Press
   local outline=b:FindFirstChild('Outline')
   TweenService:Create(b,TweenInfo.new(.12,Enum.EasingStyle.Quad),{BackgroundTransparency=press and .84 or hover and .92 or 1}):Play()
   if outline then TweenService:Create(outline,TweenInfo.new(.12,Enum.EasingStyle.Quad),{Transparency=(hover or press) and .15 or .45}):Play()end
  end
  pcall(function()self._scope:Add(b:GetPropertyChangedSignal('GuiState'):Connect(state))end)
 end
 self._scope:Add(game.GuiService:GetPropertyChangedSignal('SelectedObject'):Connect(function()self:_Selection()end))
end
function Controller:_Selection()
 local sel=game.GuiService.SelectedObject
 for _,b in {self._readButton,self._putButton}do local f=b:FindFirstChild('Selection');if f then f.Visible=sel==b end end
end
-- key chips follow the device: R / E on keyboard, RB / B on a controller, none on touch
function Controller:_Chips()
 local input=game.UserInputService.PreferredInput
 local pad=input==Enum.PreferredInput.Gamepad;local touch=input==Enum.PreferredInput.Touch
 for b,keys in {[self._readButton]={'R','RB'},[self._putButton]={'E','B'}}do
  local chip=b:FindFirstChild('KeyChip');local label=b:FindFirstChild('Label')
  if chip then chip.Visible=not touch;chip.Key.Text=pad and keys[2] or keys[1];chip.Size=UDim2.fromOffset(pad and 28 or 24,22)end
  if label then label.Position=UDim2.fromOffset(touch and 0 or 42,0);label.Size=UDim2.new(1,touch and 0 or -50,1,0);label.TextXAlignment=touch and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left end
 end
end
local KIND={Paper='LOOSE PAPER',Record='MAINTENANCE RECORD'}
function Controller:_Rustle(volume,pitch)
 local r=self._rustle;if not r then return end
 r.Volume=volume;r.PlaybackSpeed=pitch+math.random(-4,4)/100;r.TimePosition=0;r:Play()
end
-- Size the handwriting, ruled lines and signature to the current text.
local HAND_FONT,HAND_SIZE=Enum.Font.Kalam,20
local function wrap(text)
 local out={}
 local function width(s)return TextService:GetTextSize(s,HAND_SIZE,HAND_FONT,Vector2.new(1e5,1e5)).X end
 for paragraph in (text..'\n'):gmatch('(.-)\n')do
  local line=''
  for word in paragraph:gmatch('%S+')do
   local candidate=line==''and word or line..' '..word
   if line~=''and width(candidate)>TEXT_W then table.insert(out,line);line=word else line=candidate end
  end
  table.insert(out,line)
 end
 while #out>1 and out[#out]==''do table.remove(out)end
 return out
end
function Controller:_Layout()
 HAND_FONT=self._lineTemplate.Font;HAND_SIZE=self._lineTemplate.TextSize -- measure with the authored handwriting
 local wrapped=wrap(self._text or '')
 for i=1,math.max(#wrapped,#self._lines)do
  local l=self._lines[i]
  if i<=#wrapped then
   if not l then
    l=self._lineTemplate:Clone();l.Name='Line'
    l.Parent=self._writing;self._lines[i]=l
   end
   -- Line i sits on rule i+1: bottom-aligned just above it.
   l.Position=UDim2.fromOffset(0,TOP+(i-1)*RULE);l.Size=UDim2.fromOffset(TEXT_W,RULE-3);l.Text=wrapped[i];l.Visible=true
  elseif l then l.Visible=false end
 end
 local lines=#wrapped
 local signatureY=TOP+(lines+1)*RULE -- one blank ruled line, then the signature sits on the next rule
 self._signature.Position=UDim2.fromOffset(TEXT_X,signatureY)
 local height=math.max((self._height or PAPER.Y)-FOOTER,signatureY+RULE*2)
 self._sheet.CanvasSize=UDim2.fromOffset(0,height)
 local count=math.floor((height-TOP)/RULE)+1
 for i=1,math.max(count,#self._rules)do
  local rule=self._rules[i]
  if i<=count then
   if not rule then rule=self._ruleTemplate:Clone();rule.Name='Rule';rule.Parent=self._sheet;self._rules[i]=rule end
   rule.Position=UDim2.fromOffset(0,TOP+(i-1)*RULE);rule.Visible=true
  elseif rule then rule.Visible=false end
 end
end
function Controller:_Close()
 if not self._panel.Visible or self._closing then return end
 self._closing=true;self._origin=nil;self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('Lore',false)
 local bd=self._backdrop
 if bd then local tw=TweenService:Create(bd,TweenInfo.new(.25,Enum.EasingStyle.Quad),{BackgroundTransparency=1});tw.Completed:Connect(function(s)if s==Enum.PlaybackState.Completed and not self._panel.Visible then bd.Visible=false end end);tw:Play()end
 if self._controls then self._controls:Enable()end
 if game.GuiService.SelectedObject and game.GuiService.SelectedObject:IsDescendantOf(self._panel)then game.GuiService.SelectedObject=nil end
 self:_Rustle(.35,1.12)
 -- Lay the sheet back down: slide off the bottom, then hide.
 if self._tween then self._tween:Cancel()end
 self._tween=TweenService:Create(self._panel,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Position=UDim2.fromScale(.5,1.4),Rotation=-5})
 self._tween.Completed:Connect(function(state)if state==Enum.PlaybackState.Completed then self._panel.Visible=false end;self._closing=false end)
 self._tween:Play()
end
function Controller:_Expand()
 if not self._panel.Visible or self._closing then return end
 self._expanded=not self._expanded
 self._text=self._expanded and (self._player:GetAttribute('EHLoreBody')or '')or(self._player:GetAttribute('EHLoreExcerpt')or '')
 local label=self._readButton:FindFirstChild('Label');if label then label.Text=self._expanded and 'SHOW LESS'or 'READ ALL'end
 self._signature.Visible=self._expanded
 self._sheet.CanvasPosition=Vector2.zero;self:_Layout();self:_Rustle(.3,1.25)
end
function Controller:_Open()
 self._expanded=false;self._closing=false;self._signature.Visible=false
 local label=self._readButton:FindFirstChild('Label');if label then label.Text='READ ALL'end
 self:_Chips();self:_Selection()
 if self._eyebrow then
  local kind=KIND[self._player:GetAttribute('EHLoreKind')or 'Record']or 'RECORD'
  self._eyebrow.Text=kind..'  ·  LEVEL '..tostring(self._player:GetAttribute('EHLoreLevel') or 5)
 end
 if self._backdrop then self._backdrop.Visible=true;self._backdrop.BackgroundTransparency=1;TweenService:Create(self._backdrop,TweenInfo.new(.3,Enum.EasingStyle.Quad),{BackgroundTransparency=.45}):Play()end
 self._title.Text=self._player:GetAttribute('EHLoreTitle')or 'Maintenance record';self._signature.Text=self._player:GetAttribute('EHLoreAuthor')or ''
 self._text=self._player:GetAttribute('EHLoreExcerpt')or '';self._sheet.CanvasPosition=Vector2.zero;if self._fit then self._fit()end;self:_Layout()
 -- Pick the sheet up: it rises into view with a slight turn and a paper rustle.
 if self._tween then self._tween:Cancel()end
 self._panel.Position=UDim2.fromScale(.5,1.4);self._panel.Rotation=-6;self._panel.Visible=true
 self._tween=TweenService:Create(self._panel,TweenInfo.new(.28,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5),Rotation=-1.2});self._tween:Play()
 self:_Rustle(.55,1)
 self._player:SetAttribute('EHLoreOpen',true);self._input:SetBlocked('Lore',true);if self._controls then self._controls:Disable()end
 if game.UserInputService.PreferredInput==Enum.PreferredInput.Gamepad then game.GuiService.SelectedObject=self._readButton end
 local root=self._player.Character and self._player.Character:FindFirstChild('HumanoidRootPart');self._origin=root and root.Position
end
function Controller:Start()
 task.spawn(function()
  local scripts=self._player:WaitForChild('PlayerScripts');local module=scripts:WaitForChild('PlayerModule',10)
  if module then local ok,controls=pcall(function()return require(module):GetControls()end);if ok then self._controls=controls;if self._panel.Visible then controls:Disable()end end end
 end)
 self._scope:Add(self._player:GetAttributeChangedSignal('EHLoreSerial'):Connect(function()self:_Open()end))
 CAS:BindAction('BlackwaterLore',function(_,state,key)
  if not self._panel.Visible or self._closing then return Enum.ContextActionResult.Pass end
  if state==Enum.UserInputState.Begin then if key.KeyCode==Enum.KeyCode.R or key.KeyCode==Enum.KeyCode.ButtonR1 then self:_Expand()else self:_Close()end end
  return Enum.ContextActionResult.Sink
 end,false,Enum.KeyCode.R,Enum.KeyCode.ButtonR1,Enum.KeyCode.E,Enum.KeyCode.Backspace,Enum.KeyCode.ButtonB)
 self._scope:Add(function()CAS:UnbindAction('BlackwaterLore')end)
 self._scope:Add(game:GetService('RunService').Heartbeat:Connect(function()
  if not self._panel.Visible or self._closing then return end
  local root=self._player.Character and self._player.Character:FindFirstChild('HumanoidRootPart')
  if self._player:GetAttribute('EHContext')~='ActiveFloor' or not root or(self._origin and(root.Position-self._origin).Magnitude>10)then self:_Close()end
 end))
end
function Controller:Destroy()
 if self._tween then self._tween:Cancel()end
 if self._panel.Visible then self._player:SetAttribute('EHLoreOpen',false);self._input:SetBlocked('Lore',false);if self._controls then self._controls:Enable()end end
 if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
