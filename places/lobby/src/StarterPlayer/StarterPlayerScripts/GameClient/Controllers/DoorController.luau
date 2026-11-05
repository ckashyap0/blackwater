--!nonstrict
-- Animates the lobby elevator doors locally, every frame.
-- PartyService (server) only decides open/closed: it sets the bay attributes DoorClosed and
-- DoorChangedAt (server time) and snaps the door parts to their final state. Each client then
-- slides the doors from the other end over DURATION with smooth easing, so motion isn't limited
-- by network update rate. Doors fade in as they start closing and fade out once fully open.
-- It also drives each bay's ReadyLamp from the server's Occupied / DepartAt / ReadyState attributes:
-- soft white while empty, fades to green when someone steps in (and back to white when they leave),
-- and glows brighter across the departure countdown.
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local DURATION=2.6
local FADE=.25
local COUNTDOWN=5
local LAMP_WHITE=Color3.fromRGB(236,232,220)
local LAMP_GREEN=Color3.fromRGB(110,220,130)
local COLOR_RATE=1.25 -- white<->green fade, ~0.8s
local GLOW_IDLE,GLOW_OCCUPIED,GLOW_DEPART=.9,1.4,3.4
local function ease(t) -- quintic smootherstep: zero velocity and acceleration at both ends
	return t*t*t*(t*(t*6-15)+10)
end
function Controller.new()return setmetatable({Name="DoorController",Dependencies={},_bays={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_Track(bay)
	local entry={bay=bay,doors={}}
	for _,side in {"Left","Right"} do
		local door,open,closed=bay:FindFirstChild("Door"..side),bay:FindFirstChild("Door"..side.."Open"),bay:FindFirstChild("Door"..side.."Closed")
		if door and open and closed then table.insert(entry.doors,{part=door,open=open.CFrame,closed=closed.CFrame})end
	end
	if #entry.doors==0 then return end
	entry.lamp=bay:FindFirstChild("ReadyLamp");entry.glow=entry.lamp and entry.lamp:FindFirstChild("Glow")
	entry.lampGreen=bay:GetAttribute("Occupied") and 1 or 0;entry.lampGlow=GLOW_IDLE
	self._bays[bay]=entry
	local function changed()
		local closed=bay:GetAttribute("DoorClosed")==true
		entry.closed=closed;entry.start=bay:GetAttribute("DoorChangedAt") or workspace:GetServerTimeNow()
		-- Reverse from wherever the door was last drawn (e.g. reopening mid-close), not from the far end.
		for _,d in entry.doors do d.from=d.last or (closed and d.open or d.closed) end
		entry.active=true
	end
	self._scope:Add(bay:GetAttributeChangedSignal("DoorChangedAt"):Connect(changed))
	-- Joining mid-animation picks up where everyone else is; otherwise settle instantly.
	if bay:GetAttribute("DoorChangedAt") then changed() end
end
function Controller:_Lamp(e,now,dt)
	local lamp=e.lamp;if not lamp then return end
	local bay=e.bay
	local state=bay:GetAttribute("ReadyState") or "Off"
	local departAt=bay:GetAttribute("DepartAt")
	local occupied=bay:GetAttribute("Occupied")==true or state=="Launching"
	-- colour: white when empty, green when someone is inside (smooth fade both ways)
	local g=occupied and 1 or 0
	local step=math.min(1,dt*COLOR_RATE)
	if e.lampGreen<g then e.lampGreen=math.min(g,e.lampGreen+step) else e.lampGreen=math.max(g,e.lampGreen-step) end
	local k=e.lampGreen;k=k*k*(3-2*k)
	local color=LAMP_WHITE:Lerp(LAMP_GREEN,k)
	-- glow: brighter while occupied, swelling across the countdown
	local glow=occupied and GLOW_OCCUPIED or GLOW_IDLE
	if state=="Launching" then glow=GLOW_DEPART
	elseif departAt then glow=GLOW_OCCUPIED+(GLOW_DEPART-GLOW_OCCUPIED)*math.clamp(1-(departAt-now)/COUNTDOWN,0,1) end
	e.lampGlow+=(glow-e.lampGlow)*math.min(1,dt*5)
	lamp.Color=color
	if lamp.Material~=Enum.Material.Neon then lamp.Material=Enum.Material.Neon end
	if e.glow then e.glow.Enabled=true;e.glow.Color=color;e.glow.Brightness=e.lampGlow end
end
function Controller:_Step(dt)
	local now=workspace:GetServerTimeNow()
	for _,e in self._bays do
		self:_Lamp(e,now,dt)
		if e.active then
			local elapsed=math.max(0,now-e.start)
			local t=math.clamp(elapsed/DURATION,0,1)
			local k=ease(t)
			for _,d in e.doors do
				local to=e.closed and d.closed or d.open
				d.last=d.from:Lerp(to,k)
				d.part.CFrame=d.last
				if e.closed then
					d.part.Transparency=1-math.clamp(elapsed/FADE,0,1)
					d.part.CanCollide=true
				else
					d.part.Transparency=math.clamp((elapsed-DURATION)/FADE,0,1)
					d.part.CanCollide=t<1
				end
			end
			-- Done once the slide (and, when opening, the fade-out) has finished.
			if t>=1 and (e.closed or elapsed>=DURATION+FADE) then e.active=false end
		end
	end
end
function Controller:Start()
	task.spawn(function()
		local runtime=workspace:WaitForChild("Runtime")
		local env=runtime:WaitForChild("LobbyEnvironment",30)
		if not env then return end -- not a lobby place
		local function consider(child)if child.Name:match("^Bay%d+$") then self:_Track(child)end end
		for _,child in env:GetChildren() do consider(child) end
		self._scope:Add(env.ChildAdded:Connect(consider))
	end)
	self._scope:Add(RunService.RenderStepped:Connect(function(dt)self:_Step(dt)end))
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
