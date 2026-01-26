local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

-- Shared state table for cross-script communication
-- Scripts can use _G.BatchState to pass data between scripts
if not _G.BatchState then
	_G.BatchState = {}
end

local function getTableType(arg)
	local hasArray = false
	local hasTable = false
	for key, _value in arg do
		if typeof(key) == "number" then
			hasArray = true
		else
			hasTable = true
		end
		if hasArray and hasTable then
			break
		end
	end
	return hasArray, hasTable
end

local function serializeTable(arg): any
	if typeof(arg) == "table" then
		local _, isTable = getTableType(arg)

		local newArg = {}
		for key, value in arg do
			local newKey = serializeTable(key)
			newArg[if isTable then tostring(newKey) else newKey] = serializeTable(value)
		end
		return newArg
	elseif type(arg) == "userdata" then
		return tostring(arg) or "UNABLE_TO_SERIALIZE"
	end
	return arg
end

local function deepClone(t, cache)
	local clone = {}
	for key, value in t do
		local newKey = key
		if typeof(key) == "table" then
			if not cache[key] then
				cache[key] = deepClone(key, cache)
			end
			newKey = cache[key]
		end

		local newValue = value
		if typeof(value) == "table" then
			if not cache[value] then
				cache[value] = deepClone(value, cache)
			end
			newValue = cache[value]
		end

		clone[newKey] = newValue
	end
	return clone
end

local function toStrTable(t: { any }): { string }
	local clonedTable = deepClone(t, {})
	local strTable = table.create(#clonedTable)
	for i, arg in clonedTable do
		local serializedArg = serializeTable(arg)
		strTable[i] = if typeof(serializedArg) == "table"
			then HttpService:JSONEncode(serializedArg)
			else tostring(serializedArg)
	end
	return strTable
end

local function runSingleScript(code: string, index: number): { success: boolean, index: number, output: string?, error: string? }
	local output = ""

	local function addToOutput(header: string, ...)
		local strResults = toStrTable(table.pack(...))
		output ..= header .. " " .. table.concat(strResults, "\t") .. "\n"
	end

	local function executeCode()
		local chunk = loadstring(code) :: any
		if not chunk then
			error("Failed to parse script")
		end

		local chunkfenv = getfenv(chunk)

		local oldPrint = print
		chunkfenv.print = function(...)
			oldPrint(...)
			addToOutput("[OUTPUT]", ...)
		end

		local oldWarn = warn
		chunkfenv.warn = function(...)
			oldWarn(...)
			addToOutput("[WARNING]", ...)
		end

		local oldError = error
		chunkfenv.error = function(...)
			oldError(...)
			addToOutput("[ERROR]", ...)
		end

		local results = table.pack(chunk())
		if #results > 0 then
			addToOutput("[RETURNED RESULTS]", table.unpack(results))
		end

		return results
	end

	local ok, errorMessage = pcall(executeCode)
	if ok then
		return {
			success = true,
			index = index,
			output = if #output > 0 then output else nil,
		}
	else
		return {
			success = false,
			index = index,
			output = if #output > 0 then output else nil,
			error = tostring(errorMessage),
		}
	end
end

local function handleBatchRunCode(args: Types.ToolArgs): string?
	if not args["BatchRunCode"] then
		return nil
	end

	local batchArgs: Types.BatchRunCodeArgs = args["BatchRunCode"]
	if type(batchArgs.scripts) ~= "table" then
		error("Missing scripts array in BatchRunCode")
	end

	local stopOnError = if batchArgs.stop_on_error ~= nil then batchArgs.stop_on_error else true

	-- Clear shared state at the start of a batch
	_G.BatchState = {}

	local results = {
		success = true,
		executed = 0,
		results = {} :: { { index: number, success: boolean, output: string?, error: string?, description: string? } },
	}

	for i, entry in batchArgs.scripts do
		local scriptResult = runSingleScript(entry.code, i)

		results.executed += 1
		table.insert(results.results, {
			index = scriptResult.index,
			success = scriptResult.success,
			output = scriptResult.output,
			error = scriptResult.error,
			description = entry.description,
		})

		if not scriptResult.success then
			results.success = false
			if stopOnError then
				break
			end
		end
	end

	return HttpService:JSONEncode(results)
end

return handleBatchRunCode :: Types.ToolFunction
