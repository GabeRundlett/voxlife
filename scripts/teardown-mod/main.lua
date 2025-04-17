--[[
#include scripts/libraries/Automatic.lua
#include scripts/libraries/loader.lua
#include scripts/libraries/LnL.lua
]]

---@alias autu_script { path:string, identification:string, tags:string[], environment:table?, reload_count:integer }

---@type autu_script[]
local scripts = {
	{ path = 'tools.lua', identification = 't', tags = {  } },
}

for i=1, #scripts do
	scripts[i].reload_count = 0
end

global_file_saves = {}

local function rawcall(t, k, ...)
	if t then
		local raw = rawget(t, k)
		if raw then
			local arguments = { pcall(raw, ...) }

			if not arguments[1] then DebugPrint(arguments[2]) end
			return unpack(arguments, 2)
		end
	end
end

local function reload_script(i)
	local script = scripts[i]
	script.reload_count = script.reload_count + 1

	local before_kb = collectgarbage 'count'
	
	local reload_data = { rawcall(script.environment, 'reload') }
	
	script.environment = nil
	collectgarbage 'collect'
	local after_kb = collectgarbage 'count'

	print(string.format('[%s Reloaded] : [Script Handle %s] : [Reload %s] : [File %s] : [%dkb collected]',
		Loader.mod_id,
		AutoGetScriptHandle(),
		script.reload_count,
		script.path,
		before_kb - after_kb
	))

	_, script.environment = Loader.File(script.path)
	return reload_data
end

local function hot_reload()
	local reload_data = {}

	for i = 1, #scripts do
		reload_data[i] = reload_script(i)
	end

	for i = 1, #scripts do
		rawcall(scripts[i].environment, 'init', unpack(reload_data[i]))
	end
end

---@param script_identification string
---@return integer?
function get_script_index(script_identification)
	for i = 1, #scripts do
		if scripts[i].identification == script_identification then
			return i
		end
	end

	return
end

---@param script_identification string
---@return table?
function get_script_environment(script_identification)
	-- print(AutoGetStackTrace(1))
	local index = get_script_index(script_identification)

	if index then
		return scripts[index].environment
    else
		DebugPrint(string.format('[%s] Failed get script environment from identification [%s]: Script not found!',
			Loader.mod_id,
			script_identification
		))
	end
end

---@param tag string
---@return table[]
function get_script_environments_with_tag(tag)
	local found = {}
	
	for i = 1, #scripts do
		local s = scripts[i]
		if AutoTableContains(s.tags, tag) then
			found[#found+1] = s.environment
		end
	end

	return found
end

function init( ... )
	for i=1, #scripts do
		local script = scripts[i]
        _, script.environment = Loader.File(script.path)
	end

	for i=1, #scripts do
		rawcall(scripts[i].environment, 'init', ...)
	end
end

function handleCommand( ... )
    local cmd = ({...})[1]

	if cmd == 'quicksave' then
		for i = 1, #scripts do
			local script = scripts[i]
			local data = { rawcall(script.environment, 'quicksave') }
			-- AutoInspect(data, i .. ' : quicksave : ', nil, 1)

			global_file_saves[i] = data
		end
	end
	
    if cmd == 'quickload' then
		for i=1, #scripts do
			local script = scripts[i]
			_, script.environment = Loader.File(script.path)
			
			local data = global_file_saves[i]
			-- AutoInspect(data, i .. ' : quickload : ', nil, 1)

			rawcall(script.environment, 'quickload', unpack(data))
			
			global_file_saves[i] = nil
		end
	end

	for i=1, #scripts do
		rawcall(scripts[i].environment, 'handleCommand', ...)
	end
end

function tick( ... )
	if InputPressed 'l' then
		hot_reload()
		return
	end

	for i = 1, #scripts do
		rawcall(scripts[i].environment, 'tick', ...)
	end
end

function update( ... )
	for i = 1, #scripts do
		rawcall(scripts[i].environment, 'update', ... )
	end
end

function postPhysicsUpdate(...)
	for i = 1, #scripts do
		rawcall(scripts[i].environment, 'postPhysicsUpdate', ...)
	end
end

function draw(...)
	for i = 1, #scripts do
		UiPush()
		rawcall(scripts[i].environment, 'draw', ... )
		UiPop()
	end
end

function render(...)
	for i = 1, #scripts do
		rawcall(scripts[i].environment, 'render', ...)
	end
end

function export(file, str)
	return assert(SaveToFile, 'TDLL NOT INSTALLED / CANNOT SAVE TO FILE')(file, str)
end