-- Walkability flood fill (edit-time tool). Finds where a player can walk from a start point and reports
-- cells with no floor under them or outside the given bounds (= places a barrier is missing).
return function(root,start,opts)
 opts=opts or {}
 local step=opts.step or 2
 local saved={}
 for _,p in root:GetDescendants() do if p:IsA('BasePart') and p.CanCollide and not p.CanQuery then saved[p]=true p.CanQuery=true end end
 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={root} rp.RespectCanCollide=true rp.CollisionGroup=opts.group or "Default"
 local function floorAt(x,z,y) local r=workspace:Raycast(Vector3.new(x,y+3,z),Vector3.new(0,-(opts.drop or 9),0),rp) return r and r.Position.Y end
 local function open(a,b)
  for _,h in {1.2,3.0,4.6} do
   local o=a+Vector3.new(0,h,0) local d=(b-a)*Vector3.new(1,0,1)+Vector3.new(0,(b.Y-a.Y),0)
   if workspace:Spherecast(o,0.9,d,rp) and h>2.2 then return false end
   if h<=2.2 then local r=workspace:Spherecast(o+Vector3.new(0,1.2,0),0.9,d,rp) if r then return false end end
  end
  return true
 end
 local y0=floorAt(start.X,start.Z,start.Y) if not y0 then for p in saved do p.CanQuery=false end return {error='no floor at start'} end
 local seen,queue,leaks,n={},{Vector3.new(start.X,y0,start.Z)},{},0
 local function key(p) return math.floor(p.X/step+.5)..','..math.floor(p.Z/step+.5) end
 seen[key(queue[1])]=true
 local mn,mx=Vector3.new(1e9,1e9,1e9),Vector3.new(-1e9,-1e9,-1e9)
 local head=1
 while head<=#queue and n<(opts.max or 60000) do
  local p=queue[head] head+=1 n+=1 mn=mn:Min(p) mx=mx:Max(p)
  for _,d in {Vector3.new(step,0,0),Vector3.new(-step,0,0),Vector3.new(0,0,step),Vector3.new(0,0,-step)} do
   local q=p+d local k=key(q)
   if not seen[k] then
    local fy=floorAt(q.X,q.Z,p.Y)
    if fy and math.abs(fy-p.Y)<=(opts.stepUp or 2.6) then
     local qq=Vector3.new(q.X,fy,q.Z)
     if open(p,qq) then seen[k]=true
      if opts.inside and not opts.inside(qq) then leaks[#leaks+1]={qq,'outside'} else queue[#queue+1]=qq end
     end
    elseif not fy then
     -- open edge into nothing?
     if open(p,Vector3.new(q.X,p.Y,q.Z)) then seen[k]=true leaks[#leaks+1]={Vector3.new(q.X,p.Y,q.Z),'void'} end
    end
   end
  end
 end
 for p in saved do p.CanQuery=false end
 return {count=n,min=mn,max=mx,leaks=leaks,cells=queue}
end
