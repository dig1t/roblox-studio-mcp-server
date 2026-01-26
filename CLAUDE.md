# Roblox Studio MCP Server Fork

This is a fork of the Roblox Studio MCP server being enhanced with batch operations, terrain tools, and scene management features.

## On Session Start

When starting work on this project, create these tasks:

### Phase 1: Batch Operations (Priority: High)
1. **Explore codebase** - Understand current architecture, tool registration, and communication protocol
2. **Implement batch_insert_models** - Insert multiple models in single call with position/rotation/scale
3. **Implement batch_run_code** - Execute multiple scripts sequentially with shared state
4. **Test batch operations** - Verify with environment builder agent

### Phase 2: Terrain Tools (Priority: High)
5. **Implement generate_terrain** - Create terrain with noise-based heightmaps
6. **Implement fill_terrain_region** - Fill region with specific material
7. **Implement sculpt_terrain** - Raise/lower terrain at points

### Phase 3: Scene Management (Priority: Medium)
8. **Implement clear_workspace** - Remove objects from workspace
9. **Implement save_scene / load_scene** - Serialize and load workspace

## Tech Stack

- **Server**: Rust (see `src/`)
- **Plugin**: Lua/Luau (see `plugin/`)
- **Build**: Cargo

## Key Files

| File | Purpose |
|------|---------|
| `src/main.rs` | Entry point |
| `src/tools/` | Tool implementations (likely) |
| `plugin/` | Roblox Studio plugin |
| `docs/SESSION-HANDOFF.md` | Full context |
| `docs/mcp-enhancement-roadmap.md` | Detailed API specs |

## Commands

```bash
# Build
cargo build

# Run
cargo run
```
