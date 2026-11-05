--!nonstrict
-- Explicit authored references.
-- Scripts locate operable parts by a stable `Ref` attribute instead of by their place in
-- Explorer, so the authored map can be regrouped into Architecture / Interactables / Anchors
-- (etc.) without breaking objectives. A legacy root child with the same Name still resolves,
-- which keeps older templates and test fixtures working.
local Refs={}
local cache=setmetatable({},{__mode='k'})
local MISS_RETRY=1
local function direct(root,name)
	local hit=root:FindFirstChild(name)
	if hit and (hit:GetAttribute('Ref')==nil or hit:GetAttribute('Ref')==name) then return hit end
	return nil
end
local function scan(root,name)
	for _,d in root:GetDescendants() do if d:GetAttribute('Ref')==name then return d end end
	return nil
end
function Refs.Find(root,name)
	if not root or not name then return nil end
	local map=cache[root];if not map then map={};cache[root]=map end
	local hit=map[name]
	if typeof(hit)=='Instance' then
		if hit.Parent and hit:IsDescendantOf(root) and (hit:GetAttribute('Ref')==name or hit.Name==name) then return hit end
	end
	-- A direct child is always checked (cheap); only the full descendant scan is throttled after a miss.
	hit=direct(root,name)
	if not hit then
		local missed=map[name]
		if type(missed)=='number' and os.clock()-missed<MISS_RETRY then return nil end
		hit=scan(root,name)
	end
	map[name]=hit or os.clock()
	return hit
end
function Refs.Get(root,name)
	local hit=Refs.Find(root,name)
	assert(hit,'MissingRef:'..tostring(name))
	return hit
end
-- Tag an authored object so every script can find it wherever it lives in the hierarchy.
function Refs.Tag(inst,name)inst:SetAttribute('Ref',name or inst.Name);return inst end
function Refs.Clear(root)cache[root]=nil end
-- Fill the cache for a whole map in ONE pass (every Ref it contains), so later lookups never scan.
-- A big floor has ~15k descendants and its setup asks for dozens of refs: scanning for each one
-- separately froze the server for a moment mid-ride. yieldEvery>0 spreads the pass over frames.
function Refs.Index(root,yieldEvery)
	if not root then return end
	local map=cache[root];if not map then map={};cache[root]=map end
	for i,d in root:GetDescendants() do
		local r=d:GetAttribute('Ref')
		if r and typeof(map[r])~='Instance' then map[r]=d end
		if yieldEvery and yieldEvery>0 and i%yieldEvery==0 then task.wait() end
	end
end
return table.freeze(Refs)
