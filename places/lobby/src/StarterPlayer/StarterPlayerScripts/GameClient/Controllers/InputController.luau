--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local CAS=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local GuiService=game:GetService("GuiService")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Config=require(Shared.Config.InputConfig)
local Policy=require(Shared.Contracts.CharacterContract)
local Scope=require(Shared.Utilities.CleanupScope)
local Responsive=require(Shared.Utilities.ResponsiveScale)
local Controller={}
Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="InputController",Dependencies={"StateController"},_player=player,_gui=gui,
		_handlers={},_held={},_buttons={},_bound={},_blocks={},_availability={},_focused=true},Controller)
end
function Controller:Init(dependencies)
	self._state=dependencies.StateController;self._scope=Scope.new()
	self._promptChanged=self._scope:Add(Instance.new("BindableEvent"))
	-- authored in StarterGui.PlayerControls: TouchActions holds the grid; ActionTemplate is copied per action
	local gui=AuthoredGui.Get(self._gui,"PlayerControls");self._screen=gui;Responsive.Watch(gui)
	local actions=gui:WaitForChild("TouchActions")
	self._template=actions:WaitForChild("ActionTemplate");self._template.Visible=false
	self._touchFrame=actions
end
function Controller:GetContext()
	return self._player:GetAttribute("EHContext") or "Lobby"
end
function Controller:GetPrompt(action)
	local item=Config[action];if not item then return nil end
	if UIS.PreferredInput==Enum.PreferredInput.Touch then return item.label end
	if UIS.PreferredInput==Enum.PreferredInput.Gamepad then return item.pad.Name.." · "..item.label end
	return item.key.Name.." · "..item.label
end
function Controller:SubscribePrompts(callback) return self._promptChanged.Event:Connect(callback) end
function Controller:_Allowed(action)
	local policy=Policy.Contexts[self:GetContext()]
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
		if held then
			held[source]=nil
			if next(held)==nil or state=="Cancel" then self._held[action]=nil;self._handlers[action](state) end
		end
		return true
	end
	if state~="Begin" or not self:_Allowed(action) then return false end
	local held=self._held[action]
	if not held then held={};self._held[action]=held;held[source]=true;self._handlers[action]("Begin")
	else held[source]=true end
	return true
end
function Controller:Register(action,callback)
	assert(Config[action] and type(callback)=="function" and not self._handlers[action],"Invalid or duplicate action")
	self._handlers[action]=callback
	CAS:BindAction("EH_"..action,function(_,state,input)
		local used=self:Handle(action,state.Name,input and input.KeyCode or action)
		return used and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
	end,false,Config[action].key,Config[action].pad)
	self._bound[action]=true
	local button=self._template:Clone();button.Name=action;button.Text=Config[action].label;button.Parent=self._touchFrame
	self._buttons[action]=button
	self._scope:Add(button.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch then self:Handle(action,"Begin",input) end
	end))
	self._scope:Add(button.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch then self:Handle(action,"End",input) end
	end))
	self:_UpdateButtons()
	local active=true
	return function()
		if not active then return end;active=false
		if self._held[action] then callback("Cancel");self._held[action]=nil end
		self._handlers[action]=nil;self._bound[action]=nil;CAS:UnbindAction("EH_"..action)
		self._buttons[action]=nil;button:Destroy()
	end
end
function Controller:_UpdateButtons()
	local policy=Policy.Contexts[self:GetContext()]
	for action,button in self._buttons do
		-- Keep controls visible when Studio/the OS loses focus; held input is still canceled.
		button.Visible=UIS.PreferredInput==Enum.PreferredInput.Touch and policy~=nil
			and Config[action].groups[policy.group]==true and next(self._blocks)==nil and self._availability[action]~=false
	end
	if game:GetService("RunService"):IsStudio() then
		script.Parent:SetAttribute("InputFocused",self._focused)
		script.Parent:SetAttribute("InputDevice",UIS.PreferredInput.Name)
	end
end
function Controller:Start()
	self._scope:Add(UIS.WindowFocusReleased:Connect(function() self._focused=false;self:CancelAll();self:_UpdateButtons() end))
	self._scope:Add(UIS.WindowFocused:Connect(function() self._focused=true;self:_UpdateButtons() end))
	self._scope:Add(UIS.TextBoxFocused:Connect(function() self:SetBlocked("TextEntry",true) end))
	self._scope:Add(UIS.TextBoxFocusReleased:Connect(function() self:SetBlocked("TextEntry",false) end))
	self._scope:Add(GuiService.MenuOpened:Connect(function() self:SetBlocked("RobloxMenu",true) end))
	self._scope:Add(GuiService.MenuClosed:Connect(function() self:SetBlocked("RobloxMenu",false) end))
	self._scope:Add(UIS.GamepadDisconnected:Connect(function() self:CancelAll() end))
	self._scope:Add(UIS.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch then for action in self._handlers do self:Handle(action,"End",input) end end
	end))
	for _,attr in {"EHContext","EHCharacterEpoch"} do
		self._scope:Add(self._player:GetAttributeChangedSignal(attr):Connect(function() self:CancelAll();self:_UpdateButtons() end))
	end
	self._scope:Add(UIS:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		self:CancelAll();self:_UpdateButtons();self._promptChanged:Fire()
	end))
	self:_UpdateButtons()
end
function Controller:Destroy()
	self:CancelAll()
	for action in self._bound do CAS:UnbindAction("EH_"..action) end
	table.clear(self._bound);table.clear(self._handlers);table.clear(self._buttons)
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
