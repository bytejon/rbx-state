--[=[ .luau

	| Group
	| bytejon
	| 2023
	
	A module for storing state objects in a key-value structure.
	Attempts to 'get' a state that has not been defined will return nil instead of erroring.

--]=]

-- typedefs
type map = { [string] : any }
type callback = (...any) -> (...any)

-- thread cache
local threads = {}

-- creates and resumes a new thread
local load = function(code: callback, ...: any): thread
	local thread = coroutine.create(code)
	coroutine.resume(thread, ...)
	return thread
end

-- main function enabling thread reuse
local main = function(): nil
	local thread = coroutine.running()
	local ref, code, argc, argv, value = nil, nil, nil, nil, nil
	while true do
		ref, code, argc, argv, value = coroutine.yield()
		if ref == threads then
			code(value, table.unpack(argv, 1, argc))
			table.insert(threads, thread)
		end
	end
	return nil
end

local module = {}
export type Group = typeof(module) & {
	state : map,
	cache : { [string] : map }
}

-- returns specified state table or also creates it if does not exist
local get_state = function(self: Group, key: string, value: any?)
	if self.cache[key] ==  nil then
		self.cache[key] = { value = value, cns = {} }
	end
	return self.cache[key]
end

-- wrapper function for setting the property of an object to a value
local set_prop = function(value, object, prop): nil
	object[prop] = value
	return nil
end

-- returns the state value specified by the key
function module.get(self: Group, key: string): any
	return if self.cache[key] then self.cache[key].value else nil
end

-- sets the state value specified by the key to the new value
function module.set(self: Group, key: string, value: any): nil
	local state = get_state(self, key)
	state.value = value
	self.state[key] = value
	for _, data in state.cns do
		coroutine.resume(table.remove(threads) or load(main), threads, data[1], data[2], data[3], value)
	end
	return nil
end

-- sets the state value specified by the key to the value returned by the callback if non-nil
function module.exec(self: Group, key: string, code: callback, ...: any): nil
	local state = get_state(self, key)
	local value = code(key, ...)
	if value ~= nil then
		state.value = value
		self.state[key] = value
		for _, data in state.cns do
			coroutine.resume(table.remove(threads) or load(main), threads, data[1], data[2], data[3], value)
		end
	end
	return nil
end

-- calls the callback when the state value specified by the key when the state emits
function module.listen(self: Group, key: string, code: callback, ...: any): callback
	local state = get_state(self, key)
	local conn = { code, select('#', ...), {...} }
	local cns = state.cns
	table.insert(cns, conn)
	return function()
		return table.remove(cns, table.find(cns, conn))
	end
end

-- binds an object's property value to the state value specified by the key
-- when the state value changes, the object property will change
function module.bind(self: Group, key: string, object: Instance, prop: string)
	return self:listen(key, set_prop, object, prop)
end

return module
