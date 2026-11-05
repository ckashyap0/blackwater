--!nonstrict
-- Brings the lobby machinery to life, purely visually and locally (no server traffic):
--   EHSpin (number, rev/sec-ish) on a Model -> spins it about its pivot's X axis
--     (the hoist sheave speeds up while any elevator is departing)
--   EHBlink (seconds) on a part             -> indicator lamp blinks
--   EHJitter (radians) on a gauge needle    -> needle quivers about its base
--   EHFire on a part with a PointLight      -> firelight flicker
--   Bay*.DialNeedle / DialPivot             -> mechanical floor dial: rests on L, trembles during
--     the countdown, sweeps L -> 5 -> 1 while that elevator departs
-- Everything here is authored in Studio; tag new parts with the same attributes to animate them.
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local DIAL_L,DIAL_1=-70,70 -- degrees; L on the left, 1 on the right
local DESCEND_SECONDS=14
function Controller.new()return setmetatable({Name="MachineController",Dependencies={},_spin={},_blink={},_jitter={},_dials={},_fires={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_Collect(env)
	for _,d in env:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("EHSpin") then
			table.insert(self._spin,{model=d,base=d:GetPivot(),rate=d:GetAttribute("EHSpin"),angle=0,hoist=d.Parent and d.Parent.Name=="Hoist"})
		elseif d:IsA("BasePart") and d:GetAttribute("EHBlink") then
			table.insert(self._blink,{part=d,period=d:GetAttribute("EHBlink"),color=d.Color,phase=math.random()})
		elseif d:IsA("BasePart") and d:GetAttribute("EHFire") then
			local l=d:FindFirstChildWhichIsA("PointLight")
			if l then table.insert(self._fires,{light=l,base=l.Brightness,seed=math.random()*10}) end
		elseif d:IsA("BasePart") and d:GetAttribute("EHJitter") then
			local pivot=d.CFrame*CFrame.new(0,-d.Size.Y/2+.01,0)
			table.insert(self._jitter,{part=d,pivot=pivot,offset=d.Size.Y/2-.01,amp=d:GetAttribute("EHJitter"),seed=math.random()*10})
		end
	end
	for _,bay in env:GetChildren() do
		local needle,pivot=bay:FindFirstChild("DialNeedle"),bay:FindFirstChild("DialPivot")
		if needle and pivot then
			table.insert(self._dials,{bay=bay,needle=needle,origin=pivot.Position+Vector3.new(0,0,.02),len=needle.Size.Y,angle=DIAL_L,seed=math.random()*10})
		end
	end
end
function Controller:_Step(dt)
	local t=os.clock()
	local now=workspace:GetServerTimeNow()
	-- dials (and note whether anything is departing, for the hoist)
	local departing=false
	for _,d in self._dials do
		local bay=d.bay
		local state=bay:GetAttribute("ReadyState")
		local departAt=bay:GetAttribute("DepartAt")
		local target=DIAL_L
		if state=="Launching" then
			departing=true
			d.descendStart=d.descendStart or t
			local k=math.clamp((t-d.descendStart)/DESCEND_SECONDS,0,1)
			target=DIAL_L+28+(DIAL_1-DIAL_L-28)*k -- passes 5 first, then down to 1
		else
			d.descendStart=nil
			if departAt then departing=true end
		end
		d.angle+=(target-d.angle)*math.min(1,dt*(state=="Launching" and 2 or 6))
		-- the needle trembles against its stop while the countdown runs
		local tremble=(departAt and state~="Launching") and (math.sin(t*41+d.seed)*2+math.sin(t*17+d.seed)*1.2) or 0
		d.needle.CFrame=CFrame.new(d.origin)*CFrame.Angles(0,0,math.rad(-(d.angle+tremble)))*CFrame.new(0,d.len/2-.04,0)
	end
	for _,s in self._spin do
		local rate=s.rate*(s.hoist and departing and 5 or 1)
		s.angle=(s.angle+rate*dt*math.pi*2)%(math.pi*2)
		s.model:PivotTo(s.base*CFrame.Angles(s.angle,0,0))
	end
	for _,b in self._blink do
		local on=((t/b.period)+b.phase)%1<.5
		if b.on~=on then
			b.on=on
			b.part.Material=on and Enum.Material.Neon or Enum.Material.SmoothPlastic
			b.part.Color=on and b.color or b.color:Lerp(Color3.new(0,0,0),.75)
		end
	end
	for _,f in self._fires do
		local n=math.sin(t*7.3+f.seed)*.5+math.sin(t*13.1+f.seed*2)*.3+math.sin(t*23.7)*.2
		f.light.Brightness=f.base*(.85+.25*n)
	end
	for _,j in self._jitter do
		local a=(math.sin(t*9+j.seed)+math.sin(t*23+j.seed*2)*.5)*j.amp
		j.part.CFrame=j.pivot*CFrame.Angles(a,0,0)*CFrame.new(0,j.offset,0)
	end
end
function Controller:Start()
	task.spawn(function()
		local runtime=workspace:WaitForChild("Runtime")
		local env=runtime:WaitForChild("LobbyEnvironment",30)
		if not env then return end -- not the lobby place
		self:_Collect(env)
		self._scope:Add(RunService.RenderStepped:Connect(function(dt)self:_Step(dt)end))
	end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
