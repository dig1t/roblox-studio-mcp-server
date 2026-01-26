local Main = script:FindFirstAncestor("MCPStudioPlugin")
local Types = require(Main.Types)
local HttpService = game:GetService("HttpService")

local TERRAIN_MATERIALS = {
	Grass = Enum.Material.Grass,
	Sand = Enum.Material.Sand,
	Rock = Enum.Material.Rock,
	Snow = Enum.Material.Snow,
	Mud = Enum.Material.Mud,
	Ground = Enum.Material.Ground,
	Slate = Enum.Material.Slate,
	Concrete = Enum.Material.Concrete,
	Brick = Enum.Material.Brick,
	Cobblestone = Enum.Material.Cobblestone,
	Ice = Enum.Material.Ice,
	Salt = Enum.Material.Salt,
	Sandstone = Enum.Material.Sandstone,
	Limestone = Enum.Material.Limestone,
	Asphalt = Enum.Material.Asphalt,
	LeafyGrass = Enum.Material.LeafyGrass,
	Pavement = Enum.Material.Pavement,
	Water = Enum.Material.Water,
	Air = Enum.Material.Air,
}

local function getMaterial(name: string): Enum.Material
	return TERRAIN_MATERIALS[name] or Enum.Material.Grass
end

local function handleFillTerrainRegion(args: Types.ToolArgs): string?
	if not args["FillTerrainRegion"] then
		return nil
	end

	local fillArgs: Types.FillTerrainRegionArgs = args["FillTerrainRegion"]
	local terrain = workspace.Terrain

	local minPos = Vector3.new(fillArgs.region.min.x, fillArgs.region.min.y, fillArgs.region.min.z)
	local maxPos = Vector3.new(fillArgs.region.max.x, fillArgs.region.max.y, fillArgs.region.max.z)

	local material = getMaterial(fillArgs.material)
	local replaceAir = fillArgs.replace_air or false
	local resolution = 4

	local region = Region3.new(minPos, maxPos)

	if replaceAir then
		local regionSize = maxPos - minPos
		local voxelSize = region:ExpandToGrid(resolution).Size / resolution

		local materials, occupancies = terrain:ReadVoxels(region, resolution)

		for x = 1, voxelSize.X do
			for y = 1, voxelSize.Y do
				for z = 1, voxelSize.Z do
					if materials[x][y][z] == Enum.Material.Air then
						materials[x][y][z] = material
						occupancies[x][y][z] = 1
					end
				end
			end
		end

		terrain:WriteVoxels(region, resolution, materials, occupancies)
	else
		terrain:FillRegion(region, resolution, material)
	end

	local size = maxPos - minPos

	return HttpService:JSONEncode({
		success = true,
		region = {
			min = { x = minPos.X, y = minPos.Y, z = minPos.Z },
			max = { x = maxPos.X, y = maxPos.Y, z = maxPos.Z },
		},
		size = { x = size.X, y = size.Y, z = size.Z },
		material = fillArgs.material,
		replaceAirOnly = replaceAir,
	})
end

return handleFillTerrainRegion :: Types.ToolFunction
