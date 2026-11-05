--!nonstrict
-- Loading screen for the Game place, in the lobby's style. The screen itself is the ScreenGui
-- "BlackwaterLoading" inside this script (edit it there; to see it while editing, drag a copy into
-- StarterGui and delete the copy afterwards). It has to live here in ReplicatedFirst because it is the
-- very first thing drawn - before the map or the game scripts arrive - and replaces Roblox's default
-- screen. The dots run Loading. -> Loading.. -> Loading... on a steady beat. When your character is
-- standing on the surface and the wake-up is about to begin, the AtmosphereController sets
-- EHArrivalReady and this screen fades its words out over solid black.
-- Going back: the same card is handed to TeleportService, and when the server says you are returning
-- to the lobby (EHPartyMessage) the screen fades to it - so the trip back is the same card both ways,
-- and the lobby's own loading screen (Lobby ReplicatedFirst) picks it up and fades it away.
local Players=game:GetService('Players')
local TeleportService=game:GetService('TeleportService')
local RunService=game:GetService('RunService')
local ReplicatedFirst=game:GetService('ReplicatedFirst')
local player=Players.LocalPlayer
local template=script:WaitForChild('BlackwaterLoading')
local gui=template:Clone()
-- any trip out of here (back to the lobby, or being sent back because this isn't your descent)
-- shows this card instead of Roblox's default teleport screen
local function card()
 local c=template:Clone();c.Panel.Status.Text='Loading...'
 local w=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 420
 local s=c.Panel:FindFirstChildOfClass('UIScale');if s then s.Scale=math.clamp(w/420,.7,1.25) end
 return c
end
pcall(function()TeleportService:SetTeleportGui(card())end)
local back=gui:WaitForChild('Black')
local panel=gui:WaitForChild('Panel')
local scale=panel:FindFirstChildOfClass('UIScale') or Instance.new('UIScale',panel)
local status=panel:WaitForChild('Status')
local words={}
for _,o in panel:GetChildren() do if o:IsA('TextLabel') then words[o]=o.TextTransparency end end
local lines={}
for _,o in panel:GetChildren() do if o:IsA('Frame') then lines[o]=o.BackgroundTransparency end end
local backBase=back.BackgroundTransparency
-- the dots grow without the word sliding sideways: pad with spaces to a fixed width
local FRAMES={'Loading.  ','Loading.. ','Loading...'}
gui.Parent=player:WaitForChild('PlayerGui')
pcall(function()ReplicatedFirst:RemoveDefaultLoadingScreen()end)
local t0=os.clock();local fadeAt
local STEP=.45 -- seconds per frame of the dots
local conn
conn=RunService.RenderStepped:Connect(function()
 local now=os.clock()
 -- small screens: shrink the panel to fit
 local w=gui.AbsoluteSize.X;scale.Scale=math.clamp(w/420,.7,1.25)
 -- starts on 'Loading...', the same text the lobby's teleport card was showing
 status.Text=FRAMES[((math.floor((now-t0)/STEP)+2)%#FRAMES)+1]
 if not fadeAt and player:GetAttribute('EHArrivalReady')==true then fadeAt=now end
 -- safety: never block the screen for ever if the arrival signal is lost
 -- (90 s: the crew's arrival window is 45 s, plus loading on slow devices)
 if not fadeAt and now-t0>90 then fadeAt=now end
 if fadeAt then
  local u=math.clamp((now-fadeAt)/.45,0,1);u=u*u*(3-2*u)
  for o,base in words do o.TextTransparency=base+(1-base)*u end
  for o,base in lines do o.BackgroundTransparency=base+(1-base)*u end
  -- the black stays a moment longer so the eyes open out of the same black
  back.BackgroundTransparency=backBase+(1-backBase)*math.clamp((now-fadeAt-.45)/.2,0,1)
  if now-fadeAt>.7 then conn:Disconnect();gui:Destroy() end
 end
end)
-- returning to the lobby: ease the card back in over the game, then hold it through the teleport
local leaving=false
local function onMessage()
 local m=player:GetAttribute('EHPartyMessage')
 if leaving or type(m)~='string' or not m:find('Returning to lobby') then return end
 leaving=true
 pcall(function()TeleportService:SetTeleportGui(card())end)
 local out=card();out.DisplayOrder=240
 local fwords={};for _,o in out.Panel:GetChildren() do if o:IsA('TextLabel') then fwords[o]=o.TextTransparency;o.TextTransparency=1 end end
 out.Black.BackgroundTransparency=1
 out.Parent=player:WaitForChild('PlayerGui')
 local s0=os.clock();local c
 c=RunService.RenderStepped:Connect(function()
  local t=os.clock()-s0
  local b=math.clamp(t/.5,0,1);b=b*b*(3-2*b)
  out.Black.BackgroundTransparency=1-b
  local w=math.clamp((t-.35)/.35,0,1)
  for o,base in fwords do o.TextTransparency=1-(1-base)*w end
  out.Panel.Status.Text=FRAMES[(math.floor(os.clock()/STEP)%#FRAMES)+1]
  -- the teleport didn't happen (it failed): give the screen back after a while
  if t>25 then c:Disconnect();out:Destroy();leaving=false end
 end)
end
player:GetAttributeChangedSignal('EHPartyMessage'):Connect(onMessage)
