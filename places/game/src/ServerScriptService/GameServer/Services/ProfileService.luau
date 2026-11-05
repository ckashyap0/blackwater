--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Service={}
Service.__index=Service
function Service.new(repository,players,diagnostics)
	return setmetatable({Name="ProfileService",Dependencies={},_repository=repository,
		_players=players or game:GetService("Players"),_diagnostics=diagnostics,_profiles={},
		_status={},_generation={},_active=false},Service)
end
function Service:Init(_dependencies)
	self._scope=Scope.new()
end
function Service:_SetStatus(player,status,code)
	self._status[player]=status
	player:SetAttribute("ProfileStatus",status)
	player:SetAttribute("ProfileError",code)
	player:SetAttribute("ProfileStorageMode","DevelopmentMemory")
end
function Service:LoadPlayer(player)
	if not self._active or player.Parent~=self._players then return {ok=false,code="PlayerUnavailable"} end
	if self._status[player]=="Loading" then return {ok=false,code="LoadInProgress"} end
	local generation=(self._generation[player] or 0)+1
	self._generation[player]=generation
	self:_SetStatus(player,"Loading",nil)
	local callOk,response=pcall(function() return self._repository:Load(player.UserId) end)
	if not self._active or player.Parent~=self._players or self._generation[player]~=generation then
		return {ok=false,code="PlayerUnavailable"}
	end
	if not callOk then response={ok=false,code="StorageUnavailable"} end
	if response.ok then
		self._profiles[player]=response.profile
		self:_SetStatus(player,"Ready",nil)
	else
		self._profiles[player]=nil
		self:_SetStatus(player,"Failed",response.code)
	end
	return response
end
function Service:GetProfile(player)
	return self._profiles[player]
end
function Service:IsReady(player)
	return self._active and self._status[player]=="Ready" and self._profiles[player]~=nil
end
function Service:_Mutate(player,method,...)
	if not self:IsReady(player) or player.Parent~=self._players then return {ok=false,code="ProfileNotReady"} end
	local generation=self._generation[player]
	local args=table.pack(...)
	local ok,response=pcall(function()
		return self._repository[method](self._repository,player.UserId,table.unpack(args,1,args.n))
	end)
	if not ok then return {ok=false,code="StorageUnavailable"} end
	if response.ok and self._active and self._generation[player]==generation and player.Parent==self._players then
		self._profiles[player]=response.profile
	end
	return response
end
function Service:SavePreferences(player,patch) return self:_Mutate(player,"SavePreferences",patch) end
function Service:GrantCosmetic(player,id) return self:_Mutate(player,"GrantCosmetic",id) end
function Service:EquipCosmetic(player,slot,id) return self:_Mutate(player,"EquipCosmetic",slot,id) end
function Service:RecordDiscovery(player,id) return self:_Mutate(player,"RecordDiscovery",id) end
function Service:ApplyAward(player,receipt) return self:_Mutate(player,"ApplyAward",receipt) end
function Service:RecordCompletion(player,runId,occurredAt) return self:_Mutate(player,"RecordCompletion",runId,occurredAt) end
function Service:Start()
	self._active=true
	if self._diagnostics then self._diagnostics:SetAttribute("ProfileStorageMode","DevelopmentMemory") end
	self._scope:Add(self._players.PlayerAdded:Connect(function(player) self:LoadPlayer(player) end))
	self._scope:Add(self._players.PlayerRemoving:Connect(function(player)
		self._generation[player]=nil;self._profiles[player]=nil;self._status[player]=nil
	end))
	for _,player in self._players:GetPlayers() do self:LoadPlayer(player) end
end
function Service:Destroy()
	self._active=false
	if self._scope then self._scope:Destroy() end
	table.clear(self._profiles);table.clear(self._status);table.clear(self._generation)
end
return table.freeze(Service)
