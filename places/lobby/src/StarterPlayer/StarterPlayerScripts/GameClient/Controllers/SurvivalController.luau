--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Spectator=require(Shared.Utilities.SpectatorPolicy)
local Controller={};Controller.__index=Controller
function Controller.new(player,gui)
	return setmetatable({Name="SurvivalController",Dependencies={"InputController","CameraController"},_player=player,_gui=gui,_ids={}},Controller)
end
function Controller:Init(deps)
	self._input=deps.InputController;self._scope=Scope.new();self._tweens={}
	-- authored in StarterGui.SurvivalPresentation (SurvivalStatus, UpperLid, LowerLid)
	local gui=AuthoredGui.Get(self._gui,"SurvivalPresentation")
	self._label=gui:WaitForChild("SurvivalStatus");self._label.Text=""
	self._lids={gui:WaitForChild("UpperLid"),gui:WaitForChild("LowerLid")}
end
function Controller:_EyesOpen()
	for _,t in self._tweens do t:Cancel() end;self._tweens={}
	for _,lid in self._lids do
		lid.Size=UDim2.fromScale(1,.51)
		local tween=TweenService:Create(lid,TweenInfo.new(.65,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Size=UDim2.fromScale(1,0)})
		table.insert(self._tweens,tween);tween:Play()
	end
end
function Controller:_Targets()
	local ids={};local p=self._player
	for _,other in Players:GetPlayers() do
		local c=other.Character;local h=c and c:FindFirstChildOfClass("Humanoid");local head=c and c:FindFirstChild("Head")
		if Spectator.Eligible(p.UserId,p:GetAttribute("EHRunId"),other.UserId,other:GetAttribute("EHRunId"),other:GetAttribute("EHLifeState"),other.Parent==Players,h and h.Health>0 and head~=nil) then table.insert(ids,other.UserId) end
	end
	table.sort(ids);self._ids=ids;self._target=Spectator.Select(ids,self._target,0)
end
function Controller:_Render()
	local p=self._player;local context=self._input:GetContext();local now=workspace:GetServerTimeNow()
	local dead=context=="Dead";local downed=context=="Downed"
	if dead then self:_Targets() else self._target=nil;self._ids={} end
	self._input:SetAvailable("SpectateNext",dead and #self._ids>1)
	self._input:SetAvailable("SpectatePrevious",dead and #self._ids>1)
	local text=""
	if dead then
		local target=self._target and Players:GetPlayerByUserId(self._target)
		local head=target and target.Character and target.Character:FindFirstChild("Head")
		local camera=workspace.CurrentCamera
		if camera then
			camera.CameraType=Enum.CameraType.Scriptable
			if head then
				camera.CFrame=head.CFrame*CFrame.new(0,.15,-.55)
			else
				local runtime=workspace:FindFirstChild("Runtime")
				local environment=runtime and runtime:FindFirstChild("DescentEnvironment")
				local spawn=environment and environment:FindFirstChild("GameSpawn")
				camera.CFrame=spawn and CFrame.lookAt(spawn.Position+Vector3.new(0,4,0),spawn.Position+Vector3.new(0,4,5)) or CFrame.new(0,25,0)
			end
		end
		text=target and ("Watching "..target.DisplayName) or "Waiting for a teammate…"
		if #self._ids>1 then text..="\n"..self._input:GetPrompt("SpectatePrevious").."  ·  "..self._input:GetPrompt("SpectateNext") end
	elseif downed then
		text="Downed · "..math.max(0,math.ceil((p:GetAttribute("EHDownedDeadline") or now)-now)).."s to rescue"
	elseif (p:GetAttribute("EHProtectionUntil") or 0)>now and context~="Results" then
		text="Recovering · interactions available shortly"
	end
	if p:GetAttribute("EHAwaitingReconnect") then text="Waiting for a teammate to reconnect…" end
	self._label.Text=text
end
function Controller:Start()
	for _,pair in {{"SpectateNext",1},{"SpectatePrevious",-1}} do
		self._scope:Add(self._input:Register(pair[1],function(state)
			if state=="Begin" and self._input:GetContext()=="Dead" then self:_Targets();self._target=Spectator.Select(self._ids,self._target,pair[2]) end
		end))
	end
	self._scope:Add(self._player:GetAttributeChangedSignal("EHReturnSerial"):Connect(function() self:_EyesOpen() end))
	RunService:BindToRenderStep("EHSurvivalCamera",Enum.RenderPriority.Camera.Value+2,function() self:_Render() end)
	self._scope:Add(function() RunService:UnbindFromRenderStep("EHSurvivalCamera") end)
end
function Controller:Destroy()
	for _,t in self._tweens do t:Cancel() end
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Controller)
