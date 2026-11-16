return function()
local L4=workspace.BlackwaterAuthoring.Level4
local saved={}
for _,p in L4:GetDescendants() do if p:IsA('BasePart') and not p.CanQuery then saved[p]=true p.CanQuery=true end end
local function top(p) local m=p while m.Parent and m.Parent~=L4 and not (m.Parent:IsA('Folder')) do m=m.Parent end return m end
local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Exclude
local seen={} local o={}
for _,root in {L4.Dressing,L4.Interactables,L4.LightingGroups} do
 for _,p in root:GetDescendants() do if p:IsA('BasePart') and p.Transparency<0.95 and p.Size.Magnitude>.15 then
  local mine=top(p)
  op.FilterDescendantsInstances={mine,L4.Architecture,L4.Services,L4:FindFirstChild('RoomPipework'),L4:FindFirstChild('CeilingDrips'),L4:FindFirstChild('Ventilation')}
  for _,h in workspace:GetPartBoundsInBox(p.CFrame,p.Size*.75,op) do if h.Transparency<0.95 and h:IsDescendantOf(L4) then
   local other=top(h) if other~=mine then local a,b=mine:GetFullName(),other:GetFullName() local k=a<b and a..'|'..b or b..'|'..a
    if not seen[k] then seen[k]=true o[#o+1]=string.format('%s [%s] <> %s [%s] at %.0f,%.0f (%s / %s)',mine.Name,mine.Parent.Name,other.Name,other.Parent.Name,p.Position.X,p.Position.Z,p.Name:sub(1,26),h.Name:sub(1,26)) end end
  end end
 end end
end
for p in saved do p.CanQuery=false end
return o
end
