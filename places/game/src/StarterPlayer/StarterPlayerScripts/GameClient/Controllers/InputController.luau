--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local CAS=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Config=require(Shared.Config.InputConfig)
local Policy=require(Shared.Contracts.CharacterContract)
local Scope=require(Shared.Utilities.CleanupScope)
local MobileLayout=require(Shared.Utilities.MobileLayout)
local Reveal=require(Shared.Utilities.HudReveal)
local Lock=require(Shared.Utilities.ControlLock)
local Controller={}
Controller.__index=Controller
-- The abilities you only get once the opening is over (see _AbilitiesLocked). Sprint and crouch
-- work from the moment you spawn on every device; the flashlight works on the surface and on every
-- floor, and is only hidden during the lift's descent cinematic.
local ABILITIES={Flashlight=true}
local LEGEND={
 {id='Move',kb='W A S D  Move',pad='LEFT STICK  Move'},
 {id='Sprint',kb='SHIFT  Sprint',pad='L3  Sprint'},
 {id='Crouch',kb='C / CTRL  Crouch',pad='R3 / B  Crouch'},
 {id='Interact',kb='E  Interact',pad='X  Interact'},
 {id='Flashlight',kb='F  Flashlight',pad='Y  Flashlight'},
 {id='Drop',kb='X  Drop item',pad='D-PAD DOWN  Drop item'},
 {id='Cursor',kb='ALT  Lock / unlock cursor',pad=nil},
}
function Controller.new(player,gui)
	return setmetatable({Name="InputController",Dependencies={"StateController"},_player=player,_gui=gui,
		_handlers={},_held={},_buttons={},_bound={},_blocks={},_availability={},_focused=true},Controller)
end
function Controller:Init(dependencies)
	self._state=dependencies.StateController;self._scope=Scope.new()
	-- Authored in StarterGui (edit there):
	--   PlayerControls > TouchActions (SafeArea padding) > one button per action (Interact, Sprint, Crouch, ...)
	--                  > ControlLegend > one row per control (attributes Keyboard / Gamepad hold the two texts)
	--   SafeAreaProbe  > Probe   (invisible; measures the device safe area for the touch cluster)
	-- The touch buttons' places and sizes come from MobileLayout so they fit every phone and tablet.
	local gui=AuthoredGui.Get(self._gui,"PlayerControls");self._screen=gui
	local probe=AuthoredGui.Get(self._gui,"SafeAreaProbe")
	self._safeProbe=probe:WaitForChild("Probe")
	local actions=gui:WaitForChild("TouchActions")
	self._touchPad=actions:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding",actions)
	self._touchFrame=actions
	for _,b in actions:GetChildren() do if b:IsA("GuiObject") then b.Visible=false end end
	local help=gui:WaitForChild("ControlLegend");help.Visible=false;self._legend=help
	self._legendRows={}
	for _,row in LEGEND do
		local l=help:FindFirstChild(row.id)
		if l then
			row.kb=l:GetAttribute("Keyboard") or row.kb;row.pad=l:GetAttribute("Gamepad") or row.pad
			self._legendRows[row.id]=l
		end
	end
 self._fade={}
end
-- During the descent cinematic the flashlight is switched off, its button and legend line hidden.
-- On the surface (it is night out there) it works as soon as you wake up.
function Controller:_AbilitiesLocked()
 return Shared.Parent:GetAttribute('SurfaceBoarding')~=true and self:GetContext()=='Intro'
end
-- Every touch button and legend row pops in and out instantly (no fade): when you look at
-- something you can use, its button is there on the very next frame.
-- friendly names for keys and pad buttons in prompts: "[E] Interact", "[RB] Next"
local KEY_NAMES={LeftShift='SHIFT',Return='ENTER',Backspace='BACKSPACE'}
local PAD_NAMES={ButtonX='X',ButtonY='Y',ButtonA='A',ButtonB='B',ButtonR1='RB',ButtonL1='LB',ButtonR3='R3',ButtonL3='L3',DPadDown='D-PAD DOWN',DPadUp='D-PAD UP'}
function Controller:_Fader(o)
 local f=self._fade[o]
 if not f then
  f={alpha=0,want=false,since=0,base={}}
  for _,d in {o,table.unpack(o:GetDescendants())} do
   local b={}
   if d:IsA('GuiObject') then b.bg=d.BackgroundTransparency end
   if d:IsA('TextLabel') or d:IsA('TextButton') then b.text=d.TextTransparency;b.textStroke=d.TextStrokeTransparency end
   if d:IsA('ImageLabel') or d:IsA('ImageButton') then b.image=d.ImageTransparency end
   if d:IsA('UIStroke') then b.stroke=d.Transparency end
   f.base[d]=b
  end
  self._fade[o]=f
  o.Visible=false
 end
 return f
