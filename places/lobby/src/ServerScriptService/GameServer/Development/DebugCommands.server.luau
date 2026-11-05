--!nonstrict
-- Studio-only entry point. These suites use isolated in-memory fixtures.
-- They no longer run on every playtest. To run them: set the attribute RunDevChecks = true on Workspace.
if not game:GetService("RunService"):IsStudio() then return end
if workspace:GetAttribute("RunDevChecks")~=true then return end
local root=script.Parent
if root:GetAttribute("DebugChecksState")~=nil then return end
root:SetAttribute("DebugChecksState","Running")
local all={}
local ok,err=xpcall(function()
	local suites={"TestScenarios","PersistenceChecks","RunChecks","CharacterChecks","InteractionChecks","SurvivalChecks","PartySessionChecks","LobbyChecks"}
	local config=require(game.ReplicatedStorage.Game.Shared.Config.PlaceConfig)
	if config.Resolve(game.PlaceId,true,workspace:GetAttribute("EHStudioPlaceRole"))=="Game"then
		table.insert(suites,"WorkshopChecks");table.insert(suites,"ElevatorChecks")
	end
	for _,name in suites do
		local report=require(root[name]).Run()
		for _,result in report.results do table.insert(all,result) end
	end
end,debug.traceback)
if not ok then
	root:SetAttribute("DebugChecksState","Errored")
	warn("[ElevatorHorror] Development checks crashed: "..tostring(err))
	return
end
local passed=0
for _,result in all do
	if result.passed then passed+=1 else warn("[ElevatorHorror] FAILED "..result.name..": "..tostring(result.error)) end
end
root:SetAttribute("DebugChecksState",passed==#all and "Passed" or "Failed")
root:SetAttribute("DebugChecksPassed",passed);root:SetAttribute("DebugChecksTotal",#all)
print(string.format("[ElevatorHorror] Foundation/data/run checks: %d/%d passed",passed,#all))

