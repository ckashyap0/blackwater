--!nonstrict
-- The TV above the fireplace in the secret room.
--  * Everyone sees the authored title card (SecretRoom.Fireplace.TV.Screen.Picture.Feed): the ticker
--    crawls, the REC dot blinks and the clock runs.
--  * Players with secret-room access (player attribute EHSecretAccess, set by the server) also get a
--    security camera high on the lobby's left wall (ReplicatedStorage.Game.LobbyArt.SecurityCam - it
--    exists only on their screen) that sweeps slowly back and forth, and the TV switches to its live,
--    grainy feed of the main hall, players and all (Picture.Feed.CamFeed - edit the look there).
--    The camera's sweep comes from its attributes: BaseYaw, Sweep (degrees each way), Pitch, Period.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local Scope=require(game.ReplicatedStorage.Game.Shared.Utilities.CleanupScope)
local Controller={};Controller.__index=Controller
local SPEED=60          -- ticker pixels per second
local FEED_FPS=15       -- how often the picture updates (a real CCTV feed is a little choppy)
local WATCH_RANGE=70    -- the feed only updates while you are this close to the TV
local SOURCES={"Architecture","Fixtures","Bay1","Bay2","Bay3","Bay4","MachineHall"}
local KEEP={SpecialMesh=true,BlockMesh=true,CylinderMesh=true,FileMesh=true,Decal=true,Texture=true,SurfaceAppearance=true}
local TITLE_CARD={"Kicker","Title","Underline","Sub","Ticker"}

function Controller.new(player)return setmetatable({Name="TVController",Dependencies={},_player=player,_people={}},Controller)end
function Controller:Init()self._scope=Scope.new()end

-- smooth sweep with a short pause at each end, like a real pan-and-tilt camera
local function sweep(u)
	local function ease(k)return k*k*(3-2*k)end
	if u<.4 then return -1+2*ease(u/.4)
	elseif u<.5 then return 1
	elseif u<.9 then return 1-2*ease((u-.5)/.4)
	else return -1 end
end

local function strip(inst)
	for _,d in inst:GetDescendants() do
		if d.Parent and not d:IsA("BasePart") and not d:IsA("Model") and not d:IsA("Accessory") and not d:IsA("Humanoid")
			and not d:IsA("Clothing") and not d:IsA("BodyColors") and not d:IsA("Attachment") and not KEEP[d.ClassName] then
			d:Destroy()
		end
	end
end

-- the hall, copied once into the feed's 3D view (spread over a few frames so nothing hitches)
function Controller:_FillWorld(env,origin)
	local world=Instance.new("Model");world.Name="Hall";world.Parent=self._view
	local n=0
	for _,name in SOURCES do
		local src=env:FindFirstChild(name)
		if src then
			for _,p in src:GetDescendants() do
				if p:IsA("BasePart") and p.Transparency<.98 and (p.Position-origin).Magnitude<130 then
					local ok,c=pcall(function()return p:Clone()end)
					if ok and c then
						c:ClearAllChildren()
						for _,k in p:GetChildren() do if KEEP[k.ClassName] then k:Clone().Parent=c end end
						c.Anchored=true;c.Parent=world
						n+=1;if n%150==0 then task.wait() end
					end
				end
			end
		end
	end
end

-- people: a stand-in copy of each character, posed from the real one every feed frame
function Controller:_Person(p)
	local char=p.Character
	local h=self._people[p]
	if h and h.char==char and not h.dirty then return h end
	if h then h.model:Destroy();for _,c in h.conns do c:Disconnect() end end
	self._people[p]=nil
	if not char or not char.Parent then return end
	local was=char.Archivable;char.Archivable=true
	local ok,copy=pcall(function()return char:Clone()end)
	char.Archivable=was
	if not ok or not copy then return end
	strip(copy)
	local hum=copy:FindFirstChildOfClass("Humanoid");if hum then hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
	local pairsList={}
	local function walk(a,b)
		for _,ca in a:GetChildren() do
			local cb=b:FindFirstChild(ca.Name)
			if cb and cb.ClassName==ca.ClassName then
				if ca:IsA("BasePart") then cb.Anchored=true;cb.CanCollide=false;table.insert(pairsList,{ca,cb}) end
				walk(ca,cb)
			end
		end
	end
	walk(char,copy)
	copy.Parent=self._view
	h={char=char,model=copy,pairs=pairsList,conns={}}
	local function dirty()h.dirty=true end
	table.insert(h.conns,char.ChildAdded:Connect(dirty));table.insert(h.conns,char.ChildRemoved:Connect(dirty))
	self._people[p]=h
	return h
end
function Controller:_UpdatePeople()
	local seen={}
	for _,p in Players:GetPlayers() do
		local h=self:_Person(p)
		if h then
			seen[p]=true
			for _,pr in h.pairs do if pr[1].Parent then pr[2].CFrame=pr[1].CFrame end end
		end
	end
	for p,h in self._people do
		if not seen[p] then h.model:Destroy();for _,c in h.conns do c:Disconnect() end;self._people[p]=nil end
	end
end

