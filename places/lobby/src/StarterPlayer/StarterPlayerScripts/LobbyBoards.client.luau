--!nonstrict
-- Lobby boards on the window wall (Oct 18): TOP DONORS, the tip jar (SUPPORT THE DEVELOPERS) and
-- TOP COINS. The boards are authored in Runtime.LobbyEnvironment.Fixtures.LobbyBoard_*; each screen
-- is drawn through a copy in PlayerGui (Adornee = the screen part).
-- INPUT is done here by pointing at the board (a ray from the camera through the mouse / the tap /
-- the centre of the screen on a gamepad) instead of relying on the SurfaceGui receiving clicks:
-- full-screen HUD layers above it were swallowing those, so the tip buttons did nothing.
--   * tip buttons: hover glow, press, Roblox purchase prompt
--   * lists: mouse wheel, touch drag, or the right stick / D-pad while you look at the board
-- Data: Network.Leaderboards (LeaderboardService). Tips are announced in chat in green.
local Players=game:GetService("Players")
local Marketplace=game:GetService("MarketplaceService")
local TweenService=game:GetService("TweenService")
local TextChatService=game:GetService("TextChatService")
local HttpService=game:GetService("HttpService")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local playerGui=player:WaitForChild("PlayerGui")
local net=game.ReplicatedStorage:WaitForChild("Game"):WaitForChild("Network")
local Config=require(game.ReplicatedStorage.Game.Shared.Config.DonationConfig)
local TOP={Color3.fromRGB(176,138,62),Color3.fromRGB(128,132,140),Color3.fromRGB(140,92,60)}
local ROW=Color3.fromRGB(28,27,26)
local REACH=60 -- studs: you can use a board from anywhere in front of it
local function commas(n)
	local s=tostring(math.floor(n));local out=s:reverse():gsub("(%d%d%d)","%1,"):reverse()
	return (out:gsub("^,",""))
end
local function short(n)
	if n>=1e9 then return string.format("%.2fB",n/1e9) elseif n>=1e6 then return string.format("%.2fM",n/1e6) end
	return commas(n)
end
local boards={} -- screen part -> {gui=, kind=, list=, buttons=}
local screens={}
local function mount(board)
	local screen=board:WaitForChild("Screen",30);local gui=screen and screen:WaitForChild("Board",30)
	if not gui then return nil end
	local copy=gui:Clone();copy.Adornee=screen;copy.ResetOnSpawn=false;copy.Parent=playerGui
	gui.Enabled=false
	table.insert(screens,screen)
	return copy,screen
end
------------------------------------------------------------------ leaderboards
local function leaderboard(board,valueName)
	local gui,screen=mount(board);if not gui then return end
	local root=gui.Root;local list=root.List;local template=list.RowTemplate
	local empty=root:FindFirstChild("Empty");local you=root.You.Text
	boards[screen]={gui=gui,kind="list",list=list}
	local rows={}
	local value=net:WaitForChild("Leaderboards",60):WaitForChild(valueName,60)
	local function draw()
		local ok,data=pcall(HttpService.JSONDecode,HttpService,value.Value)
		if not ok or type(data)~="table" then data={} end
		local mine
		for i,e in data do
			local r=rows[i]
			if not r then r=template:Clone();r.Name="Row"..i;r.LayoutOrder=i;r.Parent=list;rows[i]=r end
			r.Visible=true
			r.Rank.Text=tostring(i)
			r.PlayerName.Text=e.n or "?"
			r.Value.Text=short(e.v or 0)
			local img="rbxthumb://type=AvatarHeadShot&id="..tostring(e.i).."&w=48&h=48"
			if r.Avatar.Image~=img then r.Avatar.Image=img end
			r.BackgroundColor3=i<=3 and TOP[i] or ROW
			r.BackgroundTransparency=i<=3 and .35 or 0
			local isMe=e.i==player.UserId
			r.Stroke.Thickness=isMe and 2 or 0;r.Stroke.Transparency=isMe and 0 or 1
			if isMe then mine={i,e.v} end
		end
		for i=#data+1,#rows do rows[i].Visible=false end
		if empty then empty.Visible=#data==0 end
		if mine then you.Text=string.format("YOUR RANK  #%d  ·  %s",mine[1],commas(mine[2]))
		else you.Text=valueName=="Donors" and "Tip to get on the board!" or "Not in the top 100 yet" end
	end
	value.Changed:Connect(draw)
	draw()
