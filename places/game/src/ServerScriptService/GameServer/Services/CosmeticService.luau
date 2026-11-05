--!nonstrict
-- Unlockable cosmetics (chat titles, flashlight skins, beam colours). Same file in the Lobby and Game places.
-- Saved in their own DataStore (Config.CosmeticsConfig.Store) so a found item follows the player between
-- places and rejoins. Every write is an UpdateAsync merge, so a failed load can never wipe a save.
-- Replicated player attributes (everyone can read them):
--   EHOwnedCosmetics   "Beam:Phantom,Flashlight:Phantom,Title:Secret"
--   EHTitle            "Secret" or ""   (chat tag)
--   EHFlashlightSkin   "Phantom" or ""  (held flashlight model)
--   EHFlashlightColor  "Phantom" or ""  (beam colour)
--   EHCosmeticsReady   true once loaded
-- Network.Cosmetics: client -> ("Equip",slot,id) / ("Buy",slot,id) / ("OpenBox",boxId)
--                   server -> ("BoxResult",boxId,slot,id,refundCoins,rarity) / ("BoxFailed",boxId,reason)
--                             slot "Token" = a token (TokenService), id = its TokenConfig Id
--                   server -> ("Found",collectibleName) / ("Unlocked",passItemName)
--                             ("Bought",slot,id) / ("BuyFailed",slot,id,reason)  reason: "Funds" | "Owned" | "Unavailable"
-- Coin purchases (entries with a Price) need CoinService, which only the Lobby has: buying there unlocks
-- the item and equips it straight away; the Game place just reads what is equipped.
-- Lobby only: hold-E pickups in SecretRoom.Collectibles, placed at a random SecretRoom.HidingSpots part
-- each server, claimable once per player from inside the secret room.
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local MarketplaceService=game:GetService("MarketplaceService")
-- Gamepasses (Config.GamePasses) unlock their items on every join and right after an in-game purchase.
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.CosmeticsConfig)
-- mystery boxes (Lobby only: needs CoinService and Config.MysteryBoxConfig)
local BoxConfig=Shared.Config:FindFirstChild("MysteryBoxConfig") and require(Shared.Config.MysteryBoxConfig)
local Service={};Service.__index=Service
local ATTR={Title="EHTitle",Flashlight="EHFlashlightSkin",Beam="EHFlashlightColor"}

local function known(slot,id)
	if type(slot)~="string" or type(id)~="string" or not Config[slot] then return nil end
	for _,entry in Config[slot] do if entry.Id==id then return entry end end
	return nil
end
-- leaderboard titles show the live rank (EHDonorRank / EHCoinRank from RankTags)
local RANK_ATTR={Donor="EHDonorRank",Coin="EHCoinRank"}
local function rankLabel(p,e)
	local r=p:GetAttribute(RANK_ATTR[e.Leaderboard] or "")
	if type(r)~="number" then return nil end
	return (r<=10 and ("#"..r) or "TOP 100").." "..(e.Leaderboard=="Donor" and "DONOR" or "COINS")
end
local function rename(key)return Config.Renamed[key] or key end
local function clean(raw)
	local data={owned={},equipped={}}
	if type(raw)=="table" then
		if type(raw.owned)=="table" then
			for key,flag in raw.owned do
				key=rename(tostring(key))
				local slot,id=key:match("^(%w+):(%w+)$")
				if flag==true and known(slot,id) then data.owned[key]=true end
			end
			-- a collectible unlocks its items together: owning any part of one (e.g. a save from before the
			-- Phantom Flashlight also gave a beam colour) means owning all of it
			for _,spec in Config.Collectibles do
				local any=false
				for _,g in spec.Grants do if data.owned[g[1]..":"..g[2]] then any=true end end
				if any then for _,g in spec.Grants do data.owned[g[1]..":"..g[2]]=true end end
			end
		end
		if type(raw.equipped)=="table" then
			for _,slot in Config.Slots do
				local id=raw.equipped[slot]
				if type(id)=="string" then
					id=(rename(slot..":"..id)):match(":(%w+)$")
					local ke=known(slot,id)
					if id~="Default" and (data.owned[slot..":"..id] or (ke and ke.Leaderboard)) then data.equipped[slot]=id end -- (leaderboard titles: shown only while ranked)
				end
			end
		end
		-- saves from before beam colours were their own slot: the Phantom Flashlight brought its purple beam with it
		if (tonumber(raw.v) or 0)<3 and data.equipped.Flashlight=="Phantom" and not data.equipped.Beam and data.owned["Beam:Phantom"] then
			data.equipped.Beam="Phantom"
		end
	end
	return data
