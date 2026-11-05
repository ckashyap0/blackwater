--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Http=game:GetService("HttpService")
local GuiService=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local TeleportService=game:GetService("TeleportService")
local FADE_LEAD=.9 -- seconds before departure the screen starts going black
local FADE_HOLD=1.4 -- minimum time to stay black if the departure doesn't happen (e.g. Studio)
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Responsive=require(game.ReplicatedStorage.Game.Shared.Utilities.ResponsiveScale)
local PanelFade=require(game.ReplicatedStorage.Game.Shared.Utilities.PanelFade)
local Controller={};Controller.__index=Controller
-- Palette: off-white text and thin white borders on black glass; green when ready.
local C={text=Color3.fromRGB(235,232,225),faint=Color3.fromRGB(95,93,88),line=Color3.fromRGB(235,232,225),button=Color3.new(0,0,0),
	green=Color3.fromRGB(110,220,130),greenBg=Color3.fromRGB(14,48,24)}
function Controller.new(p,gui)return setmetatable({Name="PartyController",Dependencies={"StateController","FocusController"},_player=p,_gui=gui},Controller)end
function Controller:Init(deps)
	self._state=deps.StateController;self._focus=deps.FocusController;self._scope=Scope.new()
	-- BoardingControls lives under StarterGui and is auto-cloned into PlayerGui; this only
	-- references it. Layout: Crew -> Body -> Title, CapacityRow(Less/Capacity/More), Access,
	-- Ready, Countdown, Exit. Edit visuals directly in Studio.
	local gui=AuthoredGui.Get(self._gui,"BoardingControls")
	local panel=gui:WaitForChild("Crew");self._panel=panel
	local body=panel:WaitForChild("Body")
	self._title=body:WaitForChild("Title")
	local cap=body:WaitForChild("CapacityRow");self._minus=cap:WaitForChild("Less");self._capacity=cap:WaitForChild("Capacity");self._plus=cap:WaitForChild("More")
	self._mode=body:WaitForChild("Access")
	self._ready=body:WaitForChild("Ready");self._readyStroke=self._ready:FindFirstChildOfClass("UIStroke")
	self._countdown=body:WaitForChild("Countdown")
	self._leave=body:WaitForChild("Exit")
	self._reconnect=gui:WaitForChild("Reconnect");self._feedback=gui:WaitForChild("TransferMessage")
	-- One uniform scale off a 16:9 design canvas: identical proportions and placement on every device.
	Responsive.WatchDesignSize(gui,900,506,.4,2.5)
	panel.Visible=false
	self._panelFade=PanelFade.new(panel,function(shown)if shown then self:_Refresh() end end)
	-- the shop / locker panels, so the crew panel can wait for them to finish closing
	local controls=AuthoredGui.Get(self._gui,"ShopControls")
	self._others={controls and controls:FindFirstChild("ShopPanel"),controls and controls:FindFirstChild("LockerPanel")}
	local function configure(delta,access)
		local p=self._party;if p then self._state:SendAction("PartyConfigure",{capacity=math.clamp(p.capacity+delta,1,4),accessMode=access or p.accessMode})end
	end
	local function wire(button,fn)self._scope:Add(button.Activated:Connect(function()if button.Active then fn()end end))end
	wire(self._minus,function()configure(-1)end)
	wire(self._plus,function()configure(1)end)
	wire(self._mode,function()if self._party then configure(0,self._party.accessMode=="Public" and "FriendsOfHost" or "Public")end end)
	wire(self._ready,function()if self._party then self._state:SendAction("PartyReady",{ready=not self._party.ready[tostring(self._player.UserId)]})end end)
	wire(self._leave,function()self._state:SendAction("PartyLeave",{})end)
	wire(self._reconnect,function()self._state:SendAction(self._player:GetAttribute("EHContext")=="Results" and "ReturnLobby" or "ReconnectRun",{})end)
	self._ready.NextSelectionDown=self._leave;self._leave.NextSelectionUp=self._ready
	self:_BuildFade()
