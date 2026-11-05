--!nonstrict
-- Game place (Oct 18): the lobby leaderboard tags work down here too. Every minute this reads the
-- top 100 of the donor and coin boards (same ordered DataStores as the lobby's LeaderboardService)
-- and sets EHDonorRank / EHCoinRank on players in this server; CosmeticsController turns those into
-- chat tags. Tips bought in any lobby are announced in chat here as well (MessagingService BWTips).
local Players=game:GetService("Players")
local DataStoreService=game:GetService("DataStoreService")
local MessagingService=game:GetService("MessagingService")
local Config=require(game.ReplicatedStorage.Game.Shared.Config.DonationConfig)
local net=game.ReplicatedStorage.Game:WaitForChild("Network")
local tip=net:FindFirstChild("Tip") or Instance.new("RemoteEvent");tip.Name="Tip";tip.Parent=net
local function ods(name)local ok,st=pcall(function()return DataStoreService:GetOrderedDataStore(name)end);return ok and st or nil end
local boards={Donor=ods(Config.DonationBoard),Coin=ods(Config.CoinBoard)}
local ranks={Donor={},Coin={}}
local function read(store)
	if not store then return nil end
	local ok,page=pcall(function()return store:GetSortedAsync(false,Config.BoardSize):GetCurrentPage()end)
	if not ok then return nil end
	local r={}
	for i,e in page do local id=tonumber(e.key);if id and (tonumber(e.value) or 0)>0 then r[id]=i end end
	return r
end
local function apply(p)
	local d=ranks.Donor[p.UserId];local c=ranks.Coin[p.UserId]
	if p:GetAttribute("EHDonorRank")~=d then p:SetAttribute("EHDonorRank",d) end
	if p:GetAttribute("EHCoinRank")~=c then p:SetAttribute("EHCoinRank",c) end
	-- an equipped leaderboard title floats over the head with the live rank (hidden if you dropped off)
	local t=p:GetAttribute("EHTitle")
	local r=(t=="DonorTag" and d) or (t=="CoinTag" and c) or nil
	local head=p.Character and p.Character:FindFirstChild("Head")
	local g=head and head:FindFirstChild("EHTitleTag")
	if g and (t=="DonorTag" or t=="CoinTag") then
		g.Enabled=r~=nil
		if r and g:FindFirstChild("Label") then g.Label.Text=(r<=10 and ("#"..r) or "TOP 100").." "..(t=="DonorTag" and "DONOR" or "COINS") end
	end
end
Players.PlayerAdded:Connect(apply)
task.spawn(function()
	local ok,conn=pcall(function()
		return MessagingService:SubscribeAsync("BWTips",function(msg)
			local d=msg.Data
			if type(d)=="table" and type(d.n)=="string" and type(d.r)=="number" then tip:FireAllClients(d.n,d.r) end
		end)
	end)
end)
while true do
	for k,store in boards do local r=read(store);if r then ranks[k]=r end end
	for _,p in Players:GetPlayers() do apply(p) end
	task.wait(Config.RefreshSeconds)
end
