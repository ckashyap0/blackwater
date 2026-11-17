--!nonstrict
-- (Nov 16, Ryan: 'while venting on mobile don't get rid of the controls, same with the lift going down to
-- Floor 4 - just disable them') Roblox's ControlModule:Disable() HIDES the touch thumbstick and jump button.
-- Install() patches the one shared ControlModule so that on a touch screen Disable() keeps the pad and button
-- on screen and simply makes them do nothing (the character is held still every frame), and Enable() gives
-- movement back. On keyboard, mouse and gamepad nothing changes. Every script that calls
-- PlayerModule:GetControls():Disable()/Enable() gets this automatically.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local M = {}
local installed = false
local holding = false
local function touch()
	local ok, pref = pcall(function() return UIS.PreferredInput end)
	if ok and pref then return pref == Enum.PreferredInput.Touch end
	return UIS.TouchEnabled and not UIS.KeyboardEnabled
end
local function hold(on)
	if on == holding then return end
	holding = on
	if on then
		RunService:BindToRenderStep('BlackwaterTouchHold', Enum.RenderPriority.Input.Value + 2, function()
			local c = Players.LocalPlayer.Character
			local h = c and c:FindFirstChildOfClass('Humanoid')
			if h then h:Move(Vector3.zero, false); h.Jump = false end
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep('BlackwaterTouchHold') end)
	end
end
-- true on a phone / tablet (the touch thumbstick and jump button are on screen)
function M.IsTouch() return touch() end
-- Roblox hides the touch JUMP button whenever jumping is switched off (JumpHeight/JumpPower 0, or the Jumping
-- state disabled). Code that wants 'no jumping' on a touch screen calls NoJump(key,true): the button stays and
-- every jump press is simply swallowed each frame; NoJump(key,false) gives jumping back.
local noJump = {}
function M.NoJump(key, on)
	noJump[key] = on or nil
	if next(noJump) then
		RunService:BindToRenderStep('BlackwaterTouchNoJump', Enum.RenderPriority.Input.Value + 2, function()
			local c = Players.LocalPlayer.Character
			local h = c and c:FindFirstChildOfClass('Humanoid')
			if h and h.Jump then h.Jump = false end
		end)
	else
		pcall(function() RunService:UnbindFromRenderStep('BlackwaterTouchNoJump') end)
	end
end
function M.Install()
	if installed or not RunService:IsClient() then return end
	local player = Players.LocalPlayer
	local ps = player:WaitForChild('PlayerScripts', 10)
	local pm = ps and ps:WaitForChild('PlayerModule', 10)
	if not pm then return end
	local ok, controls = pcall(function() return require(pm):GetControls() end)
	if not ok or not controls then return end
	installed = true
	local disable, enable = controls.Disable, controls.Enable
	controls.Disable = function(self, ...)
		if touch() then
			pcall(enable, self) -- (keep the pad on screen)
			hold(true)
		else
			hold(false)
			return disable(self, ...)
		end
	end
	controls.Enable = function(self, ...)
		hold(false)
		return enable(self, ...)
	end
end
return M
