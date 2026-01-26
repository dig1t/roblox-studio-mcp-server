use crate::error::Result;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::{extract::State, Json};
use color_eyre::eyre::{Error, OptionExt};
use rmcp::{
    handler::server::{router::tool::ToolRouter, wrapper::Parameters},
    model::{
        CallToolResult, Content, Implementation, ProtocolVersion, ServerCapabilities, ServerInfo,
    },
    schemars, tool, tool_handler, tool_router, ErrorData, ServerHandler,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::oneshot::Receiver;
use tokio::sync::{mpsc, watch, Mutex};
use tokio::time::Duration;
use uuid::Uuid;

pub const STUDIO_PLUGIN_PORT: u16 = 44755;
const LONG_POLL_DURATION: Duration = Duration::from_secs(15);

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct ToolArguments {
    args: ToolArgumentValues,
    id: Option<Uuid>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct RunCommandResponse {
    response: String,
    id: Uuid,
}

pub struct AppState {
    process_queue: VecDeque<ToolArguments>,
    output_map: HashMap<Uuid, mpsc::UnboundedSender<Result<String>>>,
    waiter: watch::Receiver<()>,
    trigger: watch::Sender<()>,
}
pub type PackedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        let (trigger, waiter) = watch::channel(());
        Self {
            process_queue: VecDeque::new(),
            output_map: HashMap::new(),
            waiter,
            trigger,
        }
    }
}

impl ToolArguments {
    fn new(args: ToolArgumentValues) -> (Self, Uuid) {
        Self { args, id: None }.with_id()
    }
    fn with_id(self) -> (Self, Uuid) {
        let id = Uuid::new_v4();
        (
            Self {
                args: self.args,
                id: Some(id),
            },
            id,
        )
    }
}
#[derive(Clone)]
pub struct RBXStudioServer {
    state: PackedState,
    tool_router: ToolRouter<Self>,
}

