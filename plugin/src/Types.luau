export type InsertModelArgs = {
	query: string,
}

export type RunCodeArgs = {
	command: string,
}

export type Position = {
	x: number,
	y: number,
	z: number,
}

export type Rotation = {
	x: number,
	y: number,
	z: number,
}

export type Scale = {
	x: number,
	y: number,
	z: number,
}

export type BatchModelEntry = {
	query: string,
	position: Position?,
	rotation: Rotation?,
	scale: Scale?,
	name: string?,
	parent: string?,
}

export type BatchInsertModelsArgs = {
	models: { BatchModelEntry },
}

export type ScriptEntry = {
	code: string,
	description: string?,
}

export type BatchRunCodeArgs = {
	scripts: { ScriptEntry },
	stop_on_error: boolean?,
}

export type Region = {
	min: Position,
	max: Position,
}

export type HeightmapConfig = {
	heightmap_type: string,
	amplitude: number?,
	frequency: number?,
	seed: number?,
}

export type GenerateTerrainArgs = {
	region: Region,
	material: string,
	heightmap: HeightmapConfig?,
	water_level: number?,
}

export type FillTerrainRegionArgs = {
	region: Region,
	material: string,
	replace_air: boolean?,
}

export type SculptPoint = {
	position: Position,
	radius: number,
	strength: number,
	material: string?,
}

export type SculptTerrainArgs = {
	points: { SculptPoint },
	mode: string,
}

export type ClearWorkspaceArgs = {
	preserve_camera: boolean?,
	preserve_terrain: boolean?,
	preserve_names: { string }?,
	region: Region?,
}

export type SaveSceneArgs = {
	name: string,
	region: Region?,
	exclude_names: { string }?,
}

export type LoadSceneArgs = {
	name: string,
	position: Position?,
	parent: string?,
	clear_existing: boolean?,
}

export type ToolArgs =
	{ InsertModel: InsertModelArgs } |
	{ RunCode: RunCodeArgs } |
	{ BatchInsertModels: BatchInsertModelsArgs } |
	{ BatchRunCode: BatchRunCodeArgs } |
	{ GenerateTerrain: GenerateTerrainArgs } |
	{ FillTerrainRegion: FillTerrainRegionArgs } |
	{ SculptTerrain: SculptTerrainArgs } |
	{ ClearWorkspace: ClearWorkspaceArgs } |
	{ SaveScene: SaveSceneArgs } |
	{ LoadScene: LoadSceneArgs }

export type ToolFunction = (ToolArgs) -> string?

return {}