end
-- Full-screen black "GOING DOWN" card shown as the countdown ends. The same card is handed to
-- TeleportService so the screen stays black straight through the teleport into the descent.
function Controller:_BuildFade()
	-- authored in StarterGui.DepartureFade: Black + Panel (Title, Underline, Subtitle, Status). It is the exact
	-- same card as the Game place's loading screen (ReplicatedFirst.LoadingScreen.BlackwaterLoading), so the
	-- teleport goes black -> card -> the same card, with nothing jumping. Keep the two in step if you edit one.
	self._fade=AuthoredGui.Get(self._gui,"DepartureFade");self._fade.Enabled=false
	self._fadeLevel=0
	local panel=self._fade:WaitForChild("Panel")
	self._fadeScale=panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale",panel)
	self._fadeStatus=panel:FindFirstChild("Status")
	self._fadeWords={};self._fadeLines={}
	for _,o in panel:GetChildren() do
		if o:IsA("TextLabel") then self._fadeWords[o]=o.TextTransparency elseif o:IsA("Frame") then self._fadeLines[o]=o.BackgroundTransparency end
	end
	self._fadeBlack=self._fade:WaitForChild("Black").BackgroundTransparency
end
-- same sizing rule as the Game loading screen: scale the card with the screen width
local function cardScale(width)return math.clamp(width/420,.7,1.25)end
local DOTS={'Loading.  ','Loading.. ','Loading...'}
function Controller:_TeleportCard()
	local copy=self._fade:Clone();copy.Enabled=true
	copy.Black.BackgroundTransparency=self._fadeBlack
	for _,o in copy.Panel:GetChildren() do
		local src=self._fade.Panel:FindFirstChild(o.Name)
		if o:IsA("TextLabel") and src then o.TextTransparency=self._fadeWords[src] or 0
		elseif o:IsA("Frame") and src then o.BackgroundTransparency=self._fadeLines[src] or 0 end
	end
	local scale=copy.Panel:FindFirstChildOfClass("UIScale")
	if scale then scale.Scale=self._fadeScale.Scale end
	if copy.Panel:FindFirstChild("Status") then copy.Panel.Status.Text=DOTS[3] end
	return copy
