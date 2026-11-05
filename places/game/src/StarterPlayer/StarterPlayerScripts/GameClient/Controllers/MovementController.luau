--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.MovementConfig)
local Crouch=require(Shared.Utilities.CrouchState)
local Crawl=require(Shared.Utilities.CrawlState)
local Reveal=require(Shared.Utilities.HudReveal)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="MovementController",Dependencies={"StateController","InputController"},_player=player,_gui=gui,_held=false},Controller)
end
function Controller:Init(dependencies)
	self._state=dependencies.StateController;self._input=dependencies.InputController;self._scope=Scope.new()
	-- authored in StarterGui.Stamina (Root > Meter > Fill)
	local gui=AuthoredGui.Get(self._gui,"Stamina")
	local bar=gui:WaitForChild("Root"):WaitForChild("Meter");local fill=bar:WaitForChild("Fill")
	self._bar=bar;self._fill=fill
end
-- down after a slip or the crash (lying there or still getting up): sprint requests wait until
-- you are fully back on your feet (the server enforces the same rule)
local GETUP=require(Shared.Utilities.IntroTimeline).GetUpSeconds
function Controller:_Down()
	local t1=self._player:GetAttribute("EHKnockedUntil");if type(t1)~="number" then return false end
	local rise=self._player:GetAttribute("EHKnockStyle")=="Crash" and GETUP or .85
	return workspace:GetServerTimeNow()<t1+rise+.15
end
function Controller:_Send(enabled)
	if enabled and self:_Down() then return end
	local epoch=self._player:GetAttribute("EHCharacterEpoch")
	if self._state:GetSnapshot() and type(epoch)=="number" and epoch>0 then
		self._state:SendAction(enabled and "BeginSprint" or "EndSprint",{characterEpoch=epoch})
	end
end
-- Jumping is removed from the game: the state is disabled on every character and any jump
-- request (space, gamepad A, touch) is cleared before physics runs. The server also keeps
-- JumpPower/JumpHeight at 0, which hides Roblox's mobile jump button.
function Controller:_NoJump()
 local c=self._player.Character;local h=c and c:FindFirstChildOfClass('Humanoid')
 if not h then return end
 if h~=self._jumpHumanoid then
  self._jumpHumanoid=h;h.AutoJumpEnabled=false
  h:SetStateEnabled(Enum.HumanoidStateType.Jumping,false)
 end
 if h.Jump then h.Jump=false end
end
-- Crouch is predicted locally (the camera moves the instant the key is pressed) and confirmed
-- by the server, which owns the slower walk speed. If the server disagrees for longer than a
-- moment (context change, respawn, rejected request) the local state follows the server.
function Controller:_SetCrouch(on)
 on=on==true
 -- crawling through a vent: the crouch is locked on until you drop out of the far end
 if not on and (self._player:GetAttribute("EHInVent") or Crawl.state=='Vent') then return end
 -- (Oct 25) no crouching while down from a slip, in a cutscene or while the controls are still locked (getting out
 -- of the car, the head-shake): the button stays on screen but does nothing until you have control again
 if on and (self:_Down() or self._player:GetAttribute("EHCinematic") or require(Shared.Utilities.ControlLock).active) then return end
 if Crouch.wanted==on then return end
 Crouch.wanted=on;self._crouchSent=os.clock()
 local epoch=self._player:GetAttribute("EHCharacterEpoch")
 if self._state:GetSnapshot() and type(epoch)=="number" and epoch>0 then
  self._state:SendAction(on and "BeginCrouch" or "EndCrouch",{characterEpoch=epoch})
 end
 self._input:SetTouchActive("Crouch",on)
