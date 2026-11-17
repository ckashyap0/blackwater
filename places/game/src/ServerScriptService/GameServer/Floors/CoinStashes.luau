--!nonstrict
-- HIDDEN COIN STASHES (Nov 16). Floors 5 and 4 each carry ~30 authored hiding spots
-- (Level<n>.CoinSpots: invisible marker parts, made with ServerStorage.ArtTools.CoinSpotFinder and
-- free to move / add / delete by hand). Every time a floor opens, 4 or 5 of them get a small pile of
-- coins (ServerStorage.GameAssets.CoinStash - the shop's coin pile mesh). Anyone can pick one up
-- (PICK UP); the first to finish the hold gets a random 1-50 coins, low amounts far more likely than
-- high ones, through CoinService:Award (so the 2x Coins pass applies and the "+N coins" line shows
-- under the objective). The pile is gone for everyone after that.
--   Place(model, context, coinService, floorNumber) - called by ElevatorService right after a floor's
--   Prepare, with that floor's context (interactions are cleaned up with the floor).
local M={}
M.MIN,M.MAX=4,5            -- piles per floor
M.LOW,M.HIGH=1,50          -- coins per pile
M.CURVE=3                  -- higher = big piles rarer (1 + 49*r^3: half of all piles are 6 or less, ~7% are 40+)
local PICKUP_SFX='rbxassetid://9113867249'
function M.Roll(rng)
 rng=rng or Random.new()
 return M.LOW+math.floor((M.HIGH-M.LOW+1)*rng:NextNumber()^M.CURVE)
end
function M.Place(model,context,coins,floorNumber)
 local folder=model:FindFirstChild('CoinSpots');local template=game.ServerStorage.GameAssets:FindFirstChild('CoinStash')
 if not folder or not template then return 0 end
 local spots={}
 for _,p in folder:GetChildren()do if p:IsA('BasePart') then table.insert(spots,p) end end
 local rng=Random.new()
 for i=#spots,2,-1 do local j=rng:NextInteger(1,i);spots[i],spots[j]=spots[j],spots[i] end
 local count=math.min(#spots,rng:NextInteger(M.MIN,M.MAX))
 local stashes=Instance.new('Folder');stashes.Name='CoinStashes';stashes.Parent=model
 for i=1,count do
  local spot=spots[i]
  local pile=template:Clone();pile.Name='CoinStash'..i
  pile:PivotTo(spot.CFrame*CFrame.new(0,-.05,0))
  pile.Parent=stashes
  local hit=pile.PrimaryPart or pile:FindFirstChildWhichIsA('BasePart')
  local taken=false
  local id='BWCoins'..tostring(floorNumber)..'_'..i
  context.RegisterInteraction({interactionId=id,target=hit,interactionType='Panel',label='PICK UP',holdDuration=.35,quick=true,
   lineOfSightModel=pile,allowedRunPhases={FloorActive=true},
   canUse=function()if taken then return false,'Unavailable' end;return true end,
   complete=function(player)
    if taken then return false,'Unavailable' end
    taken=true
    local amount=M.Roll(rng)
    if coins then coins:Award(player,amount,'HiddenCoins') end
    if context.SetInteractionEnabled then context.SetInteractionEnabled(id,false) end
    -- a little chink where it lay, then the pile is gone
    local a=Instance.new('Attachment');a.WorldPosition=hit.Position;a.Parent=workspace.Terrain
    local s=Instance.new('Sound');s.SoundId=PICKUP_SFX;s.Volume=.6;s.PlaybackSpeed=1.25;s.RollOffMinDistance=4;s.RollOffMaxDistance=40;s.Parent=a;s:Play()
    game:GetService('Debris'):AddItem(a,3)
    pile:Destroy()
    return true,'Collected'
   end})
 end
 return count
end
return table.freeze(M)