end

function Service.new()
	-- CoinService is only a dependency where it exists (the Lobby), so this file stays the same in both places
	local deps=script.Parent:FindFirstChild("CoinService") and {"EnvironmentService","CoinService"} or {"EnvironmentService"}
	-- tokens can come out of a mystery box (TokenService is registered before this service)
	if script.Parent:FindFirstChild("TokenService") then table.insert(deps,"TokenService") end
	return setmetatable({Name="CosmeticService",Dependencies=deps,_data={},_last={},_saving={}},Service)
end
function Service:Init(deps)
	self._env=deps.EnvironmentService
	self._coins=deps.CoinService
	self._tokens=deps.TokenService
	self._scope=Scope.new()
	local ok,store=pcall(function()return DataStoreService:GetDataStore(Config.Store)end)
	self._store=ok and store or nil
	local network=game.ReplicatedStorage.Game.Network
	local remote=network:FindFirstChild("Cosmetics")
	if not remote then remote=Instance.new("RemoteEvent");remote.Name="Cosmetics";remote.Parent=network end
	self._remote=remote
	-- the Robux mystery box is a Developer Product; CoinService owns ProcessReceipt and routes it here
	self._boxReceipts={}
	if BoxConfig and self._coins then
		for _,box in BoxConfig.Boxes do
			if (box.ProductId or 0)>0 then
				self._coins:RegisterProduct(box.ProductId,function(info)
					local p=Players:GetPlayerByUserId(info.PlayerId)
					if not p or not self._data[p] then return false end
					local key=tostring(info.PurchaseId)
					if self._boxReceipts[key] then return true end
					self._boxReceipts[key]=true
					local r=self:_OpenBox(p,box)
					if p.Parent==Players then self._remote:FireClient(p,"BoxResult",box.Id,r.slot,r.id,r.refund,r.tier) end
					return true
				end)
			end
		end
	end
end

-- ===== data =====
function Service:_Key(p)return "U_"..p.UserId end
function Service:_Apply(p)
	local d=self._data[p];if not d or p.Parent~=Players then return end
	local list={}
	for key in d.owned do table.insert(list,key) end
	table.sort(list)
	p:SetAttribute("EHOwnedCosmetics",table.concat(list,","))
	for slot,attr in ATTR do p:SetAttribute(attr,d.equipped[slot] or "") end
	p:SetAttribute("EHCosmeticsReady",true)
	self:_Tag(p)
end
-- the equipped title floats just above the player's Roblox name (BillboardGui "EHTitleTag" on the Head):
-- "VIP", "SECRET"... in its colour, no brackets (chat shows it as [VIP]). Roblox's own name display stays;
-- only its health bar is turned off. In the Game place the tag is hidden from its owner so it never floats
-- into their own first-person view.
local TAG_FONT=Font.new("rbxasset://fonts/families/RobotoMono.json",Enum.FontWeight.Medium) -- (no bold anywhere in the game)
-- It rides on the HumanoidRootPart, not the head: the head bobs and sways with every walk/idle animation,
-- which made the tag jitter; the root glides, so the tag floats smoothly. It is placed at the head's
-- height plus a gap, and drawn a fixed number of pixels higher (the label sits in the top of a taller
-- billboard), so it stays clearly above the Roblox name at any distance instead of sliding into it.
local TAG_GAP=2.25 -- studs above the head's centre
function Service:_Tag(p)
	-- (Oct 25) in the game the title only shows in chat ([VIP] Name); the floating name tag is lobby-only
	local hd=p.Character and p.Character:FindFirstChild("Head");local tg=hd and hd:FindFirstChild("EHTitleTag");if tg then tg:Destroy() end
	if true then return end
	local head=p.Character and p.Character:FindFirstChild("Head")
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local hum=p.Character:FindFirstChildOfClass("Humanoid")
	-- names and titles are a lobby thing only: down in the game nobody has a name or tag over their head
	local lobby=self._env.Role=="Lobby"
	if hum then
		hum.DisplayDistanceType=lobby and Enum.HumanoidDisplayDistanceType.Viewer or Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType=Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local old=head:FindFirstChild("EHTitleTag")
	if not lobby then if old then old:Destroy() end return end
	local d=self._data[p]
	local e=d and d.equipped.Title and known("Title",d.equipped.Title)
	if not e or not e.Color then if old then old:Destroy() end return end
	local g=old or Instance.new("BillboardGui")
	-- the head's height above the root, measured on this avatar (any size or body type)
	local rise=root and math.clamp(root.CFrame:PointToObjectSpace(head.Position).Y,.8,5) or 1.5
	g.Name="EHTitleTag";g.Size=UDim2.fromOffset(200,66);g.StudsOffset=Vector3.new(0,rise+TAG_GAP,0);g.MaxDistance=80;g.LightInfluence=0
	g.Adornee=root or head
	if self._env.Role~="Lobby" then g.PlayerToHideFrom=p end
	for _,c in g:GetChildren() do if c.Name~="Label" then c:Destroy() end end
	local l=g:FindFirstChild("Label") or Instance.new("TextLabel")
	l.Name="Label";l.BackgroundTransparency=1;l.Position=UDim2.new();l.Size=UDim2.new(1,0,0,22);l.FontFace=TAG_FONT;l.TextSize=18
	l.Text=e.Label;l.TextColor3=Color3.fromHex(e.Color);l.TextStrokeColor3=Color3.new(0,0,0);l.TextStrokeTransparency=.3
	l.Parent=g
	g.Parent=head
