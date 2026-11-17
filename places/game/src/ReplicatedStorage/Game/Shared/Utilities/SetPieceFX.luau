--!nonstrict
-- R43: the visual effects kit for set pieces (client only, nothing replicated). Used by SetPieceController to
-- draw a floor's beats (Config.<Floor>.Beats) and by floor controllers directly.
--   Burst(part, kind, seconds)   particles at a part: Steam, Spray, Gas, Sparks, Boil, Mist, Drip
--   Lights(parts, on, gap, opts) switch the lights in parts off (or on) one after another, with flicker and pops
--   Beacons(parts, seconds)      spin amber beacons and light them
--   Shake(amplitude, seconds)    camera shake that never builds into your aim
--   Sound(id, parent, volume, speed, life)
--   Show(parts, visible)         hide or show parts on this screen only
-- Textures for particles come from Config.FX (Blender sprites); empty entries fall back to the engine's own.
-- Phones get half the particles (MobilePerf sets EHLowFx on the player).
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local SoundService=game:GetService('SoundService')
local Debris=game:GetService('Debris')
local M={}

local function fxConfig()
	local ok,c=pcall(function()return require(game.ReplicatedStorage.Game.Shared.Config.FX)end)
	return ok and c or {Textures={},Sounds={}}
end
local SMOKE='rbxasset://textures/particles/smoke_main.dds'
local SPARK='rbxasset://textures/particles/sparkles_main.dds'
local function tex(name,fallback)
	local t=fxConfig().Textures[name]
	return (t and t~='') and t or fallback
end
local function low() local p=Players.LocalPlayer;return p and p:GetAttribute('EHLowFx')==true end
local NS,CS=NumberSequence.new,ColorSequence.new
local function nsk(...) local t={};local a={...};for i=1,#a,2 do table.insert(t,NumberSequenceKeypoint.new(a[i],a[i+1])) end;return NS(t) end

-- particle presets: emitter properties, plus `rate` (per second) and `burst` (a one-off count)
local PRESETS={
	Steam={Texture=function()return tex('Steam',SMOKE)end,Color=CS(Color3.fromRGB(220,224,222)),Size=nsk(0,1.5,1,6),Transparency=nsk(0,.55,.3,.7,1,1),
		Lifetime=NumberRange.new(1.4,2.4),Speed=NumberRange.new(5,9),SpreadAngle=Vector2.new(14,14),Acceleration=Vector3.new(0,3,0),Drag=1.2,
		RotSpeed=NumberRange.new(-30,30),Rotation=NumberRange.new(0,360),LightInfluence=1,rate=40},
	Spray={Texture=function()return tex('Spray',SPARK)end,Color=CS(Color3.fromRGB(196,206,204)),Size=nsk(0,.18,1,.08),Transparency=nsk(0,.2,1,1),
		Lifetime=NumberRange.new(.5,.9),Speed=NumberRange.new(16,24),SpreadAngle=Vector2.new(18,18),Acceleration=Vector3.new(0,-40,0),LightInfluence=1,rate=220},
	Gas={Texture=function()return tex('Gas',SMOKE)end,Color=CS(Color3.fromRGB(176,150,82)),Size=nsk(0,3,1,12),Transparency=nsk(0,.75,.4,.6,1,1),
		Lifetime=NumberRange.new(4,6),Speed=NumberRange.new(1.5,3),SpreadAngle=Vector2.new(70,20),Acceleration=Vector3.new(0,-.4,0),Drag=.6,
		RotSpeed=NumberRange.new(-12,12),Rotation=NumberRange.new(0,360),LightInfluence=1,rate=26},
	Sparks={Texture=function()return tex('Spark',SPARK)end,Color=CS(Color3.fromRGB(255,190,110)),Size=nsk(0,.14,1,0),Transparency=nsk(0,0,1,1),
		Lifetime=NumberRange.new(.35,.8),Speed=NumberRange.new(12,20),SpreadAngle=Vector2.new(60,60),Acceleration=Vector3.new(0,-50,0),LightEmission=1,LightInfluence=0,burst=40,rate=0},
	Boil={Texture=function()return tex('Foam',SMOKE)end,Color=CS(Color3.fromRGB(232,236,232)),Size=nsk(0,1,1,3.2),Transparency=nsk(0,.35,1,1),
		Lifetime=NumberRange.new(.5,.9),Speed=NumberRange.new(3,6),SpreadAngle=Vector2.new(25,25),Acceleration=Vector3.new(0,-4,0),LightInfluence=1,rate=140,
		Shape=Enum.ParticleEmitterShape.Box,ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume},
	Mist={Texture=function()return tex('Mist',SMOKE)end,Color=CS(Color3.fromRGB(150,160,156)),Size=nsk(0,7,1,14),Transparency=nsk(0,1,.3,.85,1,1),
		Lifetime=NumberRange.new(5,8),Speed=NumberRange.new(.3,.8),SpreadAngle=Vector2.new(180,10),LightInfluence=1,rate=6,
		Shape=Enum.ParticleEmitterShape.Box,ShapeStyle=Enum.ParticleEmitterShapeStyle.Volume},
	Drip={Texture=function()return tex('Spray',SPARK)end,Color=CS(Color3.fromRGB(40,44,42)),Size=nsk(0,.12,1,.1),Transparency=nsk(0,.1,1,.4),
		Lifetime=NumberRange.new(.6,.9),Speed=NumberRange.new(0,.5),Acceleration=Vector3.new(0,-35,0),LightInfluence=1,rate=3},
}
M.Presets=PRESETS

