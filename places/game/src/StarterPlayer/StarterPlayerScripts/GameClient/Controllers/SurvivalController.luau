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
	-- SurvivalPresentation (the whole physical screen: no top-bar inset, no notch / home-indicator
	-- safe area, so the eyelids reach every edge on phones in either orientation)
	--   > Lids > UpperLid, LowerLid      (black, overscanned past the left and right edges)
	--   > Status (safe-area padded)  > SurvivalStatus
	local gui=AuthoredGui.Get(self._gui,"SurvivalPresentation")
	local lids=gui:WaitForChild("Lids")
	self._lids={lids:WaitForChild("UpperLid"),lids:WaitForChild("LowerLid")}
	self._label=gui:WaitForChild("Status"):WaitForChild("SurvivalStatus");self._label.Text=""
end
function Controller:_EyesOpen()
	for _,t in self._tweens do t:Cancel() end;self._tweens={}
	for _,lid in self._lids do
		lid.Size=UDim2.fromScale(1.2,.56)
		local tween=TweenService:Create(lid,TweenInfo.new(1.7,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,0,false,.3),{Size=UDim2.fromScale(1.2,0)})
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
-- how many people are in this run (you included)
function Controller:_CrewSize()
	local run=self._player:GetAttribute("EHRunId");if run==nil then return #Players:GetPlayers() end
	local n=0;for _,o in Players:GetPlayers() do if o:GetAttribute("EHRunId")==run then n+=1 end end
	return n
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
		-- playing solo there is nobody to wait for: no "waiting for a teammate" line at all
		text=target and ("Watching "..target.DisplayName) or (self:_CrewSize()>1 and "Waiting for a teammate…" or "")
		if #self._ids>1 then text..="\n"..self._input:GetPrompt("SpectatePrevious").."  ·  "..self._input:GetPrompt("SpectateNext") end
	elseif downed then
		text="You're down! "..math.max(0,math.ceil((p:GetAttribute("EHDownedDeadline") or now)-now)).."s for a teammate to revive you"
	elseif (p:GetAttribute("EHProtectionUntil") or 0)>now and context~="Results" then
		text="Getting back up..."
	end
	if p:GetAttribute("EHAwaitingReconnect") and self:_CrewSize()>1 then text="Waiting for a teammate to reconnect…" end
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
