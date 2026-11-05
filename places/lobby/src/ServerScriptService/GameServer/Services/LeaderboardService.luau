--!nonstrict
-- Lobby leaderboards (Oct 18):
--  * TOP DONORS - Robux tipped through the nine tip products (DonationConfig; gamepasses never count).
--  * TOP COINS  - each player's CURRENT coin balance (written when they join, when it changes - at most
--    every 30 s - and when they leave).
-- Top 100 of each, refreshed every minute (and a few seconds after a tip) and published as JSON to
-- Network.Leaderboards.Donors / .Coins for the boards on the window wall. Players in this server get
-- EHDonorRank / EHCoinRank (1-100, or nil) which the chat tags read: falling out of a band changes or
-- removes the tag on the next refresh. Every tip is announced in chat ("<name> has tipped 25 Robux!")
-- in this server and, through MessagingService, in every other server.
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local MessagingService=game:GetService("MessagingService")
local HttpService=game:GetService("HttpService")
local UserService=game:GetService("UserService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Config=require(Shared.Config.DonationConfig)
local TOPIC="BWTips"
local RunService=game:GetService("RunService")
-- a DataStore call that retries a couple of times before giving up (a busy moment never loses a tip)
local function retry(fn)
	local ok,res
	for i=1,3 do ok,res=pcall(fn);if ok then return true,res end;task.wait(i) end
	return false,res
end
local Service={};Service.__index=Service
function Service.new()
	return setmetatable({Name="LeaderboardService",Dependencies={"CoinService","CosmeticService"},_names={},_coinSaved={},_coinQueued={},_prev={},_announced={}},Service)
end
local function getStore(ordered,name)
	local ok,s=pcall(function()
		if ordered then return DataStoreService:GetOrderedDataStore(name) end
		return DataStoreService:GetDataStore(name)
	end)
	return ok and s or nil
end
function Service:Init(deps)
	self._coins=deps.CoinService;self._cos=deps.CosmeticService;self._scope=Scope.new()
	self._donStore=getStore(false,Config.DonationStore)
	self._donTop=getStore(true,Config.DonationBoard)
	self._coinTop=getStore(true,Config.CoinBoard)
	local net=game.ReplicatedStorage.Game.Network
	local folder=net:FindFirstChild("Leaderboards") or Instance.new("Folder");folder.Name="Leaderboards";folder.Parent=net
	for _,n in {"Donors","Coins"} do
		if not folder:FindFirstChild(n) then local v=Instance.new("StringValue");v.Name=n;v.Value="[]";v.Parent=folder end
	end
	self._folder=folder
	local tip=net:FindFirstChild("Tip") or Instance.new("RemoteEvent");tip.Name="Tip";tip.Parent=net;self._tip=tip
	local ann=net:FindFirstChild("BoardAnnounce") or Instance.new("RemoteEvent");ann.Name="BoardAnnounce";ann.Parent=net;self._announce=ann
	if self._coins then
		for _,t in Config.Tips do
			self._coins:RegisterProduct(t.ProductId,function(info)return self:_Donate(info,t.Robux)end)
		end
	end
end
------------------------------------------------------------------ tips
function Service:_Name(userId)
	if self._names[userId] then return self._names[userId] end
	local p=Players:GetPlayerByUserId(userId)
	if p then self._names[userId]=p.Name;return p.Name end
	local ok,n=pcall(Players.GetNameFromUserIdAsync,Players,userId)
	if ok and n then self._names[userId]=n;return n end
	return "Someone"
end
local function trimReceipts(receipts)
	local list={}
	for k,v in receipts do table.insert(list,{k,v}) end
	if #list<=60 then return end
	table.sort(list,function(a,b)return a[2]>b[2]end)
	for i=61,#list do local key=list[i][1];receipts[key]=nil end
end
function Service:_Donate(info,robux)
	-- Studio test purchases cost nothing: they are thanked in chat but never written to the real board
	if RunService:IsStudio() then
		self._tip:FireAllClients(self:_Name(info.PlayerId),tonumber(info.CurrencySpent) or robux)
		return true
	end
	if not self._donStore then return false end
	-- credit what was actually paid (the product's real price), not just the button's number
	local spent=tonumber(info.CurrencySpent)
	if spent and spent>0 then robux=spent end
	local total,already
	local ok,err=retry(function()
		self._donStore:UpdateAsync("U_"..info.PlayerId,function(d)
			d=type(d)=="table" and d or {}
			d.total=tonumber(d.total) or 0
			d.receipts=type(d.receipts)=="table" and d.receipts or {}
			if d.receipts[info.PurchaseId] then already=true;total=d.total;return nil end
			d.total+=robux;d.receipts[info.PurchaseId]=os.time()
			trimReceipts(d.receipts)
			total=d.total
			return d
		end)
	end)
	if not ok then warn("[ElevatorHorror] Tip delivery failed (will retry): "..tostring(err));return false end
	if self._donTop and total then retry(function()self._donTop:SetAsync(tostring(info.PlayerId),total)end) end
	if not already then
		local name=self:_Name(info.PlayerId)
		self._tip:FireAllClients(name,robux)
		self:_Bump("Donors",info.PlayerId,total,name)
		pcall(function()MessagingService:PublishAsync(TOPIC,{n=name,r=robux,s=game.JobId,i=info.PlayerId,t=total})end)
		self._soon=true
	end
	return true
end
------------------------------------------------------------------ coins
function Service:_SaveCoins(p,force)
	if not self._coinTop or p:GetAttribute("EHCoinsReady")~=true then return end
	local coins=tonumber(p:GetAttribute("EHCoins")) or 0
	self:_Bump("Coins",p.UserId,math.max(0,math.floor(coins)),p.Name)
	local now=os.clock()
	-- (join + coins-ready arrive together: one write, not two back to back)
	local since=now-(self._coinSaved[p] or -math.huge)
	if (not force and since<30) or (force and since<6) then self._coinQueued[p]=true;return end
	self._coinSaved[p]=now;self._coinQueued[p]=nil
	local id=p.UserId
	task.spawn(function()pcall(function()self._coinTop:SetAsync(tostring(id),math.max(0,math.floor(coins)))end)end)
end
function Service:_Track(p)
	self._names[p.UserId]=p.Name
	-- (self-repair: if a board write ever failed, the saved total puts this player back on the board)
	task.spawn(function()
		if not (self._donStore and self._donTop) then return end
		local ok,d=retry(function()return self._donStore:GetAsync("U_"..p.UserId)end)
		local total=ok and type(d)=="table" and tonumber(d.total) or 0
		if total>0 then retry(function()self._donTop:SetAsync(tostring(p.UserId),total)end) end
	end)
	self._scope:Add(p:GetAttributeChangedSignal("EHCoins"):Connect(function()self:_SaveCoins(p,false)end))
	self._scope:Add(p:GetAttributeChangedSignal("EHCoinsReady"):Connect(function()self:_SaveCoins(p,true)end))
	self:_SaveCoins(p,true)
end
------------------------------------------------------------------ live updates
-- The full top-100 read happens on a timer (OrderedDataStore reads lag a few seconds), but every
-- change this server knows about is put on the board straight away: the entry is updated in the
-- published list, re-sorted and sent out, and ranks / tags / announcements follow at once.
function Service:_Bump(key,userId,value,name)
	local list=self._lists and self._lists[key]
	if not list then return end
	if name then self._names[userId]=name end
	local found=false
	for _,e in list do if e.i==userId then e.v=value;found=true;break end end
	if not found then
		if value<=0 then return end
		if #list>=Config.BoardSize and value<=(list[#list].v or 0) then return end -- (not enough for the top 100)
		table.insert(list,{i=userId,v=value,n=self._names[userId] or ("Player "..userId)})
	end
	table.sort(list,function(a,b)return a.v>b.v end)
	while #list>Config.BoardSize do table.remove(list) end
	self:_Publish(key,list)
end
------------------------------------------------------------------ boards
function Service:_Read(ods)
	if not ods then return nil end
	local ok,page=pcall(function()return ods:GetSortedAsync(false,Config.BoardSize):GetCurrentPage()end)
	if not ok then return nil end
	local list,missing={},{}
	for _,e in page do
		local id=tonumber(e.key);local v=tonumber(e.value) or 0
		if id and v>0 then
			table.insert(list,{i=id,v=v})
			if not self._names[id] then table.insert(missing,id) end
		end
	end
	if #missing>0 then
		local ok2,infos=pcall(UserService.GetUserInfosByUserIdsAsync,UserService,missing)
		if ok2 and infos then for _,u in infos do self._names[u.Id]=u.Username end end
	end
	for _,e in list do e.n=self._names[e.i] or ("Player "..e.i) end
	return list
end
function Service:_Refresh()
	for key,ods in {Donors=self._donTop,Coins=self._coinTop} do
		local list=self:_Read(ods)
		if not list then
			-- (a failed read keeps the last good board, and the tags it gave)
			local ok,old=pcall(HttpService.JSONDecode,HttpService,self._folder[key].Value)
			list=ok and old or {}
		end
		self:_Publish(key,list)
	end
end
-- send a board out, work out ranks for players here, refresh their tags and announce rank-ups
function Service:_Publish(key,list)
	self._lists=self._lists or {};self._lists[key]=list
	local json=HttpService:JSONEncode(list)
	if self._folder[key].Value~=json then self._folder[key].Value=json end
	local ranks={}
	for r,e in list do ranks[e.i]=r end
	-- rank-ups since the last time: #1, into the top 10, into the top 100 (announced once each per
	-- server; the first board after the server starts only sets the baseline)
	local prev=self._prev[key]
	if prev then
		for r,e in list do
			local old=prev[e.i];local band
			if r==1 and old~=1 then band="#1"
			elseif r<=10 and (not old or old>10) then band="TOP 10"
			elseif not old then band="TOP 100" end
			local tag=band and (key..":"..band..":"..e.i)
			if tag and not self._announced[tag] then
				self._announced[tag]=true
				self._announce:FireAllClients(e.n or "Someone",key=="Donors" and "TOP DONORS" or "TOP COINS",band,r)
			end
		end
	end
	self._prev[key]=ranks
	local attr=key=="Donors" and "EHDonorRank" or "EHCoinRank"
	for _,p in Players:GetPlayers() do
		local r=ranks[p.UserId]
		if p:GetAttribute(attr)~=r then
			p:SetAttribute(attr,r)
			if self._cos and self._cos.RefreshRanks then pcall(self._cos.RefreshRanks,self._cos,p) end
		end
	end
end
function Service:Start()
	self._scope:Add(Players.PlayerAdded:Connect(function(p)self:_Track(p);self._soon=true end))
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)
		self._coinSaved[p]=nil;self:_SaveCoins(p,true);self._coinSaved[p]=nil;self._coinQueued[p]=nil -- (leaving always writes)
	end))
	for _,p in Players:GetPlayers() do self:_Track(p) end
	task.spawn(function()
		local ok,conn=pcall(function()
			return MessagingService:SubscribeAsync(TOPIC,function(msg)
				local d=msg.Data
				if type(d)=="table" and d.s~=game.JobId and type(d.n)=="string" and type(d.r)=="number" then
					self._tip:FireAllClients(d.n,d.r)
					if type(d.i)=="number" and type(d.t)=="number" then self:_Bump("Donors",d.i,d.t,d.n) end
				end
			end)
		end)
		if ok and conn then self._scope:Add(function()conn:Disconnect()end) end
	end)
	self._running=true
	task.spawn(function()
		task.wait(3)
		local last=-math.huge
		while self._running do
			local now=os.clock()
			if now-last>=Config.RefreshSeconds or (self._soon and now-last>=8) then
				self._soon=false;last=now
				local ok,err=pcall(self._Refresh,self)
				if not ok then warn("[ElevatorHorror] Leaderboard refresh: "..tostring(err)) end
			end
			for p in self._coinQueued do if p.Parent then self:_SaveCoins(p,false) end end
			task.wait(2)
		end
	end)
end
function Service:Destroy()
	self._running=false
	for _,p in Players:GetPlayers() do pcall(self._SaveCoins,self,p,true) end
	if self._scope then self._scope:Destroy() end
end
return Service
