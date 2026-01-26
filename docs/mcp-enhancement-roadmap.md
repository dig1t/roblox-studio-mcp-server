# MCP Enhancement Roadmap

This document outlines planned enhancements for a future fork of the Roblox Studio MCP server. These features would significantly improve the environment builder agent's capabilities and efficiency.

## Current Limitations

The existing MCP server provides:
- `insert_model` - Insert a single rbxmx asset
- `run_code` - Execute a single Luau script

Current bottlenecks:
- **No batch operations** - Must call `insert_model` separately for each asset
- **No terrain tools** - Terrain generation requires complex `run_code` scripts
- **No scene management** - Cannot save, load, or clear scenes
- **No spatial queries** - Cannot detect existing objects or collisions

---

## Phase 1: Batch Operations

**Priority: High**
**Complexity: Low**

### `batch_insert_models`

Insert multiple models in a single call, reducing round-trip latency.

```typescript
interface BatchInsertModelsParams {
  models: Array<{
    assetPath: string;
    position: { x: number; y: number; z: number };
    rotation?: { x: number; y: number; z: number };
    scale?: { x: number; y: number; z: number };
    name?: string;
    parent?: string; // Instance path, defaults to workspace
  }>;
}

interface BatchInsertModelsResult {
  success: boolean;
  inserted: number;
  failed: Array<{ index: number; error: string }>;
  instances: Array<{ index: number; path: string }>;
}
```

**Example:**
```json
{
  "models": [
    { "assetPath": "Trees/Pine Tree.rbxmx", "position": { "x": 10, "y": 0, "z": 10 } },
    { "assetPath": "Trees/Pine Tree.rbxmx", "position": { "x": 20, "y": 0, "z": 10 } },
    { "assetPath": "Trees/Pine Tree.rbxmx", "position": { "x": 30, "y": 0, "z": 10 } }
  ]
}
```

### `batch_run_code`

Execute multiple scripts sequentially with shared state.

```typescript
interface BatchRunCodeParams {
  scripts: Array<{
    code: string;
    description?: string;
  }>;
  stopOnError?: boolean; // Default true
}

interface BatchRunCodeResult {
  success: boolean;
  executed: number;
  results: Array<{
    index: number;
    success: boolean;
    output?: string;
    error?: string;
  }>;
}
```

---

## Phase 2: Terrain Tools

**Priority: High**
**Complexity: Medium**

### `generate_terrain`

Create terrain using noise-based heightmaps.

```typescript
interface GenerateTerrainParams {
  region: {
    min: { x: number; y: number; z: number };
    max: { x: number; y: number; z: number };
  };
  material: TerrainMaterial;
  heightmap?: {
    type: "flat" | "perlin" | "ridged" | "custom";
    amplitude?: number; // Height variation
    frequency?: number; // Detail level
    seed?: number;
  };
  waterLevel?: number; // Y level for water fill
}

type TerrainMaterial =
  | "Grass"
  | "Sand"
  | "Rock"
  | "Snow"
  | "Mud"
  | "Ground"
  | "Slate"
  | "Concrete"
  | "Brick"
  | "Cobblestone"
  | "Ice"
  | "Salt"
  | "Sandstone"
  | "Limestone"
  | "Asphalt"
  | "LeafyGrass"
  | "Pavement";
```

### `fill_terrain_region`

Fill a region with a specific terrain material.

```typescript
interface FillTerrainRegionParams {
  region: {
    min: { x: number; y: number; z: number };
    max: { x: number; y: number; z: number };
  };
  material: TerrainMaterial;
  replaceAir?: boolean; // Only fill empty space
}
```

### `sculpt_terrain`

Raise or lower terrain at specific points.

```typescript
interface SculptTerrainParams {
  points: Array<{
    position: { x: number; y: number; z: number };
    radius: number;
    strength: number; // Positive = raise, negative = lower
    material?: TerrainMaterial;
  }>;
  mode: "add" | "subtract" | "paint" | "smooth";
}
```

