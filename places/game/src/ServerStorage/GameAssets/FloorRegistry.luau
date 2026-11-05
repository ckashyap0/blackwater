--!nonstrict
-- Every floor is an authored model (Workspace.BlackwaterAuthoring.Level<n>, parked here as a
-- template by EnvironmentService). Floors are cloned, never generated.
local Registry={}
function Registry.Build(number)
	local folder=assert(script.Parent:FindFirstChild("FloorTemplates"),"Missing authored floor templates")
	local template=folder:FindFirstChild("Level"..tostring(number))
	return assert(template,"Missing authored Level"..tostring(number).." template"):Clone()
end
return table.freeze(Registry)

