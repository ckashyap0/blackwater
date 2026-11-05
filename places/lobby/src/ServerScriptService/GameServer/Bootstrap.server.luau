--!nonstrict
local root=script.Parent
if root:GetAttribute("BootstrapState")~=nil then
	warn("[ElevatorHorror] Duplicate server startup prevented")
	return
end
root:SetAttribute("BootstrapState","Starting")
local runner
local ok,err=xpcall(function()
	local ReplicatedStorage=game:GetService("ReplicatedStorage")
	local gameRoot=ReplicatedStorage:WaitForChild("Game",15)
	assert(gameRoot,"Missing Game root")
	local Shared=gameRoot:WaitForChild("Shared",15)
	assert(Shared,"Missing Shared root")
	local Lifecycle=require(Shared.Utilities.Lifecycle)
	local Constants=require(Shared.Constants)
	local FoundationStateService=require(root.Services.FoundationStateService)
	local NetworkService=require(root.Services.NetworkService)
	local ProfileService=require(root.Services.ProfileService)
	local GameRunService=require(root.Services.GameRunService)
	local CharacterService=require(root.Services.CharacterService)
	local RunDriver=require(root.Development.RunDriver)
	local EnvironmentService=require(root.Services.EnvironmentService)
	local InteractionService=require(root.Services.InteractionService)
	local InventoryService=require(root.Services.InventoryService)
	local EquipmentService=require(root.Services.EquipmentService)
	local SurvivalService=require(root.Services.SurvivalService)
	local SessionService=require(root.Services.SessionService)
	local PartyService=require(root.Services.PartyService)
	local LobbyFeatureService=require(root.Services.LobbyFeatureService)
	local CosmeticService=require(root.Services.CosmeticService)
	local TokenService=require(root.Services.TokenService)
	local CoinService=require(root.Services.CoinService)
	local AdminService=require(root.Services.AdminService)
	local LeaderboardService=require(root.Services.LeaderboardService)
	local MemoryProfileStore=require(root.Data.MemoryProfileStore)
	local ProfileRepository=require(root.Data.ProfileRepository)
	local repository=ProfileRepository.new(MemoryProfileStore.new())
	local diagnostics=game:GetService("RunService"):IsStudio() and root or nil
	runner=Lifecycle.new({
		EnvironmentService.new(),
		ProfileService.new(repository,nil,diagnostics),
		GameRunService.new({diagnostics=diagnostics}),
		CharacterService.new(),
		InteractionService.new(),
		InventoryService.new(),
		SurvivalService.new(),
		SessionService.new(),
		PartyService.new(),
		LobbyFeatureService.new(),
		CoinService.new(), -- before CosmeticService, which spends coins for shop cosmetics
		TokenService.new(), -- Jumpscare / Extra Life tokens (after CoinService, which routes their purchases)
		CosmeticService.new(), -- (after TokenService: mystery boxes can give tokens)
		AdminService.new(), -- owner chat commands (/cmds): coins and tokens (after Coin/TokenService)
		LeaderboardService.new(), -- lobby donor / coin boards and tips (after CoinService, which routes the tip products)
		EquipmentService.new(),
		FoundationStateService.new(),
		NetworkService.new(gameRoot.Network,diagnostics),
		RunDriver.new(root.Development),
	})
	runner:Start()
	root:SetAttribute("BuildVersion",Constants.BuildVersion)
	root:SetAttribute("BootstrapState","Running")
	game:BindToClose(function()
		runner:Destroy()
		root:SetAttribute("BootstrapState","Stopped")
	end)
	script.Destroying:Connect(function() runner:Destroy() end)
	print("[ElevatorHorror] Server foundation ready ("..Constants.BuildVersion..")")
end,debug.traceback)
if not ok then
	if runner then runner:Destroy() end
	root:SetAttribute("BootstrapState","Failed")
	warn("[ElevatorHorror] Server startup failed: "..tostring(err))
	
end
