--!nonstrict
local Players=game:GetService("Players")
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Contract=require(Shared.Contracts.NetworkContract)
local Config=require(Shared.Config.GameConfig)
local CleanupScope=require(Shared.Utilities.CleanupScope)
local RequestGuard=require(script.Parent.RequestGuard)
local Service={}
Service.__index=Service
function Service.new(network,diagnostics)
	return setmetatable({Name="NetworkService",Dependencies={"FoundationStateService","CharacterService","InteractionService","InventoryService","EquipmentService","PartyService","SessionService","ElevatorService"},
		_network=network,_diagnostics=diagnostics,_active=false,_rejected=0,_accepted=0,_sent=0},Service)
end
function Service:Init(dependencies)
	self._state=dependencies.FoundationStateService;self._elevator=dependencies.ElevatorService
	self._characters=dependencies.CharacterService
	self._parties=dependencies.PartyService;self._sessions=dependencies.SessionService
	self._interactions=dependencies.InteractionService;self._inventory=dependencies.InventoryService;self._equipment=dependencies.EquipmentService
	self._scope=CleanupScope.new()
	self._guard=RequestGuard.new(Config.Network.Burst,Config.Network.RefillPerSecond)
	self._scope:Add(self._guard)
	for _,name in {"ClientAction","ClientReady","StateSnapshot","PresentationEvent"} do
		assert(self._network:FindFirstChild(name) and self._network[name]:IsA("RemoteEvent"),"Missing RemoteEvent "..name)
	end
end
function Service:_Reject(reason)
	self._rejected+=1
	-- Read locally in Studio; no broadcast amplification and no per-packet warning spam.
	if self._diagnostics then
		self._diagnostics:SetAttribute("RejectedRequests",self._rejected)
		self._diagnostics:SetAttribute("LastRejection",reason)
	end
	return false,reason
end
function Service:Receive(player,channel,packet)
	if not self._active or typeof(player)~="Instance" or not player:IsA("Player") or player.Parent~=Players then
		return self:_Reject("NotAdmitted")
	end
	if not self._guard:Consume(player) then return self:_Reject("RateLimited") end
	local valid,reason
	if channel=="ClientReady" then valid,reason=Contract.ValidateReady(packet)
	elseif channel=="ClientAction" then valid,reason=Contract.ValidateAction(packet)
	else return self:_Reject("WrongDirection") end
	if not valid then return self:_Reject(reason) end
	if channel=="ClientAction" and not self._guard:IsReady(player) then return self:_Reject("NotReady") end
	if not self._guard:AcceptId(player,packet.requestId) then return self:_Reject("StaleRequest") end
	if channel=="ClientReady" then self._guard:SetReady(player);self._sessions:ClientReady(player) end
	if channel=="ClientAction" and packet.action~="RequestSnapshot" then
		local action,payload=packet.action,packet.payload
		local accepted,code=false,"UnsupportedAction"
		if action=="PartyConfigure" or action=="PartyReady" or action=="PartyLeave" or action=="PartyLaunch" or action=="ReconnectRun" then
			accepted,code=self._parties:Handle(player,action,payload)
		elseif action=="ReturnLobby" then accepted,code=self._sessions:ReturnLobby(player)
		elseif not self._sessions:IsReady(player) then code="NotAdmitted"
		elseif action=="SkipIntro" then accepted,code=self._elevator:SkipIntro(player,payload.runId,payload.characterEpoch)
		elseif action=="BeginSprint" or action=="EndSprint" then
			accepted,code=self._characters:SetSprint(player,payload.characterEpoch,action=="BeginSprint")
		elseif action=="BeginCrouch" or action=="EndCrouch" then
			accepted,code=self._characters:SetCrouch(player,payload.characterEpoch,action=="BeginCrouch")
		elseif action=="BeginInteraction" then accepted,code=self._interactions:Begin(player,payload.interactionId,payload.characterEpoch)
		elseif action=="ContinueInteraction" then accepted,code=self._interactions:Continue(player,payload.interactionId,payload.characterEpoch)
		elseif action=="EndInteraction" then accepted,code=self._interactions:Cancel(player,"Released",payload.interactionId,payload.characterEpoch)
		elseif action=="FlashlightAim" then accepted,code=self._equipment:SetAim(player,payload.characterEpoch,payload.yaw,payload.pitch)
		elseif action=="ToggleFlashlight" then accepted,code=self._equipment:Toggle(player,payload.characterEpoch,payload.on)
		elseif action=="DropObjectiveItem" then
			if player:GetAttribute("EHCharacterEpoch")~=payload.characterEpoch then code="StaleCharacter"
			elseif player:GetAttribute("EHLifeState")~="Alive" then code="InvalidLifeState"
			else self._interactions:Cancel(player,"DroppedItem");accepted,code=self._inventory:Drop(player,payload.frame) end
		end
		if not accepted then return self:_Reject(code) end
		self._accepted+=1
		if self._diagnostics then self._diagnostics:SetAttribute("AcceptedRequests",self._accepted) end
		return true,"OK"
	end
	self._accepted+=1
	self._network.StateSnapshot:FireClient(player,self._state:GetSnapshot(player))
	self._sent+=1
	if self._diagnostics then
		self._diagnostics:SetAttribute("AcceptedRequests",self._accepted)
		self._diagnostics:SetAttribute("SentSnapshots",self._sent)
	end
	return true,"OK"
end
function Service:Start()
	self._active=true
	self._scope:Add(self._state:Subscribe(function()
		if not self._active then return end
		for _,player in Players:GetPlayers() do
			if self._guard:IsReady(player) then
				self._network.StateSnapshot:FireClient(player,self._state:GetSnapshot(player))
				self._sent+=1
			end
		end
		if self._diagnostics then self._diagnostics:SetAttribute("SentSnapshots",self._sent) end
	end))
	for _,channel in {"ClientReady","ClientAction","StateSnapshot","PresentationEvent"} do
		self._scope:Add(self._network[channel].OnServerEvent:Connect(function(player,packet)
			self:Receive(player,channel,packet)
		end))
	end
	self._scope:Add(Players.PlayerRemoving:Connect(function(player) self._guard:Forget(player) end))
end
function Service:Destroy()
	self._active=false
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Service)