function Controller:_StartFeed(env,feed,tv)
	if self._feedOn then return end
	local template=game.ReplicatedStorage.Game:FindFirstChild("LobbyArt") and game.ReplicatedStorage.Game.LobbyArt:FindFirstChild("SecurityCam")
	local camFeed=feed:FindFirstChild("CamFeed")
	if not template or not camFeed then return end
	self._feedOn=true
	-- the camera on the wall (only on this player's screen)
	local rig=template:Clone();rig.Name="SecurityCam";rig.Parent=workspace
	self._scope:Add(rig)
	local head=rig:WaitForChild("Head");local eye=head:FindFirstChild("Eye",true)
	local pivot=head.WorldPivot
	local base,amp,pitch,period=rig:GetAttribute("BaseYaw") or 0,rig:GetAttribute("Sweep") or 30,rig:GetAttribute("Pitch") or -14,rig:GetAttribute("Period") or 16
	local led=head:FindFirstChild("LED")
	-- the picture
	self._view=camFeed:WaitForChild("View")
	local cam=Instance.new("Camera");cam.FieldOfView=62;cam.Parent=self._view;self._view.CurrentCamera=cam
	camFeed.Visible=true
	for _,n in TITLE_CARD do local o=feed:FindFirstChild(n);if o then o.Visible=false end end
	local rec=feed:FindFirstChild("Rec");if rec then rec.Text="REC  CAM 02 · LOBBY" end
	task.spawn(function()self:_FillWorld(env,pivot.Position)end)
	local roll,tear,view=camFeed:FindFirstChild("Roll"),camFeed:FindFirstChild("Tear"),self._view
	local screen=tv:FindFirstChild("Screen")
	local t,acc,tearAt,tearUntil=0,0,os.clock()+3,0
	self._scope:Add(RunService.RenderStepped:Connect(function(dt)
		t+=dt
		local a=math.rad(base+amp*sweep((t%period)/period))
		local cf=CFrame.new(pivot.Position)*CFrame.Angles(0,a,0)*CFrame.Angles(math.rad(pitch),0,0)
		head:PivotTo(cf)
		if led then led.Transparency=(t%1.6)<.9 and 0 or .8 end
		-- the feed itself only runs while you're near enough to watch it
		local root=self._player.Character and self._player.Character:FindFirstChild("HumanoidRootPart")
		if not root or not screen or (root.Position-screen.Position).Magnitude>WATCH_RANGE then return end
		acc+=dt
		if acc<1/FEED_FPS then return end
		acc=0
		local now=os.clock()
		local shake=Vector3.new((math.random()-.5)*.012,(math.random()-.5)*.012,0)
		cam.CFrame=(eye and eye.WorldCFrame or cf)*CFrame.new(shake)
		self:_UpdatePeople()
		-- distortion: rolling band, the odd tear and sideways slip, a faint flicker
		if roll then roll.Position=UDim2.fromScale(0,((t*.11)%1.35)-.25) end
		if now>tearAt then tearUntil=now+.12;tearAt=now+2.5+math.random()*4 end
		local tearing=now<tearUntil
		if tear then tear.BackgroundTransparency=tearing and .55 or 1;if tearing then tear.Position=UDim2.fromScale(0,math.random()) end end
		view.Position=UDim2.new(.5,tearing and math.random(-6,6) or 0,.5,0)
		view.ImageTransparency=math.random()*.06
	end))
end

function Controller:Start()
	task.spawn(function()
		local env=workspace:WaitForChild("Runtime"):WaitForChild("LobbyEnvironment",30)
		local room=env and env:WaitForChild("SecretRoom",10)
		local fp=room and room:WaitForChild("Fireplace",10)
		local tv=fp and fp:WaitForChild("TV",10)
		local pic=tv and tv:WaitForChild("Screen"):WaitForChild("Picture",10)
		if not pic then return end
		-- the screen runs from PlayerGui, pinned onto the TV: a 3D view kept inside the world would also
		-- draw its copies of the hall out in the world
		local live=pic:Clone();live.Name="TVPicture";live.Adornee=pic.Parent;live.ResetOnSpawn=false
		pic.Enabled=false
		live.Parent=self._player:WaitForChild("PlayerGui")
		self._scope:Add(live)
		local feed=live:WaitForChild("Feed")
		local ticker=feed:FindFirstChild("Ticker");local text=ticker and ticker:FindFirstChild("Text")
		local dot=feed:FindFirstChild("RecDot");local clock=feed:FindFirstChild("Clock")
		local x=0;local t=0;local last=""
		self._scope:Add(RunService.Heartbeat:Connect(function(dt)
			t+=dt
			if text and ticker and ticker.Visible then
				local w=math.max(text.TextBounds.X,1)
				x-=dt*SPEED
				if x<-w then x=ticker.AbsoluteSize.X end
				text.Position=UDim2.new(0,x,0,0)
			end
			if dot then dot.Visible=(t%1.2)<.7 end
			if clock then
				local s=os.date("!%H:%M:%S",math.floor(workspace:GetServerTimeNow()))
				if s~=last then last=s;clock.Text=s end
			end
		end))
		-- secret-room members get the camera and its feed
		local function check()if self._player:GetAttribute("EHSecretAccess")==true then self:_StartFeed(env,feed,tv) end end
		self._scope:Add(self._player:GetAttributeChangedSignal("EHSecretAccess"):Connect(check))
		check()
	end)
end
function Controller:Destroy()
	for _,h in self._people do h.model:Destroy();for _,c in h.conns do c:Disconnect() end end
	table.clear(self._people)
	if self._scope then self._scope:Destroy()end
end
return table.freeze(Controller)
