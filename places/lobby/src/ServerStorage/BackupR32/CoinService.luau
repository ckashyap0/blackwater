--!nonstrict
-- Coins: balance, coin-pack purchases and earning. Same file in the Lobby and Game places.
-- Saved in its own DataStore (Config.CoinConfig.Store), key "U_<userId>" -> {v=1,coins=n,receipts={[purchaseId]=time}}.
--
-- Replicated player attributes:
--   EHCoins          current balance (what the shop header shows)
--   EHCoinsReady     true once loaded
--   EHCoinMultiplier 2 for 2x Coins owners, else 1
-- Network.Coins (server -> client): ("Bought",coins,packId) after a pack is delivered,
--                                  ("Earned",coins,reason) after Award
--
-- Other services:
--   CoinService:Award(player,amount,reason) -> coins given (x2 with the gamepass); for in-game rewards
--   CoinService:Give(player,amount,reason) -> gives coins as they are (no x2); refunds
--   CoinService:Spend(player,amount)        -> true if they could afford it (and it was taken)
--   CoinService:Get(player)                 -> balance
--   CoinService:RegisterProduct(productId,function(receiptInfo)->granted end) for other Developer Products
--
-- Saving is delta-based: earned/spent coins collect in a pending total that is merged into the saved
-- number with UpdateAsync (every SaveInterval seconds and when the player leaves), so a failed load or
-- two servers at once can never overwrite a balance. Purchases are written straight away, and every
-- purchase id is remembered so a pack is never delivered twice.
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local MarketplaceService=game:GetService("MarketplaceService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.CoinConfig)
local Service={};Service.__index=Service
local KEEP_RECEIPTS=60

local function clean(raw)
	local d={v=1,coins=0,receipts={}}
	if type(raw)=="table" then
		local c=tonumber(raw.coins);if c and c==c then d.coins=math.max(0,math.floor(c)) end
		if type(raw.receipts)=="table" then for k,t in raw.receipts do if type(k)=="string" then d.receipts[k]=tonumber(t) or 0 end end end
	end
	return d
end
local function trim(receipts)
	local list={}
	for k,t in receipts do table.insert(list,{k,t}) end
	if #list<=KEEP_RECEIPTS then return end
	table.sort(list,function(a,b)return a[2]>b[2] end)
	for i=KEEP_RECEIPTS+1,#list do receipts[list[i][1]]=nil end
end

function Service.new()
	return setmetatable({Name="CoinService",Dependencies={},_base={},_pending={},_ready={},_mult={},_saving={},_products={}},Service)
end
function Service:Init()
	self._scope=Scope.new()
	local ok,store=pcall(function()return DataStoreService:GetDataStore(Config.Store)end)
	self._store=ok and store or nil
	local network=game.ReplicatedStorage.Game.Network
	local remote=network:FindFirstChild("Coins")
	if not remote then remote=Instance.new("RemoteEvent");remote.Name="Coins";remote.Parent=network end
	self._remote=remote
	-- coin packs
	for _,pack in Config.Packs do
		if (pack.ProductId or 0)>0 then
			self:RegisterProduct(pack.ProductId,function(info)return self:_GrantPack(info,pack) end)
		end
	end
end

-- ===== balance =====
function Service:_Key(userId)return "U_"..userId end
function Service:Get(p)return (self._base[p] or 0)+(self._pending[p] or 0) end
function Service:_Apply(p)
	if p.Parent~=Players then return end
	p:SetAttribute("EHCoins",self:Get(p))
	p:SetAttribute("EHCoinMultiplier",self._mult[p] or 1)
	if self._ready[p] then p:SetAttribute("EHCoinsReady",true) end
end
function Service:_Load(p)
	local raw,ok=nil,false
	if self._store then
		local fresh=Instance.new("DataStoreGetOptions");fresh.UseCache=false
		for attempt=1,3 do
			ok,raw=pcall(function()return self._store:GetAsync(self:_Key(p.UserId),fresh)end)
			if ok then break end
			task.wait(attempt)
		end
	end
	if p.Parent~=Players then return end
	if not ok then warn("[ElevatorHorror] Coins load failed for "..p.UserId.."; earned coins are still kept and merged on save") end
	self._base[p]=clean(ok and raw or nil).coins
	self._ready[p]=true
	self:_Apply(p)
	-- 2x Coins gamepass
	task.spawn(function()
		for attempt=1,3 do
			local okPass,owns=pcall(function()return MarketplaceService:UserOwnsGamePassAsync(p.UserId,Config.TwoXPassId)end)
			if okPass then if owns then self._mult[p]=Config.EarnMultiplier;self:_Apply(p) end return end
			task.wait(attempt*2)
		end
	end)
end
-- merge pending earned/spent coins into the saved balance
function Service:_Flush(p,userId)
	if not self._store then return false end
	userId=userId or p.UserId
	local delta=self._pending[p] or 0
	if delta==0 then return true end
	while self._saving[p] do task.wait() end
	delta=self._pending[p] or 0
	if delta==0 then return true end
	self._saving[p]=true
	local ok,res=pcall(function()
		return self._store:UpdateAsync(self:_Key(userId),function(old)
			local d=clean(old)
			d.coins=math.max(0,d.coins+delta)
			return d
		end)
	end)
	self._saving[p]=nil
	if ok then
		self._pending[p]=(self._pending[p] or 0)-delta
		if self._base[p]~=nil then self._base[p]=clean(res).coins end
		self:_Apply(p)
	else
		warn("[ElevatorHorror] Coins save failed: "..tostring(res))
	end
	return ok
end

-- coins earned in game; x2 for 2x Coins owners. Returns the amount actually given.
function Service:Award(p,amount,reason)
	amount=math.floor(tonumber(amount) or 0)
	if amount<=0 or p.Parent~=Players then return 0 end
	local given=amount*(self._mult[p] or 1)
	self._pending[p]=(self._pending[p] or 0)+given
	self:_Apply(p)
	self._remote:FireClient(p,"Earned",given,reason)
	return given
end
-- coins handed back (a duplicate from a mystery box): never doubled, saved soon after
function Service:Give(p,amount,reason)
	amount=math.floor(tonumber(amount) or 0)
	if amount<=0 or p.Parent~=Players then return 0 end
	self._pending[p]=(self._pending[p] or 0)+amount
	self:_Apply(p)
	self._remote:FireClient(p,"Earned",amount,reason)
	task.spawn(function()self:_Flush(p) end)
	return amount
end
-- take coins if the player can afford it
function Service:Spend(p,amount)
	amount=math.floor(tonumber(amount) or 0)
	if amount<=0 or not self._ready[p] or self:Get(p)<amount then return false end
	self._pending[p]=(self._pending[p] or 0)-amount
	self:_Apply(p)
	task.spawn(function()self:_Flush(p) end)
	return true
end

-- ===== Developer Products =====
function Service:RegisterProduct(productId,handler)
	self._products[productId]=handler
end
function Service:_GrantPack(info,pack)
	if not self._store then return false end
	local key=tostring(info.PurchaseId)
	local already=false
	local ok,res=pcall(function()
		return self._store:UpdateAsync(self:_Key(info.PlayerId),function(old)
			local d=clean(old)
			if d.receipts[key] then already=true;return nil end
			d.coins+=pack.Coins
			d.receipts[key]=os.time()
			trim(d.receipts)
			return d
		end)
	end)
	if not ok then warn("[ElevatorHorror] Coin pack delivery failed (will retry): "..tostring(res));return false end
	local p=Players:GetPlayerByUserId(info.PlayerId)
	if p and not already then
		if self._base[p]~=nil and res then self._base[p]=clean(res).coins end
		self:_Apply(p)
		self._remote:FireClient(p,"Bought",pack.Coins,pack.Id)
	end
	return true
end

function Service:Start()
	MarketplaceService.ProcessReceipt=function(info)
		local handler=self._products[info.ProductId]
		if not handler then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local ok,granted=pcall(handler,info)
		if ok and granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
		if not ok then warn("[ElevatorHorror] Purchase handler error: "..tostring(granted)) end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	self._scope:Add(function()MarketplaceService.ProcessReceipt=nil end)
	-- buying 2x Coins in game turns the multiplier on straight away
	self._scope:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p,passId,bought)
		if bought and passId==Config.TwoXPassId then self._mult[p]=Config.EarnMultiplier;self:_Apply(p) end
	end))
	self._scope:Add(Players.PlayerAdded:Connect(function(p)self:_Load(p)end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)
		local userId=p.UserId
		task.spawn(function()
			self:_Flush(p,userId)
			self._base[p]=nil;self._pending[p]=nil;self._ready[p]=nil;self._mult[p]=nil
		end)
	end))
	for _,p in Players:GetPlayers() do task.spawn(function()self:_Load(p)end) end
	-- Studio only: a test hook (ServerStorage.CoinDebug) - Invoke("Award",player,n) / ("Buy",player,packIndex)
	if game:GetService("RunService"):IsStudio() then
		local fn=Instance.new("BindableFunction");fn.Name="CoinDebug";fn.Parent=game:GetService("ServerStorage")
		fn.OnInvoke=function(action,p,n)
			if action=="Award" then return self:Award(p,n,"Debug") end
			if action=="Spend" then return self:Spend(p,n) end
			if action=="Flush" then return self:_Flush(p) end
			if action=="Buy" then
				local pack=Config.Packs[n]
				return self:_GrantPack({PlayerId=p.UserId,PurchaseId="studio-"..os.clock(),ProductId=pack.ProductId},pack)
			end
		end
		self._scope:Add(fn)
	end
	-- periodic save of earned coins
	local alive=true
	self._scope:Add(function()alive=false end)
	task.spawn(function()
		while alive do
			task.wait(Config.SaveInterval)
			for p,delta in self._pending do if delta~=0 then task.spawn(function()self:_Flush(p) end) end end
		end
	end)
end
function Service:Destroy()
	-- server closing: save whatever is still pending
	local waiting=0
	for p,delta in self._pending do
		if delta~=0 then
			waiting+=1
			task.spawn(function()pcall(function()self:_Flush(p,p.UserId) end);waiting-=1 end)
		end
	end
	local t=os.clock()
	while waiting>0 and os.clock()-t<20 do task.wait() end
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Service)