end
------------------------------------------------------------------ tip jar
local function tipJar(board)
	local gui,screen=mount(board);if not gui then return end
	local root=gui.Root;local thanks=root:FindFirstChild("Thanks")
	local buttons={}
	for _,btn in root.Grid:GetChildren() do
		if btn:IsA("GuiButton") then
			btn.Interactable=false -- (input comes from the board ray below, never twice)
			local id=btn:GetAttribute("ProductId")
			local scale=Instance.new("UIScale");scale.Parent=btn
			local stroke=btn:FindFirstChildOfClass("UIStroke")
			local b={btn=btn,id=id,scale=scale,stroke=stroke,hover=false}
			table.insert(buttons,b)
			task.spawn(function()
				local ok,info=pcall(Marketplace.GetProductInfo,Marketplace,id,Enum.InfoType.Product)
				local amount=btn:FindFirstChild("Amount")
				if ok and info and info.PriceInRobux and amount then amount.Text="R$ "..commas(info.PriceInRobux);amount.TextSize=info.PriceInRobux>=1000 and 34 or 40 end
			end)
		end
	end
	boards[screen]={gui=gui,kind="tips",buttons=buttons}
	if thanks then
		Marketplace.PromptProductPurchaseFinished:Connect(function(userId,productId,bought)
			if userId~=player.UserId or not bought then return end
			for _,t in Config.Tips do if t.ProductId==productId then
				thanks.Text="Thank you for the tip!";thanks.TextTransparency=0
				task.delay(6,function()TweenService:Create(thanks,TweenInfo.new(1),{TextTransparency=1}):Play()end)
			end end
		end)
	end
end
------------------------------------------------------------------ pointing at a board
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include
-- where on which board the given screen point is (canvas pixels), or nil
local function pick(x,y)
	local cam=workspace.CurrentCamera;if not cam or #screens==0 then return nil end
	params.FilterDescendantsInstances=screens
	local ray=cam:ViewportPointToRay(x,y)
	local hit=workspace:Raycast(ray.Origin,ray.Direction*REACH,params)
	if not hit then return nil end
	local s=hit.Instance;local b=boards[s];if not b then return nil end
	local l=s.CFrame:PointToObjectSpace(hit.Position)
	local pps=b.gui.PixelsPerStud
	-- (the screen faces -X: across the face is +Z, up is +Y)
	return b,Vector2.new((l.Z+s.Size.Z/2)*pps,(s.Size.Y/2-l.Y)*pps)
end
local function inside(g,p)
	local a,z=g.AbsolutePosition,g.AbsoluteSize
	return p.X>=a.X and p.X<=a.X+z.X and p.Y>=a.Y and p.Y<=a.Y+z.Y
end
-- generous: the nearest button within 26 board-pixels (half a stud) counts, so the gaps between
-- buttons and their edges never miss
local function buttonAt(b,p,touch)
	if not b or b.kind~="tips" or not p then return nil end
	local reach=touch and 46 or 26
	local best,bd
	for _,t in b.buttons do
		local a,z=t.btn.AbsolutePosition,t.btn.AbsoluteSize
		local dx=math.max(a.X-p.X,0,p.X-(a.X+z.X));local dy=math.max(a.Y-p.Y,0,p.Y-(a.Y+z.Y))
		local d=math.sqrt(dx*dx+dy*dy)
		if d<=reach and (not bd or d<bd) then best,bd=t,d end
	end
	return best
end
local hovered
local function setHover(t)
	if hovered==t then return end
	if hovered then
		TweenService:Create(hovered.scale,TweenInfo.new(.12,Enum.EasingStyle.Quad),{Scale=1}):Play()
		if hovered.stroke then TweenService:Create(hovered.stroke,TweenInfo.new(.12),{Thickness=2}):Play() end
	end
	hovered=t
	if t then
		TweenService:Create(t.scale,TweenInfo.new(.12,Enum.EasingStyle.Quad),{Scale=1.04}):Play()
		if t.stroke then TweenService:Create(t.stroke,TweenInfo.new(.12),{Thickness=3}):Play() end
	end