-- particles at a part (or an Attachment) for `seconds` (nil = until the returned stop() is called)
function M.Burst(at,kind,seconds,overrides)
	local preset=PRESETS[kind];if not preset or not at then return function()end end
	local e=Instance.new('ParticleEmitter')
	for k,v in preset do
		if k=='Texture' then e.Texture=v()
		elseif k~='rate' and k~='burst' then pcall(function()e[k]=v end) end
	end
	for k,v in overrides or {} do pcall(function()e[k]=v end) end
	local scale=low() and .5 or 1
	e.Rate=(overrides and overrides.Rate or preset.rate or 0)*scale
	e.Parent=at
	if preset.burst then e:Emit(math.floor(preset.burst*scale)) end
	local function stop() e.Enabled=false;Debris:AddItem(e,8) end
	if seconds then task.delay(seconds,stop) end
	return stop
end

function M.Sound(id,parent,volume,speed,life)
	if not id or id=='' then return nil end
	local s=Instance.new('Sound');s.SoundId=id;s.Volume=volume or .5;s.PlaybackSpeed=speed or 1
	if parent then s.RollOffMinDistance=8;s.RollOffMaxDistance=90 end
	s.Parent=parent or SoundService;s:Play();Debris:AddItem(s,life or 8)
	return s
end

local function lightsIn(part)
	local t={}
	for _,d in part:GetDescendants() do if d:IsA('Light') then table.insert(t,d) end end
	if part:IsA('Light') then table.insert(t,part) end
	return t
end
-- the glowing parts of a lamp: Neon parts in it (or the part itself if Neon)
local function glowIn(part)
	local t={}
	if part:IsA('BasePart') and part.Material==Enum.Material.Neon then table.insert(t,part) end
	for _,d in part:GetDescendants() do if d:IsA('BasePart') and (d.Material==Enum.Material.Neon or d:GetAttribute('BWGlow')) then table.insert(t,d) end end
	return t
end
local saved=setmetatable({},{__mode='k'})
function M.Lamp(part,on)
	for _,l in lightsIn(part) do
		if saved[l]==nil then saved[l]=l.Enabled end
		l.Enabled=on and saved[l] or false
	end
	for _,g in glowIn(part) do
		if not g:GetAttribute('BWGlow') then g:SetAttribute('BWGlow',true);g:SetAttribute('BWGlowColor',g.Color) end
		g.Material=on and Enum.Material.Neon or Enum.Material.Glass
		g.Color=on and g:GetAttribute('BWGlowColor') or Color3.fromRGB(70,68,60)
	end
