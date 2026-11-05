--!strict
local Refs=require(script.Parent.Parent.Utilities.FloorRefs)
local FloorContract = {}
FloorContract.RequiredAnchors = table.freeze({"ElevatorDock","PlayerRecovery","ObjectiveRecovery","FloorBounds"})
function FloorContract.ValidateTemplate(template: Instance)
	assert(template:IsA("Model"), "Floor template must be a Model")
	for _,name in FloorContract.RequiredAnchors do
		local anchor=Refs.Find(template,name)
		assert(anchor and anchor:IsA("BasePart"), "Missing BasePart anchor: "..name)
		assert((anchor :: BasePart).Anchored, name.." must be anchored")
	end
end
return table.freeze(FloorContract)
