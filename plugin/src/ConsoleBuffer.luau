--[[
	ConsoleBuffer: Circular buffer for capturing global console logs via LogService.MessageOut.
	Provides polling support with sequence numbers for incremental log retrieval.
]]

local LogService = game:GetService("LogService")

local MAX_BUFFER_SIZE = 500

export type LogEntry = {
	seq: number,
	timestamp: number,
	level: string, -- "info", "warn", "error"
	source: string,
	message: string,
}

export type ConsoleBuffer = {
	initialize: () -> (),
	addLog: (level: string, message: string, source: string?) -> (),
	getLogsSince: (sinceSequence: number?, levelFilter: string?, limit: number?) -> { logs: { LogEntry }, currentSequence: number, hasMore: boolean, overflow: boolean },
	clearLogs: () -> (),
	getCurrentSequence: () -> number,
}

local buffer: { LogEntry } = {}
local headIndex = 1 -- Points to oldest entry (or next write position if buffer not full)
local count = 0 -- Current number of entries in buffer
local currentSequence = 0 -- Monotonically increasing sequence number
local lowestAvailableSeq = 1 -- Lowest sequence still in buffer
local startTime = os.clock()
local connection: RBXScriptConnection? = nil

local function mapMessageType(messageType: Enum.MessageType): string
	if messageType == Enum.MessageType.MessageOutput then
		return "info"
	elseif messageType == Enum.MessageType.MessageWarning then
		return "warn"
	elseif messageType == Enum.MessageType.MessageError then
		return "error"
	elseif messageType == Enum.MessageType.MessageInfo then
		return "info"
	else
		return "info"
	end
end

local function addLog(level: string, message: string, source: string?)
	currentSequence += 1

	local entry: LogEntry = {
		seq = currentSequence,
		timestamp = os.clock() - startTime,
		level = level,
		source = source or "Roblox",
		message = message,
	}

	if count < MAX_BUFFER_SIZE then
		-- Buffer not full yet
		count += 1
		buffer[count] = entry
	else
		-- Buffer full, overwrite oldest entry (circular)
		buffer[headIndex] = entry
		headIndex = (headIndex % MAX_BUFFER_SIZE) + 1
		lowestAvailableSeq = buffer[headIndex].seq
	end
end

local function initialize()
	if connection then
		return -- Already initialized
	end

	-- Reset state
	buffer = {}
	headIndex = 1
	count = 0
	currentSequence = 0
	lowestAvailableSeq = 1
	startTime = os.clock()

	-- Subscribe to LogService.MessageOut for global capture
	connection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
		local level = mapMessageType(messageType)
		addLog(level, message, "Roblox")
	end)
end

local function getLogsSince(sinceSequence: number?, levelFilter: string?, limit: number?): { logs: { LogEntry }, currentSequence: number, hasMore: boolean, overflow: boolean }
	local filterSeq = sinceSequence or 0
	local maxLimit = limit or 100
	local filter = levelFilter or "all"

	local overflow = false
	if filterSeq > 0 and filterSeq < lowestAvailableSeq then
		overflow = true
	end

	local logs: { LogEntry } = {}
	local collected = 0

	-- Iterate through buffer in sequence order
	if count > 0 then
		for i = 1, count do
			local actualIndex = if count < MAX_BUFFER_SIZE
				then i
				else ((headIndex - 1 + i - 1) % MAX_BUFFER_SIZE) + 1
			local entry = buffer[actualIndex]

			if entry and entry.seq > filterSeq then
				-- Apply level filter
				local includeEntry = false
				if filter == "all" then
					includeEntry = true
				elseif filter == "error" and entry.level == "error" then
					includeEntry = true
				elseif filter == "warn" and (entry.level == "warn" or entry.level == "error") then
					includeEntry = true
				elseif filter == "info" then
					includeEntry = true
				end

				if includeEntry then
					if collected < maxLimit then
						collected += 1
						table.insert(logs, entry)
					end
				end
			end
		end
	end

	-- Check if there are more entries beyond the limit
	local hasMore = false
	if #logs == maxLimit and count > 0 then
		local lastLog = logs[#logs]
		if lastLog then
			-- Check if there are entries with higher sequence numbers
			for i = 1, count do
				local actualIndex = if count < MAX_BUFFER_SIZE
					then i
					else ((headIndex - 1 + i - 1) % MAX_BUFFER_SIZE) + 1
				local entry = buffer[actualIndex]
				if entry and entry.seq > lastLog.seq then
					hasMore = true
					break
				end
			end
		end
	end

	return {
		logs = logs,
		currentSequence = currentSequence,
		hasMore = hasMore,
		overflow = overflow,
	}
end

local function clearLogs()
	buffer = {}
	headIndex = 1
	count = 0
	lowestAvailableSeq = currentSequence + 1
end

local function getCurrentSequence(): number
	return currentSequence
end

local ConsoleBuffer: ConsoleBuffer = {
	initialize = initialize,
	addLog = addLog,
	getLogsSince = getLogsSince,
	clearLogs = clearLogs,
	getCurrentSequence = getCurrentSequence,
}

return ConsoleBuffer
