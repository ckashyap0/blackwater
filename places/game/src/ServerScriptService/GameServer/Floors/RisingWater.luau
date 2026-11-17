--!nonstrict
-- R43: a flood that rises in stages, for any floor. One zone = a Folder tagged BWRisingWater in the floor:
--   Surface*  parts: the water surface(s), moved up and down by every client (SetPieceController)
--   Volume    an invisible part: the area that floods (players inside it and under the surface wade in it)
--   attributes  Stages = "0;2;4.5;7"  heights above the surface's starting height, one per stage
--               FailRise = 6.5        when the water reaches this height the floor's onFail runs (push-back)
--               Drain = 12            stamina per second while wading       Slow = .7  walk speed while wading
-- The server owns the level and publishes it as a curve (FromRise, ToRise, StartAt, Duration) on the folder,
-- so every client moves the surface smoothly with no per-frame traffic. Lamps under the surface go out on
-- the clients. Nobody is hurt or caught: wading drains stamina and slows you, and reaching FailRise pushes
-- the crew back to a checkpoint (Floors.PushBack).
local CS=game:GetService('CollectionService')
local Water={};Water.__index=Water
Water.Tag='BWRisingWater'

local function heights(s)
	local t={}
	for v in string.gmatch(s or '','[^;]+') do table.insert(t,tonumber(v) or 0) end
	if #t==0 then t={0} end
	return t
end

-- options: now(), crew() -> players, drain(player, amount, kind), slow(player, multiplier or nil), onFail(water)
function Water.new(folder,options)
	options=options or {}
	local self=setmetatable({Folder=folder,_now=options.now or function()return workspace:GetServerTimeNow()end,
		_crew=options.crew or function()return {} end,_drain=options.drain,_slow=options.slow,_onFail=options.onFail,
		_stage=1,_failed=false,_wading={}},Water)
	self.Stages=heights(folder:GetAttribute('Stages'))
	self.FailRise=folder:GetAttribute('FailRise') or math.huge
	self.Volume=folder:FindFirstChild('Volume')
	local base
	for _,p in folder:GetChildren() do if p:IsA('BasePart') and p.Name:sub(1,7)=='Surface' then base=base and math.min(base,p.Position.Y) or p.Position.Y end end
	self.Base=base or (self.Volume and self.Volume.Position.Y-self.Volume.Size.Y/2) or 0
	folder:SetAttribute('Base',self.Base)
	self:_Curve(self.Stages[1],self.Stages[1],0)
	return self
end

function Water.All(model)
	local t={}
	for _,f in CS:GetTagged(Water.Tag) do if f:IsDescendantOf(model) then table.insert(t,f) end end
	return t
end

function Water:_Curve(from,to,seconds)
	local f=self.Folder
	f:SetAttribute('FromRise',from);f:SetAttribute('ToRise',to)
	f:SetAttribute('StartAt',self._now());f:SetAttribute('Duration',math.max(seconds,0))
end

-- height of the surface above its start, now
function Water:Rise()
	local f=self.Folder
	local from,to=f:GetAttribute('FromRise') or 0,f:GetAttribute('ToRise') or 0
	local d=f:GetAttribute('Duration') or 0
	if d<=0 then return to end
	local u=math.clamp((self._now()-(f:GetAttribute('StartAt') or 0))/d,0,1)
	return from+(to-from)*u
end
function Water:Level() return self.Base+self:Rise() end
function Water:Stage() return self._stage end

-- rise (or fall) to a stage over n seconds
function Water:ToStage(stage,seconds)
	stage=math.clamp(stage,1,#self.Stages)
	self._stage=stage
	self:_Curve(self:Rise(),self.Stages[stage],seconds or 8)
	if self.Stages[stage]<self.FailRise then self._failed=false end
end
-- straight to a height (not tied to a stage), e.g. a surge
function Water:ToHeight(rise,seconds)
	self:_Curve(self:Rise(),rise,seconds or 4)
	if rise<self.FailRise then self._failed=false end
end

local function under(volume,pos)
	if not volume then return false end
	local p=volume.CFrame:PointToObjectSpace(pos);local h=volume.Size/2
	return math.abs(p.X)<=h.X and math.abs(p.Z)<=h.Z
end

-- call from the floor's tick
function Water:Step(dt)
	local level=self:Level()
	local drain=self.Folder:GetAttribute('Drain') or 12
	local slow=self.Folder:GetAttribute('Slow') or .7
	local still={}
	for _,p in self._crew() do
		local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
		-- wading: inside the flooded area with the water above your shins
		if root and under(self.Volume,root.Position) and level>root.Position.Y-2.4 then
			still[p]=true
			if not self._wading[p] then self._wading[p]=true;if self._slow then self._slow(p,slow) end;p:SetAttribute('EHWading',true) end
			if self._drain then self._drain(p,drain*dt,'Flood') end
		end
	end
	for p in self._wading do
		if not still[p] then self._wading[p]=nil;if self._slow then self._slow(p,nil) end;if p.Parent then p:SetAttribute('EHWading',nil) end end
	end
	if not self._failed and self:Rise()>=self.FailRise then
		self._failed=true
		if self._onFail then task.spawn(self._onFail,self) end
	end
end

function Water:Stop()
	for p in self._wading do if self._slow then self._slow(p,nil) end;if p.Parent then p:SetAttribute('EHWading',nil) end end
	table.clear(self._wading)
end

return Water