### `paint_terrain`

Apply materials to existing terrain surface.

```typescript
interface PaintTerrainParams {
  center: { x: number; y: number; z: number };
  radius: number;
  material: TerrainMaterial;
  strength?: number; // 0-1, blending with existing
}
```

---

## Phase 3: Scene Management

**Priority: Medium**
**Complexity: Medium**

### `save_scene`

Serialize the current workspace to a file.

```typescript
interface SaveSceneParams {
  path: string; // Output file path
  region?: { // Optional: save only a region
    min: { x: number; y: number; z: number };
    max: { x: number; y: number; z: number };
  };
  includeServices?: string[]; // Additional services to include
  excludeNames?: string[]; // Instance names to exclude
}

interface SaveSceneResult {
  success: boolean;
  path: string;
  objectCount: number;
  fileSize: number;
}
```

### `load_scene`

Load a previously saved scene.

```typescript
interface LoadSceneParams {
  path: string;
  position?: { x: number; y: number; z: number }; // Offset position
  parent?: string; // Target parent, defaults to workspace
  clearExisting?: boolean; // Clear workspace first
}

interface LoadSceneResult {
  success: boolean;
  objectCount: number;
  rootInstance: string; // Path to loaded root
}
```

### `clear_workspace`

Remove all non-essential objects from workspace.

```typescript
interface ClearWorkspaceParams {
  preserveCamera?: boolean;
  preserveTerrain?: boolean;
  preserveNames?: string[]; // Instance names to keep
  region?: { // Clear only within region
    min: { x: number; y: number; z: number };
    max: { x: number; y: number; z: number };
  };
}

interface ClearWorkspaceResult {
  success: boolean;
  removedCount: number;
}
```

### `undo_last`

Revert the last operation.

```typescript
interface UndoLastParams {
  steps?: number; // Number of operations to undo, default 1
}

interface UndoLastResult {
  success: boolean;
  undoneOperations: string[];
  remainingHistory: number;
}
```

---

## Phase 4: Advanced Queries

**Priority: Medium**
**Complexity: High**

### `get_workspace_bounds`

Return the bounding box of all objects in workspace.

```typescript
interface GetWorkspaceBoundsParams {
  filter?: {
    className?: string;
    namePattern?: string;
    tags?: string[];
  };
}

interface GetWorkspaceBoundsResult {
  min: { x: number; y: number; z: number };
  max: { x: number; y: number; z: number };
  center: { x: number; y: number; z: number };
  size: { x: number; y: number; z: number };
  objectCount: number;
}
```

### `get_objects_in_region`

Find all objects within a specified region.

```typescript
interface GetObjectsInRegionParams {
  region: {
    min: { x: number; y: number; z: number };
    max: { x: number; y: number; z: number };
  };
  filter?: {
    className?: string;
    namePattern?: string;
    tags?: string[];
  };
  includePartial?: boolean; // Include objects partially in region
}

interface GetObjectsInRegionResult {
  objects: Array<{
    path: string;
    name: string;
    className: string;
    position: { x: number; y: number; z: number };
    size: { x: number; y: number; z: number };
  }>;
  count: number;
}
```

### `validate_placement`

Check if a position is suitable for placing an object.

```typescript
interface ValidatePlacementParams {
  position: { x: number; y: number; z: number };
  size: { x: number; y: number; z: number };
  checkTerrain?: boolean; // Verify terrain exists below
  checkCollision?: boolean; // Check for existing objects
  requiredClearance?: number; // Minimum distance from other objects
}

interface ValidatePlacementResult {
  valid: boolean;
  issues: Array<{
    type: "collision" | "no_terrain" | "out_of_bounds" | "insufficient_clearance";
    details: string;
    conflictingObject?: string;
  }>;
  suggestedPosition?: { x: number; y: number; z: number }; // Nearest valid position
}
```

