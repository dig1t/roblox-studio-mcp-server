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

local function getMaterial(name: string): Enum.Material
	return TERRAIN_MATERIALS[name] or Enum.Material.Grass
end

local function generatePerlinNoise(x: number, z: number, seed: number, frequency: number, amplitude: number): number
	local noiseValue = math.noise(x * frequency + seed, z * frequency + seed)
	return noiseValue * amplitude
end

local function generateRidgedNoise(x: number, z: number, seed: number, frequency: number, amplitude: number): number
	local noiseValue = math.noise(x * frequency + seed, z * frequency + seed)
	noiseValue = 1 - math.abs(noiseValue)
	noiseValue = noiseValue * noiseValue
	return noiseValue * amplitude
end

local function handleGenerateTerrain(args: Types.ToolArgs): string?
	if not args["GenerateTerrain"] then
		return nil
	end

	local terrainArgs: Types.GenerateTerrainArgs = args["GenerateTerrain"]
	local terrain = workspace.Terrain

	local minPos = Vector3.new(terrainArgs.region.min.x, terrainArgs.region.min.y, terrainArgs.region.min.z)
	local maxPos = Vector3.new(terrainArgs.region.max.x, terrainArgs.region.max.y, terrainArgs.region.max.z)

	local material = getMaterial(terrainArgs.material)

	local heightmapType = "flat"
	local amplitude = 10
	local frequency = 0.02
	local seed = 0

	if terrainArgs.heightmap then
		heightmapType = terrainArgs.heightmap.heightmap_type or "flat"
		amplitude = terrainArgs.heightmap.amplitude or 10
		frequency = terrainArgs.heightmap.frequency or 0.02
		seed = terrainArgs.heightmap.seed or math.random(0, 10000)
	end

	local voxelsGenerated = 0
	local resolution = 4

	for x = minPos.X, maxPos.X, resolution do
		for z = minPos.Z, maxPos.Z, resolution do
			local height = minPos.Y

			if heightmapType == "perlin" then
				height = minPos.Y + generatePerlinNoise(x, z, seed, frequency, amplitude)
			elseif heightmapType == "ridged" then
				height = minPos.Y + generateRidgedNoise(x, z, seed, frequency, amplitude)
			else
				height = minPos.Y
			end

			height = math.clamp(height, minPos.Y, maxPos.Y)

			local regionMin = Vector3.new(x - resolution / 2, minPos.Y, z - resolution / 2)
			local regionMax = Vector3.new(x + resolution / 2, height, z + resolution / 2)
			local region = Region3.new(regionMin, regionMax)

			terrain:FillRegion(region, resolution, material)
			voxelsGenerated += 1
		end
	end

	if terrainArgs.water_level then
		local waterMin = Vector3.new(minPos.X, minPos.Y, minPos.Z)
		local waterMax = Vector3.new(maxPos.X, terrainArgs.water_level, maxPos.Z)
		local waterRegion = Region3.new(waterMin, waterMax)
		terrain:FillRegion(waterRegion, resolution, Enum.Material.Water)
	end

	return HttpService:JSONEncode({
		success = true,
		voxelsGenerated = voxelsGenerated,
		region = {
			min = { x = minPos.X, y = minPos.Y, z = minPos.Z },
			max = { x = maxPos.X, y = maxPos.Y, z = maxPos.Z },
		},
		material = terrainArgs.material,
		heightmapType = heightmapType,
	})
end

return handleGenerateTerrain :: Types.ToolFunction