end
local function aimPoint()
	local cam=workspace.CurrentCamera
	if UIS.PreferredInput==Enum.PreferredInput.Gamepad or UIS.MouseBehavior==Enum.MouseBehavior.LockCenter then
		return cam.ViewportSize/2
	end
	return UIS:GetMouseLocation()
end
local GuiService=game:GetService("GuiService")
-- never tip through a menu: the shop / locker / gallery panels (or any other on-screen panel or
-- button under your finger or cursor) block the boards
local MENUS={{"ShopControls","ShopPanel"},{"ShopControls","LockerPanel"},{"GalleryPanel","Panel"}}
local function menuOpen()
	for _,m in MENUS do local g=playerGui:FindFirstChild(m[1]);local f=g and g:FindFirstChild(m[2]);if g and g.Enabled and f and f.Visible then return true end end
	return false
end
local function overScreenUi(x,y)
	local inset=GuiService:GetGuiInset()
	for _,o in playerGui:GetGuiObjectsAtPosition(x-inset.X,y-inset.Y) do
		local lc=o:FindFirstAncestorWhichIsA("LayerCollector")
		if lc and lc:IsA("ScreenGui") and o.Visible and (o:IsA("GuiButton") or (o.BackgroundTransparency<.9 and o.Active)) then return true end
	end
	return false
end
local function blocked(x,y)return menuOpen() or (x and overScreenUi(x,y)) end
local lastBuy=0
local function press(t)
	if not t or os.clock()-lastBuy<.6 or menuOpen() then return end
	lastBuy=os.clock()
	TweenService:Create(t.scale,TweenInfo.new(.06),{Scale=.95}):Play()
	task.delay(.08,function()TweenService:Create(t.scale,TweenInfo.new(.12),{Scale=hovered==t and 1.04 or 1}):Play()end)
	if type(t.id)=="number" then pcall(Marketplace.PromptProductPurchase,Marketplace,player,t.id) end
end
local function scroll(b,dy)
	if not b or b.kind~="list" then return end
	local l=b.list
	local max=math.max(0,l.AbsoluteCanvasSize.Y-l.AbsoluteWindowSize.Y)
	l.CanvasPosition=Vector2.new(0,math.clamp(l.CanvasPosition.Y+dy,0,max))
end
local drag -- {board,lastY,moved}
UIS.InputBegan:Connect(function(input)
	local t=input.UserInputType
	if t==Enum.UserInputType.MouseButton1 then
		if UIS.TouchEnabled and not UIS.MouseEnabled then return end -- (phones: handled as a touch below)
		local p=aimPoint();if blocked(p.X,p.Y) then return end
		local b,c=pick(p.X,p.Y);press(buttonAt(b,c))
	elseif t==Enum.UserInputType.Touch then
		-- (a touch's Position is measured below the top bar; the camera ray needs whole-screen
		-- coordinates - without this every tap landed a little ABOVE the finger, missing the top row)
		local inset=GuiService:GetGuiInset()
		local x,y=input.Position.X+inset.X,input.Position.Y+inset.Y
		if blocked(x,y) then return end
		local b,c=pick(x,y)
		if b then drag={board=b,lastY=input.Position.Y,startY=input.Position.Y,canvas=c,touch=true} end
	elseif input.KeyCode==Enum.KeyCode.ButtonA or input.KeyCode==Enum.KeyCode.ButtonR2 then
		local p=aimPoint();local b,c=pick(p.X,p.Y);press(buttonAt(b,c))
	end
end)
UIS.InputChanged:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseWheel then
		local p=UIS:GetMouseLocation();local b=pick(p.X,p.Y)
		scroll(b,-input.Position.Z*62)
	elseif input.UserInputType==Enum.UserInputType.Touch and drag then
		local dy=input.Position.Y-drag.lastY;drag.lastY=input.Position.Y
		scroll(drag.board,-dy*1.6)
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.Touch and drag then
		-- a tap (no real drag) on a tip button buys
		if math.abs(input.Position.Y-drag.startY)<18 then press(buttonAt(drag.board,drag.canvas,true)) end
		drag=nil
	end
