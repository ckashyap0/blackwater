--!strict
local Validation = {}
function Validation.IsInteger(value: any, minimum: number, maximum: number): boolean
	return type(value) == "number" and value == value and value >= minimum
		and value <= maximum and value % 1 == 0
end
function Validation.IsIdentifier(value: any, maximumLength: number): boolean
	return type(value) == "string" and #value > 0 and #value <= maximumLength
		and string.match(value, "^[%w_%-]+$") ~= nil
end
function Validation.HasExactKeys(value: any, allowed: {[string]: boolean}, maximum: number): boolean
	if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
	local count = 0
	for key in pairs(value) do
		count += 1
		if count > maximum or type(key) ~= "string" or allowed[key] ~= true then return false end
	end
	return true
end
return table.freeze(Validation)
