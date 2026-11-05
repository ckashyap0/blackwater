--!strict
-- Stable party order, independent of connection/arrival order.
local Slots={}
function Slots.Index(userId:number,roster:{number}?):number
	if roster then for i,id in roster do if id==userId then return math.clamp(i,1,4) end end end
	return 1
end
-- Side-by-side layouts across the cabin floor, keyed by crew size (offsets from GameSpawn, which
-- sits three studs behind cabin center). Every slot is >=5 studs from every other, inside the
-- cabin walls (|x|<7.6) and clear of the gate.
local LAYOUT={
	[1]={Vector2.new(0,-2)},
	[2]={Vector2.new(-3,-2),Vector2.new(3,-2)},
	[3]={Vector2.new(-5.2,-2),Vector2.new(0,-2),Vector2.new(5.2,-2)},
	[4]={Vector2.new(-3,-5),Vector2.new(3,-5),Vector2.new(-3,0.5),Vector2.new(3,0.5)},
}
function Slots.Frame(spawn:CFrame,userId:number,roster:{number}?):CFrame
	local i=Slots.Index(userId,roster)
	local n=math.clamp(roster and #roster or 1,1,4)
	if i>n then n=4 end
	local o=LAYOUT[n][i]
	return spawn*CFrame.new(o.X,3,o.Y)
end
return table.freeze(Slots)
