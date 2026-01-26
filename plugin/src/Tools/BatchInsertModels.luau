local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")

type GetFreeModelsResponse = {
	[number]: {
		CurrentStartIndex: number,
		TotalCount: number,
		Results: {
			[number]: {
				Name: string,
				AssetId: number,
				AssetVersionId: number,
				CreatorName: string,
			},
		},
	},
}

local function toTitleCase(str: string): string
	local function titleCase(first: string, rest: string)
		return first:upper() .. rest:lower()
	end

	local intermediate = string.gsub(str, "(%a)([%w_']*)", titleCase :: (string) -> string)
	return intermediate:gsub("%s+", "")
end

local function collapseObjectsIntoContainer(objects: { Instance }): Instance?
	local isPhysical = false
	for _, object in objects do
		if object:IsA("PVInstance") then
			isPhysical = true
			break
		end
	end

	if isPhysical then
		local model = Instance.new("Model")
		for _, object in objects do
			object.Parent = model
		end
		return model
	end

	if #objects > 1 then
		local folder = Instance.new("Folder")
		for _, object in objects do
			object.Parent = folder
		end
		return folder
	end

	return objects[1]
end

local function loadAsset(assetId: number): Instance?
	local objects = game:GetObjects("rbxassetid://" .. assetId)
	return collapseObjectsIntoContainer(objects)
end

local function getAssetId(query: string): number?
	local results: GetFreeModelsResponse = InsertService:GetFreeModels(query, 0)
	if not results[1] or not results[1].Results or #results[1].Results == 0 then
		return nil
	end
	return results[1].Results[1].AssetId
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

local function generateUniqueName(parent: Instance, baseName: string): string
	local name = baseName
	local i = 1
	while parent:FindFirstChild(name) do
		name = baseName .. i
		i += 1
	end
	return name
end

local function insertModel(entry: Types.BatchModelEntry, index: number): { success: boolean, index: number, name: string?, path: string?, error: string? }
	local success, result = pcall(function()
		local assetId = getAssetId(entry.query)
		if not assetId then
			error("Failed to find asset for query: " .. entry.query)
		end

		local instance = loadAsset(assetId)
		if not instance then
			error("Failed to load asset")
		end

		local parent = resolveParent(entry.parent)
		local baseName = entry.name or toTitleCase(entry.query)
		local finalName = generateUniqueName(parent, baseName)
		instance.Name = finalName

		if instance:IsA("Model") then
			local cframe = CFrame.new(0, 0, 0)

			if entry.position then
				cframe = CFrame.new(entry.position.x, entry.position.y, entry.position.z)
			end

			if entry.rotation then
				local rotCFrame = CFrame.Angles(
					math.rad(entry.rotation.x),
					math.rad(entry.rotation.y),
					math.rad(entry.rotation.z)
				)
				cframe = cframe * rotCFrame
			end

			instance:PivotTo(cframe)

			if entry.scale then
				instance:ScaleTo(entry.scale.x)
			end
		elseif instance:IsA("BasePart") then
			if entry.position then
				instance.Position = Vector3.new(entry.position.x, entry.position.y, entry.position.z)
			end

			if entry.rotation then
				instance.Orientation = Vector3.new(entry.rotation.x, entry.rotation.y, entry.rotation.z)
			end

			if entry.scale then
				instance.Size = instance.Size * Vector3.new(entry.scale.x, entry.scale.y, entry.scale.z)
			end
		end

		instance.Parent = parent

		return {
			name = finalName,
			path = instance:GetFullName(),
		}
	end)

	if success then
		return {
			success = true,
			index = index,
			name = result.name,
			path = result.path,
		}
	else
		return {
			success = false,
			index = index,
			error = tostring(result),
		}
	end
end

local function handleBatchInsertModels(args: Types.ToolArgs): string?
	if not args["BatchInsertModels"] then
		return nil
	end

	local batchArgs: Types.BatchInsertModelsArgs = args["BatchInsertModels"]
	if type(batchArgs.models) ~= "table" then
		error("Missing models array in BatchInsertModels")
	end

	local results = {
		success = true,
		inserted = 0,
		failed = {} :: { { index: number, error: string } },
		instances = {} :: { { index: number, name: string, path: string } },
	}

	for i, entry in batchArgs.models do
		local result = insertModel(entry, i)

		if result.success then
			results.inserted += 1
			table.insert(results.instances, {
				index = result.index,
				name = result.name,
				path = result.path,
			})
		else
			results.success = false
			table.insert(results.failed, {
				index = result.index,
				error = result.error,
			})
		end
	end

	return HttpService:JSONEncode(results)
end

return handleBatchInsertModels :: Types.ToolFunction
