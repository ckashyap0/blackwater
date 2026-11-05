--!nonstrict
local AuthoredGui=require(game.ReplicatedStorage.Game.Shared.Utilities.AuthoredGui)
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local GuiService=game:GetService("GuiService")
local Input=game:GetService("UserInputService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local C={bg=Color3.fromRGB(29,35,33),surface=Color3.fromRGB(43,51,47),text=Color3.fromRGB(232,236,240),muted=Color3.fromRGB(150,160,174),line=Color3.fromRGB(88,98,112),primary=Color3.fromRGB(42,48,59),readyBg=Color3.fromRGB(44,57,54),readyBorder=Color3.fromRGB(160,188,172)}
function Controller.new(p,gui)return setmetatable({Name="PartyController",Dependencies={"StateController"},_player=p,_gui=gui},Controller)end
function Controller:Init(deps)
	self._state=deps.StateController;self._scope=Scope.new()
    local shared=game.ReplicatedStorage.Game.Shared
    local role=shared.Parent:GetAttribute("PlaceRole")or require(shared.Config.PlaceConfig).Resolve(game.PlaceId,game:GetService("RunService"):IsStudio(),workspace:GetAttribute("EHStudioPlaceRole"))
    if role=="Game"then
        self._gameOnly=true
        -- authored in StarterGui.DescentReturn (ReturnButton)
        local gui=AuthoredGui.Get(self._gui,"DescentReturn")
        local button=gui:WaitForChild("ReturnButton");button.Visible=false;self._return=button
        self._scope:Add(button.Activated:Connect(function()self._state:SendAction("ReturnLobby",{})end))
        return
    end
	-- BoardingControls now lives permanently under StarterGui (Explorer > StarterGui > BoardingControls),
	-- which Roblox auto-clones into every player's PlayerGui on join -- we just reference that copy
	-- rather than cloning it ourselves. To live-preview it while editing in Studio: select
	-- StarterGui.BoardingControls.Crew and toggle its Visible property. Just remember to set it back
	-- to false before playtesting/publishing, or it'll show permanently even with no active party.
	-- We do NOT own this instance (no self._scope:Add on the gui itself) -- it persists for the
	-- whole PlayerGui lifetime, not just this Controller's, so Destroy() below only tears down our
	-- event connections, never the gui itself.
	local gui=self._gui:WaitForChild("BoardingControls")
	local panel=gui:WaitForChild("Crew");self._panel=panel;self._limit=panel:WaitForChild("SizeLimit")
	local body=panel:WaitForChild("Body");local footer=panel:WaitForChild("Footer");local header=body:WaitForChild("Header")
	self._title=header:WaitForChild("Title");self._subtitle=header:WaitForChild("Subtitle")
	self._host=body:WaitForChild("Host")
	local cap=body:WaitForChild("CapacityRow");self._minus=cap:WaitForChild("Less");self._capacity=cap:WaitForChild("Capacity");self._plus=cap:WaitForChild("More")
	self._mode=body:WaitForChild("Access");self._message=body:WaitForChild("Message")
	self._ready=footer:WaitForChild("Ready");self._readyStroke=self._ready:FindFirstChildOfClass("UIStroke")
	local actions=footer:WaitForChild("Actions");self._launch=actions:WaitForChild("Launch");self._leave=actions:WaitForChild("Exit")
	self._reconnect=gui:WaitForChild("Reconnect");self._feedback=gui:WaitForChild("TransferMessage")
	panel.Visible=false
	local function configure(delta,access)
		local p=self._party;if p then self._state:SendAction("PartyConfigure",{capacity=math.clamp(p.capacity+delta,1,4),accessMode=access or p.accessMode})end
	end
	local function wire(button,fn)self._scope:Add(button.Activated:Connect(function()if button.Active then fn()end end))end
	wire(self._minus,function()configure(-1)end)
	wire(self._plus,function()configure(1)end)
	wire(self._mode,function()if self._party then configure(0,self._party.accessMode=="Public" and "FriendsOfHost" or "Public")end end)
	wire(self._ready,function()if self._party then self._state:SendAction("PartyReady",{ready=not self._party.ready[tostring(self._player.UserId)]})end end)
	wire(self._launch,function()self._state:SendAction("PartyLaunch",{})end)
	wire(self._leave,function()self._state:SendAction("PartyLeave",{})end)
	wire(self._reconnect,function()self._state:SendAction(self._player:GetAttribute("EHContext")=="Results" and "ReturnLobby" or "ReconnectRun",{})end)
	self._ready.NextSelectionDown=self._launch;self._launch.NextSelectionRight=self._leave;self._leave.NextSelectionLeft=self._launch;self._leave.NextSelectionUp=self._ready;self._launch.NextSelectionUp=self._ready;self._ready.NextSelectionRight=self._leave
end
function Controller:_Refresh()
    if self._gameOnly then self._return.Visible=self._player:GetAttribute("EHContext")=="Results";return end
	local p=self._player;local raw=p:GetAttribute("EHPartyView");local party
	if raw then local ok,value=pcall(function()return Http:JSONDecode(raw)end);if ok then party=value end end
	self._party=party;local appeared=party~=nil and not self._panel.Visible;self._panel.Visible=party~=nil
	if party then
		local host=party.hostUserId==p.UserId;local open=party.state=="Open";local count=0
		for _,id in party.members do if party.ready[tostring(id)] then count+=1 end end
		local bayId=tostring(party.bayId)
		self._title.Text=open and ("ELEVATOR "..(bayId:match("%d+") or bayId)) or "DEPARTING"
		self._subtitle.Text=#party.members.."/"..party.capacity.." players   â€¢   "..count.." ready"
		local hostPlayer=Players:GetPlayerByUserId(party.hostUserId)
		self._host.Text="Host: "..(hostPlayer and hostPlayer.DisplayName or "Teammate")
		self._capacity.Text=party.capacity==1 and "Solo" or (party.capacity.." players");self._mode.Text=party.accessMode=="Public" and "Anyone can join" or "Friends only"
		local isReady=party.ready[tostring(p.UserId)]
		self._ready.Text=isReady and "READY" or "I'M READY";self._ready.BackgroundColor3=isReady and C.readyBg or C.surface;self._readyStroke.Color=isReady and C.readyBorder or C.line
		local function enable(b,value)b.Active=value;b.Selectable=value;b.AutoButtonColor=value;b.TextColor3=value and C.text or C.muted;b.BackgroundTransparency=value and 0 or .4 end
		enable(self._minus,host and open and party.capacity>#party.members);enable(self._plus,host and open and party.capacity<4);enable(self._mode,host and open);enable(self._launch,host and open and count==#party.members);enable(self._ready,open);enable(self._leave,open)
		self._message.Text=p:GetAttribute("EHPartyMessage") or ""
        if self._message.Text=="" then self._message.Text=host and "Pick your crew size, then press READY." or "The host decides when to go down." end
		self._message.Visible=self._message.Text~=""
		if appeared and Input.PreferredInput==Enum.PreferredInput.Gamepad then GuiService.SelectedObject=self._ready end
	end
	local results=p:GetAttribute("EHContext")=="Results";self._reconnect.Visible=not party and (p:GetAttribute("EHReconnectAvailable")==true or results);self._reconnect.Text=results and "Return to lobby" or "Rejoin your crew"
	self._feedback.Text=not party and (p:GetAttribute("EHPartyMessage") or "") or ""
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(self._panel) and not party then GuiService.SelectedObject=nil end
end
function Controller:Start()
	for _,attr in {"EHPartyView","EHPartyMessage","EHReconnectAvailable","EHContext"}do self._scope:Add(self._player:GetAttributeChangedSignal(attr):Connect(function()self:_Refresh()end))end;self:_Refresh()
end
function Controller:Destroy()if self._scope then self._scope:Destroy()end end
return table.freeze(Controller)
