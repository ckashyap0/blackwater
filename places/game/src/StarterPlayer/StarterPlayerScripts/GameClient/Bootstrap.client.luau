--!nonstrict
local root=script.Parent
if root:GetAttribute("BootstrapState")~=nil then
	warn("[ElevatorHorror] Duplicate client startup prevented")
	return
end
root:SetAttribute("BootstrapState","Starting")
local runner
local alive=true
local ok,err=xpcall(function()
	local ReplicatedStorage=game:GetService("ReplicatedStorage")
	local Players=game:GetService("Players")
	local gameRoot=ReplicatedStorage:WaitForChild("Game")
	assert(gameRoot,"Missing Game root")
	local Shared=gameRoot:WaitForChild("Shared")
	assert(Shared,"Missing Shared root")
	-- Wait for required descendants as well as roots before any eager module require.
	local function need(parent,name)
		local child=parent:WaitForChild(name)
		assert(child,"Missing replicated dependency: "..parent.Name.."."..name)
		return child
	end
	local configFolder=need(Shared,"Config")
	local utilities=need(Shared,"Utilities")
	local contracts=need(Shared,"Contracts")
	need(Shared,"Constants")
	for _,name in {"GameConfig","MovementConfig","InputConfig"} do need(configFolder,name) end
	for _,name in {"Lifecycle","CleanupScope","TableUtil","Validation"} do need(utilities,name) end
	for _,name in {"ServiceContract","RunContract","NetworkContract","CharacterContract"} do need(contracts,name) end
	-- Parents may replicate before their ModuleScript children on live clients.
 for _,name in {"GameConfig","MovementConfig","InputConfig","PlaceConfig","ImmersionConfig","Level5","Level4","CosmeticsConfig"}do need(configFolder,name)end
 for _,name in {"CleanupScope","TableUtil","Validation","Lifecycle","SprintModel","SpectatorPolicy","IntroTimeline","RouteGuide","HeldItemMotion","ObjectiveVisibility","MobileLayout","FloorRefs","SoundFade","AuthoredGui","ControlLock","ScreenFade","HudReveal","CrawlState","SinkCurve"}do need(utilities,name)end
 for _,name in {"ServiceContract","RunContract","NetworkContract","CharacterContract"}do need(contracts,name)end
 local controllers=need(root,"Controllers")
 for _,name in {"StateController","InterfaceController","InputController","MovementController","CameraController","InteractionController","EquipmentController","SurvivalController","PartyController","ArrivalController","FixtureController","ImmersionController","ObjectiveController","LoreController","CrouchPoseController","MechanismController","HazardController","AtmosphereController","VentScrewController","CosmeticsController","CrawlController","ControlRoomController","AssetWarmupController"}do need(controllers,name)end
 local Config=require(configFolder.GameConfig)
	local Constants=require(Shared.Constants)
	local Lifecycle=require(Shared.Utilities.Lifecycle)
	local player=Players.LocalPlayer
	local playerGui=player:WaitForChild("PlayerGui")
	assert(playerGui,"Missing PlayerGui")
	local network=gameRoot:WaitForChild("Network")
	assert(network,"Missing Network")
	for _,name in Constants.RemoteNames do
		local remote=network:WaitForChild(name)
		assert(remote and remote:IsA("RemoteEvent"),"Missing RemoteEvent "..name)
	end
	local StateController=require(root.Controllers.StateController)
	local InterfaceController=require(root.Controllers.InterfaceController)
	local InputController=require(root.Controllers.InputController)
	local MovementController=require(root.Controllers.MovementController)
	local CameraController=require(root.Controllers.CameraController)
	local InteractionController=require(root.Controllers.InteractionController)
	local EquipmentController=require(root.Controllers.EquipmentController)
	local SurvivalController=require(root.Controllers.SurvivalController)
	local PartyController=require(root.Controllers.PartyController)
	local ArrivalController=require(root.Controllers.ArrivalController)
	local FixtureController=require(root.Controllers.FixtureController)
	local ImmersionController=require(root.Controllers.ImmersionController)
 local ObjectiveController=require(root.Controllers.ObjectiveController)
 local LoreController=require(root.Controllers.LoreController)
 local CrouchPoseController=require(root.Controllers.CrouchPoseController)
 local MechanismController=require(root.Controllers.MechanismController)
 local HazardController=require(root.Controllers.HazardController)
 local AtmosphereController=require(root.Controllers.AtmosphereController)
 local VentScrewController=require(root.Controllers.VentScrewController)
 local CosmeticsController=require(root.Controllers.CosmeticsController)
 local CrawlController=require(root.Controllers.CrawlController)
 local ControlRoomController=require(root.Controllers.ControlRoomController)
 local AssetWarmupController=require(root.Controllers.AssetWarmupController)
	local diagnostics=game:GetService("RunService"):IsStudio() and root or nil
	local state=StateController.new(network,player,diagnostics)
	runner=Lifecycle.new({state,InputController.new(player,playerGui),
		MovementController.new(player,playerGui),CameraController.new(player),InteractionController.new(player,playerGui),
		EquipmentController.new(player),SurvivalController.new(player,playerGui),PartyController.new(player,playerGui),ArrivalController.new(player,playerGui),FixtureController.new(),ImmersionController.new(player),ObjectiveController.new(player,playerGui),LoreController.new(player,playerGui),CrouchPoseController.new(player),MechanismController.new(),HazardController.new(player),AtmosphereController.new(player),VentScrewController.new(player),CosmeticsController.new(player),CrawlController.new(player),ControlRoomController.new(player,playerGui),AssetWarmupController.new(player),InterfaceController.new(playerGui)})
	runner:Start()
	script.Destroying:Connect(function() alive=false;runner:Destroy() end)
	root:SetAttribute("ConnectionState","Connecting")
 task.spawn(function()
  local attempts=0
  while alive and root.Parent and not state:GetSnapshot()do
   attempts+=1;state:SendReady();task.wait(attempts<15 and 1 or 3)
  end
  if alive and root.Parent then root:SetAttribute("ConnectionState","Ready")end
 end)
	root:SetAttribute("BuildVersion",Constants.BuildVersion)
	root:SetAttribute("BootstrapState","Running")
	print("[ElevatorHorror] Client foundation ready ("..Constants.BuildVersion..")")
end,debug.traceback)
if not ok then
    alive=false
	if runner then runner:Destroy() end
	root:SetAttribute("BootstrapState","Failed")
	warn("[ElevatorHorror] Client startup failed: "..tostring(err))
end