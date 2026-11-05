--!nonstrict
-- The site keycard on the surface (Oct 25, rebuilt on the shared item system).
-- The card itself is an ordinary objective item (server InventoryService "SiteKeycard", kind Keycard): you are
-- handed it at the gatehouse, it sits in your LEFT hand (everyone sees it) and in your own view exactly like the
-- fuse, X drops it as a real tumbling object, anyone can take it back ("TAKE KEYCARD"), and holding E on the
-- card reader (its socket, "SiteKeycardReader") puts it in the slot and opens the works gate.
-- This module only does what is particular to the reader and the objective line:
--  * the reader's little screen: SWIPE CARD -> READING (+ a beep everyone near hears) while anyone holds E on
--    it -> ACCESS GRANTED once the gate opens (read from replicated attributes, so every player sees the same);
--  * the objective "Use your keycard on the gate reader" in the top task bar (ObjectiveSources): for whoever
--    carries the card, and for everyone while it lies on the ground (white outline on the card and the reader).
-- CardTemplate (child) is the card's look; the server clones it for the world item.
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local M={}
local ITEM,SOCKET='SiteKeycard','SiteKeycardReader'
local toastGui
function M.Toast(text,secs)
 local pg=Players.LocalPlayer:FindFirstChild('PlayerGui');if not pg then return end
 if toastGui then toastGui:Destroy() end
 local g=Instance.new('ScreenGui');g.Name='KeycardNotice';g.ResetOnSpawn=false;g.DisplayOrder=40;g.IgnoreGuiInset=true
 local l=Instance.new('TextLabel');l.BackgroundTransparency=1;l.AnchorPoint=Vector2.new(.5,1);l.Position=UDim2.fromScale(.5,.86);l.Size=UDim2.fromScale(.5,.035)
 l.FontFace=Font.new('rbxasset://fonts/families/RobotoMono.json',Enum.FontWeight.Bold);l.TextScaled=true;l.TextColor3=Color3.fromRGB(232,226,206);l.TextTransparency=1;l.Text=text;l.Parent=g
 local c=Instance.new('UITextSizeConstraint');c.MaxTextSize=22;c.Parent=l
 g.Parent=pg;toastGui=g
 local t0=os.clock();local life=secs or 3.5
 local conn;conn=RunService.RenderStepped:Connect(function()
  local t=os.clock()-t0
  l.TextTransparency=t<.3 and 1-t/.3 or (t>life-.5 and math.clamp((t-(life-.5))/.5,0,1) or 0)
  if t>life or not g.Parent then conn:Disconnect();g:Destroy() end
 end)
end
local function yardNow()
 local runtime=workspace:FindFirstChild('Runtime');local env=runtime and runtime:FindFirstChild('DescentEnvironment')
 return env and env:FindFirstChild('SurfaceYard')
end
local function setScreen(reader,text,col,led)
 local scr=reader:FindFirstChild('Reader_Screen');local msg=scr and scr:FindFirstChild('Msg',true)
 if msg then msg.Text=text;msg.TextColor3=col end
 local l=reader:FindFirstChild('ReaderLED');if l then l.Color=led end
end
-- (kept for callers from before the rebuild: the reader is now an ordinary socket interaction)
function M.Allowed() return true end
function M.Begin() end
function M.Cancel() end
-- the reader screen, the same on every screen
local watchConn
function M.Hold()
 if watchConn then return end
 local state,greened=nil,false
 watchConn=RunService.Heartbeat:Connect(function()
  local yard=yardNow();if not yard then state=nil;greened=false;return end
  local rd=yard:FindFirstChild('KeycardReader',true);if not rd then return end
  if yard:GetAttribute('GateOpenedAt') then
   if not greened then greened=true;state='open';setScreen(rd,'ACCESS\nGRANTED',Color3.fromRGB(110,235,120),Color3.fromRGB(60,255,90)) end
   return
  end
  local reading=false
  for _,p in Players:GetPlayers()do if p:GetAttribute('EHActiveInteraction')==SOCKET and p:GetAttribute('EHInteractionState')=='Holding' then reading=true;break end end
  local want=reading and 'reading' or 'idle'
  if want~=state then
   state=want
   if reading then
    setScreen(rd,'READING',Color3.fromRGB(255,200,90),Color3.fromRGB(255,170,40))
    local b=rd:FindFirstChild('Reader_Body',true)
    if b then local s=Instance.new('Sound');s.SoundId='rbxassetid://9113880475';s.Volume=.6;s.PlaybackSpeed=1.35;s.RollOffMinDistance=6;s.RollOffMaxDistance=60;s.Parent=b;s:Play();s.Ended:Once(function()s:Destroy()end) end
   else setScreen(rd,'SWIPE\nCARD',Color3.fromRGB(255,170,60),Color3.fromRGB(255,40,30)) end
  end
 end)
end
function M.Watch()
 M.Hold()
 local me=Players.LocalPlayer
 local Sources=require(script.Parent:WaitForChild('ObjectiveSources'))
 local Lock=require(script.Parent:WaitForChild('ControlLock'))
 Sources.Register('Keycard',function(p)
  if p~=me or Lock.active or me:GetAttribute('EHCinematic') then return nil end
  local yard=yardNow();if not yard or yard:GetAttribute('GateOpenedAt') then return nil end
  if not yard:GetAttribute('GateDriveDone') then return nil end -- (Nov 3: the car comes first - the reader is past the barrier) -- (Nov 3: the car comes first - the reader is past the barrier)
  local rd=yard:FindFirstChild('KeycardReader',true)
  if me:GetAttribute('EHCarriedKind')=='Keycard' then return {key=yard,text='Use your keycard on the gate reader',targets={rd}} end
  -- lying on the ground: everyone is pointed at it (and the reader)
  local card=yard:FindFirstChild(ITEM)
  if card and card:GetAttribute('EHItemState')=='Dropped' then return {key=yard,text='Use your keycard on the gate reader',targets={card,rd}} end
  return nil
 end)
end
return M
