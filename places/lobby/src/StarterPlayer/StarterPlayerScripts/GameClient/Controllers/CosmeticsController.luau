--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- Client side of the unlockable cosmetics.
--  * chat: an equipped title shows in front of the sender's name, e.g. [Secret] in purple
--  * lobby: secret-room pickups you already own vanish for you (other players still see theirs)
--  * a short FOUND card when you pick one up (authored in StarterGui.CosmeticToast > Card)
local Players=game:GetService("Players")
local TextChatService=game:GetService("TextChatService")
local TweenService=game:GetService("TweenService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Responsive=require(Shared.Utilities.ResponsiveScale)
local Config=require(Shared.Config.CosmeticsConfig)
local Controller={};Controller.__index=Controller
local function entry(slot,id)
	for _,e in Config[slot] or {} do if e.Id==id then return e end end
end
function Controller.Owns(player,slot,id)
	if id=="Default" then return true end
	local owned=player:GetAttribute("EHOwnedCosmetics")
	if type(owned)~="string" then return false end
	for key in owned:gmatch("[^,]+") do if key==slot..":"..id then return true end end
	return false
end
function Controller.OwnsAll(player,grants)
	for _,g in grants do if not Controller.Owns(player,g[1],g[2]) then return false end end
	return true
end

function Controller.new(player,gui)
	return setmetatable({Name="CosmeticsController",Dependencies={},_player=player,_gui=gui,_hidden={}},Controller)
end
function Controller:Init()
	self._scope=Scope.new()
	task.spawn(function()
		local g=AuthoredGui.Get(self._gui,"CosmeticToast")
		if not g then return end
		Responsive.WatchDesignSize(g,900,506,.4,2.5)
		local card=g:WaitForChild("Card")
		local stroke=card:FindFirstChildOfClass("UIStroke")
		-- remember the look authored in Studio, then start hidden
		local labels={}
		for _,l in card:GetChildren() do if l:IsA("TextLabel") then labels[l]=l.TextTransparency;l.TextTransparency=1 end end
		local kicker=card:FindFirstChild("Kicker")
		local t={card=card,bg=card.BackgroundTransparency,stroke=stroke,strokeT=stroke and stroke.Transparency,labels=labels,title=card:FindFirstChild("ItemName"),
			kicker=kicker,kickerText=kicker and kicker.Text}
		card.BackgroundTransparency=1;if stroke then stroke.Transparency=1 end;card.Visible=false
		self._toast=t
	end)
end
function Controller:_Toast(name,kicker)
	local t=self._toast;if not t then return end
	if t.kicker then t.kicker.Text=kicker or t.kickerText end
	local spec=Config.Collectibles[name]
	if t.title then t.title.Text=spec and spec.Name or name end
	t.card.Visible=true
	local info=TweenInfo.new(.35,Enum.EasingStyle.Quint,Enum.EasingDirection.Out)
	TweenService:Create(t.card,info,{BackgroundTransparency=t.bg}):Play()
	if t.stroke then TweenService:Create(t.stroke,info,{Transparency=t.strokeT}):Play() end
	for l,v in t.labels do TweenService:Create(l,info,{TextTransparency=v}):Play() end
	local token={};self._toastToken=token
	task.delay(4.5,function()
		if self._toastToken~=token then return end
		local out=TweenInfo.new(.6)
		TweenService:Create(t.card,out,{BackgroundTransparency=1}):Play()
		if t.stroke then TweenService:Create(t.stroke,out,{Transparency=1}):Play() end
		for l in t.labels do TweenService:Create(l,out,{TextTransparency=1}):Play() end
		task.delay(.65,function()if self._toastToken==token then t.card.Visible=false end end)
	end)
end
-- pickups you already own: hidden for you only
function Controller:_Hide(model)
	if self._hidden[model] then return end
	self._hidden[model]=true
	for _,d in model:GetDescendants() do
		if d:IsA("BasePart") then d.Transparency=1;d.CanQuery=false
		elseif d:IsA("Light") then d.Enabled=false
		elseif d:IsA("SurfaceGui") or d:IsA("Decal") then if d:IsA("Decal") then d.Transparency=1 else d.Enabled=false end
		elseif d:IsA("ProximityPrompt") then d.Enabled=false end
	end
	-- the server adds the prompt a moment after the model replicates
	self._scope:Add(model.DescendantAdded:Connect(function(d)if d:IsA("ProximityPrompt") then d.Enabled=false end end))
end
function Controller:_WatchPickups(items)
	local function refresh()
		for _,m in items:GetChildren() do
			local spec=Config.Collectibles[m.Name]
			if spec and Controller.OwnsAll(self._player,spec.Grants) then self:_Hide(m) end
		end
	end
	self._scope:Add(self._player:GetAttributeChangedSignal("EHOwnedCosmetics"):Connect(refresh))
	self._scope:Add(items.ChildAdded:Connect(function()task.wait();refresh()end))
	refresh()
end
function Controller:Start()
	-- chat titles
	TextChatService.OnIncomingMessage=function(message)
		local source=message.TextSource
		local sender=source and Players:GetPlayerByUserId(source.UserId)
		local id=sender and sender:GetAttribute("EHTitle")
		local e=type(id)=="string" and id~="" and entry("Title",id)
		if not e or not e.Color then return nil end
		local label=e.Label
		if e.Leaderboard then
			-- leaderboard titles carry the live rank; dropped off the board = no tag
			local r=sender:GetAttribute(e.Leaderboard=="Donor" and "EHDonorRank" or "EHCoinRank")
			if type(r)~="number" then return nil end
			label=(r<=10 and ("#"..r) or "TOP 100").." "..(e.Leaderboard=="Donor" and "DONOR" or "COINS")
		end
		local props=Instance.new("TextChatMessageProperties")
		props.PrefixText=string.format('<font color="%s">[%s]</font> %s',e.Color,label,message.PrefixText)
		return props
	end
	self._scope:Add(function()TextChatService.OnIncomingMessage=nil end)
	local remote=game.ReplicatedStorage.Game.Network:WaitForChild("Cosmetics",15)
	if remote then
		self._scope:Add(remote.OnClientEvent:Connect(function(kind,name)
			if kind=="Found" then self:_Toast(name)
			elseif kind=="Unlocked" then self:_Toast(name,"U N L O C K E D") end
		end))
	end
	task.spawn(function()
		local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",30)
		local room=env and env:WaitForChild("SecretRoom",10)
		local items=room and room:WaitForChild("Collectibles",10)
		if items then self:_WatchPickups(items) end
	end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