end
function Service:_Load(p)
	local raw,ok=nil,false
	if self._store then
		local fresh=Instance.new("DataStoreGetOptions");fresh.UseCache=false -- never trust a cached copy across places
		for attempt=1,3 do
			ok,raw=pcall(function()return self._store:GetAsync(self:_Key(p),fresh)end)
			if ok then break end
			task.wait(attempt)
		end
	end
	if p.Parent~=Players then return end
	if not ok then warn("[ElevatorHorror] Cosmetics load failed for "..p.UserId.."; using an empty set this session") end
	self._data[p]=clean(ok and raw or nil)
	self:_Apply(p)
	self:_CheckPasses(p)
end
-- merge a change into the saved record and the live copy; returns true when the save went through
function Service:_Write(p,change)
	local d=self._data[p];if not d then return false end
	change(d)
	self:_Apply(p)
	if not self._store then return false end
	-- one save at a time per player, so quick equips can't overtake each other
	while self._saving[p] do task.wait() end
	if p.Parent~=Players then return false end
	self._saving[p]=true
	local ok,result=pcall(function()
		return self._store:UpdateAsync(self:_Key(p),function(old)
			local merged=clean(old)
			for key in d.owned do merged.owned[key]=true end
			change(merged)
			return {v=3,owned=merged.owned,equipped=merged.equipped}
		end)
	end)
	self._saving[p]=nil
	if ok and p.Parent==Players then
		self._data[p]=clean(result)
		self:_Apply(p)
	elseif not ok then
		warn("[ElevatorHorror] Cosmetics save failed: "..tostring(result))
	end
	return ok
end
function Service:Owns(p,slot,id)
	if id=="Default" then return true end
	local d=self._data[p];return d~=nil and d.owned[slot..":"..id]==true
end
-- grants = {{slot,id},...}; returns true if anything new was unlocked
function Service:Grant(p,grants)
	local fresh={}
	for _,g in grants do if known(g[1],g[2]) and not self:Owns(p,g[1],g[2]) then table.insert(fresh,g[1]..":"..g[2]) end end
	if #fresh==0 then return false end
	self:_Write(p,function(d)for _,key in fresh do d.owned[key]=true end end)
	return true
end
function Service:Equip(p,slot,id)
	if not known(slot,id) or not self:Owns(p,slot,id) then return false end
	self:_Write(p,function(d)d.equipped[slot]=(id~="Default") and id or nil end)
	return true
end
-- coin-shop purchase: takes the price, unlocks the item and equips it. Returns ok, reason.
function Service:Buy(p,slot,id)
	local e=known(slot,id)
	if not e or type(e.Price)~="number" or e.Pass or not self._coins or not self._data[p] then return false,"Unavailable" end
	if self:Owns(p,slot,id) then return false,"Owned" end
	if not self._coins:Spend(p,e.Price) then return false,"Funds" end
	-- ownership lands in the live copy before anything yields, so a double click can't pay twice
	self:Grant(p,{{slot,id}})
	self:Equip(p,slot,id)
	return true
end

-- ===== mystery boxes =====
-- everything a box can give, grouped by rarity: only the box exclusives (Box = true - flashlights and
-- colours never sold in the shop; a "Jackpot" item is only ever won by its jackpot roll) and the tokens
local function boxPool()
	local pool={}
	local function add(r,item)pool[r]=pool[r] or {};table.insert(pool[r],item) end
	for _,slot in {"Flashlight","Beam"} do
		for _,e in Config[slot] do
			if e.Box==true then add(BoxConfig.Rarity(slot,e),{slot=slot,e=e}) end
		end
	end
	for _,t in BoxConfig.Tokens or {} do add(t.Rarity,{slot="Token",e={Id=t.Id}}) end
	return pool