#[tool_handler]
impl ServerHandler for RBXStudioServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::LATEST,
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: Implementation {
                name: "Roblox_Studio".to_string(),
                version: env!("CARGO_PKG_VERSION").to_string(),
                title: Some("Roblox Studio MCP Server".to_string()),
                icons: None,
                website_url: None,
            },
            instructions: Some(
                "User run_command to query data from Roblox Studio place or to change it"
                    .to_string(),
            ),
        }
    }
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct RunCode {
    #[schemars(description = "Code to run")]
    command: String,
}
#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct InsertModel {
    #[schemars(description = "Query to search for the model")]
    query: String,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct Position {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct Rotation {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct Scale {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct BatchModelEntry {
    #[schemars(description = "Query to search for the model in the marketplace")]
    query: String,
    #[schemars(description = "Position to place the model (x, y, z)")]
    position: Option<Position>,
    #[schemars(description = "Rotation in degrees (x, y, z)")]
    rotation: Option<Rotation>,
    #[schemars(description = "Scale multiplier (x, y, z)")]
    scale: Option<Scale>,
    #[schemars(description = "Custom name for the inserted model")]
    name: Option<String>,
    #[schemars(description = "Parent instance path (defaults to workspace)")]
    parent: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct BatchInsertModels {
    #[schemars(description = "Array of models to insert")]
    models: Vec<BatchModelEntry>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct ScriptEntry {
    #[schemars(description = "Luau code to execute")]
    code: String,
    #[schemars(description = "Optional description of what this script does")]
    description: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct BatchRunCode {
    #[schemars(description = "Array of scripts to execute sequentially")]
    scripts: Vec<ScriptEntry>,
    #[schemars(description = "Stop execution if any script fails (default: true)")]
    stop_on_error: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct Region {
    #[schemars(description = "Minimum corner position")]
    min: Position,
    #[schemars(description = "Maximum corner position")]
    max: Position,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct HeightmapConfig {
    #[schemars(description = "Type of heightmap: flat, perlin, or ridged")]
    heightmap_type: String,
    #[schemars(description = "Height variation amplitude")]
    amplitude: Option<f64>,
    #[schemars(description = "Detail level/frequency")]
    frequency: Option<f64>,
    #[schemars(description = "Random seed for noise generation")]
    seed: Option<i32>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct GenerateTerrain {
    #[schemars(description = "Region to generate terrain in (min/max positions)")]
    region: Region,
    #[schemars(description = "Terrain material: Grass, Sand, Rock, Snow, Mud, Ground, Slate, Concrete, Brick, Cobblestone, Ice, Salt, Sandstone, Limestone, Asphalt, LeafyGrass, Pavement")]
    material: String,
    #[schemars(description = "Heightmap configuration (type, amplitude, frequency, seed)")]
    heightmap: Option<HeightmapConfig>,
    #[schemars(description = "Y level for water fill")]
    water_level: Option<f64>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct FillTerrainRegion {
    #[schemars(description = "Region to fill (min/max positions)")]
    region: Region,
    #[schemars(description = "Terrain material to fill with")]
    material: String,
    #[schemars(description = "Only fill empty space (air)")]
    replace_air: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct SculptPoint {
    #[schemars(description = "Position to sculpt at")]
    position: Position,
    #[schemars(description = "Radius of sculpting effect")]
    radius: f64,
    #[schemars(description = "Strength of effect (positive = raise, negative = lower)")]
    strength: f64,
    #[schemars(description = "Optional material to use")]
    material: Option<String>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct SculptTerrain {
    #[schemars(description = "Array of points to sculpt")]
    points: Vec<SculptPoint>,
    #[schemars(description = "Sculpting mode: add, subtract, paint, or smooth")]
    mode: String,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct ClearWorkspace {
    #[schemars(description = "Preserve the camera")]
    preserve_camera: Option<bool>,
    #[schemars(description = "Preserve terrain")]
    preserve_terrain: Option<bool>,
    #[schemars(description = "Instance names to preserve (e.g., ['SpawnLocation', 'Baseplate'])")]
    preserve_names: Option<Vec<String>>,
    #[schemars(description = "Optional region to clear (only removes objects within this region)")]
    region: Option<Region>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct SaveScene {
    #[schemars(description = "Name/identifier for this scene snapshot")]
    name: String,
    #[schemars(description = "Optional region to save (only saves objects within this region)")]
    region: Option<Region>,
    #[schemars(description = "Instance names to exclude from save")]
    exclude_names: Option<Vec<String>>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
struct LoadScene {
    #[schemars(description = "Name of the previously saved scene to load")]
    name: String,
    #[schemars(description = "Position offset to apply to loaded objects")]
    position: Option<Position>,
    #[schemars(description = "Parent instance path (defaults to workspace)")]
    parent: Option<String>,
    #[schemars(description = "Clear workspace before loading")]
    clear_existing: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
enum ToolArgumentValues {
    RunCode(RunCode),
    InsertModel(InsertModel),
    BatchInsertModels(BatchInsertModels),
    BatchRunCode(BatchRunCode),
    GenerateTerrain(GenerateTerrain),
    FillTerrainRegion(FillTerrainRegion),
    SculptTerrain(SculptTerrain),
    ClearWorkspace(ClearWorkspace),
    SaveScene(SaveScene),
    LoadScene(LoadScene),
}
#[tool_router]
impl RBXStudioServer {
    pub fn new(state: PackedState) -> Self {
        Self {
            state,
            tool_router: Self::tool_router(),
        }
    }

    #[tool(
        description = "Runs a command in Roblox Studio and returns the printed output. Can be used to both make changes and retrieve information"
    )]
    async fn run_code(
        &self,
        Parameters(args): Parameters<RunCode>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::RunCode(args))
            .await
    }

    #[tool(
        description = "Inserts a model from the Roblox marketplace into the workspace. Returns the inserted model name."
    )]
    async fn insert_model(
        &self,
        Parameters(args): Parameters<InsertModel>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::InsertModel(args))
            .await
    }

    #[tool(
        description = "Inserts multiple models from the Roblox marketplace in a single call. Each model can have custom position, rotation, scale, name, and parent. Returns JSON with inserted count, failures, and instance paths."
    )]
    async fn batch_insert_models(
        &self,
        Parameters(args): Parameters<BatchInsertModels>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::BatchInsertModels(args))
            .await
    }

    #[tool(
        description = "Executes multiple Luau scripts sequentially with shared state between them. Scripts can store values in _G to pass data to subsequent scripts. Returns JSON with execution results for each script."
    )]
    async fn batch_run_code(
        &self,
        Parameters(args): Parameters<BatchRunCode>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::BatchRunCode(args))
            .await
    }

    #[tool(
        description = "Generates terrain using noise-based heightmaps. Supports flat, perlin, and ridged noise types. Can optionally fill water below a specified level."
    )]
    async fn generate_terrain(
        &self,
        Parameters(args): Parameters<GenerateTerrain>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::GenerateTerrain(args))
            .await
    }

    #[tool(
        description = "Fills a terrain region with a specific material. Can optionally only fill empty space (air)."
    )]
    async fn fill_terrain_region(
        &self,
        Parameters(args): Parameters<FillTerrainRegion>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::FillTerrainRegion(args))
            .await
    }

    #[tool(
        description = "Sculpts terrain by raising, lowering, painting, or smoothing at specified points. Each point has position, radius, and strength."
    )]
    async fn sculpt_terrain(
        &self,
        Parameters(args): Parameters<SculptTerrain>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::SculptTerrain(args))
            .await
    }

    #[tool(
        description = "Clears objects from the workspace. Can optionally preserve camera, terrain, and specific named instances. Can also clear only within a region."
    )]
    async fn clear_workspace(
        &self,
        Parameters(args): Parameters<ClearWorkspace>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::ClearWorkspace(args))
            .await
    }

    #[tool(
        description = "Saves a snapshot of the current workspace to memory with a given name. Can optionally save only objects within a region or exclude specific objects."
    )]
    async fn save_scene(
        &self,
        Parameters(args): Parameters<SaveScene>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::SaveScene(args))
            .await
    }

    #[tool(
        description = "Loads a previously saved scene snapshot by name. Can apply position offset and optionally clear workspace before loading."
    )]
    async fn load_scene(
        &self,
        Parameters(args): Parameters<LoadScene>,
    ) -> Result<CallToolResult, ErrorData> {
        self.generic_tool_run(ToolArgumentValues::LoadScene(args))
            .await
    }

    async fn generic_tool_run(
        &self,
        args: ToolArgumentValues,
    ) -> Result<CallToolResult, ErrorData> {
        let (command, id) = ToolArguments::new(args);
        tracing::debug!("Running command: {:?}", command);
        let (tx, mut rx) = mpsc::unbounded_channel::<Result<String>>();
        let trigger = {
            let mut state = self.state.lock().await;
            state.process_queue.push_back(command);
            state.output_map.insert(id, tx);
            state.trigger.clone()
        };
        trigger
            .send(())
            .map_err(|e| ErrorData::internal_error(format!("Unable to trigger send {e}"), None))?;
        let result = rx
            .recv()
            .await
            .ok_or(ErrorData::internal_error("Couldn't receive response", None))?;
        {
            let mut state = self.state.lock().await;
            state.output_map.remove_entry(&id);
        }
        tracing::debug!("Sending to MCP: {result:?}");
        match result {
            Ok(result) => Ok(CallToolResult::success(vec![Content::text(result)])),
            Err(err) => Ok(CallToolResult::error(vec![Content::text(err.to_string())])),
        }
    }
}

