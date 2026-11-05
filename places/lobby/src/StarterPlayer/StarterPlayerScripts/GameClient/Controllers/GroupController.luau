--!nonstrict
-- Shows Roblox's built-in group join prompt (GroupService:PromptJoinAsync -- client only):
--  * once on a player's first-ever visit, when the server says so (Network.GroupPrompt)
--  * whenever they step onto the lobby's square pad (Fixtures.GroupCircle, with a cooldown)
-- Members are never prompted. The pad's outline breathes and its floating text bobs gently.
local Players=game:GetService("Players")
local GroupService=game:GetService("GroupService")
local RunService=game:GetService("RunService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.LobbyFeaturesConfig)
local Controller={};Controller.__index=Controller
function Controller.new(player)return setmetatable({Name="GroupController",Dependencies={},_player=player,_busy=false,_last=-math.huge},Controller)end
function Controller:Init()self._scope=Scope.new()end
function Controller:_IsMember()
	if self._member then return true end
	local ok,res=pcall(function()return self._player:IsInGroupAsync(Config.GroupId)end)
	self._member=ok and res or false
	return self._member
end
function Controller:Prompt()
	if self._busy then return end
	self._busy=true
	task.spawn(function()
		if not self:_IsMember() then
			local ok,status=pcall(function()return GroupService:PromptJoinAsync(Config.GroupId)end)
			if ok and (status==Enum.GroupMembershipStatus.Joined or status==Enum.GroupMembershipStatus.AlreadyMember) then self._member=true end
		else
			self._player:SetAttribute("EHPartyMessage","You're already in Blackwater Productions.")
			task.delay(3,function()if self._player:GetAttribute("EHPartyMessage")=="You're already in Blackwater Productions." then self._player:SetAttribute("EHPartyMessage","")end end)
		end
		self._last=os.clock()
		self._busy=false
	end)
end
function Controller:Start()
	local remote=game.ReplicatedStorage.Game.Network:WaitForChild("GroupPrompt",10)
	if remote then self._scope:Add(remote.OnClientEvent:Connect(function()self:Prompt()end)) end
	task.spawn(function()
		local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",30)
		local circle=env and env:WaitForChild("Fixtures"):WaitForChild("GroupCircle",10)
		if not circle then return end
		local center=circle:WaitForChild("Pad").Position
		local half=circle:GetAttribute("Half") or 4
		local outline={}
		for _,p in circle:GetChildren() do if p:GetAttribute("EHPulse") then table.insert(outline,p) end end
		local anchor=circle:FindFirstChild("TextAnchor")
		local base=anchor and anchor.CFrame
		local inside=false
		self._scope:Add(RunService.Heartbeat:Connect(function()
			local t=os.clock()
			local tr=.15+.25*(.5+.5*math.sin(t*2))
			for _,p in outline do p.Transparency=tr end
			if anchor then anchor.CFrame=base+Vector3.new(0,math.sin(t*1.3)*.18,0) end
			local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
			if not root then inside=false return end
			local d=root.Position-center
			local now=math.abs(d.X)<=half and math.abs(d.Z)<=half and d.Y>=-1 and d.Y<=6
			if now and not inside and os.clock()-self._last>=Config.CircleCooldownSeconds then self:Prompt() end
			inside=now
		end))
	end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
