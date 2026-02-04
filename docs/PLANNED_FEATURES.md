# Planned MCP Features for Map Generation

This document outlines new MCP tools designed to improve AI-assisted map creation quality.

## Problem Statement

Current map generation has these issues:
1. **Gaps between elements** - Floor doesn't meet walls, plateaus float above cliffs
2. **Uniform part sizes** - All parts same dimensions = obviously generated
3. **No feedback loop** - AI can't see what it built or analyze existing good maps

## Proposed Features (Priority Order)

---

### 1. `get_model_bounds`

**Purpose**: Get the bounding box of a model or part. Essential for positioning elements relative to each other without gaps.

**Rust Struct**:
```rust
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct GetModelBounds {
    #[schemars(description = "Path to instance (e.g., 'Workspace.GrandCanyon.CanyonWalls')")]
    path: String,
}
```

**Response**:
```json
{
  "success": true,
  "bounds": {
    "min": { "x": -400, "y": 0, "z": -300 },
    "max": { "x": 400, "y": 214, "z": 300 },
    "size": { "x": 800, "y": 214, "z": 600 },
    "center": { "x": 0, "y": 107, "z": 0 }
  }
}
```

**Lua Implementation** (`Tools/GetModelBounds.luau`):
```lua
local function handleGetModelBounds(args: Types.ToolArgs): string?
    if not args["GetModelBounds"] then
        return nil
    end

    local toolArgs = args["GetModelBounds"]
    local instance = getInstanceFromPath(toolArgs.path)

    if not instance then
        error("Instance not found: " .. toolArgs.path)
    end

    local cf, size
    if instance:IsA("Model") then
        cf, size = instance:GetBoundingBox()
    elseif instance:IsA("BasePart") then
        cf = instance.CFrame
        size = instance.Size
    else
        error("Instance must be a Model or BasePart")
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
```

**Use Cases**:
- Get wall bounds → position floor to overlap by 2 studs
- Get cliff top Y → position plateau to connect seamlessly
- Calculate gap between two models

---

### 2. `get_workspace_stats`

**Purpose**: Return statistics about parts in workspace or a model. Detect uniform sizes, analyze color distribution.

**Rust Struct**:
```rust
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct GetWorkspaceStats {
    #[schemars(description = "Optional path to analyze (defaults to entire Workspace)")]
    path: Option<String>,

    #[schemars(description = "Include size distribution histogram")]
    include_sizes: Option<bool>,

    #[schemars(description = "Include color distribution")]
    include_colors: Option<bool>,
}
```

**Response**:
```json
{
  "success": true,
  "partCount": 1497,
  "modelCount": 12,
  "sizeStats": {
    "min": { "x": 2, "y": 2, "z": 2 },
    "max": { "x": 48, "y": 35, "z": 24 },
    "mean": { "x": 24.3, "y": 18.7, "z": 16.2 },
    "stdDev": { "x": 8.2, "y": 12.1, "z": 5.4 },
    "uniformityScore": 0.73
  },
  "colorStats": {
    "uniqueColors": 24,
    "dominantColors": [
      { "color": [155, 75, 60], "percentage": 18.2 },
      { "color": [235, 225, 200], "percentage": 15.7 }
    ]
  }
}
```

**Key Metric**: `uniformityScore` (0-1, lower = more varied = better)
- Score > 0.8 = "parts look too uniform, vary sizes more"
- Score < 0.5 = "good natural variation"

**Use Cases**:
- After generation, check if sizes are too uniform
- Verify color palette is being used correctly
- Count parts to estimate performance

---

### 3. `capture_viewport`

**Purpose**: Take a screenshot of the current Studio viewport. AI can see what it built.

**Rust Struct**:
```rust
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct CaptureViewport {
    #[schemars(description = "Optional: Set camera position before capture")]
    camera_position: Option<Position>,

    #[schemars(description = "Optional: Set camera look-at target")]
    camera_target: Option<Position>,

    #[schemars(description = "Image format: 'png' or 'jpg'")]
    format: Option<String>,
}
```

**Response**:
```json
{
  "success": true,
  "imagePath": "/tmp/viewport_capture_abc123.png",
  "resolution": { "width": 1920, "height": 1080 }
}
```

**Note**: May need to use `ContentProvider:PreloadAsync` and `ViewportFrame` capture, or investigate if Studio has screenshot APIs available to plugins.

**Use Cases**:
- AI captures view after building → can see gaps visually
- Iterative refinement without human describing issues
- Before/after comparisons

---

### 4. `find_gaps`

**Purpose**: Detect gaps between two models or regions. Returns locations where geometry doesn't connect.

**Rust Struct**:
```rust
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct FindGaps {
    #[schemars(description = "Path to first model/part")]
    model_a: String,

    #[schemars(description = "Path to second model/part")]
    model_b: String,

    #[schemars(description = "Maximum distance to consider a 'gap' (default: 2 studs)")]
    threshold: Option<f64>,
}
```

**Response**:
```json
{
  "success": true,
  "hasGaps": true,
  "gapCount": 12,
  "gaps": [
    {
      "position": { "x": 45, "y": 6, "z": -120 },
      "distance": 3.5,
      "nearestInA": { "x": 43, "y": 6, "z": -120 },
      "nearestInB": { "x": 46.5, "y": 6, "z": -120 }
    }
  ]
}
```

**Algorithm**:
1. Get surface points of model A facing model B
2. For each point, raycast toward model B
3. If ray travels > threshold before hitting B, it's a gap
4. Return gap locations

**Use Cases**:
- After building floor + walls, check for gaps
- Validate transitions between terrain layers
- Automated quality check before finishing

---

### 6. `get_children_info`

**Purpose**: Get information about direct children of a model/folder. Lighter than full workspace stats.

**Rust Struct**:
```rust
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct GetChildrenInfo {
    #[schemars(description = "Path to parent instance")]
    path: String,

    #[schemars(description = "Include bounds for each child")]
    include_bounds: Option<bool>,
}
```

**Response**:
```json
{
  "success": true,
  "children": [
    {
      "name": "CanyonFloor",
      "className": "Model",
      "partCount": 60,
      "bounds": { "min": {...}, "max": {...} }
    },
    {
      "name": "ColoradoRiver",
      "className": "Model",
      "partCount": 120
    }
  ]
}
```

**Use Cases**:
- Understand what's in workspace without full traversal
- Get bounds of specific layer to position next layer
- Debug model hierarchy

---

## Implementation Priority

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| 1 | `get_model_bounds` | Low | High - enables seamless positioning |
| 2 | `get_workspace_stats` | Medium | High - detects uniformity issues |
| 3 | `capture_viewport` | High | Medium - visual feedback |
| 4 | `find_gaps` | High | Medium - automated validation |
| 5 | `get_children_info` | Low | Low - convenience |

**Note**: `load_model_file` was removed - Lune can already parse .rbxm/.rbxmx files externally.

## Recommendation

Start with **`get_model_bounds`** - it's simple to implement and immediately useful for positioning layers relative to each other without gaps.

Then add **`get_workspace_stats`** to detect the "uniform size" problem automatically.
