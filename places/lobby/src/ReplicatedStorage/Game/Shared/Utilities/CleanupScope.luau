--!nonstrict
local CleanupScope = {}
CleanupScope.__index = CleanupScope
local function dispose(resource)
	if typeof(resource) == "RBXScriptConnection" then resource:Disconnect()
	elseif typeof(resource) == "Instance" then resource:Destroy()
	elseif type(resource) == "function" then resource()
	elseif type(resource) == "table" and type(resource.Destroy) == "function" then resource:Destroy()
	else error("Unsupported cleanup resource") end
end
function CleanupScope.new()
	return setmetatable({_resources={}, _destroyed=false}, CleanupScope)
end
function CleanupScope:Add(resource)
	assert(typeof(resource) == "RBXScriptConnection" or typeof(resource) == "Instance"
		or type(resource) == "function" or (type(resource) == "table" and type(resource.Destroy) == "function"),
		"Unsupported cleanup resource")
	if self._destroyed then dispose(resource) else table.insert(self._resources,resource) end
	return resource
end
function CleanupScope:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for index=#self._resources,1,-1 do
		local resource=self._resources[index]
		self._resources[index]=nil
		local ok,err=pcall(dispose,resource)
		if not ok then warn("[ElevatorHorror] Cleanup failed: "..tostring(err)) end
	end
end
return table.freeze(CleanupScope)
