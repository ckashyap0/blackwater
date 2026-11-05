--!strict
local TableUtil = {}
function TableUtil.DeepFreeze<T>(value: T): T
	local seen: {[any]: boolean} = {}
	local function visit(item: any)
		if type(item) ~= "table" or seen[item] then return end
		seen[item] = true
		for key,child in pairs(item) do visit(key); visit(child) end
		if not table.isfrozen(item) then table.freeze(item) end
	end
	visit(value)
	return value
end
function TableUtil.DeepClone<T>(value: T): T
	local seen: {[any]: any} = {}
	local function visit(item: any): any
		if type(item) ~= "table" then return item end
		if seen[item] then return seen[item] end
		local copy = {}
		seen[item] = copy
		for key,child in pairs(item) do copy[visit(key)] = visit(child) end
		return copy
	end
	return visit(value) :: T
end
return table.freeze(TableUtil)
