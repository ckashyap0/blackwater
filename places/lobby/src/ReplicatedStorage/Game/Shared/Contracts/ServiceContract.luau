--!strict
local ServiceContract = {}
function ServiceContract.Validate(service: any)
	assert(type(service) == "table", "Service must be a table")
	assert(type(service.Name) == "string" and #service.Name > 0, "Service must have a name")
	assert(type(service.Dependencies) == "table", service.Name..": missing dependencies")
	for _,method in {"Init","Start","Destroy"} do
		assert(type(service[method]) == "function", service.Name..": missing "..method)
	end
	local seen: {[string]: boolean} = {}
	for _,dependency in service.Dependencies do
		assert(type(dependency) == "string" and dependency ~= service.Name,
			service.Name..": invalid dependency")
		assert(not seen[dependency], service.Name..": duplicate dependency")
		seen[dependency] = true
	end
end
return table.freeze(ServiceContract)