end
-- roll a box: the jackpot first (if the box has one), then a rarity by the box's odds and any item of that
-- rarity. A new item is unlocked; one they already own pays back part of its coin value instead; a token
-- is simply added to the ones they have. force = {slot,id} (Studio testing only) skips the rolls.
function Service:_OpenBox(p,box,force)
	self._pool=self._pool or boxPool()
	self._rng=self._rng or Random.new()
	local pick,tier
	if force then
		local e=force[1]=="Token" and {Id=force[2]} or known(force[1],force[2])
		if e then pick={slot=force[1],e=e} end
	end
	local jp=box.Jackpot
	if not pick and jp and self._rng:NextNumber()*100<(jp.Chance or 0) then
		local e=known(jp.Slot,jp.Id)
		if e then pick={slot=jp.Slot,e=e} end
	end
	if not pick then
		local total=0
		for r,w in box.Odds do if self._pool[r] then total+=w end end
		local roll=self._rng:NextNumber()*total
		for _,r in BoxConfig.Order do
			local w=box.Odds[r]
			if w and self._pool[r] then tier=r;roll-=w;if roll<=0 then break end end
		end
		local list=self._pool[tier]
		pick=list[self._rng:NextInteger(1,#list)]
	end
	if pick.slot=="Token" then
		for _,t in BoxConfig.Tokens or {} do if t.Id==pick.e.Id then tier=t.Rarity end end
		local tokens=self._tokens
		if tokens then task.spawn(function()tokens:Add(p,pick.e.Id,1) end) end
		return {slot="Token",id=pick.e.Id,refund=0,tier=tier}
	end
	tier=BoxConfig.Rarity(pick.slot,pick.e)
	local refund=0
	if self:Owns(p,pick.slot,pick.e.Id) then
		refund=math.floor((pick.e.Price or pick.e.Value or 0)*BoxConfig.Refund)
		if self._coins and refund>0 then self._coins:Give(p,refund,"Box") end
	else
		task.spawn(function()self:Grant(p,{{pick.slot,pick.e.Id}}) end)
		-- (Grant marks it owned straight away, before it saves)
	end
	return {slot=pick.slot,id=pick.e.Id,refund=refund,tier=tier}
end
-- a coin box from the shop. Returns the result, or nil + "Funds" | "Unavailable".
function Service:BuyBox(p,boxId)
	if not BoxConfig or not self._coins or not self._data[p] then return nil,"Unavailable" end
	local box
	for _,b in BoxConfig.Boxes do if b.Id==boxId then box=b end end
	if not box or type(box.Coins)~="number" then return nil,"Unavailable" end
	if not self._coins:Spend(p,box.Coins) then return nil,"Funds" end
	return self:_OpenBox(p,box)
end

-- ===== gamepasses =====
function Service:_CheckPasses(p)
	for _,spec in Config.GamePasses do
		task.spawn(function()
			for attempt=1,3 do
				local ok,owns=pcall(function()return MarketplaceService:UserOwnsGamePassAsync(p.UserId,spec.Id)end)
				if ok then
					if owns and p.Parent==Players then self:Grant(p,spec.Grants) end
					return
				end
				task.wait(attempt*2)
			end
		end)
	end
end

-- ===== lobby pickups =====
function Service:_InRoom(p,room)
	local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local bounds=room:FindFirstChild("Bounds")
	if not root or not bounds then return false end
	local o=bounds.CFrame:PointToObjectSpace(root.Position);local h=bounds.Size/2
	return math.abs(o.X)<=h.X and math.abs(o.Y)<=h.Y and math.abs(o.Z)<=h.Z
end
function Service:_OwnsAll(p,spec)
	for _,g in spec.Grants do if not self:Owns(p,g[1],g[2]) then return false end end
	return true
end
function Service:_SetupPickups()
	local room=self._env.Model:FindFirstChild("SecretRoom")
	local items=room and room:FindFirstChild("Collectibles")
	if not items then return end
	local spots=room:FindFirstChild("HidingSpots")
	local rng=Random.new()
	for _,item in items:GetChildren() do
		local spec=Config.Collectibles[item.Name]
		if spec and item:IsA("Model") and item.PrimaryPart then
			local options={}
			if spots then for _,s in spots:GetChildren() do if s:GetAttribute("For")==item.Name then table.insert(options,s) end end end
			local forced=room:GetAttribute("ForceSpot_"..item.Name)
			if forced then for _,s in options do if s.Name==forced then options={s} break end end end
			if #options>0 then
				local pick=options[rng:NextInteger(1,#options)]
				item:PivotTo(pick.CFrame)
				item:SetAttribute("Spot",pick.Name)
			end
			local point=Instance.new("Attachment");point.Name="PromptPoint";point.Parent=item.PrimaryPart
			point.WorldPosition=item.PrimaryPart.Position+Vector3.new(0,item:GetAttribute("PromptLift") or 1.1,0)
			local pp=Instance.new("ProximityPrompt")
			pp.Name="TakePrompt";pp.ActionText="Take";pp.ObjectText="???";pp.HoldDuration=.8
			pp.MaxActivationDistance=5;pp.RequiresLineOfSight=true;pp.KeyboardKeyCode=Enum.KeyCode.E
			pp.Parent=point
			self._scope:Add(pp.Triggered:Connect(function(p)
				if self:_OwnsAll(p,spec) or not self:_InRoom(p,room) then return end
				local root=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position-item.PrimaryPart.Position).Magnitude>Config.ClaimDistance then return end
				if self:Grant(p,spec.Grants) then self._remote:FireClient(p,"Found",item.Name) end
			end))
		end
	end
end

function Service:Start()
	self._scope:Add(self._remote.OnServerEvent:Connect(function(p,action,slot,id)
		if os.clock()-(self._last[p] or 0)<.25 then return end
		self._last[p]=os.clock()
		if action=="Equip" then self:Equip(p,slot,id)
		elseif action=="OpenBox" then
			local r,reason=self:BuyBox(p,slot)
			if p.Parent==Players then
				if r then self._remote:FireClient(p,"BoxResult",slot,r.slot,r.id,r.refund,r.tier)
				else self._remote:FireClient(p,"BoxFailed",slot,reason) end
			end
		elseif action=="Buy" then
			local ok,reason=self:Buy(p,slot,id)
			if p.Parent==Players then
				if ok then self._remote:FireClient(p,"Bought",slot,id) else self._remote:FireClient(p,"BuyFailed",slot,id,reason) end
			end
		end
	end))
	self._scope:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p,passId,purchased)
		if not purchased then return end
		for _,spec in Config.GamePasses do
			if spec.Id==passId and self:Grant(p,spec.Grants) then self._remote:FireClient(p,"Unlocked",spec.Name) end
		end
	end))
	local function watch(p)
		self._scope:Add(p.CharacterAdded:Connect(function(char)
			char:WaitForChild("Head",10);char:WaitForChild("HumanoidRootPart",10)
			-- (once the body is in the world and its joints have placed the head, so its height is right)
			if not char:IsDescendantOf(workspace) then char.AncestryChanged:Wait() end
			task.wait(.25)
			if p.Parent==Players and p.Character==char then self:_Tag(p) end
		end))
	end
	for _,p in Players:GetPlayers() do watch(p) end
	self._scope:Add(Players.PlayerAdded:Connect(function(p)watch(p);self:_Load(p)end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)self._data[p]=nil;self._last[p]=nil;self._saving[p]=nil end))
	for _,p in Players:GetPlayers() do task.spawn(function()self:_Load(p)end) end
	if self._env.Role=="Lobby" then self:_SetupPickups() end
	-- Studio only: ServerStorage.BoxDebug:Invoke(player,boxId,slot?,id?) opens a box for free (slot/id force
	-- the prize, e.g. "Flashlight","Supernova" or "Token","Life") and plays the reveal
	if BoxConfig and game:GetService("RunService"):IsStudio() then
		local fn=Instance.new("BindableFunction");fn.Name="BoxDebug";fn.Parent=game:GetService("ServerStorage")
		fn.OnInvoke=function(p,boxId,slot,id)
			local box;for _,b in BoxConfig.Boxes do if b.Id==boxId then box=b end end
			if not box or not self._data[p] then return nil end
			local r=self:_OpenBox(p,box,slot and {slot,id} or nil)
			self._remote:FireClient(p,"BoxResult",box.Id,r.slot,r.id,r.refund,r.tier)
			return r.slot..":"..r.id.." "..tostring(r.tier).." refund "..r.refund
		end
		self._scope:Add(fn)
	end
end
function Service:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Service)
