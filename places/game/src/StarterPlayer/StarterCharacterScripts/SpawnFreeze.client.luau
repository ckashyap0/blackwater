--!nonstrict
-- First frames of every new character (Game place): the character stands perfectly still - no
-- walking, jumping or turning - from the very first frame, before the game's own controllers
-- have started. InputController's control lock (Shared.Utilities.ControlLock) takes over as soon as
-- it runs (EHControlLocked), and decides when control comes back; this script then stops.
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local character=script.Parent
local humanoid=character:WaitForChild('Humanoid',10)
if not humanoid then return end
-- only in the Game place (the lobby has no spawn cutscene)
local shared=game.ReplicatedStorage:FindFirstChild('Game')
if shared and shared:GetAttribute('PlaceRole')=='Lobby' then return end
local started=os.clock()
local walk,jumpH,jumpP,rotate=humanoid.WalkSpeed,humanoid.JumpHeight,humanoid.JumpPower,humanoid.AutoRotate
local function freeze()
 humanoid.WalkSpeed=0;humanoid.JumpHeight=0;humanoid.JumpPower=0;humanoid.AutoRotate=false;humanoid.Jump=false
 humanoid:Move(Vector3.zero)
end
freeze()
local conn
conn=RunService.PreRender:Connect(function()
 -- handed over (or a safety limit, so nobody can ever be left frozen)
 if player:GetAttribute('EHControlLocked')==true or not humanoid.Parent then conn:Disconnect();return end
 if os.clock()-started>10 then
  -- the lock never took over: give the character back exactly as it was
  conn:Disconnect()
  humanoid.WalkSpeed=walk>0 and walk or 12;humanoid.JumpHeight=jumpH;humanoid.JumpPower=jumpP;humanoid.AutoRotate=true
  return
 end
 freeze()
end)