end
function Controller:_StepFade(dt)
	local party=self._party
	local now=workspace:GetServerTimeNow()
	local target=0
	if party then
		local env=workspace:FindFirstChild("Runtime") and workspace.Runtime:FindFirstChild("LobbyEnvironment")
		local bay=env and env:FindFirstChild("Bay"..tostring(party.bayId))
		local departAt=bay and bay:GetAttribute("DepartAt")
		if party.state~="Open" then target=1
		elseif departAt then target=math.clamp((now-(departAt-FADE_LEAD))/FADE_LEAD,0,1) end
	end
	local width=self._fade.AbsoluteSize.X
	if width<=0 and workspace.CurrentCamera then width=workspace.CurrentCamera.ViewportSize.X end
	self._fadeScale.Scale=cardScale(width)
	if target>=1 and not self._blackSince then
		self._blackSince=os.clock()
		pcall(function()TeleportService:SetTeleportGui(self:_TeleportCard())end)
	elseif target<1 and self._blackSince then
		-- departure didn't happen: hold black briefly, then fade back in
		if os.clock()-self._blackSince<FADE_HOLD then target=1 else self._blackSince=nil end
	end
	local rate=target>self._fadeLevel and 1/FADE_LEAD or 1.6
	if target>self._fadeLevel then self._fadeLevel=math.min(target,self._fadeLevel+dt*rate*1.5)
	else self._fadeLevel=math.max(target,self._fadeLevel-dt*rate) end
	local k=self._fadeLevel
	self._fade.Enabled=k>0
	if k<=0 then return end
	self._fade.Black.BackgroundTransparency=1-(1-self._fadeBlack)*k
	local textAlpha=math.clamp((k-.55)/.45,0,1)
	for o,base in self._fadeWords do o.TextTransparency=1-(1-base)*textAlpha end
	for o,base in self._fadeLines do o.BackgroundTransparency=1-(1-base)*textAlpha end
	if self._fadeStatus then self._fadeStatus.Text=DOTS[(math.floor(os.clock()/.45)%#DOTS)+1] end
end
-- Stepping onto an elevator pad while the shop or locker is open: that panel fades out first, then
-- the crew panel fades in where it was - one hand-off, never two panels on top of each other.
function Controller:_ShowPanel(show)
	if show==self._want then return end
	self._want=show
	self._showToken=(self._showToken or 0)+1
	local token=self._showToken
	if not show then self._panelFade:Show(false) return end
	task.spawn(function()
		local t0=os.clock()
		while os.clock()-t0<.5 do
			local busy=false
			for _,o in self._others do if o and o.Visible then busy=true end end
			if not busy then break end
			task.wait()
		end
		if self._showToken==token and self._want then self._panelFade:Show(true) end
	end)
end
function Controller:_Refresh()
	local p=self._player;local raw=p:GetAttribute("EHPartyView");local party
	if raw then local ok,value=pcall(function()return Http:JSONDecode(raw)end);if ok then party=value end end
	self._party=party;local appeared=party~=nil and not self._panelFade:IsShown()
	self:_ShowPanel(party~=nil)
	-- other buttons step aside + light background blur while the elevator panel is up
	if self._focus then self._focus:Set("Party",party~=nil) end
	if party then
		local host=party.hostUserId==p.UserId;local open=party.state=="Open"
		local bayId=tostring(party.bayId)
		self._title.Text="ELEVATOR "..(bayId:match("%d+") or bayId)
		self._capacity.Text=party.capacity==1 and "1 player" or (party.capacity.." players")
		self._mode.Text=party.accessMode=="Public" and "Anyone can join" or "Friends only"
		local function enable(b,value)b.Active=value;b.Selectable=value;b.TextColor3=value and C.text or C.faint end
		enable(self._minus,host and open and party.capacity>#party.members);enable(self._plus,host and open and party.capacity<4);enable(self._mode,host and open);enable(self._ready,open);enable(self._leave,open)
		-- Ready lights up green.
		local isReady=party.ready[tostring(p.UserId)]
		self._ready.Text=isReady and "READY" or "READY UP"
		self._ready.BackgroundColor3=isReady and C.greenBg or C.button
		self._ready.BackgroundTransparency=isReady and .1 or .45
		self._readyStroke.Color=isReady and C.green or C.line;self._readyStroke.Transparency=isReady and 0 or .55
		if isReady and open then self._ready.TextColor3=C.green end
		-- Countdown replaces the old Descend button entirely: the server starts a 10s timer
		-- the instant every crew member is ready, and auto-launches at zero -- no button, no
		-- host action needed. If anyone un-readies, the server cancels it and this goes blank.
		self._countdown.Visible=party.countdown~=nil
		self._countdown.Text=party.countdown and string.format("DESCENDING IN %02d",party.countdown) or ""
		if appeared and Input.PreferredInput==Enum.PreferredInput.Gamepad then GuiService.SelectedObject=self._ready end
	end
	local results=p:GetAttribute("EHContext")=="Results";self._reconnect.Visible=not party and (p:GetAttribute("EHReconnectAvailable")==true or results);self._reconnect.Text=results and "RETURN TO LOBBY" or "REJOIN YOUR CREW"
	self._feedback.Text=p:GetAttribute("EHPartyMessage") or ""
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._panel) and not party then GuiService.SelectedObject=nil end
end
function Controller:Start()
	for _,attr in {"EHPartyView","EHPartyMessage","EHReconnectAvailable","EHContext"}do self._scope:Add(self._player:GetAttributeChangedSignal(attr):Connect(function()self:_Refresh()end))end;self:_Refresh()
	self._scope:Add(RunService.RenderStepped:Connect(function(dt)self:_StepFade(dt)end))
end
function Controller:Destroy()
	if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
