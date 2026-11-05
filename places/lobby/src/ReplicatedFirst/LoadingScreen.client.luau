--!nonstrict
-- Loading screen for the Lobby. It is the same "BlackWater / Loading" card the Game place uses and the
-- one the teleport hands over, so coming back up from a descent (or joining) is one unbroken card:
-- black -> card -> the lobby fading in. The screen itself is the ScreenGui "BlackwaterLoading" inside
-- this script (edit it there - keep it in step with StarterGui.DepartureFade and the Game place's copy).
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local ReplicatedFirst=game:GetService('ReplicatedFirst')
local TeleportService=game:GetService('TeleportService')
local player=Players.LocalPlayer
local gui=script:WaitForChild('BlackwaterLoading'):Clone()
local back=gui:WaitForChild('Black')
local panel=gui:WaitForChild('Panel')
local scale=panel:FindFirstChildOfClass('UIScale') or Instance.new('UIScale',panel)
local status=panel:WaitForChild('Status')
local words={}
for _,o in panel:GetChildren() do if o:IsA('TextLabel') then words[o]=o.TextTransparency end end
local backBase=back.BackgroundTransparency
local FRAMES={'Loading.  ','Loading.. ','Loading...'}
local STEP=.45
gui.Parent=player:WaitForChild('PlayerGui')
pcall(function()ReplicatedFirst:RemoveDefaultLoadingScreen()end)
-- the card the teleport carried over is identical; ours is now on top, so it can go
task.defer(function()
 local arriving;pcall(function()arriving=TeleportService:GetArrivingTeleportGui()end)
 if arriving then arriving:Destroy() end
end)
local t0=os.clock();local fadeAt
local function ready()
 if not game:IsLoaded() then return false end
 local env=workspace:FindFirstChild('Runtime') and workspace.Runtime:FindFirstChild('LobbyEnvironment')
 local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 return env~=nil and root~=nil
end
local conn
conn=RunService.RenderStepped:Connect(function()
 local now=os.clock()
 scale.Scale=math.clamp(gui.AbsoluteSize.X/420,.7,1.25)
 status.Text=FRAMES[((math.floor((now-t0)/STEP)+2)%#FRAMES)+1]
 -- stay up a moment once everything is in, so the world has drawn before it shows
 if not fadeAt and now-t0>.8 and ready() then fadeAt=now+.35 end
 if not fadeAt and now-t0>30 then fadeAt=now end
 if fadeAt and now>=fadeAt then
  local u=math.clamp((now-fadeAt)/.45,0,1);u=u*u*(3-2*u)
  for o,base in words do o.TextTransparency=base+(1-base)*u end
  local b=math.clamp((now-fadeAt-.35)/.6,0,1);b=b*b*(3-2*b)
  back.BackgroundTransparency=backBase+(1-backBase)*b
  if now-fadeAt>1 then conn:Disconnect();gui:Destroy() end
 end
end)
