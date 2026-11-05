--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Constants=require(Shared.Constants)
local Freeze=require(Shared.Utilities.TableUtil).DeepFreeze
local Service={}
Service.__index=Service
function Service.new()
	return setmetatable({Name="FoundationStateService",Dependencies={"GameRunService"},_active=false},Service)
end
function Service:Init(dependencies)
	self._run=assert(dependencies.GameRunService,"Missing GameRunService")
end
function Service:Start() self._active=true end
function Service:Subscribe(callback) return self._run:Subscribe(callback) end
function Service:GetSnapshot(player)
	assert(self._active,"Foundation state is not ready")
	return Freeze({
		schemaVersion=Constants.SchemaVersion,revision=self._run:GetRevision(),
		phase=Constants.FoundationPhase,buildVersion=Constants.BuildVersion,
		implementedChunk=Constants.ImplementedChunk,recipientUserId=player.UserId,
		availableActions=require(Shared.Contracts.NetworkContract).Actions,run=self._run:GetViewFor(player.UserId),
	})
end
function Service:Destroy() self._active=false end
return table.freeze(Service)
