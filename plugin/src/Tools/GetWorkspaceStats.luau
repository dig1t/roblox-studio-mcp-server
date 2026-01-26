local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

-- Helper to resolve a path string to an Instance
local function resolvePath(pathStr: string): Instance?
	if not pathStr or pathStr == "" then
		return workspace
	end

	local parts = string.split(pathStr, ".")
	local current: Instance = game

	for _, part in parts do
		local child = current:FindFirstChild(part)
		if not child then
			return nil
		end
		current = child
	end

	return current
end

-- Helper to convert Color3 to an array of RGB values (0-255)
local function color3ToArray(color: Color3): { number }
	return {
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
	}
end

-- Helper to create a color key for grouping
local function colorKey(color: Color3): string
	local rgb = color3ToArray(color)
	return string.format("%d,%d,%d", rgb[1], rgb[2], rgb[3])
end

-- Calculate standard deviation
local function calculateStdDev(values: { number }, mean: number): number
	if #values < 2 then
		return 0
	end

	local sumSquaredDiff = 0
	for _, value in values do
		local diff = value - mean
		sumSquaredDiff += diff * diff
	end

	return math.sqrt(sumSquaredDiff / #values)
end

-- Calculate uniformity score based on coefficient of variation
-- Higher score (> 0.8) means parts are too uniform
-- Lower score (< 0.5) means good natural variation
local function calculateUniformityScore(stdDevX: number, stdDevY: number, stdDevZ: number, meanX: number, meanY: number, meanZ: number): number
	-- Coefficient of variation (CV) = stdDev / mean
	-- Lower CV means more uniform
	-- We invert it: uniformityScore = 1 - normalizedCV

	local cvX = if meanX > 0 then stdDevX / meanX else 0
	local cvY = if meanY > 0 then stdDevY / meanY else 0
	local cvZ = if meanZ > 0 then stdDevZ / meanZ else 0

	local avgCV = (cvX + cvY + cvZ) / 3

	-- Normalize CV to a 0-1 scale
	-- CV of 0 = perfectly uniform = score of 1.0
	-- CV of 1 or higher = very varied = score of 0.0
	local uniformityScore = math.max(0, 1 - avgCV)

	-- Round to 2 decimal places
	return math.floor(uniformityScore * 100 + 0.5) / 100
end

local function handleGetWorkspaceStats(args: Types.ToolArgs): string?
	if not args["GetWorkspaceStats"] then
		return nil
	end

	local statsArgs: Types.GetWorkspaceStatsArgs = args["GetWorkspaceStats"]

	local path = statsArgs.path
	local includeSizes = if statsArgs.include_sizes ~= nil then statsArgs.include_sizes else false
	local includeColors = if statsArgs.include_colors ~= nil then statsArgs.include_colors else false

	-- Resolve target instance
	local target: Instance
	if path and path ~= "" then
		local resolved = resolvePath(path)
		if not resolved then
			return HttpService:JSONEncode({
				success = false,
				error = "Could not resolve path: " .. path,
			})
		end
		target = resolved
	else
		target = workspace
	end

	-- Initialize counters
	local partCount = 0
	local modelCount = 0

	-- Size tracking
	local sizesX: { number } = {}
	local sizesY: { number } = {}
	local sizesZ: { number } = {}

	-- Color tracking
	local colorCounts: { [string]: number } = {}
	local totalColoredParts = 0

	-- Recursive function to traverse descendants
	local function processInstance(instance: Instance)
		if instance:IsA("Model") then
			modelCount += 1
		end

		if instance:IsA("BasePart") then
			partCount += 1

			-- Collect size data
			if includeSizes then
				local size = instance.Size
				table.insert(sizesX, size.X)
				table.insert(sizesY, size.Y)
				table.insert(sizesZ, size.Z)
			end

			-- Collect color data
			if includeColors then
				local color = instance.Color
				local key = colorKey(color)
				colorCounts[key] = (colorCounts[key] or 0) + 1
				totalColoredParts += 1
			end
		end

		-- Process children
		for _, child in instance:GetChildren() do
			processInstance(child)
		end
	end

	-- Start processing from target
	processInstance(target)

	-- Build response
	local response: { [string]: any } = {
		success = true,
		partCount = partCount,
		modelCount = modelCount,
	}

	-- Calculate size statistics if requested
	if includeSizes and partCount > 0 then
		-- Calculate min, max, mean for each dimension
		local minX, maxX, sumX = math.huge, -math.huge, 0
		local minY, maxY, sumY = math.huge, -math.huge, 0
		local minZ, maxZ, sumZ = math.huge, -math.huge, 0

		for i, x in sizesX do
			minX = math.min(minX, x)
			maxX = math.max(maxX, x)
			sumX += x

			local y = sizesY[i]
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
			sumY += y

			local z = sizesZ[i]
			minZ = math.min(minZ, z)
			maxZ = math.max(maxZ, z)
			sumZ += z
		end

		local meanX = sumX / partCount
		local meanY = sumY / partCount
		local meanZ = sumZ / partCount

		local stdDevX = calculateStdDev(sizesX, meanX)
		local stdDevY = calculateStdDev(sizesY, meanY)
		local stdDevZ = calculateStdDev(sizesZ, meanZ)

		local uniformityScore = calculateUniformityScore(stdDevX, stdDevY, stdDevZ, meanX, meanY, meanZ)

		-- Round values for cleaner output
		local function round(n: number, decimals: number?): number
			local mult = 10 ^ (decimals or 1)
			return math.floor(n * mult + 0.5) / mult
		end

		response.sizeStats = {
			min = { x = round(minX), y = round(minY), z = round(minZ) },
			max = { x = round(maxX), y = round(maxY), z = round(maxZ) },
			mean = { x = round(meanX), y = round(meanY), z = round(meanZ) },
			stdDev = { x = round(stdDevX), y = round(stdDevY), z = round(stdDevZ) },
			uniformityScore = uniformityScore,
		}
	end

	-- Calculate color statistics if requested
	if includeColors and totalColoredParts > 0 then
		-- Count unique colors
		local uniqueColors = 0
		local colorList: { { key: string, count: number } } = {}

		for key, count in colorCounts do
			uniqueColors += 1
			table.insert(colorList, { key = key, count = count })
		end

		-- Sort by count descending to find dominant colors
		table.sort(colorList, function(a, b)
			return a.count > b.count
		end)

		-- Get top 5 dominant colors with percentages
		local dominantColors: { { color: { number }, percentage: number } } = {}
		local maxDominant = math.min(5, #colorList)

		for i = 1, maxDominant do
			local entry = colorList[i]
			local parts = string.split(entry.key, ",")
			local rgb = {
				tonumber(parts[1]) :: number,
				tonumber(parts[2]) :: number,
				tonumber(parts[3]) :: number,
			}
			local percentage = math.floor((entry.count / totalColoredParts) * 1000 + 0.5) / 10

			table.insert(dominantColors, {
				color = rgb,
				percentage = percentage,
			})
		end

		response.colorStats = {
			uniqueColors = uniqueColors,
			dominantColors = dominantColors,
		}
	end

	return HttpService:JSONEncode(response)
end

return handleGetWorkspaceStats :: Types.ToolFunction
