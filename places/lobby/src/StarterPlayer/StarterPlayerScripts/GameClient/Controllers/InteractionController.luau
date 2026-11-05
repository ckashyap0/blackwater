--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Players=game:GetService("Players")
local Tags=game:GetService("CollectionService")
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Responsive=require(game.ReplicatedStorage.Game.Shared.Utilities.ResponsiveScale)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="InteractionController",Dependencies={"StateController","InputController"},_player=player,_gui=gui,_targets={}},Controller)
end
function Controller:Init(deps)
	self._state=deps.StateController;self._input=deps.InputController;self._scope=Scope.new()
	-- authored in StarterGui.InteractionHint (Prompt, HoldProgress > Fill, AimDot)
	local gui=AuthoredGui.Get(self._gui,"InteractionHint");Responsive.Watch(gui)
	self._label=gui:WaitForChild("Prompt");self._label.Text=""
	self._bar=gui:WaitForChild("HoldProgress");self._fill=self._bar:WaitForChild("Fill")
	self._dot=gui:WaitForChild("AimDot")
end
function Controller:_Send(action,id,epoch)
	epoch=epoch or self._player:GetAttribute("EHCharacterEpoch")
	if type(epoch)~="number" or epoch<1 then return false end
	local payload={characterEpoch=epoch};if id then payload.interactionId=id end
	return self._state:SendAction(action,payload)
end
function Controller:_Cancel()
	if self._holding then self:_Send("EndInteraction",self._holding.id,self._holding.epoch);self._holding=nil end
end
function Controller:_Target()
	local context=self._input:GetContext()
	if context~="ActiveFloor" and context~="Transit" then return nil end
	if (self._player:GetAttribute("EHProtectionUntil") or 0)>workspace:GetServerTimeNow() then return nil end
	local character=self._player.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
	local camera=workspace.CurrentCamera;if not root or not camera then return nil end
	local best,bestScore=nil,math.huge
	for target in self._targets do
		if target:IsDescendantOf(workspace) and target:GetAttribute("EHInteractionEnabled") then
			local distance=(root.Position-target.Position).Magnitude
			if distance<=(target:GetAttribute("EHMaximumDistance") or 8) then
				local direction=target.Position-camera.CFrame.Position
				local dot=direction.Magnitude>.01 and camera.CFrame.LookVector:Dot(direction.Unit) or 1
				if dot>.94 then
					local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude;params.FilterDescendantsInstances={character}
					local head=character:FindFirstChild("Head") or root
					local hit=workspace:Raycast(head.Position,target.Position-head.Position,params)
					local score=(1-dot)*100+distance*.05
					if (not hit or hit.Instance==target or (target:GetAttribute("EHInteractionType")=="Revive" and hit.Instance:IsDescendantOf(target.Parent))) and score<bestScore then best=target;bestScore=score end
				end
			end
		end
	end
	return best
end
function Controller:_Render()
	local p=self._player;self._target=self:_Target()
	self._input:SetAvailable("Interact",self._target~=nil)
	local holding=p:GetAttribute("EHInteractionState")=="Holding"
	self._bar.Visible=holding
	if holding then
		local duration=p:GetAttribute("EHInteractionDuration") or 1
		local started=p:GetAttribute("EHInteractionStarted") or workspace:GetServerTimeNow()
		self._fill.Size=UDim2.fromScale(math.clamp((workspace:GetServerTimeNow()-started)/math.max(.01,duration),0,1),1)
	end
	self._dot.Visible=self._input:GetContext()=="ActiveFloor"
	local lines={}
	if self._target then table.insert(lines,(self._input:GetPrompt("Interact") or "Interact").." · "..(self._target:GetAttribute("EHInteractionLabel") or "Use")) end
	local carried=p:GetAttribute("EHCarriedKind")
	self._input:SetAvailable("DropObjectiveItem",carried~=nil)
	if carried then table.insert(lines,carried.." · "..self._input:GetPrompt("DropObjectiveItem")) end
	if self._message and os.clock()<(self._messageUntil or 0) then table.insert(lines,self._message) end
	self._label.Text=table.concat(lines,"\n")
end
function Controller:Start()
	for _,t in Tags:GetTagged("EHInteractable") do if t:IsA("BasePart") then self._targets[t]=true end end
	self._scope:Add(Tags:GetInstanceAddedSignal("EHInteractable"):Connect(function(t) if t:IsA("BasePart") then self._targets[t]=true end end))
	self._scope:Add(Tags:GetInstanceRemovedSignal("EHInteractable"):Connect(function(t) self._targets[t]=nil end))
	self._scope:Add(self._input:Register("Interact",function(state)
		if state=="Begin" and self._target then
			local id=self._target:GetAttribute("EHInteractionId");local epoch=self._player:GetAttribute("EHCharacterEpoch")
			if self:_Send("BeginInteraction",id,epoch) then self._holding={id=id,epoch=epoch};self._elapsed=0 end
		elseif state=="End" or state=="Cancel" then self:_Cancel() end
	end))
	self._scope:Add(self._input:Register("DropObjectiveItem",function(state)
		if state=="Begin" then self:_Cancel();self:_Send("DropObjectiveItem") end
	end))
	self._scope:Add(self._player:GetAttributeChangedSignal("EHInteractionSerial"):Connect(function()
		local state=self._player:GetAttribute("EHInteractionState")
		if state=="Completed" or state=="Rejected" or state=="Canceled" then self._holding=nil end
		if state=="Rejected" then
			local reason=self._player:GetAttribute("EHInteractionReason")
			self._message=({AlreadyCarrying="Your hands are full.",WrongItemKind="That item does not fit.",Busy="A teammate is using this.",OutOfRange="Move closer.",Occluded="Something's in the way.",ObjectiveIncomplete="Finish the jobs on this level first.",CrewOutside="Everyone needs to be in the elevator.",RescueRequired="Revive your teammate before leaving.",AwaitingReconnect="Waiting for your crew to reconnect.",DoorUnavailable="Wait for the doors."})[reason] or "You can't use that yet."
			self._messageUntil=os.clock()+1.8
		end
	end))
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		self._elapsed=(self._elapsed or 0)+dt
		if self._holding and self._elapsed>=.5 then self._elapsed=0;self:_Send("ContinueInteraction",self._holding.id,self._holding.epoch) end
		self._renderElapsed=(self._renderElapsed or 0)+dt
		if self._renderElapsed>=.05 then self._renderElapsed=0;self:_Render() end
	end))
	self:_Render()
end
function Controller:Destroy()
	self:_Cancel();if self._scope then self._scope:Destroy() end;table.clear(self._targets)
end
return table.freeze(Controller)
