--!nonstrict
-- R43: draws set pieces for every floor. All of it is driven by the server's stamps, so every screen agrees:
--   * camera cuts (Utilities.Cinematic, from the floor's CineId/CineAt)
--   * beats: when the server stamps Beat_<name> on a floor, the effects listed in Config.<EncounterId>.Beats[name]
--     play here (lights cascading out, bursts of steam or gas, beacons, shakes, sounds, parts shown or hidden).
--     Entries marked keep=true (lights left off, parts hidden) are also applied for a beat that fired before
--     this screen saw the floor.
--   * rising water (Floors.RisingWater): surfaces follow the server's level curve, lamps under it go out, and
--     the picture turns murky with your eyes under the surface
--   * push-back (Floors.PushBack): a fade to black and back from EHPushBackAt
--   * moving machinery: a target with SpinRef (a Crank) turns that part with the job's progress, a target
--     with LeverRef (a Lever) swings that part down
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Lighting=game:GetService('Lighting')
local TweenService=game:GetService('TweenService')
local CS=game:GetService('CollectionService')
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Refs=require(Shared.Utilities.FloorRefs)
local FX=require(Shared.Utilities.SetPieceFX)
local Cinematic=require(Shared.Utilities.Cinematic)
local Controller={};Controller.__index=Controller
local OLD_BEAT=8 -- a beat stamped longer ago than this only re-applies its lasting (keep) effects

function Controller.new(player)return setmetatable({Name='SetPieceController',Dependencies={},_player=player,_floors={},_water={},_machines={}},Controller)end
function Controller:Init()self._scope=Scope.new()end

-- the floor model an instance belongs to (the child of Runtime.DescentEnvironment it sits under)
local function floorOf(inst)
	local f=inst
	while f and f.Parent and f.Parent.Name~='DescentEnvironment' do f=f.Parent end
	return f and f.Parent and f or nil
end
local function beatsFor(floor)
	local id=floor:GetAttribute('EncounterId');if type(id)~='string' then return nil end
	local mod=Shared.Config:FindFirstChild(id);if not mod then return nil end
	local ok,c=pcall(require,mod)
	return ok and type(c)=='table' and c.Beats or nil
end

local function resolve(floor,entry)
	local list={}
	local names=entry.refs or (entry.ref and {entry.ref}) or {}
	for _,n in names do local p=Refs.Find(floor,n);if p then table.insert(list,p) end end
	-- folder=RefName: every lamp/part directly inside a referenced model or folder
	if entry.folder then
		local f=Refs.Find(floor,entry.folder) or floor:FindFirstChild(entry.folder,true)
		if f then for _,c in f:GetChildren() do table.insert(list,c) end end
	end
	return list
end

function Controller:_Effect(floor,entry,old)
	if old and not entry.keep then return end
	local parts=resolve(floor,entry)
	local kind=entry.fx
	if kind=='Lights' then
		if entry.order=='distance' and entry.from then
			local o=Refs.Find(floor,entry.from)
			if o then table.sort(parts,function(a,b)
				local pa=a:IsA('BasePart') and a.Position or a:GetPivot().Position;local pb=b:IsA('BasePart') and b.Position or b:GetPivot().Position
				return (pa-o.Position).Magnitude<(pb-o.Position).Magnitude end) end
		end
		FX.Lights(parts,entry.on==true,old and 0 or entry.gap,{flicker=not old,pop=not old,sparks=entry.sparks})
	elseif kind=='Burst' then for _,p in parts do FX.Burst(p,entry.kind or 'Steam',entry.seconds,entry.props) end
	elseif kind=='Beacons' then FX.Beacons(parts,entry.seconds or 10)
	elseif kind=='Shake' then FX.Shake(entry.amp or .3,entry.seconds or 1,parts[1] and parts[1].Position)
	elseif kind=='Sound' then FX.Sound(entry.id,parts[1],entry.volume,entry.speed,entry.life)
	elseif kind=='Show' or kind=='Hide' then FX.Show(parts,kind=='Show')
	elseif kind=='Tint' then
		-- parts change colour (clean water turning black); a late joiner gets the end colour at once
		for _,p in parts do if p:IsA('BasePart') then
			TweenService:Create(p,TweenInfo.new(old and 0 or (entry.seconds or 4),Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Color=entry.color or Color3.new(0,0,0),Reflectance=entry.reflectance or p.Reflectance}):Play()
		end end
	end
end

function Controller:_Beat(floor,name,at)
	local beats=beatsFor(floor);local list=beats and beats[name]
	if type(list)~='table' then return end
	local age=workspace:GetServerTimeNow()-at
	local old=age>OLD_BEAT
	for _,entry in list do
		local delay=(entry.at or 0)-math.max(age,0)
		if old or delay<=0 then task.spawn(self._Effect,self,floor,entry,old)
		else task.delay(delay,function() if floor.Parent then self:_Effect(floor,entry,false) end end) end
	end
end

function Controller:_Watch(floor)
	if self._floors[floor] then return end
	local seen={}
	self._floors[floor]=true
	local function check(attr)
		if attr:sub(1,5)~='Beat_' then return end
		local at=floor:GetAttribute(attr)
		if type(at)=='number' and seen[attr]~=at then seen[attr]=at;self:_Beat(floor,attr:sub(6),at) end
	end
	self._scope:Add(floor.AttributeChanged:Connect(check))
	for k in floor:GetAttributes() do check(k) end
	floor.Destroying:Connect(function()self._floors[floor]=nil end)
end

------------------------------------------------------------------------------------------- rising water
local function curve(f)
	local from,to=f:GetAttribute('FromRise') or 0,f:GetAttribute('ToRise') or 0
	local d=f:GetAttribute('Duration') or 0
	if d<=0 then return to end
	local u=math.clamp((workspace:GetServerTimeNow()-(f:GetAttribute('StartAt') or 0))/d,0,1)
	u=u*u*(3-2*u)
	return from+(to-from)*u
end
function Controller:_WaterStep(dt)
	local cam=workspace.CurrentCamera
	local murky=false
	for _,f in CS:GetTagged('BWRisingWater') do
		if f:IsDescendantOf(workspace) then
			local base=f:GetAttribute('Base')
			if type(base)=='number' then
				local level=base+curve(f)
				local w=self._water[f]
				if not w then
					w={surfaces={},lamps={},t=0}
					for _,p in f:GetChildren() do if p:IsA('BasePart') and p.Name:sub(1,7)=='Surface' then
						-- FloorY: this surface only shows once the water is over that height (a deck over a dry gallery)
						table.insert(w.surfaces,{part=p,dy=p.Position.Y-base,floorY=p:GetAttribute('FloorY'),tr=p:GetAttribute('BWSurfaceTr') or 0})
					end end
					-- lamps that can drown: anything in the floor tagged BWLamp, or lamps listed under the zone (Lamps folder)
					local floor=floorOf(f)
					for _,l in CS:GetTagged('BWLamp') do if floor and l:IsDescendantOf(floor) then table.insert(w.lamps,{part=l,under=false}) end end
					self._water[f]=w
				end
				w.t+=dt
				local risen=curve(f)>.03
				for _,s in w.surfaces do
					local p=s.part
					local cf=p.CFrame
					local y=level+s.dy
					local show=risen and (not s.floorY or y>s.floorY)
					p.Transparency=show and s.tr or 1
					p.CFrame=CFrame.new(cf.X,s.floorY and math.max(y,s.floorY) or y,cf.Z)*cf.Rotation
					local tx=p:FindFirstChildOfClass('Texture')
					if tx then tx.OffsetStudsU=(w.t*.6)%tx.StudsPerTileU;tx.OffsetStudsV=(w.t*.25)%tx.StudsPerTileV end
				end
				for _,l in w.lamps do
					local y=(l.part:IsA('BasePart') and l.part.Position.Y) or l.part:GetPivot().Position.Y
					local under=y<level-.2
					if under~=l.under then
						l.under=under
						if under then FX.Lights({l.part},false,0,{flicker=true,pop=true}) else FX.Lamp(l.part,true) end
					end
				end
				local vol=f:FindFirstChild('Volume')
				if cam and vol and cam.CFrame.Position.Y<level then
					local lp=vol.CFrame:PointToObjectSpace(cam.CFrame.Position);local h=vol.Size/2
					if math.abs(lp.X)<=h.X and math.abs(lp.Z)<=h.Z then murky=true end
				end
			end
		end
	end
	local cc=self._murk
	if murky and not cc then
		cc=Instance.new('ColorCorrectionEffect');cc.Name='BlackwaterUnderwater';cc.TintColor=Color3.fromRGB(70,86,78);cc.Brightness=-.25;cc.Contrast=.2;cc.Saturation=-.4;cc.Parent=Lighting
		local blur=Instance.new('BlurEffect');blur.Name='BlackwaterUnderwaterBlur';blur.Size=10;blur.Parent=Lighting
		self._murk=cc;self._murkBlur=blur
	elseif not murky and cc then cc:Destroy();self._murkBlur:Destroy();self._murk=nil;self._murkBlur=nil end
end

------------------------------------------------------------------------------------------- push-back fade
function Controller:_PushBack()
	local at=self._player:GetAttribute('EHPushBackAt');if type(at)~='number' then return end
	if workspace:GetServerTimeNow()-at>3 then return end
	local pg=self._player:FindFirstChild('PlayerGui');local gui=pg and pg:FindFirstChild('Cinematic')
	local black=gui and gui:FindFirstChild('Black');if not black then return end
	gui.Enabled=true
	local PB={FadeIn=.45,Hold=1.1}
	TweenService:Create(black,TweenInfo.new(PB.FadeIn,Enum.EasingStyle.Quart,Enum.EasingDirection.In),{BackgroundTransparency=0}):Play()
	FX.Shake(.4,.6)
	task.delay(PB.FadeIn+PB.Hold,function()
		TweenService:Create(black,TweenInfo.new(.6,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
	end)
end

------------------------------------------------------------------------------------------- machinery
function Controller:_Machine(t)
	local m=self._machines[t]
	if m==nil then
		local floor=floorOf(t)
		local spin=t:GetAttribute('SpinRef');local lever=t:GetAttribute('LeverRef')
		local part=floor and (spin and Refs.Find(floor,spin) or lever and Refs.Find(floor,lever))
		if part and part:IsA('Model') then part=part.PrimaryPart end
		m=part and {part=part,base=part.CFrame,spin=spin~=nil,axis=t:GetAttribute('SpinAxis') or t:GetAttribute('LeverAxis') or 'X',
			deg=t:GetAttribute('SpinDeg') or t:GetAttribute('LeverDeg') or (spin and 360 or 70),shown=0,
			parts=part and part.Parent and part.Parent:IsA('Model') and part.Parent~=floor and part.Parent or nil} or false
		self._machines[t]=m
	end
	return m or nil
end
function Controller:_MachineStep(dt)
	for _,t in CS:GetTagged('EHInteractable') do
		if t:GetAttribute('SpinRef') or t:GetAttribute('LeverRef') then
			local m=self:_Machine(t)
			if m and m.part.Parent then
				local work=t:GetAttribute('EHWork') or 1
				local p=(t:GetAttribute('EHWorkProgress') or 0)
				local want=m.spin and p*work*m.deg or p*m.deg
				m.shown+=(want-m.shown)*(1-math.exp(-dt*8))
				local a=math.rad(m.shown)
				local r=m.axis=='Y' and CFrame.Angles(0,a,0) or m.axis=='Z' and CFrame.Angles(0,0,a) or CFrame.Angles(a,0,0)
				if m.parts then m.parts:PivotTo(m.base*r) else m.part.CFrame=m.base*r end
			end
		end
	end
end

function Controller:Start()
	pcall(Cinematic.Start)
	self._scope:Add(self._player:GetAttributeChangedSignal('EHPushBackAt'):Connect(function()self:_PushBack()end))
	self._scope:Add(RunService.RenderStepped:Connect(function(dt)
		dt=math.min(dt,1/30)
		local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
		if env then for _,f in env:GetChildren() do if f:GetAttribute('EncounterId') then self:_Watch(f) end end end
		pcall(self._WaterStep,self,dt)
		pcall(self._MachineStep,self,dt)
	end))
end
function Controller:Destroy()if self._scope then self._scope:Destroy() end end
return table.freeze(Controller)
