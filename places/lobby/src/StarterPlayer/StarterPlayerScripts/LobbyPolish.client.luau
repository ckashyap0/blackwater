--!nonstrict
-- Lobby polish (BlackWater lobby place only):
--  1. Shop / Locker buttons: smooth tweened hover (scale up, gold edge, warm tint), press (squash)
--     and click feedback (a quick flash), mouse, touch and gamepad selection alike.
local Players=game:GetService('Players')
local TweenService=game:GetService('TweenService')
local shared=game.ReplicatedStorage:WaitForChild('Game',30)
if shared and shared:GetAttribute('PlaceRole') and shared:GetAttribute('PlaceRole')~='Lobby' then return end
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local GOLD=Color3.fromRGB(226,182,81)
------------------------------------------------------------------ 1. button motion
local HOVER=TweenInfo.new(.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
local PRESS=TweenInfo.new(.08,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local SETTLE=TweenInfo.new(.22,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
local wired=setmetatable({},{__mode='k'})
local function motion(b)
 if not b or wired[b] then return end
 wired[b]=true
 local scale=b:FindFirstChild('Motion') or Instance.new('UIScale');scale.Name='Motion';scale.Parent=b
 local stroke=b:FindFirstChildOfClass('UIStroke')
 local baseColor=b.BackgroundColor3;local baseStroke=stroke and stroke.Color
 local flash=b:FindFirstChild('ClickFlash')
 if not flash then
  flash=Instance.new('Frame');flash.Name='ClickFlash';flash.Size=UDim2.fromScale(1,1);flash.BackgroundColor3=Color3.new(1,1,1);flash.BackgroundTransparency=1;flash.ZIndex=(b.ZIndex or 1)+5;flash.Parent=b
  local corner=b:FindFirstChildOfClass('UICorner');if corner then corner:Clone().Parent=flash end
 end
 local hovered,pressed=false,false
 local function paint()
  TweenService:Create(scale,pressed and PRESS or HOVER,{Scale=pressed and .92 or hovered and 1.08 or 1}):Play()
  TweenService:Create(b,SETTLE,{BackgroundColor3=hovered and baseColor:Lerp(Color3.fromRGB(46,38,22),.85) or baseColor}):Play()
  if stroke then TweenService:Create(stroke,SETTLE,{Color=hovered and GOLD or baseStroke}):Play() end
 end
 b.MouseEnter:Connect(function()hovered=true;paint()end)
 b.MouseLeave:Connect(function()hovered=false;pressed=false;paint()end)
 b.SelectionGained:Connect(function()hovered=true;paint()end)
 b.SelectionLost:Connect(function()hovered=false;pressed=false;paint()end)
 b.InputBegan:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then pressed=true;paint() end
 end)
 b.InputEnded:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch or input.KeyCode==Enum.KeyCode.ButtonA then
   pressed=false
   if input.UserInputType==Enum.UserInputType.Touch then hovered=false end
   paint()
  end
 end)
 b.Activated:Connect(function()
  flash.BackgroundTransparency=.55
  TweenService:Create(flash,TweenInfo.new(.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
 end)
end
------------------------------------------------------------------ wiring (survives respawns)
local function attach()
 local controls=pg:FindFirstChild('ShopControls')
 if controls then motion(controls:FindFirstChild('ShopButton'));motion(controls:FindFirstChild('LockerButton')) end
end
pg.ChildAdded:Connect(function()task.defer(attach)end)
attach()
