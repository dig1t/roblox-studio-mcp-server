local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

-- Global storage for saved scenes
if not _G.SavedScenes then
	_G.SavedScenes = {}
end

local MATERIAL_MAP: { [string]: Enum.Material } = {
	Plastic = Enum.Material.Plastic,
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Wood = Enum.Material.Wood,
	WoodPlanks = Enum.Material.WoodPlanks,
	Slate = Enum.Material.Slate,
	Concrete = Enum.Material.Concrete,
	CorrodedMetal = Enum.Material.CorrodedMetal,
	DiamondPlate = Enum.Material.DiamondPlate,
	Foil = Enum.Material.Foil,
	Grass = Enum.Material.Grass,
	Ice = Enum.Material.Ice,
	Marble = Enum.Material.Marble,
	Granite = Enum.Material.Granite,
	Brick = Enum.Material.Brick,
	Pebble = Enum.Material.Pebble,
	Sand = Enum.Material.Sand,
	Fabric = Enum.Material.Fabric,
	Neon = Enum.Material.Neon,
	Metal = Enum.Material.Metal,
	Glass = Enum.Material.Glass,
	ForceField = Enum.Material.ForceField,
}

local SHAPE_MAP: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
	Wedge = Enum.PartType.Wedge,
	CornerWedge = Enum.PartType.CornerWedge,
}

local function deserializeVector3(v: { x: number, y: number, z: number }): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

local function deserializeCFrame(cf: { position: { x: number, y: number, z: number }, rotation: { number } }): CFrame
	local pos = deserializeVector3(cf.position)
	local rot = cf.rotation
	return CFrame.new(pos) * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
end

local function deserializeColor3(c: { r: number, g: number, b: number }): Color3
	return Color3.new(c.r, c.g, c.b)
end

local function resolveParent(parentPath: string?): Instance
	if not parentPath or parentPath == "" then
		return workspace
	end

	local parts = string.split(parentPath, ".")
	local current: Instance = game

	for _, part in parts do
		local child = current:FindFirstChild(part)
		if not child then
			return workspace
		end
		current = child
	end

	return current
end

local function deserializeInstance(data: { [string]: any }, parent: Instance, offset: Vector3): Instance?
	local success, instance = pcall(function()
		local className = data.ClassName
		local inst: Instance

		if className == "Part" then
			local part = Instance.new("Part")
			if data.Shape then
				part.Shape = SHAPE_MAP[data.Shape] or Enum.PartType.Block
			end
			inst = part
		elseif className == "Model" then
			inst = Instance.new("Model")
		elseif className == "Folder" then
			inst = Instance.new("Folder")
		elseif className == "MeshPart" then
			inst = Instance.new("Part")
		elseif className == "UnionOperation" then
			inst = Instance.new("Part")
		elseif className == "SpawnLocation" then
			inst = Instance.new("SpawnLocation")
		else
			inst = Instance.new("Part")
		end

		inst.Name = data.Name

		if inst:IsA("BasePart") then
			if data.Size then
				inst.Size = deserializeVector3(data.Size)
			end
			if data.CFrame then
				local cf = deserializeCFrame(data.CFrame)
				cf = cf + offset
				inst.CFrame = cf
			end
			if data.Color then
				inst.Color = deserializeColor3(data.Color)
			end
			if data.Material then
				inst.Material = MATERIAL_MAP[data.Material] or Enum.Material.Plastic
			end
			if data.Transparency then
				inst.Transparency = data.Transparency
			end
			if data.Anchored ~= nil then
				inst.Anchored = data.Anchored
			end
			if data.CanCollide ~= nil then
				inst.CanCollide = data.CanCollide
			end
		end

		if data.Children then
			for _, childData in data.Children do
				deserializeInstance(childData, inst, offset)
			end
		end

		if inst:IsA("Model") and data.PrimaryPartName then
			local primaryPart = inst:FindFirstChild(data.PrimaryPartName)
			if primaryPart and primaryPart:IsA("BasePart") then
				(inst :: Model).PrimaryPart = primaryPart
			end
		end

		inst.Parent = parent
		return inst
	end)

	if success then
		return instance
	end
	return nil
end

local function clearWorkspace()
	for _, child in workspace:GetChildren() do
		if not child:IsA("Camera") and not child:IsA("Terrain") then
			child:Destroy()
		end
	end
end

local function handleLoadScene(args: Types.ToolArgs): string?
	if not args["LoadScene"] then
		return nil
	end

	local loadArgs: Types.LoadSceneArgs = args["LoadScene"]
	local sceneName = loadArgs.name

	local sceneData = _G.SavedScenes[sceneName]
	if not sceneData then
		return HttpService:JSONEncode({
			success = false,
			error = "Scene not found: " .. sceneName,
			availableScenes = (function()
				local scenes = {}
				for name in _G.SavedScenes do
					table.insert(scenes, name)
				end
				return scenes
			end)(),
		})
	end

	if loadArgs.clear_existing then
		clearWorkspace()
	end

	local parent = resolveParent(loadArgs.parent)
	local offset = Vector3.new(0, 0, 0)
	if loadArgs.position then
		offset = Vector3.new(loadArgs.position.x, loadArgs.position.y, loadArgs.position.z)
	end

	local loadedCount = 0
	local failedCount = 0

	for _, objectData in sceneData.objects do
		local instance = deserializeInstance(objectData, parent, offset)
		if instance then
			loadedCount += 1
		else
			failedCount += 1
		end
	end

	return HttpService:JSONEncode({
		success = true,
		name = sceneName,
		loadedCount = loadedCount,
		failedCount = failedCount,
		offset = if loadArgs.position then loadArgs.position else nil,
	})
end

return handleLoadScene :: Types.ToolFunction
