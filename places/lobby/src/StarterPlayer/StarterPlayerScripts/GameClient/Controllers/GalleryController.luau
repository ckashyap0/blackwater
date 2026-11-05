--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
-- Lobby Gallery. Hold E on a mannequin (press-and-hold the prompt on phones/tablets, hold X on gamepad)
-- to open a slim panel with one BUY button per clothing item in that mannequin's outfit
-- (Config.ClothingCatalog). A button opens Roblox's own purchase prompt; items the player already owns
-- read OWNED in green. Everything here is local to the player.
local Marketplace=game:GetService("MarketplaceService")
local GuiService=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local Shared=game.ReplicatedStorage.Game.Shared
local Scope=require(Shared.Utilities.CleanupScope)
local Responsive=require(Shared.Utilities.ResponsiveScale)
local Catalog=require(Shared.Config.ClothingCatalog)
local Controller={};Controller.__index=Controller
local SERIF="rbxasset://fonts/families/AccanthisADFStd.json"
local MONO="rbxasset://fonts/families/RobotoMono.json"
local WHITE=Color3.fromRGB(235,232,225)
local FAINT=Color3.fromRGB(150,146,138)
local GREEN=Color3.fromRGB(110,220,130)
local INK=Color3.fromRGB(6,6,6)
local function new(c,p,parent)local i=Instance.new(c)for k,v in p do i[k]=v end;i.Parent=parent;return i end

function Controller.new(player,gui)
	return setmetatable({Name="GalleryController",Dependencies={"FocusController","ShopController"},_player=player,_gui=gui,
		_owned={},_prices={},_checking={},_buttons={},_prompts={}},Controller)
end
function Controller:Init(deps)
	self._shop=deps.ShopController
	self._focus=deps.FocusController
	self._scope=Scope.new()
	-- The panel is authored in StarterGui.GalleryPanel (edit it there):
	--   Panel > Header (Kicker, Title, Underline, Close), Items > ItemTemplate (Label, Price, Buy)
	-- ItemTemplate is copied once per clothing item; its look is the "BUY" look, OWNED turns it green.
	local gui=AuthoredGui.Get(self._gui,"GalleryPanel")
	Responsive.WatchDesignSize(gui,900,506,.4,2.5)
	local panel=gui:WaitForChild("Panel")
	local head=panel:WaitForChild("Header")
	self._title=head:WaitForChild("Title")
	self._close=head:WaitForChild("Close")
	self._rows=panel:WaitForChild("Items")
	self._template=self._rows:WaitForChild("ItemTemplate");self._template.Visible=false
	local tb=self._template:WaitForChild("Buy")
	local ts=tb:FindFirstChildOfClass("UIStroke")
	self._look={text=tb.TextColor3,stroke=ts and ts.Color or WHITE,strokeT=ts and ts.Transparency or .55}
	panel.Visible=false
	self._panel=panel
	self._scope:Add(self._close.Activated:Connect(function()self:Close()end))
	self._scope:Add(Input.InputBegan:Connect(function(input)
		if panel.Visible and (input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB) then self:Close() end
	end))
end

-- ===== rows =====
function Controller:_Row(order,item)
	local row=self._template:Clone()
	row.Name=item.Kind;row.LayoutOrder=order;row.Visible=true
	row.Label.Text=string.upper(item.Label)
	local button=row.Buy
	local stroke=button:FindFirstChildOfClass("UIStroke")
	local entry={item=item,button=button,stroke=stroke,price=row.Price}
	self._buttons[item.AssetId]=entry
	button.MouseEnter:Connect(function()if self._owned[item.AssetId]==false and stroke then stroke.Transparency=.15 end end)
	button.MouseLeave:Connect(function()if self._owned[item.AssetId]==false and stroke then stroke.Transparency=self._look.strokeT end end)
	button.Activated:Connect(function()self:_Buy(item)end)
	self:_Paint(entry)
	row.Parent=self._rows
	return button
end
function Controller:_Paint(entry)
	local id=entry.item.AssetId
	local owned=self._owned[id]
	local b,st=entry.button,entry.stroke
	if owned then
		b.Text="OWNED";b.TextColor3=GREEN
		if st then st.Color=GREEN;st.Transparency=.35 end
	elseif owned==false then
		b.Text="BUY "..string.upper(entry.item.Kind);b.TextColor3=self._look.text
		if st then st.Color=self._look.stroke;st.Transparency=self._look.strokeT end
	else
		-- still checking: neutral, never a wrong BUY that flips a moment later
		b.Text="· · ·";b.TextColor3=FAINT
		if st then st.Color=self._look.stroke;st.Transparency=.75 end
	end
	local p=self._prices[id]
	entry.price.Text=(p and p>0) and ("R$ "..p) or ""
end