end
function Controller:_ApplyFade(o,f)
 local a=f.alpha
 for d,b in f.base do if d.Parent then
  local function t(x)return 1-(1-x)*a end
  if b.bg then d.BackgroundTransparency=t(b.bg) end
  if b.text then d.TextTransparency=t(b.text);d.TextStrokeTransparency=t(b.textStroke) end
  if b.image then d.ImageTransparency=t(b.image) end
  if b.stroke then d.Transparency=t(b.stroke) end
 end end
 local vis=a>.001
 if o.Visible~=vis then o.Visible=vis end
end
function Controller:_SetShown(o,shown)
 local f=self:_Fader(o)
 if f.want~=shown then
  f.want=shown;f.since=0
  if shown and os.clock()<(self._easeUntil or 0) then f.alpha=math.max(f.alpha,.001) else f.alpha=shown and 1 or 0 end
  self:_ApplyFade(o,f)
 end
end
function Controller:_StepFades(dt)
 -- (after a cutscene the controls ease back in over a moment instead of popping)
 local easing=os.clock()<(self._easeUntil or 0)
 for o,f in self._fade do
  if not o.Parent then self._fade[o]=nil;continue end
  if f.want then f.since+=dt end
  local target=f.want and 1 or 0
  if f.alpha~=target then
   if easing and target==1 then f.alpha=math.min(1,f.alpha+dt/(Reveal.Active() and 1.3 or .45)) else f.alpha=target end
   self:_ApplyFade(o,f)
  end
 end
end
function Controller:GetContext()
	return self._player:GetAttribute("EHContext") or "Lobby"
end
function Controller:GetPrompt(action)
	local item=Config[action];if not item then return nil end
	if UIS.PreferredInput==Enum.PreferredInput.Touch then return item.label end
	if UIS.PreferredInput==Enum.PreferredInput.Gamepad then return "["..(PAD_NAMES[item.pad.Name] or item.pad.Name).."] "..item.label end
	return "["..(KEY_NAMES[item.key.Name] or item.key.Name).."] "..item.label
end
function Controller:_Allowed(action)
	local policy=Policy.Contexts[self:GetContext()]
	if ABILITIES[action] and self:_AbilitiesLocked() then return false end
	return self._focused and next(self._blocks)==nil and UIS:GetFocusedTextBox()==nil
		and policy~=nil and Config[action].groups[policy.group]==true and self._handlers[action]~=nil and self._availability[action]~=false
end
function Controller:SetAvailable(action,available)
	assert(Config[action],"Unknown action")
	if self._availability[action]==available then return end
	self._availability[action]=available
	if not available and self._held[action] then self:Handle(action,"Cancel") end
	self:_UpdateButtons()
end
function Controller:CancelAll()
	local held=self._held;self._held={}
	for action in held do local callback=self._handlers[action];if callback then callback("Cancel") end end
end
function Controller:SetBlocked(reason,blocked)
	assert(type(reason)=="string","Block reason required")
	self._blocks[reason]=blocked and true or nil
	if blocked then self:CancelAll() end
	self:_UpdateButtons()
