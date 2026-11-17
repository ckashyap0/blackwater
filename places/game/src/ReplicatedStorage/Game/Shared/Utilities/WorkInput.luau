--!nonstrict
-- R43: input for the work-mode jobs (InteractionService modes Crank, Lever, Pump). Used by InteractionController.
--   Crank  hold E and turn: circle the mouse, the right stick or a finger. The view stops turning while you
--          crank. A dial (StarterGui.InteractionHint.WorkDial) shows the handle going round.
--   Lever  hold E and pull: drag the mouse, the stick or a finger down.
--   Pump   tap E in a steady beat. Each tap is one stroke; the job lapses if the beat stops.
-- The client only reports effort four times a second (ContinueInteraction.work). The server caps it.
local UIS=game:GetService('UserInputService')
local CAS=game:GetService('ContextActionService')
local StarterPlayer=game:GetService('StarterPlayer')
local M={}
local RADIUS=90        -- virtual crank handle radius, screen pixels
local LEVER_PX=280     -- mouse/finger travel for one full pull
local SEND=.25         -- seconds between effort reports
local PUMP_LAPSE=1.35  -- a pump hold lets go this long after the last tap
local SINK='BlackwaterWorkLook'

local function lookLock(on)
	-- the camera and character contexts run on the Input Action System, which ContextActionService can't
	-- sink, so they are switched off at the source while cranking or pulling (as InputController does)
	local folder=StarterPlayer:FindFirstChild('PlayerModule');folder=folder and folder:FindFirstChild('InputContexts')
	local ctx=folder and folder:FindFirstChild('CameraContext')
	if ctx then pcall(function()ctx.Enabled=not on end) end
	if on then
		CAS:BindActionAtPriority(SINK,function()return Enum.ContextActionResult.Sink end,false,Enum.ContextActionPriority.High.Value+90,
			Enum.UserInputType.MouseMovement,Enum.KeyCode.Thumbstick2)
	else pcall(function()CAS:UnbindAction(SINK)end) end
end

local function dial(ctrl)
	local gui=ctrl._hint;local d=gui and gui:FindFirstChild('WorkDial')
	return d,d and d:FindFirstChild('Knob')
end

function M.Begin(ctrl,target,mode)
	local w=ctrl._work
	table.clear(w)
	w.mode=mode;w.target=target;w.pending=0;w.sent=os.clock();w.v=Vector2.new(0,-RADIUS);w.dir=0;w.shown=0
	if mode=='Crank' or mode=='Lever' then
		lookLock(true)
		w.conn=UIS.InputChanged:Connect(function(input)
			if input.UserInputType==Enum.UserInputType.Touch then w.touch=(w.touch or Vector2.zero)+Vector2.new(input.Delta.X,input.Delta.Y)
			elseif input.KeyCode==Enum.KeyCode.Thumbstick2 then w.stick=Vector2.new(input.Position.X,-input.Position.Y) end
		end)
	end
	local d=dial(ctrl);if d then d.Visible=mode=='Crank' end
end

function M.End(ctrl)
	local w=ctrl._work
	if w.conn then w.conn:Disconnect() end
	if w.mode=='Crank' or w.mode=='Lever' then lookLock(false) end
	local d=dial(ctrl);if d then d.Visible=false end
	table.clear(w)
end

-- one pump stroke: a short kick of the view so the beat is felt
function M.Pulse(ctrl)
	ctrl._work.kick=os.clock()
end

-- the delta the player's input moved this frame, in screen pixels
local function delta(w,dt)
	local d=Vector2.zero
	if UIS.MouseEnabled then UIS.MouseBehavior=Enum.MouseBehavior.LockCenter;local m=UIS:GetMouseDelta();d+=Vector2.new(m.X,m.Y) end
	if w.touch then d+=w.touch;w.touch=nil end
	return d
end

function M.Step(ctrl,dt)
	local w=ctrl._work;local h=ctrl._holding
	if not w.mode or not h then return end
	if w.mode=='Pump' then
		if os.clock()-(w.lastTap or 0)>PUMP_LAPSE then ctrl:_Cancel();return end
		if os.clock()-w.sent>=1 then w.sent=os.clock();ctrl:_Send('ContinueInteraction',h.id,h.epoch) end -- keepalive between taps
		return
	end
	local d=delta(w,dt)
	if w.mode=='Crank' then
		local old=w.v
		if w.stick and w.stick.Magnitude>.35 then w.v=w.stick.Unit*RADIUS
		else
			local v=w.v+d
			w.v=v.Magnitude>1 and v.Unit*RADIUS or w.v
		end
		local a0=math.atan2(old.Y,old.X);local a1=math.atan2(w.v.Y,w.v.X)
		local da=(a1-a0+math.pi)%(2*math.pi)-math.pi
		-- turn one way: the first real movement picks the direction, going back the other way does nothing
		if w.dir==0 and math.abs(da)>.05 then w.dir=da>0 and 1 or -1 end
		if w.dir~=0 and da*w.dir>0 then w.pending+=math.abs(da)/(2*math.pi) end
		local dl,knob=dial(ctrl)
		if knob then knob.Position=UDim2.new(.5,w.v.X*.5,.5,w.v.Y*.5) end
	elseif w.mode=='Lever' then
		local pull=math.max(0,d.Y)/LEVER_PX
		if w.stick and w.stick.Y<-.35 then pull+=(-w.stick.Y)*dt*1.4 end
		w.pending+=pull
	end
	if os.clock()-w.sent>=SEND then
		w.sent=os.clock()
		ctrl:_Send('ContinueInteraction',h.id,h.epoch,w.pending)
		w.pending=0
	end
end

-- 0..1 to show on the bar: the server's progress, nudged forward by effort not yet confirmed
function M.Shown(ctrl)
	local w=ctrl._work;local t=w.target
	if not t then return 0 end
	local p=t:GetAttribute('EHWorkProgress') or 0
	local work=t:GetAttribute('EHWork') or 1
	return math.clamp(p+(w.pending or 0)/work,0,1)
end

-- the prompt line for a target, by how it is worked
function M.Hint(ctrl,target,action)
	local mode=target:GetAttribute('EHInteractionMode')
	if mode==nil or mode=='Hold' or mode=='Sync' then return action end
	local touch=UIS.PreferredInput==Enum.PreferredInput.Touch
	local pad=UIS.PreferredInput==Enum.PreferredInput.Gamepad
	local working=ctrl._work.mode~=nil and ctrl._work.target==target
	if mode=='Crank' then return working and (touch and 'Circle your finger' or pad and 'Circle the right stick' or 'Circle the mouse') or action end
	if mode=='Lever' then return working and (touch and 'Drag down' or pad and 'Pull the right stick down' or 'Pull the mouse down') or action end
	if mode=='Pump' then return working and 'Keep tapping' or action end
	return action
end

return M
