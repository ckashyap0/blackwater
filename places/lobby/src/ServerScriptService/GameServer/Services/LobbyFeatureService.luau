--!nonstrict
-- Lobby-only extras:
--  * SECRET door: hold E. With access (gamepass, allow-list or group rank) the server tells only that
--    player's client to swing the doors open (Network.SecretDoor) -- everyone else still sees, and
--    collides with, closed doors. Without access: Roblox's gamepass purchase prompt; buying opens it.
--    Anyone found inside without access is put back outside.
--  * First visit: tells a player's client to show Roblox's group join prompt exactly once, ever
--    (DataStore flag), and only if they aren't already in the group.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Marketplace=game:GetService("MarketplaceService")
local DataStoreService=game:GetService("DataStoreService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.LobbyFeaturesConfig)
local Service={};Service.__index=Service
local ACCESS_TTL=60
function Service.new()
	return setmetatable({Name="LobbyFeatureService",Dependencies={"EnvironmentService"},_access={},_moving={},_busy={}},Service)
end
function Service:Init(deps)
	self._env=deps.EnvironmentService
	self._scope=Scope.new()
end
-- ===== access =====
-- Returns (hasAccess, sure). sure=false means a Roblox web check failed, so we can't tell yet.
function Service:_Compute(p)
	local cfg=Config.SecretRoom
	if table.find(cfg.AllowUserIds,p.UserId) then return true,true end
	if game.CreatorType==Enum.CreatorType.User and p.UserId==game.CreatorId then return true,true end
	local sure=true
	local ok,rank=pcall(function()return p:GetRankInGroupAsync(Config.GroupId)end)
	if ok and rank>=cfg.MinGroupRank then return true,true end
	if cfg.GamePassId>0 then
		for attempt=1,3 do
			local fine,has=pcall(function()return Marketplace:UserOwnsGamePassAsync(p.UserId,cfg.GamePassId)end)
			if fine then
				if has then return true,true end
				sure=true;break
			end
			sure=false
			if attempt<3 then task.wait(.5*attempt) end
		end
	end
	return false,sure
end
-- Access, once confirmed, sticks for the whole visit (a pass can't be un-owned mid-session), so an
-- owner is never re-checked and never sees the purchase prompt again.
function Service:HasAccess(p,fresh)
	local c=self._access[p]
	if c and c.ok then return true,true end
	if not fresh and c and os.clock()-c.at<ACCESS_TTL then return false,true end
	local ok,sure=self:_Compute(p)
	if p.Parent==Players and sure then self._access[p]={ok=ok,at=os.clock()} end
	-- lets that player's client show secret-room-only things (the lobby camera feed on the TV)
	if ok and p.Parent==Players then p:SetAttribute("EHSecretAccess",true) end
	return ok,sure
end
function Service:_Move(p,target)
	local char=p.Character;local root=char and char:FindFirstChild("HumanoidRootPart")
	if not root or self._moving[p] then return end
	self._moving[p]=true
	root.AssemblyLinearVelocity=Vector3.zero
	char:PivotTo(target.CFrame)
	task.delay(.6,function()self._moving[p]=nil end)
end
function Service:_Notify(p,text)
	p:SetAttribute("EHPartyMessage",text)
	task.delay(3,function()if p.Parent==Players and p:GetAttribute("EHPartyMessage")==text then p:SetAttribute("EHPartyMessage","")end end)
end
function Service:_SetupSecretRoom()
	local L=self._env.Model
	local door=L:FindFirstChild("Fixtures") and L.Fixtures:FindFirstChild("SecretDoor")
	local remote=game.ReplicatedStorage.Game.Network:FindFirstChild("SecretDoor")
	local function tell(p,cmd) if remote and p.Parent==Players then remote:FireClient(p,cmd) end end
	local room=L:FindFirstChild("SecretRoom")
	if not door or not room then return end
	local function prompt(anchor,action)
		local pp=Instance.new("ProximityPrompt")
		pp.ActionText=action;pp.ObjectText="Secret";pp.HoldDuration=.4;pp.MaxActivationDistance=8
		pp.RequiresLineOfSight=false;pp.KeyboardKeyCode=Enum.KeyCode.E;pp.Parent=anchor
		self._scope:Add(pp)
		return pp
	end
	-- Prompt text is per player: each client flips its own copy between "Open" and "Close".
	local enter=prompt(door.PromptAnchor,"Open")
	local exit=prompt(room.ExitAnchor,"Open")
	self._scope:Add(enter.Triggered:Connect(function(p)
		if self._busy[p] then return end
		self._busy[p]=true
		local ok,sure=self:HasAccess(p,true)
		self._busy[p]=nil
		if ok then tell(p,"Toggle")
		elseif not sure then self:_Notify(p,"Couldn't check your pass. Try again in a moment.")
		elseif Config.SecretRoom.GamePassId>0 then Marketplace:PromptGamePassPurchase(p,Config.SecretRoom.GamePassId)
		else self:_Notify(p,"This door is locked.") end
	end))
	-- anyone who is inside already had access; the inside prompt just toggles their doors
	self._scope:Add(exit.Triggered:Connect(function(p)tell(p,"Toggle")end))
	self._scope:Add(Marketplace.PromptGamePassPurchaseFinished:Connect(function(p,id,bought)
		if bought and id==Config.SecretRoom.GamePassId and p.Parent==Players then
			self._access[p]={ok=true,at=os.clock()}
			p:SetAttribute("EHSecretAccess",true)
			tell(p,"Open")
		end
	end))
	-- anyone inside without access goes back out
	local bounds=room.Bounds
	local elapsed=0
	self._scope:Add(RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.5 then return end;elapsed=0
		for _,p in Players:GetPlayers() do
			local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local o=bounds.CFrame:PointToObjectSpace(root.Position);local h=bounds.Size/2
				if math.abs(o.X)<=h.X and math.abs(o.Y)<=h.Y and math.abs(o.Z)<=h.Z then
					local c=self._access[p]
					if c and not c.ok then self:_Move(p,room.OutsideLanding) end
					if not c then task.spawn(function()self:HasAccess(p)end) end
				end
			end
		end
	end))
end
-- ===== first visit group prompt =====
function Service:_FirstVisit(p)
	local inGroup=false
	pcall(function()inGroup=p:IsInGroupAsync(Config.GroupId)end)
	local first=false
	local ok=pcall(function()
		local store=DataStoreService:GetDataStore(Config.FirstVisitStore)
		store:UpdateAsync(tostring(p.UserId),function(old)
			if old~=nil then first=false;return nil end
			first=true;return {at=os.time()}
		end)
	end)
	-- In Studio (DataStores often off) prompt every session so it can be tested; live, only on a
	-- confirmed first visit -- if the store is unavailable we stay quiet rather than risk repeats.
	if not ok then first=RunService:IsStudio() end
	if first and not inGroup and p.Parent==Players then
		task.wait(Config.FirstVisitDelaySeconds)
		if p.Parent==Players then game.ReplicatedStorage.Game.Network.GroupPrompt:FireClient(p,"FirstVisit") end
	end
end
function Service:Start()
	if self._env.Role~="Lobby" then return end
	self:_SetupSecretRoom()
	local function joined(p)
		task.spawn(function()self:HasAccess(p)end)
		task.spawn(function()self:_FirstVisit(p)end)
	end
	self._scope:Add(Players.PlayerAdded:Connect(joined));for _,p in Players:GetPlayers()do joined(p)end
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)self._access[p]=nil;self._moving[p]=nil;self._busy[p]=nil end))
end
function Service:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Service)
