local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local function serializeVector3(v: Vector3): { x: number, y: number, z: number }
	return { x = v.X, y = v.Y, z = v.Z }
end

local function resolveInstance(path: string): Instance?
	if not path or path == "" then
		return nil
	end

	-- Handle special case of just "workspace"
	if path == "workspace" then
		return workspace
	end

	-- Handle special case of just "game"
	if path == "game" then
		return game
	end

	local parts = string.split(path, ".")
	local current: Instance

	-- Determine starting point
	local firstPart = parts[1]
	if firstPart == "game" then
		current = game
		table.remove(parts, 1)
	elseif firstPart == "workspace" then
		current = workspace
		table.remove(parts, 1)
	else
		-- Default to game if no explicit root
		current = game
	end

	-- Navigate the path
	for _, part in parts do
		local child = current:FindFirstChild(part)
		if not child then
			return nil
		end
		current = child
	end

	return current
end

local function countParts(instance: Instance): number
	local count = 0

	if instance:IsA("BasePart") then
		count = 1
	end

	for _, child in instance:GetDescendants() do
		if child:IsA("BasePart") then
			count += 1
		end
	end

	return count
end

local function getBounds(instance: Instance): { min: { x: number, y: number, z: number }, max: { x: number, y: number, z: number }, size: { x: number, y: number, z: number }, center: { x: number, y: number, z: number } }?
	local success, result = pcall(function()
		if instance:IsA("Model") then
			local cframe, size = instance:GetBoundingBox()
			local halfSize = size / 2
			local min = cframe.Position - halfSize
			local max = cframe.Position + halfSize

			return {
				min = serializeVector3(min),
				max = serializeVector3(max),
				size = serializeVector3(size),
				center = serializeVector3(cframe.Position),
			}
		elseif instance:IsA("BasePart") then
			local size = instance.Size
			local position = instance.Position
			local halfSize = size / 2
			local min = position - halfSize
			local max = position + halfSize

			return {
				min = serializeVector3(min),
				max = serializeVector3(max),
				size = serializeVector3(size),
				center = serializeVector3(position),
			}
		end

		return nil
	end)

	if success then
		return result
	end
	return nil
end

local function handleGetChildrenInfo(args: Types.ToolArgs): string?
	if not args["GetChildrenInfo"] then
		return nil
	end

	local getArgs: Types.GetChildrenInfoArgs = args["GetChildrenInfo"]
	local path = getArgs.path
	local includeBounds = getArgs.include_bounds or false

	-- Resolve the parent instance from the path
	local parent = resolveInstance(path)
	if not parent then
		return HttpService:JSONEncode({
			success = false,
			error = "Instance not found at path: " .. path,
		})
	end

	local children = {}
	for _, child in parent:GetChildren() do
		local childInfo: { [string]: any } = {
			name = child.Name,
			className = child.ClassName,
			partCount = countParts(child),
		}

		if includeBounds then
			local bounds = getBounds(child)
			if bounds then
				childInfo.bounds = bounds
			end
		end

		table.insert(children, childInfo)
	end

	return HttpService:JSONEncode({
		success = true,
		path = path,
		parentName = parent.Name,
		parentClassName = parent.ClassName,
		childCount = #children,
		children = children,
	})
end

return handleGetChildrenInfo :: Types.ToolFunction
