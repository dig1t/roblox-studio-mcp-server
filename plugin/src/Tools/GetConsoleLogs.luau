local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local ConsoleBuffer = require(Main.ConsoleBuffer)
local HttpService = game:GetService("HttpService")

local function handleGetConsoleLogs(args: Types.ToolArgs): string?
	if not args["GetConsoleLogs"] then
		return nil
	end

	local getLogsArgs: Types.GetConsoleLogsArgs = args["GetConsoleLogs"]

	local sinceSequence = getLogsArgs.since_sequence
	local levelFilter = getLogsArgs.level_filter
	local limit = getLogsArgs.limit
	local clearAfterRead = getLogsArgs.clear_after_read

	-- Validate level_filter if provided
	if levelFilter and levelFilter ~= "all" and levelFilter ~= "info" and levelFilter ~= "warn" and levelFilter ~= "error" then
		return HttpService:JSONEncode({
			success = false,
			error = "Invalid level_filter. Must be 'all', 'info', 'warn', or 'error'.",
		})
	end

	-- Get logs from buffer
	local result = ConsoleBuffer.getLogsSince(sinceSequence, levelFilter, limit)

	-- Clear buffer if requested
	if clearAfterRead then
		ConsoleBuffer.clearLogs()
	end

	return HttpService:JSONEncode({
		success = true,
		logs = result.logs,
		currentSequence = result.currentSequence,
		hasMore = result.hasMore,
		overflow = result.overflow,
	})
end

return handleGetConsoleLogs :: Types.ToolFunction