end

-- lights out one after another (or back on), each with a short flicker and a bulb pop
function M.Lights(parts,on,gap,opts)
	opts=opts or {}
	local S=fxConfig().Sounds
	for i,p in parts do
		task.delay((i-1)*(gap or .25),function()
			if not p.Parent then return end
			if opts.flicker~=false then
				for k=1,3 do M.Lamp(p,k%2==1);task.wait(.04+math.random()*.06) end
			end
			M.Lamp(p,on)
			if not on and opts.pop~=false then
				M.Sound(S.BulbPop,p:IsA('BasePart') and p or p:FindFirstChildWhichIsA('BasePart',true),.45,.9+math.random()*.25,3)
				local b=p:IsA('BasePart') and p or p:FindFirstChildWhichIsA('BasePart',true)
				if b and opts.sparks then M.Burst(b,'Sparks',.2) end
			end
		end)
	end
end

function M.Beacons(parts,seconds)
	local stop=false
	local conn=RunService.RenderStepped:Connect(function(dt)
		for _,p in parts do
			for _,l in lightsIn(p) do l.Enabled=true end
			local spin=p:FindFirstChild('Spinner',true)
			if spin and spin:IsA('BasePart') then spin.CFrame*=CFrame.Angles(0,dt*7,0) end
		end
	end)
	local function off() if stop then return end;stop=true;conn:Disconnect();for _,p in parts do for _,l in lightsIn(p) do l.Enabled=false end end end
	if seconds then task.delay(seconds,off) end
	return off
end

-- camera shake: an offset added after the camera has moved and taken away again before it moves next frame
local shakes={};local shaking=false;local undo
local function bindShake()
	if shaking then return end
	shaking=true
	RunService:BindToRenderStep('BlackwaterShakeUndo',Enum.RenderPriority.First.Value,function()
		local cam=workspace.CurrentCamera
		if undo and cam then cam.CFrame=undo;undo=nil end
	end)
	RunService:BindToRenderStep('BlackwaterShake',Enum.RenderPriority.Camera.Value+3,function()
		local cam=workspace.CurrentCamera;if not cam then return end
		local now=os.clock();local amp=0
		for i=#shakes,1,-1 do
			local s=shakes[i];local u=(now-s.t0)/s.dur
			if u>=1 then table.remove(shakes,i) else amp+=s.amp*(1-u)^2 end
		end
		if amp<=.001 or cam.CameraType~=Enum.CameraType.Custom then return end
		undo=cam.CFrame
		local n=now*22
		cam.CFrame=cam.CFrame*CFrame.new(math.noise(n,4)*amp*.3,math.noise(n,5)*amp*.3,0)*CFrame.Angles(math.noise(n,6)*amp*.02,math.noise(n,7)*amp*.02,math.noise(n,8)*amp*.015)
	end)
end
function M.Shake(amp,seconds,from)
	if from then
		local cam=workspace.CurrentCamera
		local d=cam and (cam.CFrame.Position-from).Magnitude or 0
		amp*=math.clamp(1-d/90,0,1)
	end
	if amp<=0 then return end
	bindShake()
	table.insert(shakes,{amp=amp,dur=seconds or 1,t0=os.clock()})
end

local hidden=setmetatable({},{__mode='k'})
function M.Show(parts,visible)
	for _,p in parts do
		local list={p};for _,d in p:GetDescendants() do table.insert(list,d) end
		for _,d in list do
			if d:IsA('BasePart') then d.LocalTransparencyModifier=visible and 0 or 1
			elseif d:IsA('Decal') or d:IsA('Texture') then
				if hidden[d]==nil then hidden[d]=d.Transparency end
				d.Transparency=visible and hidden[d] or 1
			elseif d:IsA('Light') or d:IsA('ParticleEmitter') or d:IsA('SurfaceGui') then d.Enabled=visible end
		end
	end
end

return M