end
function Controller:Start()
 Crouch.wanted=false;Crouch.amount=0
 self._scope:Add(game:GetService("RunService").PreSimulation:Connect(function()self:_NoJump()end))
 -- C / gamepad R3 / touch button toggle crouch.
 self._scope:Add(self._input:Register("Crouch",function(state)
  if state=="Begin" then self._ctrlHeld=false;self:_SetCrouch(not Crouch.wanted) end
 end))
 -- Left Ctrl (gamepad B): a plain crouch while held - it never lies you down (only vents do that).
 -- A crouch that C turned on is left alone; releasing Ctrl only stands you up from its own crouch.
 self._scope:Add(self._input:Register("CrouchHold",function(state)
  if state=="Begin" then
   if not Crouch.wanted then self._ctrlHeld=true;self:_SetCrouch(true) end
  elseif self._ctrlHeld then
   self._ctrlHeld=false;self:_SetCrouch(false)
  end
 end))
	self._scope:Add(self._input:Register("Sprint",function(state)
		self._held=state=="Begin"
		if self._held and Crouch.wanted then self._ctrlHeld=false;self:_SetCrouch(false) end -- sprinting stands you up
		self:_Send(self._held);self._elapsed=0
	end))
	self._scope:Add(game:GetService("RunService").Heartbeat:Connect(function(dt)
		self._elapsed=(self._elapsed or 0)+dt
		if self._held and self._elapsed>=.5 then self._elapsed=0;self:_Send(true) end
		local server=self._player:GetAttribute("EHCrouching")==true
		-- In a duct you are lying down: crouch and sprint mean nothing there, so their buttons go away
		-- (on touch the crouch button used to flicker and fight the duct's own crouch lock), and the
		-- crouch state is owned by the vent code until you are out again.
		local inVent=self._player:GetAttribute("EHInVent")~=nil or Crawl.state=='Vent' or Crawl.exiting==true
		if inVent~=self._ventLocked then
			self._ventLocked=inVent
			self._input:SetAvailable("Crouch",not inVent);self._input:SetAvailable("CrouchHold",not inVent);self._input:SetAvailable("Sprint",not inVent)
			if inVent then self._ctrlHeld=false;self._crouchSent=os.clock() else self._crouchSent=os.clock();self._input:SetTouchActive("Crouch",Crouch.wanted==true) end
		end
		-- (not while climbing out of a duct: you stand up as you drop out, before the server's crouch lets go)
		if not inVent and server~=Crouch.wanted and os.clock()-(self._crouchSent or 0)>.6 and not Crawl.exiting then
			Crouch.wanted=server;if not server then self._ctrlHeld=false end;self._input:SetTouchActive("Crouch",server)
		end

	end))
    -- The bar runs its own copy of the stamina model every frame (drain while the server says you
    -- sprint, refill after the same rest delay), so it slides at a constant rate instead of
    -- stepping each time a server update lands; the server value only steers it gently.
    local displayed,opacity=1,0
    local lastSprint=-math.huge
    self._scope:Add(game:GetService("RunService").RenderStepped:Connect(function(dt)
        dt=math.min(dt,.1)
        local target=math.clamp((self._player:GetAttribute("EHStamina") or Config.MaxStamina)/Config.MaxStamina,0,1)
        local now=os.clock()
        local sprinting=self._player:GetAttribute("EHSprinting")==true
        if sprinting then lastSprint=now end
        local rate=0
        if sprinting then rate=-Config.SprintDrainPerSecond/Config.MaxStamina
        elseif now-lastSprint>=Config.RegenerationDelay then rate=Config.RegenerationPerSecond/Config.MaxStamina end
        displayed=math.clamp(displayed+rate*dt,0,1)
        local err=target-displayed
        if math.abs(err)>.2 then displayed=target -- respawn / restore: jump straight there
        else displayed+=err*(1-math.exp(-dt/.6)) end
        local blend=1-math.exp(-dt/.15)
        local context=self._player:GetAttribute("EHContext")
        local active=context=="Lobby" or context=="ActiveFloor" or context=="Transit"
        local show=active and (target<.999 or displayed<.997)
        opacity+=((show and 1 or 0)-opacity)*blend
        self._bar.Visible=active and opacity>.01
        local shown=opacity*Reveal.Alpha() -- (fades in with the rest of the HUD after the lift)
        self._bar.BackgroundTransparency=1-shown*.55
        self._fill.BackgroundTransparency=1-shown*.85
        self._fill.Size=UDim2.fromScale(displayed,1)
        local low=math.clamp((.3-target)/.3,0,1)
        self._fill.BackgroundColor3=Color3.fromRGB(210,208,192):Lerp(Color3.fromRGB(190,105,78),low)
    end))
end
function Controller:Destroy()
	if self._held then self:_Send(false) end;self._held=false
	if Crouch.wanted then self:_SetCrouch(false) end
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
