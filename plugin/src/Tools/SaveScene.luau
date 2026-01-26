local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

-- Global storage for saved scenes
if not _G.SavedScenes then
	_G.SavedScenes = {}
end

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

local function serializeVector3(v: Vector3): { x: number, y: number, z: number }
	return { x = v.X, y = v.Y, z = v.Z }
end

local function serializeCFrame(cf: CFrame): { position: { x: number, y: number, z: number }, rotation: { number } }
	local rx, ry, rz = cf:ToOrientation()
	return {
		position = serializeVector3(cf.Position),
		rotation = { math.deg(rx), math.deg(ry), math.deg(rz) },
	}
end

local function serializeColor3(c: Color3): { r: number, g: number, b: number }
	return { r = c.R, g = c.G, b = c.B }
end

local function serializeInstance(instance: Instance): { [string]: any }?
	local data: { [string]: any } = {
		ClassName = instance.ClassName,
		Name = instance.Name,
		Children = {},
	}

	if instance:IsA("BasePart") then
		data.Size = serializeVector3(instance.Size)
		data.CFrame = serializeCFrame(instance.CFrame)
		data.Color = serializeColor3(instance.Color)
		data.Material = instance.Material.Name
		data.Transparency = instance.Transparency
		data.Anchored = instance.Anchored
		data.CanCollide = instance.CanCollide

		if instance:IsA("Part") then
			data.Shape = (instance :: Part).Shape.Name
		end
	elseif instance:IsA("Model") then
		if instance.PrimaryPart then
			data.PrimaryPartName = instance.PrimaryPart.Name
		end
		local cframe, size = instance:GetBoundingBox()
		data.BoundingBox = {
			cframe = serializeCFrame(cframe),
			size = serializeVector3(size),
		}
	end

	for _, child in instance:GetChildren() do
		if not child:IsA("Camera") and not child:IsA("Terrain") then
			local childData = serializeInstance(child)
			if childData then
				table.insert(data.Children, childData)
			end
		end
	end

	return data
end

local function handleSaveScene(args: Types.ToolArgs): string?
	if not args["SaveScene"] then
		return nil
	end

	local saveArgs: Types.SaveSceneArgs = args["SaveScene"]
	local sceneName = saveArgs.name

	local excludeSet = {}
	if saveArgs.exclude_names then
		for _, name in saveArgs.exclude_names do
			excludeSet[name] = true
		end
	end

	local sceneData = {
		name = sceneName,
		timestamp = os.time(),
		objects = {} :: { any },
		objectCount = 0,
	}

	for _, child in workspace:GetChildren() do
		if child:IsA("Camera") or child:IsA("Terrain") then
			continue
		end

		if excludeSet[child.Name] then
			continue
		end

		if saveArgs.region and not isInRegion(child, saveArgs.region) then
			continue
		end

		local instanceData = serializeInstance(child)
		if instanceData then
			table.insert(sceneData.objects, instanceData)
			sceneData.objectCount += 1
		end
	end

	_G.SavedScenes[sceneName] = sceneData

	return HttpService:JSONEncode({
		success = true,
		name = sceneName,
		objectCount = sceneData.objectCount,
		savedScenes = #_G.SavedScenes,
	})
end

return handleSaveScene :: Types.ToolFunction
