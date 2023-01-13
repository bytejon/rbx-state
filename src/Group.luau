type map = {[string]: any}
type callback = (...any) -> (...any)

local threads = {} -- thread pool

local load = function(code: callback, ...: any): thread
	local thread = coroutine.create(code)
	coroutine.resume(thread, ...)
	return thread
end

-- main function for thread reusability
local main = function()
	local thread = coroutine.running()
	local ref, code, value, argc, argv = nil, nil, nil, nil, nil
	while true do
		ref, code, value, argc, argv = coroutine.yield()
		if ref == threads then
			code(value, table.unpack(argv, 1, argc))
			table.insert(threads, thread)
		end
	end
	return nil
end

-- returns the state table or also creates it if it does not exist
local get_state = function(self, key, value)
	if not self._states[key] then
		self._states[key] = { value = value, initial = value, cns = {} }
	end
	return self._states[key]
end

local group = {}
export type Group = typeof(group)

-- returns the value specified by the key
function group:get(key: string): any
	return get_state(self, key).value
end

-- sets the value specified to a new value if they are not the same (force option)
function group:set(key: string, value: any, force: boolean?): nil
	local state = get_state(self, key, value)
	if state.value ~= value or force == true then
		state.value = value
		for _, data in state.cns do
			coroutine.resume(table.remove(threads) or load(main), threads, data[1], value, data[2], data[3])
		end
	end
	return nil
end

-- sets the value to the return value of the callback if non-nil
function group:exec(key: string, code: callback, ...: any): nil
	local state = get_state(self, key)
	local value = code(state.value, ...)
	if value ~= nil then
		state.value = value
		for _, data in state.cns do
			coroutine.resume(table.remove(threads) or load(main), threads, data[1], value, data[2], data[3])
		end
	end
	return nil
end

-- sets the value to the initial value if they are not the same (force option)
function group:reset(key: string, force: boolean?): nil
	local state = get_state(self, key)
	local value = state.initial
	if state.value ~= value or force == true then
		state.value = value
		for _, data in state.cns do
			coroutine.resume(table.remove(threads) or load(main), threads, data[1], value, data[2], data[3])
		end
	end
	return nil
end

-- calls callback when state value changes
-- returns a function to disconnect listener when called
function group:listen(key: string, code: callback, ...: any): callback
	local state = get_state(self, key)
	local cns = state.cns
	local connection = {code, select('#', ...), {...}}
	table.insert(cns, connection)
	return function()
		table.remove(cns, table.find(cns, connection))
		return nil
	end
end

-- cleans up value and removes from states
function group:clean(key: string, code: callback?, ...: any): nil
	local state = get_state(self, key)
	local value = state.value
	if not code then
		local vtype = typeof(value)
		if vtype == "Instance" then
			value:Destroy()
		elseif vtype == "RBXScriptConnection" then
			value:Disconnect()
		elseif vtype == "function" then
			value()
		elseif vtype == "thread" then
			if coroutine.status(value) == "suspended" then
				coroutine.close(value)
			end
		elseif vtype == "table" then
			if value.Destroy then value:Destroy() end
			if value.Disconnect then value:Disconnect() end
		end
	else
		code(value, ...)
	end
	table.clear(state)
	self._states[key] = nil
	return nil
end

-- cleans up all states in the group without destroying
function group:clear(): nil
	for key in self._states do
		self:clean(key)
	end
	return nil
end

-- cleans up the group object
function group:destroy(): nil
	self:clear()
	table.clear(self)
	return nil
end

-- new state group constructor
return function(data: map): Group
	local self = table.clone(group)
	self._states = {}
	for k, v in data do
		self._states[k] = { value = v, initial = v, cns = {} }
	end
	return self
end