end
function Controller:Handle(action,state,source)
	if not Config[action] or not self._handlers[action] then return false end
	source=source or action
	if state=="End" or state=="Cancel" then
		local held=self._held[action]
		-- Only consume a release that belongs to this action. Several actions share keys (E is
		-- Interact and, for spectators, SpectateNext); if an idle action swallowed the key-up,
		-- the real owner never saw it, stayed "held" forever and ignored every later press
		-- until the player looked away from the target.
		if not held or (state=="End" and held[source]==nil) then return false end
		held[source]=nil
		if next(held)==nil or state=="Cancel" then self._held[action]=nil;self._handlers[action](state) end
		return true
	end
	if state~="Begin" or not self:_Allowed(action) then return false end
	local held=self._held[action]
	if not held then held={};self._held[action]=held;held[source]=true;self._handlers[action]("Begin")
	else held[source]=true end
	return true
end
function Controller:GetTouchButton(action)return self._buttons[action] end
function Controller:SetTouchCaption(action,text)
 local b=self._buttons[action];local label=b and b:FindFirstChild('Caption');if label then label.Text=text elseif b and action=='Interact'then b.Text=text end
end
-- Toggle buttons (crouch) light up while active.
function Controller:SetTouchActive(action,on)
 local b=self._buttons[action];if not b then return end
 b.BackgroundColor3=on and Color3.fromRGB(150,154,140)or Color3.fromRGB(25,28,29)
 local f=self:_Fader(b);local s=b:FindFirstChildOfClass('UIStroke')
 if f.base[b] then f.base[b].bg=on and .35 or .55 end
 if s and f.base[s] then f.base[s].stroke=on and 0 or .22 end
 self:_ApplyFade(b,f)
end
-- Safe-area padding for the touch cluster, from the device safe insets measured each layout.
-- Rounded corners and the home indicator only need a small margin, so the right/bottom edges use
-- a fraction of the reported inset; the notch side keeps its full inset.
function Controller:_SafePadding()
 local full=self._screen.AbsoluteSize;local probe=self._safeProbe
 if not probe or full.X<1 then return end
 local pos,size=probe.AbsolutePosition,probe.AbsoluteSize
 local left,top=math.max(0,pos.X),math.max(0,pos.Y)
 local right,bottom=math.max(0,full.X-(pos.X+size.X)),math.max(0,full.Y-(pos.Y+size.Y))
 local cam=workspace.CurrentCamera;local view=cam and cam.ViewportSize or full
 local landscape=view.X>=view.Y
 local pad=self._touchPad
 pad.PaddingLeft=UDim.new(0,left)
 pad.PaddingTop=UDim.new(0,top)
 pad.PaddingRight=UDim.new(0,landscape and math.clamp(right*.3,6,18) or math.clamp(right,6,24))
 pad.PaddingBottom=UDim.new(0,math.clamp(bottom*.55,6,20))
end
function Controller:_LayoutTouch()
 self:_SafePadding()
 local size=self._touchFrame.AbsoluteSize
 local pad=self._touchPad
 if pad then size=Vector2.new(size.X-pad.PaddingLeft.Offset-pad.PaddingRight.Offset,size.Y-pad.PaddingTop.Offset-pad.PaddingBottom.Offset)end
 if size.X<1 or size.Y<1 then return end
 local layout=MobileLayout.Get(size.X,size.Y)
 for action,button in self._buttons do
  -- every button has its own fixed place; one without a place is never shown (it used to fall
  -- back to the middle of the screen)
  local pos=layout[action]
  button:SetAttribute('NoLayout',pos==nil)
  if not pos then button.Visible=false;continue end
  button.AnchorPoint=Vector2.new(.5,.5);button.Size=action=='Interact'and UDim2.fromOffset(math.min(260,size.X*.55),56)or UDim2.fromOffset(layout.diameter,layout.diameter);button.Position=UDim2.fromOffset(pos.X,pos.Y)
 end
