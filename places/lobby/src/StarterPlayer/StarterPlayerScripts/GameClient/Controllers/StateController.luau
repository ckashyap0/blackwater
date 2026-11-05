--!nonstrict
local Shared=game:GetService("ReplicatedStorage").Game.Shared
local Contract=require(Shared.Contracts.NetworkContract)
local CleanupScope=require(Shared.Utilities.CleanupScope)
local Util=require(Shared.Utilities.TableUtil)
local Constants=require(Shared.Constants)
local Controller={}
Controller.__index=Controller
function Controller.new(network,player,diagnostics)
	return setmetatable({Name="StateController",Dependencies={},_network=network,_player=player,
		_diagnostics=diagnostics,_snapshot=nil,_sequence=0,_active=false},Controller)
end
function Controller:Init(_dependencies)
	self._scope=CleanupScope.new()
	self._changed=self._scope:Add(Instance.new("BindableEvent"))
end
function Controller:ApplySnapshot(packet)
	if not Contract.ValidateSnapshot(packet,self._player.UserId) then return false,"InvalidSnapshot" end
	if self._snapshot and packet.revision<=self._snapshot.revision then return false,"StaleSnapshot" end
	self._snapshot=Util.DeepFreeze(Util.DeepClone(packet))
	if self._diagnostics then
		self._diagnostics:SetAttribute("SnapshotRevision",packet.revision)
		self._diagnostics:SetAttribute("ServerPhase",packet.phase)
		self._diagnostics:SetAttribute("ActiveRunPhase",packet.run and packet.run.phase or nil)
		self._diagnostics:SetAttribute("ActiveFloorNumber",packet.run and packet.run.floorNumber or nil)
	end
	self._changed:Fire(self._snapshot)
	return true,"OK"
end
function Controller:Start()
	self._active=true
	self._scope:Add(self._network.StateSnapshot.OnClientEvent:Connect(function(packet)
		self:ApplySnapshot(packet)
	end))
end
function Controller:Subscribe(callback)
	return self._changed.Event:Connect(callback)
end
function Controller:GetSnapshot()
	return self._snapshot
end
function Controller:SendReady()
	assert(self._active,"State controller is not active")
	self._sequence+=1
	self._network.ClientReady:FireServer({schemaVersion=Constants.SchemaVersion,requestId=self._sequence})
end
function Controller:SendAction(action,payload)
	if not self._active or not self._snapshot then return false end
	local packet={schemaVersion=Constants.SchemaVersion,requestId=self._sequence+1,action=action,payload=payload}
	if not Contract.ValidateAction(packet) then return false end
	self._sequence+=1;self._network.ClientAction:FireServer(packet);return true
end
function Controller:RequestSnapshot()
	assert(self._active,"State controller is not active")
	self._sequence+=1
	self._network.ClientAction:FireServer({schemaVersion=Constants.SchemaVersion,
		requestId=self._sequence,action="RequestSnapshot",payload={}})
end
function Controller:Destroy()
	self._active=false
	self._snapshot=nil
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
