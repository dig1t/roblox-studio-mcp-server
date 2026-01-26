local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local function getInstanceFromPath(path: string): Instance?
	local parts = string.split(path, ".")
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

local function handleGetModelBounds(args: Types.ToolArgs): string?
	if not args["GetModelBounds"] then
		return nil
	end

	local toolArgs: Types.GetModelBoundsArgs = args["GetModelBounds"]
	local instance = getInstanceFromPath(toolArgs.path)

	if not instance then
		error("Instance not found: " .. toolArgs.path)
	end

	local cf: CFrame
	local size: Vector3

	if instance:IsA("Model") then
		cf, size = instance:GetBoundingBox()
	elseif instance:IsA("BasePart") then
		cf = instance.CFrame
		size = instance.Size
	else
		error("Instance must be a Model or BasePart, got: " .. instance.ClassName)
	end

	local halfSize = size / 2
	local min = cf.Position - halfSize
	local max = cf.Position + halfSize

	return HttpService:JSONEncode({
		success = true,
		bounds = {
			min = { x = min.X, y = min.Y, z = min.Z },
			max = { x = max.X, y = max.Y, z = max.Z },
			size = { x = size.X, y = size.Y, z = size.Z },
			center = { x = cf.Position.X, y = cf.Position.Y, z = cf.Position.Z },
		},
	})
end

return handleGetModelBounds :: Types.ToolFunction
