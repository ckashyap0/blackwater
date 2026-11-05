--!nonstrict
-- Opens the SECRET doors for THIS player only. The server fires Network.SecretDoor("Open") after
-- checking access; this swings both leaves 90 degrees into the room on hinges at their room-side
-- corners (they stay solid, so you collide with them open or shut). Every other player still sees
-- and collides with the closed doors. They close again once this player has been away from the doorway for a moment.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.LobbyFeaturesConfig)
local Controller={};Controller.__index=Controller
local SWING_SECONDS=1.5 -- leaves are sized so they never cross each other, the jambs or the threshold at any angle
local NEAR=7
-- one symmetric curve for both directions, so reversing mid-swing never jumps
local function smooth(t) return t*t*t*(t*(t*6-15)+10) end
function Controller.new(player)return setmetatable({Name="SecretDoorController",Dependencies={},_player=player,_t=0,_target=0,_prompts={}},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_Build(door)
	self._leaves={}
	for _,spec in {{"LeafL",-1},{"LeafR",1}} do
		local leaf=door:FindFirstChild(spec[1])
		if leaf then
			local closed=leaf.CFrame
			-- hinge on the room-side corner at the jamb
			local hinge=CFrame.new((closed*CFrame.new(spec[2]*leaf.Size.X/2,0,leaf.Size.Z/2)).Position)
			local entry={leaf=leaf,hinge=hinge,offset=hinge:ToObjectSpace(closed),sign=-spec[2],attached={}}
			for _,p in door:GetChildren() do
				if p:IsA("BasePart") and p.Name:sub(1,#spec[1]+1)==spec[1].."_" then
					table.insert(entry.attached,{part=p,offset=closed:ToObjectSpace(p.CFrame)})
				end
			end
			table.insert(self._leaves,entry)
		end
	end
	self._center=(door:GetAttribute("HingeL")+door:GetAttribute("HingeR"))/2
end
function Controller:_Pose(a)
	for _,e in self._leaves do
		local cf=e.hinge*CFrame.Angles(0,math.rad(90)*a*-e.sign,0)*e.offset
		e.leaf.CFrame=cf
		for _,at in e.attached do at.part.CFrame=cf*at.offset end
		-- leaves stay solid in every position: you bump into an open door, never walk through it
	end
end
-- "Open" only shows while shut, "Close" only while open (local to this player's prompts)
function Controller:_Label()
	local text=self._target==1 and "Close" or "Open"
	for _,pp in self._prompts do if pp.Parent and pp.ActionText~=text then pp.ActionText=text end end
end
function Controller:_Set(target)
	if not self._leaves then return end
	self._target=target;self._awaySince=nil
	self:_Label()
end
function Controller:Open()self:_Set(1)end
function Controller:Toggle()self:_Set(self._target==1 and 0 or 1)end
-- Only the prompt on the side you're standing on is shown (lobby side or room side), so there is never
-- a second Open/Close prompt peeking through the doorway. Local to this player.
function Controller:_Sides()
	local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not self._outward then return end
	local d=(root.Position-self._center):Dot(self._outward)
	-- small dead zone in the doorway so it doesn't flicker while you stand on the threshold
	if d>.3 then self._side="outside" elseif d<-.3 then self._side="inside" end
	for _,pp in self._prompts do
		local want=(pp:GetAttribute("Side")==(self._side or "outside"))
		if pp.Enabled~=want then pp.Enabled=want end
	end
end
function Controller:_Watch(anchor,side)
	if not anchor then return end
	local function hook(pp) if pp:IsA("ProximityPrompt") then pp:SetAttribute("Side",side);table.insert(self._prompts,pp) self:_Label();self:_Sides() end end
	for _,c in anchor:GetChildren() do hook(c) end
	self._scope:Add(anchor.ChildAdded:Connect(hook))
end
function Controller:_Step(dt)
	if not self._leaves then return end
	self:_Sides()
	-- close once we've been away from the doorway for a moment
	if self._target==1 then
		local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
		local d=root and (root.Position-self._center)*Vector3.new(1,0,1)
		if not d or d.Magnitude>NEAR then
			self._awaySince=self._awaySince or os.clock()
			if os.clock()-self._awaySince>=Config.SecretRoom.CloseDelaySeconds then self:_Set(0) end
		else self._awaySince=nil end
	end
	if self._t==self._target then return end
	if self._target>self._t then self._t=math.min(1,self._t+dt/SWING_SECONDS)
	else self._t=math.max(0,self._t-dt/SWING_SECONDS) end
	self:_Pose(smooth(self._t))
end
function Controller:Start()
	local remote=game.ReplicatedStorage.Game.Network:WaitForChild("SecretDoor",10)
	if remote then self._scope:Add(remote.OnClientEvent:Connect(function(cmd)
		if cmd=="Open" then self:Open() elseif cmd=="Toggle" then self:Toggle() end
	end)) end
	task.spawn(function()
		local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",30)
		local door=env and env:WaitForChild("Fixtures"):WaitForChild("SecretDoor",10)
		if not door then return end
		self:_Build(door)
		local outsideAnchor=door:FindFirstChild("PromptAnchor")
		if outsideAnchor then
			local o=(outsideAnchor.Position-self._center)*Vector3.new(1,0,1)
			self._outward=o.Magnitude>.01 and o.Unit or nil
		end
		self:_Watch(outsideAnchor,"outside")
		local room=env:WaitForChild("SecretRoom",10)
		self:_Watch(room and room:FindFirstChild("ExitAnchor"),"inside")
		self._scope:Add(RunService.RenderStepped:Connect(function(dt)self:_Step(dt)end))
	end)
end
function Controller:Destroy()
	if self._leaves then self:_Pose(0) end
	if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
