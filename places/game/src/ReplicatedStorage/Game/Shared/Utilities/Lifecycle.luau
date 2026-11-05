--!nonstrict
local Contract = require(script.Parent.Parent.Contracts.ServiceContract)
local Lifecycle = {}
Lifecycle.__index = Lifecycle
function Lifecycle.new(services)
	local seen={}
	for _,service in services do
		Contract.Validate(service)
		assert(not seen[service.Name], "Duplicate service: "..service.Name)
		for _,name in service.Dependencies do
			assert(seen[name], service.Name..": dependency must appear earlier: "..name)
		end
		seen[service.Name]=service
	end
	return setmetatable({_services=table.clone(services),_initialized={},_byName={},State="New"},Lifecycle)
end
function Lifecycle:Start()
	assert(self.State == "New", "Lifecycle may only start once")
	self.State="Starting"
	local current="unknown"
	local ok,err=xpcall(function()
		for _,service in self._services do
			current=service.Name
			-- Include partially initialized services in failure cleanup.
			table.insert(self._initialized,service)
			local dependencies={}
			for _,name in service.Dependencies do dependencies[name]=self._byName[name] end
			service:Init(table.freeze(dependencies))
			self._byName[service.Name]=service
		end
		for _,service in self._services do current=service.Name; service:Start() end
	end,debug.traceback)
	if not ok then
		self:Destroy()
		self.State="Failed"
		error("Startup failed in "..current..": "..tostring(err),0)
	end
	self.State="Running"
end
function Lifecycle:Destroy()
	if self.State == "Destroyed" then return end
	for index=#self._initialized,1,-1 do
		local service=self._initialized[index]
		self._initialized[index]=nil
		local ok,err=pcall(function() service:Destroy() end)
		if not ok then warn("[ElevatorHorror] "..service.Name.." cleanup: "..tostring(err)) end
	end
	table.clear(self._byName)
	self.State="Destroyed"
end
return table.freeze(Lifecycle)