end
function Controller:Register(action,callback)
	assert(Config[action] and type(callback)=="function" and not self._handlers[action],"Invalid or duplicate action")
	self._handlers[action]=callback
	local function dispatch(_,state,input)
		local source=input and input.KeyCode or action
		if input and input.UserInputType==Enum.UserInputType.MouseButton1 then source="MouseClick"end
		local used=self:Handle(action,state.Name,source)
		return used and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
	end
	if action=="Interact"then
		CAS:BindAction("EH_"..action,dispatch,false,Config[action].key,Config[action].pad,Enum.UserInputType.MouseButton1)
	else
		CAS:BindAction("EH_"..action,dispatch,false,Config[action].key,Config[action].pad)
	end
	self._bound[action]=true
	-- the authored button for this action (StarterGui.PlayerControls.TouchActions.<action>); an action without
	-- one gets a copy of the Sprint button with its label
	local button=self._touchFrame:FindFirstChild(action)
	if not button then
		local base=self._touchFrame:FindFirstChild("Sprint")
		button=base and base:Clone() or Instance.new("TextButton")
		for _,d in button:GetChildren() do if not d:IsA("UICorner") and not d:IsA("UIStroke") then d:Destroy() end end
		button.Name=action;button.Text=Config[action].label;button.Parent=self._touchFrame
	end
 self._buttons[action]=button;self:_LayoutTouch()
 if action=='Flashlight'then
  self._scope:Add(button.Activated:Connect(function()self:Handle(action,'Begin',button);self:Handle(action,'End',button)end))
 else
  self._scope:Add(button.InputBegan:Connect(function(input)
   if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then self:Handle(action,'Begin',input)end
  end))
  self._scope:Add(button.InputEnded:Connect(function(input)
   if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then self:Handle(action,'End',input)end
  end))
 end
	self:_UpdateButtons()
	local active=true
	return function()
		if not active then return end;active=false
		if self._held[action] then callback("Cancel");self._held[action]=nil end
		self._handlers[action]=nil;self._bound[action]=nil;CAS:UnbindAction("EH_"..action)
		self._buttons[action]=nil;button.Visible=false
	end
end
function Controller:_UpdateButtons()
	local policy=Policy.Contexts[self:GetContext()]
 local context=self:GetContext()
 local locked=self:_AbilitiesLocked()
 local legend=(context=='ActiveFloor' or context=='Transit')and next(self._blocks)==nil and UIS.PreferredInput~=Enum.PreferredInput.Touch
 self._legend.Visible=legend
 local pad=UIS.PreferredInput==Enum.PreferredInput.Gamepad
 for _,row in LEGEND do
  local l=self._legendRows[row.id];if not l then continue end;l.Text=(pad and row.pad) or row.kb
  local show=legend and not (ABILITIES[row.id] and locked) and not (row.id=='Drop' and self._player and self._player:GetAttribute('EHCarryingMop')) and not (row.id=='Cursor' and pad)
  self:_SetShown(l,show)
 end
	for action,button in self._buttons do
		-- Keep controls visible when Studio/the OS loses focus; held input is still canceled.
		self:_SetShown(button,button:GetAttribute('NoLayout')~=true and UIS.PreferredInput==Enum.PreferredInput.Touch and policy~=nil
			and Config[action].groups[policy.group]==true and next(self._blocks)==nil and self._availability[action]~=false
			and not (ABILITIES[action] and locked))
	end
	if game:GetService("RunService"):IsStudio() then
		script.Parent:SetAttribute("InputFocused",self._focused)
		script.Parent:SetAttribute("InputDevice",UIS.PreferredInput.Name)

	end
