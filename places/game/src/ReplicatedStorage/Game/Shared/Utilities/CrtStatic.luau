--!nonstrict
-- CrtStatic (Oct 26): old CRT monitors showing snow. Any part tagged "CrtStatic" with a SurfaceGui
-- ImageLabel (the noise sheet BW_CrtNoise) gets a new random window of the sheet every ~1/24 s, a
-- slight brightness flicker and now and then a darker rolling band. Its PointLight (the screen glow)
-- flickers with it. Only runs for screens within 90 studs of the camera.
local RunService=game:GetService('RunService');local CS=game:GetService('CollectionService')
local M={};local conn
local SHEET=Vector2.new(512,512)
function M.Start()
 if conn then return end
 local acc=0
 conn=RunService.RenderStepped:Connect(function(dt)
  acc+=dt;if acc<1/24 then return end;acc=0
  local cam=workspace.CurrentCamera;if not cam then return end
  local t=os.clock()
  for _,p in CS:GetTagged('CrtStatic')do
   if p:IsA('BasePart') and p:IsDescendantOf(workspace) and (p.Position-cam.CFrame.Position).Magnitude<90 then
    local im=p:FindFirstChild('Noise',true)
    if im then
     local rs=im.ImageRectSize
     im.ImageRectOffset=Vector2.new(math.random(0,SHEET.X-rs.X),math.random(0,SHEET.Y-rs.Y))
     local roll=(t*.35)%1
     im.ImageTransparency=.08+.12*math.random()+(math.abs(roll-.5)<.04 and .25 or 0)
     local l=p:FindFirstChildOfClass('PointLight');if l then l.Brightness=.45+.25*math.random() end
    end
   end
  end
 end)
end
return M
