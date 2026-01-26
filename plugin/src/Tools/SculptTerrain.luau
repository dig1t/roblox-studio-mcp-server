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
}

local function getMaterial(name: string?): Enum.Material
	if not name then
		return Enum.Material.Grass
	end
	return TERRAIN_MATERIALS[name] or Enum.Material.Grass
end

local function sculptAdd(terrain: Terrain, position: Vector3, radius: number, strength: number, material: Enum.Material)
	terrain:FillBall(position, radius * math.abs(strength), material)
end

local function sculptSubtract(terrain: Terrain, position: Vector3, radius: number, strength: number)
	terrain:FillBall(position, radius * math.abs(strength), Enum.Material.Air)
end

local function sculptPaint(terrain: Terrain, position: Vector3, radius: number, material: Enum.Material)
	local resolution = 4
	local regionSize = Vector3.new(radius * 2, radius * 2, radius * 2)
	local regionMin = position - regionSize / 2
	local regionMax = position + regionSize / 2
	local region = Region3.new(regionMin, regionMax)

	region = region:ExpandToGrid(resolution)
	local materials, occupancies = terrain:ReadVoxels(region, resolution)
	local voxelSize = region.Size / resolution

	local center = (region.CFrame.Position - regionMin) / resolution

	for x = 1, voxelSize.X do
		for y = 1, voxelSize.Y do
			for z = 1, voxelSize.Z do
				local voxelPos = Vector3.new(x, y, z)
				local worldPos = regionMin + (voxelPos - Vector3.new(0.5, 0.5, 0.5)) * resolution
				local distance = (worldPos - position).Magnitude

				if distance <= radius and materials[x][y][z] ~= Enum.Material.Air then
					materials[x][y][z] = material
				end
			end
		end
	end

	terrain:WriteVoxels(region, resolution, materials, occupancies)
end

local function sculptSmooth(terrain: Terrain, position: Vector3, radius: number, strength: number)
	local resolution = 4
	local regionSize = Vector3.new(radius * 2, radius * 2, radius * 2)
	local regionMin = position - regionSize / 2
	local regionMax = position + regionSize / 2
	local region = Region3.new(regionMin, regionMax)

	region = region:ExpandToGrid(resolution)
	local materials, occupancies = terrain:ReadVoxels(region, resolution)
	local voxelSize = region.Size / resolution

	local newOccupancies = {}
	for x = 1, voxelSize.X do
		newOccupancies[x] = {}
		for y = 1, voxelSize.Y do
			newOccupancies[x][y] = {}
			for z = 1, voxelSize.Z do
				local worldPos = regionMin + (Vector3.new(x, y, z) - Vector3.new(0.5, 0.5, 0.5)) * resolution
				local distance = (worldPos - position).Magnitude

				if distance <= radius then
					local sum = 0
					local count = 0

					for dx = -1, 1 do
						for dy = -1, 1 do
							for dz = -1, 1 do
								local nx, ny, nz = x + dx, y + dy, z + dz
								if nx >= 1 and nx <= voxelSize.X and
									ny >= 1 and ny <= voxelSize.Y and
									nz >= 1 and nz <= voxelSize.Z then
									sum += occupancies[nx][ny][nz]
									count += 1
								end
							end
						end
					end

					local average = sum / count
					local blendFactor = math.abs(strength) * (1 - distance / radius)
					newOccupancies[x][y][z] = occupancies[x][y][z] + (average - occupancies[x][y][z]) * blendFactor
				else
					newOccupancies[x][y][z] = occupancies[x][y][z]
				end
			end
		end
	end

	terrain:WriteVoxels(region, resolution, materials, newOccupancies)
end

local function handleSculptTerrain(args: Types.ToolArgs): string?
	if not args["SculptTerrain"] then
		return nil
	end

	local sculptArgs: Types.SculptTerrainArgs = args["SculptTerrain"]
	local terrain = workspace.Terrain
	local mode = sculptArgs.mode or "add"

	local results = {
		success = true,
		pointsProcessed = 0,
		mode = mode,
	}

	for _, point in sculptArgs.points do
		local position = Vector3.new(point.position.x, point.position.y, point.position.z)
		local radius = point.radius
		local strength = point.strength
		local material = getMaterial(point.material)

		if mode == "add" then
			sculptAdd(terrain, position, radius, strength, material)
		elseif mode == "subtract" then
			sculptSubtract(terrain, position, radius, strength)
		elseif mode == "paint" then
			sculptPaint(terrain, position, radius, material)
		elseif mode == "smooth" then
			sculptSmooth(terrain, position, radius, strength)
		else
			sculptAdd(terrain, position, radius, strength, material)
		end

		results.pointsProcessed += 1
	end

	return HttpService:JSONEncode(results)
end

return handleSculptTerrain :: Types.ToolFunction