end)
RunService.RenderStepped:Connect(function(dt)
	if #screens==0 then return end
	local p=aimPoint();local b,c
	if not menuOpen() then b,c=pick(p.X,p.Y) end
	setHover(buttonAt(b,c))
	-- gamepad: right stick / D-pad scrolls the list you are looking at
	if b and b.kind=="list" and UIS.PreferredInput==Enum.PreferredInput.Gamepad then
		local dy=0
		for _,s in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if s.KeyCode==Enum.KeyCode.Thumbstick2 and math.abs(s.Position.Y)>.2 then dy-=s.Position.Y*600*dt end
		end
		if UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1,Enum.KeyCode.DPadDown) then dy+=500*dt end
		if UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1,Enum.KeyCode.DPadUp) then dy-=500*dt end
		if dy~=0 then scroll(b,dy) end
	end
end)
------------------------------------------------------------------ chat announcement
task.spawn(function()
	local tip=net:WaitForChild("Tip",60);if not tip then return end
	tip.OnClientEvent:Connect(function(name,robux)
		local channels=TextChatService:FindFirstChild("TextChannels");local general=channels and channels:FindFirstChild("RBXGeneral")
		if general and type(name)=="string" and type(robux)=="number" then
			local safe=name:gsub("[<>&]","")
			general:DisplaySystemMessage(string.format('<font color="%s"><b>%s</b> has tipped %s Robux! Thank you!</font>',Config.TipColor,safe,commas(robux)))
		end
	end)
end)
------------------------------------------------------------------ rank-up announcements
-- Someone reached #1, the top 10 or the top 100 on a board: a gold line in chat and a short fanfare
-- for everyone in the lobby (LeaderboardService fires Network.BoardAnnounce once per rank-up).
local GOLD_HEX="#E2B651"
local FANFARE="rbxassetid://1840140234"
local fanfare=Instance.new("Sound");fanfare.Name="BoardFanfare";fanfare.SoundId=FANFARE;fanfare.Volume=.5;fanfare.Parent=game:GetService("SoundService")
task.spawn(function()pcall(function()game:GetService("ContentProvider"):PreloadAsync({fanfare})end)end) -- (loaded before the first rank-up)
local function playFanfare()
	fanfare.Volume=.5;fanfare.TimePosition=0;fanfare:Play()
	-- (just the opening flourish: it fades out after ~4 s)
	task.delay(3.4,function()TweenService:Create(fanfare,TweenInfo.new(1.2),{Volume=0}):Play();task.delay(1.25,function()fanfare:Stop()end)end)
end
task.spawn(function()
	local ann=net:WaitForChild("BoardAnnounce",60);if not ann then return end
	ann.OnClientEvent:Connect(function(name,board,band,rank)
		if type(name)~="string" or type(board)~="string" or type(band)~="string" then return end
		local channels=TextChatService:FindFirstChild("TextChannels");local general=channels and channels:FindFirstChild("RBXGeneral")
		local who=name:gsub("[<>&]","")
		local text
		if band=="#1" then text=string.format("👑 <b>%s</b> is now <b>#1</b> on %s!",who,board)
		elseif band=="TOP 10" then text=string.format("⭐ <b>%s</b> made the <b>TOP 10</b> on %s! (#%d)",who,board,tonumber(rank) or 10)
		else text=string.format("<b>%s</b> made the <b>TOP 100</b> on %s! (#%d)",who,board,tonumber(rank) or 100) end
		if general then general:DisplaySystemMessage(string.format('<font color="%s">%s</font>',GOLD_HEX,text)) end
		playFanfare()
	end)
end)
------------------------------------------------------------------ start
local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",60)
local fixtures=env and env:WaitForChild("Fixtures",30)
if not fixtures then return end
task.spawn(leaderboard,fixtures:WaitForChild("LobbyBoard_TopDonors",30),"Donors")
task.spawn(leaderboard,fixtures:WaitForChild("LobbyBoard_TopCoins",30),"Coins")
task.spawn(tipJar,fixtures:WaitForChild("LobbyBoard_Donate",30))
------------------------------------------------------------------ no wall climbing in the lobby
-- (stacked trims and ledges on the walls read as a ladder to the Humanoid: never climb here)
local function noClimb(char)
	local h=char:WaitForChild("Humanoid",10)
	if h then h:SetStateEnabled(Enum.HumanoidStateType.Climbing,false) end
end
if player.Character then task.spawn(noClimb,player.Character) end
player.CharacterAdded:Connect(noClimb)
