--!nonstrict
-- ADMIN CHAT COMMANDS (Lobby). Only admins can use them: the game's owner account, anyone ranked 254+
-- in the owning group, or anyone in Studio. Type them in chat; replies only you can see come back in chat.
--
--   /cmds                              list these commands
--   /coins <player> <amount>           give coins
--   /takecoins <player> <amount>       take coins away
--   /setcoins <player> <amount>        set someone's coins to an exact number
--   /balance [player]                  how many coins someone has (you, if no name)
--   /tokens <player> <spook|life> [n]  give tokens (1 if no number)
--
-- <player> is the start of a username or display name ("pan" finds PandaPenguin472), or me / all / others.
-- Every change goes through CoinService / TokenService, so it is saved like any other coins or tokens.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local TextChatService=game:GetService("TextChatService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Service={};Service.__index=Service

local OWNERS={[2403347306]=true} -- PandaPenguin472
local GROUP_ADMIN_RANK=254
local GOLD,GREEN,RED,GREY="#FFC24A","#6EE08F","#FF6B6B","#B9B6AE"
local TOKEN_ALIAS={spook="Scare",scare="Scare",jumpscare="Scare",life="Life",extralife="Life",extra="Life"}

local HELP={
	"/coins <player> <amount>  -  give coins",
	"/takecoins <player> <amount>  -  take coins",
	"/setcoins <player> <amount>  -  set coins",
	"/balance [player]  -  check coins",
	"/tokens <player> <spook|life> [amount]  -  give tokens",
	"<player> = part of a name, or me / all / others",
}

function Service.new()
	local deps={}
	for _,n in {"CoinService","TokenService"} do if script.Parent:FindFirstChild(n) then table.insert(deps,n) end end
	return setmetatable({Name="AdminService",Dependencies=deps,_admin={}},Service)
end
function Service:Init(deps)
	self._coins=deps.CoinService
	self._tokens=deps.TokenService
	self._scope=Scope.new()
	local network=game.ReplicatedStorage.Game.Network
	local remote=network:FindFirstChild("AdminChat")
	if not remote then remote=Instance.new("RemoteEvent");remote.Name="AdminChat";remote.Parent=network end
	self._remote=remote
end

function Service:IsAdmin(p)
	if not p or p.Parent~=Players then return false end
	if RunService:IsStudio() or OWNERS[p.UserId] then return true end
	local known=self._admin[p]
	if known~=nil then return known end
	local ok,rank=pcall(function()
		return game.CreatorType==Enum.CreatorType.Group and p:GetRankInGroup(game.CreatorId) or 0
	end)
	known=(ok and rank>=GROUP_ADMIN_RANK) or (game.CreatorType==Enum.CreatorType.User and p.UserId==game.CreatorId)
	self._admin[p]=known
	return known
end
function Service:_Say(p,text,color)
	if p and p.Parent==Players then self._remote:FireClient(p,text,color or GREY) end
end
-- who a name means: me / all / others, or the one player whose username or display name starts with it
function Service:_Find(admin,name)
	if not name or name=="" then return nil,"Who? Add a player name." end
	local low=string.lower(name)
	if low=="me" then return {admin} end
	if low=="all" then return Players:GetPlayers() end
	if low=="others" then local t={};for _,p in Players:GetPlayers() do if p~=admin then table.insert(t,p) end end;return t end
	local exact,starts={}, {}
	for _,p in Players:GetPlayers() do
		local u,d=string.lower(p.Name),string.lower(p.DisplayName)
		if u==low or d==low then table.insert(exact,p)
		elseif string.sub(u,1,#low)==low or string.sub(d,1,#low)==low then table.insert(starts,p) end
	end
	if #exact==1 then return exact end
	if #exact>1 or #starts>1 then return nil,"More than one player matches \""..name.."\" - type more of the name." end
	if #starts==1 then return starts end
	return nil,"No player called \""..name.."\" is in this server."
end
local function amountOf(s)
	local n=tonumber(s and (string.gsub(s,",","")))
	if not n or n~=n or n<0 or n>1e9 then return nil end
	return math.floor(n)
end
local function commas(n)
	local s=tostring(math.floor(n))
	while true do local k;s,k=string.gsub(s,"^(-?%d+)(%d%d%d)","%1,%2");if k==0 then break end end
	return s
end
local function names(list)
	if #list>3 then return #list.." players" end
	local t={};for _,p in list do table.insert(t,p.Name) end
	return table.concat(t,", ")
end

function Service:_Run(admin,cmd,args)
	if cmd=="cmds" then
		self:_Say(admin,"ADMIN COMMANDS",GOLD)
		for _,line in HELP do self:_Say(admin,line) end
		return
	end
	local coinCmd=cmd=="coins" or cmd=="takecoins" or cmd=="setcoins" or cmd=="balance"
	if coinCmd and not self._coins then return self:_Say(admin,"Coins can only be changed in the lobby.",RED) end
	if cmd=="balance" then
		local list,err=self:_Find(admin,args[1] or "me");if not list then return self:_Say(admin,err,RED) end
		for _,p in list do self:_Say(admin,p.Name.." has "..commas(self._coins:Get(p)).." coins",GOLD) end
		return
	end
	if cmd=="coins" or cmd=="takecoins" or cmd=="setcoins" then
		local list,err=self:_Find(admin,args[1]);if not list then return self:_Say(admin,err,RED) end
		local n=amountOf(args[2]);if not n then return self:_Say(admin,"Usage: /"..cmd.." <player> <amount>",RED) end
		for _,p in list do
			local have=self._coins:Get(p)
			if cmd=="coins" then self._coins:Give(p,n,"Admin")
			elseif cmd=="takecoins" then local take=math.min(n,have);if take>0 then self._coins:Spend(p,take) end
			else
				local delta=n-have
				if delta>0 then self._coins:Give(p,delta,"Admin") elseif delta<0 then self._coins:Spend(p,-delta) end
			end
		end
		local verb=cmd=="coins" and ("Gave "..commas(n).." coins to ") or cmd=="takecoins" and ("Took "..commas(n).." coins from ") or "Set coins to "..commas(n).." for "
		self:_Say(admin,verb..names(list),GREEN)
		if #list==1 then self:_Say(admin,list[1].Name.." now has "..commas(self._coins:Get(list[1])).." coins",GOLD) end
		return
	end
	if cmd=="tokens" then
		if not self._tokens then return self:_Say(admin,"Tokens aren't available here.",RED) end
		local list,err=self:_Find(admin,args[1]);if not list then return self:_Say(admin,err,RED) end
		local id=TOKEN_ALIAS[string.lower(args[2] or "")]
		if not id then return self:_Say(admin,"Usage: /tokens <player> <spook|life> [amount]",RED) end
		local n=args[3] and amountOf(args[3]) or 1
		if not n or n<1 then return self:_Say(admin,"Usage: /tokens <player> <spook|life> [amount]",RED) end
		for _,p in list do self._tokens:Add(p,id,n) end
		self:_Say(admin,"Gave "..n.." "..(id=="Scare" and "Spook" or "Extra Life").." token"..(n==1 and "" or "s").." to "..names(list),GREEN)
	end
end

function Service:Start()
	local folder=TextChatService:FindFirstChild("AdminCommands")
	if folder then folder:Destroy() end
	folder=Instance.new("Folder");folder.Name="AdminCommands"
	for _,cmd in {"cmds","coins","takecoins","setcoins","balance","tokens"} do
		local c=Instance.new("TextChatCommand");c.Name="Admin_"..cmd;c.PrimaryAlias="/"..cmd
		if cmd=="cmds" then c.SecondaryAlias="/admin" end
		c.Parent=folder
		self._scope:Add(c.Triggered:Connect(function(source,text)
			local p=source and Players:GetPlayerByUserId(source.UserId)
			if not self:IsAdmin(p) then return end
			local args={}
			for w in string.gmatch(text or "","%S+") do table.insert(args,w) end
			table.remove(args,1) -- (the command itself)
			local ok,err=pcall(self._Run,self,p,cmd,args)
			if not ok then warn("[ElevatorHorror] Admin command failed: "..tostring(err));self:_Say(p,"That didn't work - check the console.",RED) end
		end))
	end
	folder.Parent=TextChatService
	self._scope:Add(folder)
	self._scope:Add(Players.PlayerRemoving:Connect(function(p)self._admin[p]=nil end))
end
function Service:Destroy()
	if self._scope then self._scope:Destroy() end
end
return table.freeze(Service)
