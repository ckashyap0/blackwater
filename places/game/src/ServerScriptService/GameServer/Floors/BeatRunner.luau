--!nonstrict
-- R43: scripted events ("beats") for any floor. A floor hands BeatRunner a list of beats and calls :Step()
-- from its own tick. A beat fires once, when its condition is met:
--   when = {stage='Inlets'}                 the floor's Stage attribute equals this
--   when = {after='OtherBeat', delay=2}     n seconds after another beat fired
--   when = {zone='RefName'}                 any crew member's root is inside that part
--   when = {attr='InletsClosed', atLeast=4} a floor attribute reaches a number
--   when = {manual=true}                    only when the floor calls runner:Fire(name)
-- Several conditions in one `when` must all hold. Firing a beat:
--   * stamps Beat_<name> = server time on the floor (clients draw the beat's effects from Config,
--     see SetPieceController and the floor config's Beats table),
--   * runs beat.run(runner, floorModel) on the server for gameplay (start a flood, play a cut, move Marty),
--   * beat.cinematic = 'Id' plays that camera cut (Utilities.Cinematic).
local Refs=require(game.ReplicatedStorage.Game.Shared.Utilities.FloorRefs)
local Cinematic=require(game.ReplicatedStorage.Game.Shared.Utilities.Cinematic)
local Runner={};Runner.__index=Runner

function Runner.new(model,beats,options)
	options=options or {}
	local self=setmetatable({Model=model,_beats={},_order={},_fired={},_now=options.now or function()return workspace:GetServerTimeNow()end,
		_crew=options.crew or function()return {} end},Runner)
	for name,b in beats do
		assert(type(name)=='string' and #name<=40 and not name:find('[^%w_]'),'Invalid beat name: '..tostring(name))
		assert(type(b.when)=='table','Beat '..name..' needs a when')
		self._beats[name]=b;table.insert(self._order,name)
	end
	table.sort(self._order)
	return self
end

function Runner:Fired(name) return self._fired[name] end

function Runner:Fire(name)
	local b=self._beats[name];if not b or self._fired[name] then return false end
	local now=self._now()
	self._fired[name]=now
	self.Model:SetAttribute('Beat_'..name,now)
	if b.cinematic then Cinematic.Play(self.Model,b.cinematic,b.lead) end
	if b.run then
		local ok,err=pcall(b.run,self,self.Model)
		if not ok then warn('[ElevatorHorror] beat '..name..' failed: '..tostring(err)) end
	end
	return true
end

local function inside(part,pos)
	local p=part.CFrame:PointToObjectSpace(pos);local h=part.Size/2
	return math.abs(p.X)<=h.X and math.abs(p.Y)<=h.Y and math.abs(p.Z)<=h.Z
end

function Runner:_Ready(b)
	local w=b.when
	if w.manual then return false end
	if w.stage and self.Model:GetAttribute('Stage')~=w.stage then return false end
	if w.after then
		local t=self._fired[w.after];if not t or self._now()<t+(w.delay or 0) then return false end
	end
	if w.attr then
		local v=self.Model:GetAttribute(w.attr)
		if type(v)~='number' or v<(w.atLeast or 1) then return false end
	end
	if w.zone then
		local part=Refs.Find(self.Model,w.zone);if not part then return false end
		local any=false
		for _,p in self._crew() do
			local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
			if root and inside(part,root.Position) then any=true;break end
		end
		if not any then return false end
	end
	return true
end

function Runner:Step()
	for _,name in self._order do
		if not self._fired[name] and self:_Ready(self._beats[name]) then self:Fire(name) end
	end
end

-- after a push-back: forget beats so they can play again (names listed), or all of them
function Runner:Reset(names)
	for _,name in names or self._order do
		if self._fired[name] then self._fired[name]=nil;self.Model:SetAttribute('Beat_'..name,nil) end
	end
end

return Runner
