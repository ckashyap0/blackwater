--!nonstrict
-- LiftLampFlicker (Oct 25): while the lift is waiting at the surface its cabin light (the Diffuser
-- SurfaceLights) flickers a little - mostly steady, now and then a soft dip or a quick stutter.
-- Only on the surface (the yard exists), and every light goes back to its own brightness after.
local RunService=game:GetService('RunService')
local M={};local conn
function M.Start()
 if conn then return end
 local lights,base={},{}
 local nextAt,dipUntil,dipK=0,0,1
 conn=RunService.Heartbeat:Connect(function()
  local rt=workspace:FindFirstChild('Runtime');local lift=rt and rt:FindFirstChild('Elevator')
  local env=rt and rt:FindFirstChild('DescentEnvironment');local yard=env and env:FindFirstChild('SurfaceYard')
  local on=lift~=nil and yard~=nil
  if not on then for l,b in base do if l.Parent then l.Brightness=b end end;table.clear(base);table.clear(lights);return end
  if #lights==0 then for _,d in lift:GetDescendants()do if d:IsA('SurfaceLight') and d.Parent and d.Parent.Name=='Diffuser' then table.insert(lights,d);base[d]=d.Brightness end end end
  local t=os.clock()
  if t>=nextAt then
   if math.random()<.35 then dipUntil=t+.05+math.random()*.08;dipK=.25+math.random()*.3 -- quick stutter
   else dipUntil=t+.2+math.random()*.35;dipK=.65+math.random()*.2 end -- soft dip
   nextAt=t+1.2+math.random()*3.5
  end
  local k=t<dipUntil and dipK or (1-.04*math.noise(t*6,.3))
  for _,l in lights do local b=base[l];if b and l.Parent then l.Brightness=b*k end end
 end)
end
return M