end
function Controller:Start()
 self._scope:Add(self._touchFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()self:_LayoutTouch()end));self:_LayoutTouch()
 self._scope:Add(self._safeProbe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()self:_LayoutTouch()end))
 self._scope:Add(self._safeProbe:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()self:_LayoutTouch()end))
 if workspace.CurrentCamera then self._scope:Add(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()self:_LayoutTouch()end))end
	self._scope:Add(UIS.WindowFocusReleased:Connect(function() self._focused=false;self:CancelAll();self:_UpdateButtons() end))
	self._scope:Add(UIS.WindowFocused:Connect(function() self._focused=true;self:_UpdateButtons() end))
	self._scope:Add(UIS.TextBoxFocused:Connect(function() self:SetBlocked("TextEntry",true) end))
	self._scope:Add(UIS.TextBoxFocusReleased:Connect(function() self:SetBlocked("TextEntry",false) end))
	self._scope:Add(GuiService.MenuOpened:Connect(function() self:SetBlocked("RobloxMenu",true) end))
	self._scope:Add(GuiService.MenuClosed:Connect(function() self:SetBlocked("RobloxMenu",false) end))
	self._scope:Add(UIS.GamepadDisconnected:Connect(function() self:CancelAll() end))
	self._scope:Add(UIS.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then for action in self._handlers do self:Handle(action,"End",input) end end
	end))
	-- Leaving the intro (out of the lift after the crash): the whole HUD fades in together.
	self._lastContext=self:GetContext()
	self._scope:Add(self._player:GetAttributeChangedSignal("EHContext"):Connect(function()
		local context=self:GetContext()
		if self._lastContext=="Intro" and (context=="ActiveFloor" or context=="Transit") then
			Reveal.Begin(1.6);self._easeUntil=os.clock()+1.6
		end
		self._lastContext=context
		self:CancelAll();self:_UpdateButtons()
	end))
	self._scope:Add(self._player:GetAttributeChangedSignal("EHCharacterEpoch"):Connect(function() self:CancelAll();self:_UpdateButtons() end))
	self._scope:Add(UIS:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:CancelAll();self:_UpdateButtons()
	end))
	self._scope:Add(self._player:GetAttributeChangedSignal('EHCarryingMop'):Connect(function()self:_UpdateButtons()end))
	self._scope:Add(Shared.Parent:GetAttributeChangedSignal('SurfaceBoarding'):Connect(function()self:CancelAll();self:_UpdateButtons()end))
	-- TOTAL CONTROL LOCK (see Shared.Utilities.ControlLock). On from the first frame of every new
	-- character and through every cutscene: the join cover and waking up (EHSpawnHold), the gate
	-- shots (EHCinematic) and the whole lift ride, crash and get-up (context Intro). While it is on:
	-- no game actions or touch buttons, the default movement controls are switched off, the
	-- character stands still (WalkSpeed/JumpHeight 0, no turning), tools are put away and the
	-- camera cannot be panned (its rotation is held level along the fixed facing).
	-- Handshake: when the cutscene is over the lock still waits until the camera is back in your
	-- own eyes; only then are body and view squared up to the fixed facing and control returned.
	local RunService=game:GetService('RunService')
	local StarterGui=game:GetService('StarterGui')
	local p=self._player
	local spawnedAt=os.clock()
	self._scope:Add(p.CharacterAdded:Connect(function()spawnedAt=os.clock();Lock.heldRot=nil;Lock.returnRot=nil end))
	local held=nil -- humanoid values to give back when the lock ends
	local controls=nil
	local function playerControls()
		if controls then return controls end
		pcall(function()local pm=p.PlayerScripts:FindFirstChild('PlayerModule');if pm then controls=require(pm):GetControls() end end)
		return controls
	end
	local role=Shared.Parent:GetAttribute('PlaceRole')
	if not role then pcall(function()role=require(Shared.Config.PlaceConfig).Resolve(game.PlaceId,RunService:IsStudio(),workspace:GetAttribute('EHStudioPlaceRole'))end) end
	local function reasonNow()
		if role~='Game' then return nil end -- (the lobby has no cutscenes to lock for)
		if p:GetAttribute('EHCinematic')~=nil then return 'Cinematic' end
		local ctx=self:GetContext()
		if ctx=='Intro' then return 'Intro' end
		-- from the moment the lift doors start to close on the surface until the intro hands over
		if p:GetAttribute('EHElevatorLock')==true and (ctx=='ActiveFloor' or ctx=='Transit') then return 'Intro' end
		if p:GetAttribute('EHSpawnHold')==true or os.clock()-spawnedAt<.6 then return 'Spawn' end
		return nil
	end
	-- the camera is home: the normal first-person camera, on your humanoid, at your head
	local function cameraHome()
		local ctx=self:GetContext()
		if ctx~='ActiveFloor' and ctx~='Transit' and ctx~='Intro' then return true end -- (no first-person view to return to)
		local cam=workspace.CurrentCamera;local c=p.Character
		local h=c and c:FindFirstChildOfClass('Humanoid');local head=c and c:FindFirstChild('Head')
		return cam~=nil and h~=nil and head~=nil and cam.CameraType==Enum.CameraType.Custom and cam.CameraSubject==h
			and (cam.CFrame.Position-head.Position).Magnitude<2.5
	end
	local function freeze()
		local c=p.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
		if not h then return end
		if not held or held.h~=h then held={h=h,walk=h.WalkSpeed,jump=h.JumpPower,jumpH=h.JumpHeight,rotate=h.AutoRotate} end
		h.WalkSpeed=0;h.JumpPower=0;h.JumpHeight=0;h.AutoRotate=false;h.Jump=false;h:Move(Vector3.zero)
	end
	-- Look input is switched off at the source while locked: mouse movement, the right stick, the
	-- camera keys and right-drag are swallowed above the camera module's own bindings, so a flick of
	-- the mouse in a cutscene reaches nothing at all (no view jolt, no body turn).
	local LOOK_SINK='BlackwaterLookLock'
	-- Roblox's own character and camera controls now run on the Input Action System (InputContexts under
	-- StarterPlayer.PlayerModule), which ContextActionService can't sink: they are switched off at the
	-- source for the length of the lock - no walking, turning or looking around at all.
	local function playerContexts(on)
		local folder=game:GetService('StarterPlayer'):FindFirstChild('PlayerModule')
		folder=folder and folder:FindFirstChild('InputContexts')
		if not folder then return end
		for _,name in {'CharacterContext','CameraContext'} do
			local ctx=folder:FindFirstChild(name)
			if ctx then pcall(function()ctx.Enabled=on end) end
		end
	end
	local function sinkLook(on)
		playerContexts(not on)
		if on then
			CAS:BindActionAtPriority(LOOK_SINK,function()return Enum.ContextActionResult.Sink end,false,Enum.ContextActionPriority.High.Value+100,
				Enum.UserInputType.MouseMovement,Enum.UserInputType.MouseButton2,Enum.UserInputType.MouseWheel,Enum.KeyCode.Thumbstick2,
				Enum.KeyCode.Left,Enum.KeyCode.Right,Enum.KeyCode.PageUp,Enum.KeyCode.PageDown,Enum.KeyCode.I,Enum.KeyCode.O)
		else pcall(function()CAS:UnbindAction(LOOK_SINK)end) end
	end
	local function engage(reason)
		Lock.active=true;Lock.since=os.clock();Lock.heldRot=nil;Lock.heldFacing=nil
		sinkLook(true)
		p:SetAttribute('EHControlLocked',true) -- (tells the character's SpawnFreeze script the lock has taken over)
		self:SetBlocked('Cinematic',true)
		local ctl=playerControls();if ctl then pcall(function()ctl:Disable()end) end
		local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid');if h then pcall(function()h:UnequipTools()end) end
		if Lock.backpack==nil then local ok,v=pcall(function()return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)end);Lock.backpack=ok and v or false end
		pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false)end)
		freeze()
	end
	local function release()
		local c=p.Character;local root=c and c:FindFirstChild('HumanoidRootPart');local cam=workspace.CurrentCamera
		-- square body and view up to the fixed facing on the same frame: nothing turns afterwards
		local f=Lock.FacingFor(p,Lock.lastReason)
		local rr=Lock.returnRot;Lock.returnRot=nil;if rr then f=Lock.Flat(rr.LookVector) end
		if f and root then
			root.CFrame=CFrame.new(root.Position)*Lock.LevelRotation(f);root.AssemblyAngularVelocity=Vector3.zero
			if cam and cam.CameraType==Enum.CameraType.Custom then cam.CFrame=CFrame.new(cam.CFrame.Position)*(rr or Lock.LevelRotation(f)) end
		end
		local hh=held and held.h
		if hh and hh.Parent then
			local walk=held.walk
			if not walk or walk<=0 then local M=require(Shared.Config.MovementConfig);walk=p:GetAttribute('EHCrouching') and M.CrouchSpeed or M.WalkSpeed end
			hh.WalkSpeed=walk;hh.JumpPower=held.jump or 0;hh.JumpHeight=held.jumpH or 0
			hh.AutoRotate=true -- (the body turns with the view again; the first frames' freeze also turned it off)
		end
		held=nil
		local ctl=playerControls();if ctl then pcall(function()ctl:Enable()end) end
		if Lock.backpack then pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,true)end) end
		Lock.active=false;Lock.reason=nil;Lock.releasedAt=os.clock();Lock.heldRot=nil
		sinkLook(false)
		p:SetAttribute('EHControlLocked',false)
		self._easeUntil=os.clock()+.6
		self:SetBlocked('Cinematic',false)
	end
	RunService:BindToRenderStep('BlackwaterControlLock',Enum.RenderPriority.Input.Value+1,function()
		local reason=reasonNow()
		if reason then Lock.reason=reason;Lock.lastReason=reason end
		-- (cutscene over but the camera not home yet: keep holding - the handshake)
		local want=reason~=nil or (Lock.active and not cameraHome())
		if want and not Lock.active then engage(reason)
		elseif not want and Lock.active then release() end
		if Lock.active then freeze() end
	end)
	-- no camera panning while locked: the camera module's own turn is undone right after it runs
	-- (cutscene scripts that drive the view run later, at Camera+3 and up, and still win)
	RunService:BindToRenderStep('BlackwaterControlLockCamera',Enum.RenderPriority.Camera.Value+2,function(dt)
		if not Lock.active then return end
		local cam=workspace.CurrentCamera
		if not cam or cam.CameraType~=Enum.CameraType.Custom then Lock.heldRot=nil;return end
		local f=Lock.FacingFor(p,Lock.reason)
		if not Lock.heldRot then Lock.heldRot=cam.CFrame.Rotation end
		-- the view settles onto the fixed facing (e.g. the lift doors) with a short, smooth turn -
		-- never a snap - and is then held there
		if f then
			local target=Lock.returnRot or Lock.LevelRotation(f)
			Lock.heldRot=Lock.heldRot:Lerp(target,1-math.exp(-math.clamp(dt or 1/60,0,.1)*5))
		end
		cam.CFrame=CFrame.new(cam.CFrame.Position)*Lock.heldRot
	end)
	self._scope:Add(function()
		pcall(function()RunService:UnbindFromRenderStep('BlackwaterControlLock')end)
		pcall(function()RunService:UnbindFromRenderStep('BlackwaterControlLockCamera')end)
		if Lock.active then pcall(release) end
	end)
	self._scope:Add(game:GetService('RunService').RenderStepped:Connect(function(dt)self:_StepFades(math.min(dt,.1))
		-- (Oct 25) never stay frozen after the chat: if no text box has focus, the text-entry block is lifted
		if self._blocks.TextEntry and UIS:GetFocusedTextBox()==nil then self:SetBlocked('TextEntry',false) end
	end))
	-- G frees the mouse pointer (the view holds still so you can click things) and locks it
	-- again. Keyboard and mouse only, never during a cutscene lock; it resets whenever you leave
	-- a floor (death, results, the lift ride).
	local function setFree(on)
		if (p:GetAttribute('EHCursorFree')==true)~=on then p:SetAttribute('EHCursorFree',on or nil) end
	end
	CAS:BindAction('EH_CursorToggle',function(_,state)
		if state~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if role~='Game' or UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local ctx=self:GetContext()
		if Lock.active or (ctx~='ActiveFloor' and ctx~='Transit') then return Enum.ContextActionResult.Pass end
		setFree(p:GetAttribute('EHCursorFree')~=true)
		return Enum.ContextActionResult.Sink
	end,false,Enum.KeyCode.LeftAlt,Enum.KeyCode.RightAlt)
	self._scope:Add(function()pcall(function()CAS:UnbindAction('EH_CursorToggle')end)end)
	self._scope:Add(p:GetAttributeChangedSignal('EHContext'):Connect(function()
		local ctx=self:GetContext();if ctx~='ActiveFloor' and ctx~='Transit' then setFree(false) end
	end))
	self._scope:Add(p.CharacterAdded:Connect(function()setFree(false)end))
	self:_UpdateButtons()
end
function Controller:Destroy()
	self:CancelAll()
	for action in self._bound do CAS:UnbindAction("EH_"..action) end
	table.clear(self._bound);table.clear(self._handlers);table.clear(self._buttons)
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
