--!strict
local FloorContract = {}
FloorContract.RequiredAnchors = table.freeze({"ElevatorDock","PlayerRecovery","ObjectiveRecovery","FloorBounds"})
function FloorContract.ValidateController(controller: any)
	assert(type(controller) == "table", "Floor controller must be a table")
	for _,name in {"Prepare","Activate","GetObjectiveSnapshot","OnParticipantStateChanged","Stop","Destroy"} do
		assert(type(controller[name]) == "function", "Floor controller missing "..name)
	end
end
function FloorContract.ValidateTemplate(template: Instance)
	assert(template:IsA("Model"), "Floor template must be a Model")
	for _,name in FloorContract.RequiredAnchors do
		local anchor=template:FindFirstChild(name)
		assert(anchor and anchor:IsA("BasePart"), "Missing direct BasePart anchor: "..name)
		assert((anchor :: BasePart).Anchored, name.." must be anchored")
	end
end
return table.freeze(FloorContract)