-- ===== data (owned / price): fetched for every catalog item as soon as you join, then cached =====
function Controller:_Fetch(item)
	local id=item.AssetId
	if self._owned[id]==nil and not self._checking[id] then
		self._checking[id]=true
		task.spawn(function()
			for attempt=1,3 do
				local ok,has=pcall(function()return Marketplace:PlayerOwnsAsset(self._player,id)end)
				if ok then self._owned[id]=self._owned[id] or has;break end
				task.wait(attempt)
			end
			self._checking[id]=nil
			local e=self._buttons[id];if e and e.button.Parent then self:_Paint(e) end
		end)
	end
	if self._prices[id]==nil then
		self._prices[id]=false
		task.spawn(function()
			local ok,info=pcall(function()return Marketplace:GetProductInfo(id,Enum.InfoType.Asset)end)
			self._prices[id]=ok and info and (info.PriceInRobux or 0) or nil
			local e=self._buttons[id];if e and e.button.Parent then self:_Paint(e) end
		end)
	end
end
function Controller:_Prefetch()
	for _,outfit in Catalog.Outfits do
		for _,item in outfit.Items do self:_Fetch(item) end
	end
end
function Controller:_Buy(item)
	if self._owned[item.AssetId]~=false then return end
	pcall(function()Marketplace:PromptPurchase(self._player,item.AssetId)end)
end

-- ===== open / close =====
function Controller:Open(exhibit)
	local key=exhibit:GetAttribute("Outfit")
	local outfit=key and Catalog.Outfits[key]
	if not outfit then return end
	if self._shop then self._shop:SetOpen(false) end
	for _,c in self._rows:GetChildren() do if c:IsA("GuiObject") and c~=self._template then c:Destroy() end end
	table.clear(self._buttons)
	self._title.Text=outfit.Name
	local first
	for i,item in outfit.Items do
		local b=self:_Row(i,item);first=first or b
		self:_Fetch(item)
	end
	self._exhibit=exhibit
	for m,pp in self._prompts do pp.Enabled=(m~=exhibit) end
	local panel=self._panel
	panel.Position=UDim2.new(.5,0,.5,10)
	panel.Visible=true
	self._focus:Set("Gallery",true)
	TweenService:Create(panel,TweenInfo.new(.22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Position=UDim2.fromScale(.5,.5)}):Play()
	if Input.PreferredInput==Enum.PreferredInput.Gamepad then GuiService.SelectedObject=first end
end
function Controller:Close()
	if not self._panel.Visible then return end
	self._panel.Visible=false
	self._focus:Set("Gallery",false)
	self._exhibit=nil
	for _,pp in self._prompts do pp.Enabled=true end
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._panel) then GuiService.SelectedObject=nil end
end

-- ===== mannequin prompts =====
function Controller:_Hook(exhibit)
	if self._prompts[exhibit] or not exhibit:IsA("Model") then return end
	local key=exhibit:GetAttribute("Outfit")
	local outfit=key and Catalog.Outfits[key]
	if not outfit then return end
	local rig=exhibit:FindFirstChild("Rig")
	local anchor=(rig and rig:FindFirstChild("HumanoidRootPart")) or exhibit:FindFirstChild("Plinth")
	if not anchor then return end
	local pp=new("ProximityPrompt",{Name="GalleryPrompt",ActionText="View Outfit",ObjectText=outfit.Name,HoldDuration=Catalog.HoldSeconds,
		MaxActivationDistance=9,RequiresLineOfSight=false,KeyboardKeyCode=Enum.KeyCode.E},anchor)
	self._prompts[exhibit]=pp
	self._scope:Add(pp)
	self._scope:Add(pp.Triggered:Connect(function()self:Open(exhibit)end))
end
function Controller:Start()
	self:_Prefetch()
	-- purchases made through our buttons flip that button to OWNED straight away
	self._scope:Add(Marketplace.PromptPurchaseFinished:Connect(function(player,id,bought)
		if player==self._player and bought then
			self._owned[id]=true
			local e=self._buttons[id];if e and e.button.Parent then self:_Paint(e) end
		end
	end))
	-- in an elevator party the panel goes away
	self._scope:Add(self._player:GetAttributeChangedSignal("EHPartyView"):Connect(function()
		if self._player:GetAttribute("EHPartyView")~=nil then self:Close() end
	end))
	-- walk away and it closes
	self._scope:Add(RunService.Heartbeat:Connect(function()
		local ex=self._exhibit
		if not ex then return end
		local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
		local plinth=ex:FindFirstChild("Plinth")
		if not ex.Parent or (root and plinth and (root.Position-plinth.Position).Magnitude>Catalog.CloseDistance) then self:Close() end
	end))
	task.spawn(function()
		local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",30)
		local gallery=env and env:WaitForChild("Gallery",10)
		local exhibits=gallery and gallery:WaitForChild("Exhibits",10)
		if not exhibits then return end
		for _,ex in exhibits:GetChildren() do self:_Hook(ex) end
		self._scope:Add(exhibits.ChildAdded:Connect(function(ex)task.wait();self:_Hook(ex)end))
	end)
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
