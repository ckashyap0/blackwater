--!strict
local Shared=script.Parent.Parent
local Constants=require(Shared.Constants)
local Validation=require(Shared.Utilities.Validation)
local Config=require(Shared.Config.GameConfig)
local RunContract=require(script.Parent.RunContract)
local Contract={}
Contract.Actions=table.freeze({"RequestSnapshot","BeginSprint","EndSprint","BeginInteraction","ContinueInteraction","EndInteraction","ToggleFlashlight","DropObjectiveItem","PartyConfigure","PartyReady","PartyLeave","PartyLaunch","ReconnectRun","ReturnLobby"})
local enabled={} for _,action in Contract.Actions do enabled[action]=true end
local readyKeys={schemaVersion=true,requestId=true}
local actionKeys={schemaVersion=true,requestId=true,action=true,payload=true}
local snapshotKeys={schemaVersion=true,revision=true,phase=true,buildVersion=true,
	implementedChunk=true,recipientUserId=true,availableActions=true,run=true}
local function header(packet: any): boolean
	return packet.schemaVersion==Constants.SchemaVersion
		and Validation.IsInteger(packet.requestId,1,Config.Network.MaxRequestId)
end
function Contract.ValidateReady(packet: any): (boolean,string)
	if not Validation.HasExactKeys(packet,readyKeys,2) then return false,"MalformedReady" end
	if not header(packet) then return false,"InvalidHeader" end
	return true,"OK"
end
function Contract.ValidateAction(packet: any): (boolean,string)
	if not Validation.HasExactKeys(packet,actionKeys,4) then return false,"MalformedAction" end
	if not header(packet) then return false,"InvalidHeader" end
	if not enabled[packet.action] then return false,"UnsupportedAction" end
	if packet.action=="PartyConfigure" then
		return Validation.HasExactKeys(packet.payload,{capacity=true,accessMode=true},2)
			and Validation.IsInteger(packet.payload.capacity,1,4)
			and (packet.payload.accessMode=="Public" or packet.payload.accessMode=="FriendsOfHost"),"InvalidPartySettings"
	elseif packet.action=="PartyReady" then
		return Validation.HasExactKeys(packet.payload,{ready=true},1) and type(packet.payload.ready)=="boolean","InvalidReadiness"
	elseif packet.action=="RequestSnapshot" or packet.action=="PartyLeave" or packet.action=="PartyLaunch" or packet.action=="ReconnectRun" or packet.action=="ReturnLobby" then
		if not Validation.HasExactKeys(packet.payload,{},0) then return false,"InvalidPayload" end
	else
		local interaction=packet.action=="BeginInteraction" or packet.action=="ContinueInteraction" or packet.action=="EndInteraction"
		local keys=interaction and {characterEpoch=true,interactionId=true} or {characterEpoch=true}
		if not Validation.HasExactKeys(packet.payload,keys,interaction and 2 or 1)
			or not Validation.IsInteger(packet.payload.characterEpoch,1,2147483647) then return false,"InvalidPayload" end
		if interaction and not Validation.IsIdentifier(packet.payload.interactionId,64) then return false,"InvalidPayload" end
	end
	return true,"OK"
end
function Contract.ValidateSnapshot(packet: any, userId: number): boolean
	if not Validation.HasExactKeys(packet,snapshotKeys,8) then return false end
	if packet.schemaVersion~=Constants.SchemaVersion or packet.phase~=Constants.FoundationPhase then return false end
	if not Validation.IsInteger(packet.revision,1,2147483647) then return false end
	if packet.buildVersion~=Constants.BuildVersion or packet.implementedChunk~=Constants.ImplementedChunk then return false end
	if packet.recipientUserId~=userId then return false end
	if type(packet.availableActions)~="table" or getmetatable(packet.availableActions)~=nil then return false end
	local count=0
	local expected=Contract.Actions
	for key,value in packet.availableActions do
		count+=1
		if count>#expected or not Validation.IsInteger(key,1,#expected) or value~=expected[key] then return false end
	end
	return count==#expected and RunContract.ValidateView(packet.run)
end
return table.freeze(Contract)
