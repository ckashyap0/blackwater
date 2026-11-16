--!nonstrict
-- RF_Scan (2026-11-13, Ryan fixes pass): consistency scanner for BlackWater floors.
-- Units = prop models (direct children of the level's prop folders) and loose parts.
-- Floating: a unit with no outside part touching it (AABB within EPS).
-- WalkThrough: a solid-looking unit at body height with no CanCollide part covering it.
-- Overlap: two units whose parts interpenetrate (sampled OBB containment).
local M={}
local EPS=.12
local CELL=8
local function aabb(p)
 local cf,s=p.CFrame,p.Size/2
 local r=cf.RightVector*s.X;local u=cf.UpVector*s.Y;local b=cf.LookVector*s.Z
 local e=Vector3.new(math.abs(r.X)+math.abs(u.X)+math.abs(b.X),math.abs(r.Y)+math.abs(u.Y)+math.abs(b.Y),math.abs(r.Z)+math.abs(u.Z)+math.abs(b.Z))
 return cf.Position-e,cf.Position+e
end
local function key(x,y,z)return x..','..y..','..z end
local UNIT_FOLDERS={Dressing=true,PropCollections=true,Interactables=true,MaintenanceZones=true,Machinery=true,Records=true}
-- the unit a part belongs to: the model right under a room folder inside a prop folder, else the part
function M.UnitOf(p,level)
 local chain={};local a=p
 while a and a~=level do table.insert(chain,1,a);a=a.Parent end
 if #chain>=2 and UNIT_FOLDERS[chain[1].Name] then
  if chain[1].Name=='Interactables' then return chain[2] end
  -- Folder/Room/Unit: a room container holds prop models; Folder/Unit otherwise
  local c2=chain[2]
  if #chain>=3 and (c2:IsA('Folder') or c2:FindFirstChildWhichIsA('Model')~=nil) and (chain[3]:IsA('Model') or chain[3]:IsA('BasePart')) then return chain[3] end
  return c2
 end
 return nil -- architecture, pipework, lights: support only, never reported as units
end
function M.Index(level)
 local parts={};local grid={}
 for _,p in level:GetDescendants()do
  if p:IsA('BasePart') and (p.Transparency<.95 or p.CanCollide) then
   local lo,hi=aabb(p)
   local e={p=p,lo=lo,hi=hi,unit=M.UnitOf(p,level)}
   table.insert(parts,e)
   for x=math.floor(lo.X/CELL),math.floor(hi.X/CELL)do for y=math.floor(lo.Y/CELL),math.floor(hi.Y/CELL)do for z=math.floor(lo.Z/CELL),math.floor(hi.Z/CELL)do
    local k=key(x,y,z);local c=grid[k];if not c then c={};grid[k]=c end;table.insert(c,e)
   end end end
  end
 end
 return parts,grid
end
local function near(grid,lo,hi,fn)
 local seen={}
 for x=math.floor((lo.X-EPS)/CELL),math.floor((hi.X+EPS)/CELL)do for y=math.floor((lo.Y-EPS)/CELL),math.floor((hi.Y+EPS)/CELL)do for z=math.floor((lo.Z-EPS)/CELL),math.floor((hi.Z+EPS)/CELL)do
  local c=grid[key(x,y,z)]
  if c then for _,e in c do if not seen[e] then seen[e]=true;fn(e) end end end
 end end end
end
local function touch(alo,ahi,blo,bhi,eps)
 return alo.X<=bhi.X+eps and ahi.X>=blo.X-eps and alo.Y<=bhi.Y+eps and ahi.Y>=blo.Y-eps and alo.Z<=bhi.Z+eps and ahi.Z>=blo.Z-eps
end
local function inside(p,w)
 local l=p.CFrame:PointToObjectSpace(w);local s=p.Size/2
 return math.abs(l.X)<=s.X and math.abs(l.Y)<=s.Y and math.abs(l.Z)<=s.Z
end
-- share of a's volume that sits inside b (5x5x5 samples)
local function overlapShare(a,b)
 local n,inn=0,0
 for i=-2,2 do for j=-2,2 do for k=-2,2 do
  local w=a.CFrame:PointToWorldSpace(Vector3.new(a.Size.X*i/5,a.Size.Y*j/5,a.Size.Z*k/5))
  n+=1;if inside(b,w) then inn+=1 end
 end end end
 return inn/n
end
function M.Run(level,opts)
 opts=opts or {}
 local parts,grid=M.Index(level)
 task.wait()
 local units={}
 for _,e in parts do if e.unit then local u=units[e.unit];if not u then u={list={}};units[e.unit]=u end;table.insert(u.list,e) end end
 local floating,walk,overlap={}, {}, {}
 local floorY=opts.floorY
 local count=0
 for unit,u in units do
  count+=1;if count%150==0 then task.wait() end
  local supported=false;local covered=false;local solid=false
  local lo,hi
  for _,e in u.list do
   lo=lo and lo:Min(e.lo) or e.lo;hi=hi and hi:Max(e.hi) or e.hi
   local s=e.p.Size
   if e.p.Transparency<.5 and math.min(s.X,s.Y,s.Z)>=.6 and s.Y>=1 then solid=true end
  end
  local pairsSeen={}
  for _,e in u.list do
   near(grid,e.lo,e.hi,function(o)
    if o.unit==unit or o.p==e.p then return end
    if not supported and touch(e.lo,e.hi,o.lo,o.hi,EPS) then supported=true end
    -- overlap: only visible solid parts of two different units
    if o.unit and o.unit~=unit and not (unit:IsDescendantOf(level) and (unit.Parent.Name=='MountHardware' or o.unit.Parent.Name=='MountHardware')) and e.p.Transparency<.5 and o.p.Transparency<.5 and touch(e.lo,e.hi,o.lo,o.hi,-.05) then
     local va=e.p.Size.X*e.p.Size.Y*e.p.Size.Z;local vb=o.p.Size.X*o.p.Size.Y*o.p.Size.Z
     local small,big=e.p,o.p;if vb<va then small,big=o.p,e.p end
     if small.Size.X*small.Size.Y*small.Size.Z>.02 then
      local sh=overlapShare(small,big)
      if sh>=.2 then local k=tostring(unit)..'|'..tostring(o.unit);if not pairsSeen[o.unit] then pairsSeen[o.unit]=true;table.insert(overlap,{a=unit,b=o.unit,share=sh,pa=e.p,pb=o.p}) end end
     end
    end
   end)
  end
  if not supported then table.insert(floating,{unit=unit,lo=lo,hi=hi}) end
  -- walk-through: solid, standing in body height range, nothing collidable covering its middle
  if solid and lo and (hi.Y-lo.Y)>=1.2 and (not floorY or lo.Y<floorY+4) then
   local mid=(lo+hi)/2;local half=(hi-lo)/2*.6
   local clo,chi=mid-half,mid+half
   for _,e in u.list do if e.p.CanCollide and touch(e.lo,e.hi,clo,chi,0) then covered=true;break end end
   if not covered then near(grid,clo,chi,function(o) if not covered and o.p.CanCollide and o.unit~=nil and touch(o.lo,o.hi,clo,chi,0) and (o.hi.Y-o.lo.Y)<12 then covered=true end end) end
   if not covered then table.insert(walk,{unit=unit,lo=lo,hi=hi}) end
  end
 end
 return {floating=floating,walk=walk,overlap=overlap,units=count}
end
function M.Report(level,opts,limit)
 local r=M.Run(level,opts)
 local out={('units %d | floating %d | walk-through %d | overlaps %d'):format(r.units,#r.floating,#r.walk,#r.overlap)}
 local function nm(i)return i:GetFullName():gsub('^Workspace%.BlackwaterAuthoring%.','') end
 local function at(lo,hi)local c=(lo+hi)/2;return ('@%.0f,%.0f,%.0f'):format(c.X,c.Y,c.Z) end
 for i,f in r.floating do if i>(limit or 80) then break end;table.insert(out,'FLOAT '..nm(f.unit)..' '..at(f.lo,f.hi)) end
 for i,f in r.walk do if i>(limit or 80) then break end;table.insert(out,'WALK '..nm(f.unit)..' '..at(f.lo,f.hi)) end
 table.sort(r.overlap,function(a,b)return a.share>b.share end)
 for i,o in r.overlap do if i>(limit or 80) then break end;table.insert(out,('OVER %.0f%% %s <> %s [%s / %s]'):format(o.share*100,nm(o.a),nm(o.b),o.pa.Name,o.pb.Name)) end
 return table.concat(out,'\n'),r
end
return M