### `raycast`

Perform a raycast query in the workspace.

```typescript
interface RaycastParams {
  origin: { x: number; y: number; z: number };
  direction: { x: number; y: number; z: number };
  maxDistance?: number;
  filter?: {
    ignoreNames?: string[];
    ignoreClasses?: string[];
    onlyClasses?: string[];
  };
}

interface RaycastResult {
  hit: boolean;
  position?: { x: number; y: number; z: number };
  normal?: { x: number; y: number; z: number };
  distance?: number;
  instance?: string;
  material?: string;
}
```

---

## Phase 5: Instance Manipulation

**Priority: Low**
**Complexity: Medium**

### `modify_instance`

Modify properties of an existing instance.

```typescript
interface ModifyInstanceParams {
  path: string; // Instance path in workspace
  properties: Record<string, unknown>;
}
```

### `clone_instance`

Clone an instance with optional modifications.

```typescript
interface CloneInstanceParams {
  source: string; // Source instance path
  position?: { x: number; y: number; z: number };
  rotation?: { x: number; y: number; z: number };
  parent?: string;
  name?: string;
}
```

### `delete_instance`

Remove an instance from the workspace.

```typescript
interface DeleteInstanceParams {
  path: string;
  recursive?: boolean; // Delete descendants too
}
```

### `group_instances`

Group multiple instances into a Model or Folder.

```typescript
interface GroupInstancesParams {
  instances: string[]; // Instance paths
  groupType: "Model" | "Folder";
  name?: string;
  parent?: string;
}
```

---

## Phase 6: Lighting & Effects

**Priority: Low**
**Complexity: Low**

### `set_lighting`

Configure Lighting service properties.

```typescript
interface SetLightingParams {
  clockTime?: number; // 0-24
  ambient?: { r: number; g: number; b: number };
  brightness?: number;
  colorShift_Bottom?: { r: number; g: number; b: number };
  colorShift_Top?: { r: number; g: number; b: number };
  environmentDiffuseScale?: number;
  environmentSpecularScale?: number;
  globalShadows?: boolean;
  outdoorAmbient?: { r: number; g: number; b: number };
  shadowSoftness?: number;
  technology?: "Legacy" | "Voxel" | "Compatibility" | "ShadowMap" | "Future";
}
```

### `add_atmosphere`

Add or modify atmospheric effects.

```typescript
interface AddAtmosphereParams {
  density?: number;
  offset?: number;
  color?: { r: number; g: number; b: number };
  decay?: { r: number; g: number; b: number };
  glare?: number;
  haze?: number;
}
```

### `add_post_effect`

Add post-processing effects.

```typescript
interface AddPostEffectParams {
  type: "Blur" | "Bloom" | "ColorCorrection" | "DepthOfField" | "SunRays";
  properties: Record<string, unknown>;
}
```

---

## Implementation Priority

| Phase | Priority | Effort | Impact |
|-------|----------|--------|--------|
| Phase 1: Batch Operations | High | Low | High |
| Phase 2: Terrain Tools | High | Medium | High |
| Phase 3: Scene Management | Medium | Medium | Medium |
| Phase 4: Advanced Queries | Medium | High | High |
| Phase 5: Instance Manipulation | Low | Medium | Medium |
| Phase 6: Lighting & Effects | Low | Low | Low |

## Migration Strategy

1. **Fork the existing MCP server** - Maintain compatibility with existing tools
2. **Implement Phase 1 first** - Immediate performance gains
3. **Add phases incrementally** - Each phase is independently useful
4. **Version the API** - Allow agents to detect available features
5. **Document thoroughly** - Ensure agents can discover and use new features

## Compatibility Notes

All new tools should:
- Return structured JSON responses
- Include success/failure status
- Provide meaningful error messages
- Support optional parameters with sensible defaults
- Maintain backward compatibility with existing scripts
