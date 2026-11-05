--!strict
local Visibility={}
function Visibility.Clear(cameraPosition:Vector3,target:BasePart,roots:{Instance},point:Vector3?):boolean
 local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances=roots;params.RespectCanCollide=false
 if (target.Position-cameraPosition).Magnitude>85 then return false end
 -- Parts touching the target (a lever on its plate, a wheel over its valve, the box behind
 -- a non-queryable sign) count as the target; invisible helpers never block the view.
 local reach=target.Size.Magnitude/2+.35
 local origin=cameraPosition
 for _=1,6 do
  local ray=(point or target.Position)-origin
  if ray.Magnitude<1e-3 then return true end
  local hit=workspace:Raycast(origin,ray,params)
  if not hit then return true end
  if hit.Instance==target or hit.Instance:IsDescendantOf(target)or (hit.Position-target.Position).Magnitude<=reach then return true end
  if not(hit.Instance:IsA('BasePart')and hit.Instance.Transparency>=.95)then return false end
  origin=hit.Position+ray.Unit*.02
 end
 return false
end
-- Visible if the centre or any face of the part can be seen (a fuse lying half behind a crate,
-- a switch seen from the side). Needed because one centre ray alone hid outlines too often.
return table.freeze(Visibility)