pub async fn request_handler(State(state): State<PackedState>) -> Result<impl IntoResponse> {
    let timeout = tokio::time::timeout(LONG_POLL_DURATION, async {
        loop {
            let mut waiter = {
                let mut state = state.lock().await;
                if let Some(task) = state.process_queue.pop_front() {
                    return Ok::<ToolArguments, Error>(task);
                }
                state.waiter.clone()
            };
            waiter.changed().await?
        }
    })
    .await;
    match timeout {
        Ok(result) => Ok(Json(result?).into_response()),
        _ => Ok((StatusCode::LOCKED, String::new()).into_response()),
    }
}

pub async fn response_handler(
    State(state): State<PackedState>,
    Json(payload): Json<RunCommandResponse>,
) -> Result<impl IntoResponse> {
    tracing::debug!("Received reply from studio {payload:?}");
    let mut state = state.lock().await;
    let tx = state
        .output_map
        .remove(&payload.id)
        .ok_or_eyre("Unknown ID")?;
    Ok(tx.send(Ok(payload.response))?)
}

pub async fn proxy_handler(
    State(state): State<PackedState>,
    Json(command): Json<ToolArguments>,
) -> Result<impl IntoResponse> {
    let id = command.id.ok_or_eyre("Got proxy command with no id")?;
    tracing::debug!("Received request to proxy {command:?}");
    let (tx, mut rx) = mpsc::unbounded_channel();
    {
        let mut state = state.lock().await;
        state.process_queue.push_back(command);
        state.output_map.insert(id, tx);
    }
    let response = rx.recv().await.ok_or_eyre("Couldn't receive response")??;
    {
        let mut state = state.lock().await;
        state.output_map.remove_entry(&id);
    }
    tracing::debug!("Sending back to dud: {response:?}");
    Ok(Json(RunCommandResponse { response, id }))
}

pub async fn dud_proxy_loop(state: PackedState, exit: Receiver<()>) {
    let client = reqwest::Client::new();

    let mut waiter = { state.lock().await.waiter.clone() };
    while exit.is_empty() {
        let entry = { state.lock().await.process_queue.pop_front() };
        if let Some(entry) = entry {
            let res = client
                .post(format!("http://127.0.0.1:{STUDIO_PLUGIN_PORT}/proxy"))
                .json(&entry)
                .send()
                .await;
            if let Ok(res) = res {
                let tx = {
                    state
                        .lock()
                        .await
                        .output_map
                        .remove(&entry.id.unwrap())
                        .unwrap()
                };
                let res = res
                    .json::<RunCommandResponse>()
                    .await
                    .map(|r| r.response)
                    .map_err(Into::into);
                tx.send(res).unwrap();
            } else {
                tracing::error!("Failed to proxy: {res:?}");
            };
        } else {
            waiter.changed().await.unwrap();
        }
    }
}
