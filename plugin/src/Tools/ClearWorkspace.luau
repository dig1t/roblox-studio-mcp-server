local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local function isInRegion(instance: Instance, region: Types.Region): boolean
	if not instance:IsA("BasePart") and not instance:IsA("Model") then
		return true
	end

	local position: Vector3
	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart then
			position = primaryPart.Position
		else
			local cframe, _ = instance:GetBoundingBox()
			position = cframe.Position
		end
	else
		position = (instance :: BasePart).Position
	end

	local minPos = Vector3.new(region.min.x, region.min.y, region.min.z)
	local maxPos = Vector3.new(region.max.x, region.max.y, region.max.z)

	return position.X >= minPos.X and position.X <= maxPos.X
		and position.Y >= minPos.Y and position.Y <= maxPos.Y
		and position.Z >= minPos.Z and position.Z <= maxPos.Z
end

local function handleClearWorkspace(args: Types.ToolArgs): string?
	if not args["ClearWorkspace"] then
		return nil
	end

	local clearArgs: Types.ClearWorkspaceArgs = args["ClearWorkspace"]

	local preserveCamera = if clearArgs.preserve_camera ~= nil then clearArgs.preserve_camera else true
	local preserveTerrain = if clearArgs.preserve_terrain ~= nil then clearArgs.preserve_terrain else true
	local preserveNames = clearArgs.preserve_names or {}
	local region = clearArgs.region

	local preserveSet = {}
	for _, name in preserveNames do
		preserveSet[name] = true
	end

	local removedCount = 0
	local preservedCount = 0

	local children = workspace:GetChildren()

	for _, child in children do
		local shouldPreserve = false

		if preserveCamera and child:IsA("Camera") then
			shouldPreserve = true
		elseif preserveTerrain and child:IsA("Terrain") then
			shouldPreserve = true
		elseif preserveSet[child.Name] then
			shouldPreserve = true
		elseif region and not isInRegion(child, region) then
			shouldPreserve = true
		end

		if shouldPreserve then
			preservedCount += 1
		else
			-- Terrain can't be destroyed, must be cleared instead
			if child:IsA("Terrain") then
				child:Clear()
			else
				child:Destroy()
			end
			removedCount += 1
		end
	end

	return HttpService:JSONEncode({
		success = true,
		removedCount = removedCount,
		preservedCount = preservedCount,
	})
end

return handleClearWorkspace :: Types.ToolFunction
