--!nonstrict
-- TOKENS (Spook Token, Extra Life Token): how many each player has. Same file in the Lobby and Game places.
-- Saved in its own DataStore (Config.TokenConfig.Store), key "U_<userId>" ->
--   {v=1, tokens={Scare=n,Life=n}, receipts={[purchaseId]=time}, vip=true once the VIP gift was given}
-- Replicated player attributes: one per token (TokenConfig Attr, e.g. EHScareTokens = 3) and EHTokensReady.
-- Network.Tokens (server -> client): ("Bought",tokenId,amount) after a purchase is delivered
--
-- Other services:
--   TokenService:Get(player,id)    -> how many they have
--   TokenService:Add(player,id,n)  -> gives n (saved straight away)
--   TokenService:Use(player,id)    -> true if they had one (it is taken and saved)
--
-- Buying (Lobby): each token is a Developer Product. CoinService owns MarketplaceService.ProcessReceipt and
-- hands these product ids to this service; every purchase id is remembered so one is never delivered twice.
-- Every save is an UpdateAsync that applies just the change, so two servers (or a failed load) can never
-- overwrite each other.
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local MarketplaceService=game:GetService("MarketplaceService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.TokenConfig)
local Service={};Service.__index=Service
local KEEP_RECEIPTS=60
local byId={}
for _,t in Config.Tokens do byId[t.Id]=t end

local function clean(raw)
	local d={v=1,tokens={},receipts={},vip=false}
	if type(raw)=="table" then
		if type(raw.tokens)=="table" then
			for id in byId do
				local n=tonumber(raw.tokens[id])
				if n and n==n then d.tokens[id]=math.max(0,math.floor(n)) end
			end
		end
		if type(raw.receipts)=="table" then for k,t in raw.receipts do if type(k)=="string" then d.receipts[k]=tonumber(t) or 0 end end end
		d.vip=raw.vip==true
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
	-- CoinService (which routes purchases) only exists in the Lobby, so this file stays the same in both places
	local deps=script.Parent:FindFirstChild("CoinService") and {"CoinService"} or {}
	return setmetatable({Name="TokenService",Dependencies=deps,_data={},_saving={}},Service)
end
function Service:Init(deps)
	self._coins=deps.CoinService
	self._scope=Scope.new()
	local ok,store=pcall(function()return DataStoreService:GetDataStore(Config.Store)end)
	self._store=ok and store or nil
	local network=game.ReplicatedStorage.Game.Network
	local remote=network:FindFirstChild("Tokens")
	if not remote then remote=Instance.new("RemoteEvent");remote.Name="Tokens";remote.Parent=network end
	self._remote=remote
	if self._coins then
		for _,t in Config.Tokens do
			if (t.ProductId or 0)>0 then
				self._coins:RegisterProduct(t.ProductId,function(info)return self:_Purchase(info,t) end)
			end
		end
	end
end

function Service:_Key(userId)return "U_"..userId end
function Service:Get(p,id)
	local d=self._data[p]
	return d and d.tokens[id] or 0
end
function Service:_Apply(p)
	local d=self._data[p];if not d or p.Parent~=Players then return end
	for _,t in Config.Tokens do p:SetAttribute(t.Attr,d.tokens[t.Id] or 0) end
	p:SetAttribute("EHTokensReady",true)
end
-- change(record) is applied to the live copy straight away (so nothing can be used twice), then to the
-- saved record inside UpdateAsync
function Service:_Write(p,change)
	local d=self._data[p];if not d then return false end
	change(d)
	self:_Apply(p)
	if not self._store then return false end
	while self._saving[p] do task.wait() end
	if p.Parent~=Players then return false end
	self._saving[p]=true
	local userId=p.UserId
	local ok,res=pcall(function()
		return self._store:UpdateAsync(self:_Key(userId),function(old)
			local m=clean(old);change(m);return m
		end)
	end)
	self._saving[p]=nil
	if ok then
		if self._data[p] and res then self._data[p]=clean(res);self:_Apply(p) end
	else
		warn("[ElevatorHorror] Token save failed: "..tostring(res))
	end
	return ok
end
function Service:Add(p,id,n)
	n=math.floor(tonumber(n) or 0)
	if not byId[id] or n<=0 or not self._data[p] then return false end
	return self:_Write(p,function(d)d.tokens[id]=(d.tokens[id] or 0)+n end)
end
function Service:Use(p,id)
	if not byId[id] or self:Get(p,id)<1 then return false end
	self:_Write(p,function(d)d.tokens[id]=math.max(0,(d.tokens[id] or 0)-1) end)
	return true
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
	if not ok then warn("[ElevatorHorror] Tokens load failed for "..p.UserId.."; showing 0 this session") end
	self._data[p]=clean(ok and raw or nil)
	self:_Apply(p)
	-- VIP comes with a Spook Token: given once
	if not self._data[p].vip and (Config.VipPassId or 0)>0 then
		for attempt=1,3 do
			local okPass,owns=pcall(function()return MarketplaceService:UserOwnsGamePassAsync(p.UserId,Config.VipPassId)end)
			if okPass then
				if owns and p.Parent==Players then self:_GiveVipGift(p) end
				break
			end
			task.wait(attempt*2)
		end
	end
end
function Service:_GiveVipGift(p)
	if not self._data[p] or self._data[p].vip then return end
	self:_Write(p,function(d)
		if d.vip then return end
		d.vip=true
		for id,n in Config.VipGift do d.tokens[id]=(d.tokens[id] or 0)+n end
	end)
end
-- a Developer Product purchase (Lobby). Returns true once it's safely saved.
function Service:_Purchase(info,t)
	if not self._store then return false end
	local key=tostring(info.PurchaseId)
	local already=false
	local ok,res=pcall(function()
		return self._store:UpdateAsync(self:_Key(info.PlayerId),function(old)
			local d=clean(old)
			if d.receipts[key] then already=true;return nil end
			d.tokens[t.Id]=(d.tokens[t.Id] or 0)+(t.Amount or 1)
			d.receipts[key]=os.time()
			trim(d.receipts)
			return d
		end)
	end)
	if not ok then warn("[ElevatorHorror] Token delivery failed (will retry): "..tostring(res));return false end
	local p=Players:GetPlayerByUserId(info.PlayerId)
	if p and not already then
		if self._data[p] and res then self._data[p]=clean(res);self:_Apply(p) end
		self._remote:FireClient(p,"Bought",t.Id,t.Amount or 1)
	end
	return true
end

function Service:Start()
	self._scope:Add(Players.PlayerAdded:Connect(function(p)self:_Load(p)end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)
		task.delay(5,function()if p.Parent~=Players then self._data[p]=nil;self._saving[p]=nil end end)
	end))
	for _,p in Players:GetPlayers() do task.spawn(function()self:_Load(p)end) end
	-- buying VIP in game gives the token straight away
	self._scope:Add(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p,passId,bought)
		if bought and passId==Config.VipPassId then task.spawn(function()self:_GiveVipGift(p) end) end
	end))
	-- Studio only: a test hook (ServerStorage.TokenDebug) - Invoke("Add",player,"Scare",n) / ("Use",player,"Life") / ("Buy",player,"Scare")
	if game:GetService("RunService"):IsStudio() then
		local fn=Instance.new("BindableFunction");fn.Name="TokenDebug";fn.Parent=game:GetService("ServerStorage")
		fn.OnInvoke=function(action,p,id,n)
			if action=="Add" then return self:Add(p,id,n or 1) end
			if action=="Use" then return self:Use(p,id) end
			if action=="Get" then return self:Get(p,id) end
			if action=="Buy" then return self:_Purchase({PlayerId=p.UserId,PurchaseId="studio-"..os.clock(),ProductId=0},byId[id]) end
		end
		self._scope:Add(fn)
	end
end
function Service:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Service)
