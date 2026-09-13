extends Node2D
## Base class for every playable level.
##
## Owns the level's lifecycle: it bakes the ASCII map through
## [LevelTileBuilder], spawns the player, runs the death/respawn loop, and
## reports win/lose back to [code]LevelManager[/code] through the three
## template signals.
##
## [b]Authoring a level[/b] means editing the [code]map[/code] string on the
## [LevelTileBuilder] node and nothing else. The builder places terrain, merged
## collision, spike hazards, the spawn point and the goal from the map's
## legend. See [LevelTileBuilder] for the character list.
##
## A level scene is expected to contain:
## [codeblock]
##   Level            (Node2D, this script)
##   ├── TileBuilder  (LevelTileBuilder, holds the ASCII map)
##   │   ├── Terrain          (TileMapLayer)
##   │   ├── TerrainCollision (Node2D)
##   │   └── Hazards          (Node2D)
##   └── SpawnPoint   (Marker2D, moved by the builder)
## [/codeblock]

@warning_ignore("unused_signal")
signal level_lost
@warning_ignore("unused_signal")
signal level_won(level_path : String)
@warning_ignore("unused_signal")
signal level_changed(level_path : String)

@export_group("Flow")
## Optional path to the next level if using an open world level system.
## Left empty in the standard linear progression, where the level list decides.
@export_file("*.tscn") var next_level_path : String
## Seconds to wait after a death before the player reappears.
@export var respawn_delay : float = 0.35
## If true, dying sends the player back to the last checkpoint instead of the
## level's spawn point.
@export var use_checkpoints : bool = false
## Instanced into the level on ready. Defaults to the project player scene.
@export var player_scene : PackedScene

@export_group("Hazards")
## Y position below which the player is considered fallen out of the world and
## dies. Levels can override this if they are unusually tall.
@export var kill_plane_y : float = 2000.0

@export_group("Debug")
## Print level lifecycle events to the output panel.
@export var debug_logging : bool = false

const DEFAULT_PLAYER_SCENE := "res://scenes/game/player/player.tscn"
const GOAL_SCENE := "res://scenes/game/levels/goal.tscn"

var level_state : LevelState

## Where the player appears on entry and after a death.
@onready var spawn_point : Marker2D = %SpawnPoint
## Set while the player is dead and the respawn timer is running.
var player_is_dead : bool = false
## Seconds since the level was entered, used for best-time tracking.
var elapsed_time : float = 0.0

var _tile_builder : LevelTileBuilder
var _player : Node2D
var _active_checkpoint : Marker2D
var _goal : Area2D
var _is_completed : bool = false

func _log(message : String) -> void:
	if debug_logging:
		print("[%s] %s" % [name, message])

# --- Level lifecycle ---------------------------------------------------------

func _ready() -> void:
	level_state = GameState.get_level_state(scene_file_path)
	if level_state:
		level_state.reached = true
	_active_checkpoint = null
	_is_completed = false
	elapsed_time = 0.0
	_build_from_map()
	_spawn_player()
	_log("ready (player at %s)" % spawn_point.global_position)

## Bakes the ASCII map and wires the resulting spawn and goal positions.
func _build_from_map() -> void:
	_tile_builder = _find_tile_builder()
	if _tile_builder == null:
		push_error("%s: no LevelTileBuilder found; level will have no terrain" % name)
		return
	_tile_builder.hazard_handler = _on_hazard_body_entered
	# Connect before baking so the first bake's positions are applied too.
	_tile_builder.baked.connect(_on_map_baked)
	_tile_builder.bake()
	_on_map_baked(_tile_builder.get_spawn_position(), _tile_builder.get_goal_position())

func _find_tile_builder() -> LevelTileBuilder:
	for child in get_children():
		if child is LevelTileBuilder:
			return child
	return null

func _on_map_baked(spawn_position : Vector2, goal_position : Vector2) -> void:
	if spawn_point == null:
		push_error("%s: no %%SpawnPoint Marker2D found" % name)
	else:
		spawn_point.global_position = spawn_position
	if goal_position != Vector2.ZERO:
		_place_goal(goal_position)

func _place_goal(goal_position : Vector2) -> void:
	if _goal == null:
		var goal_scene : PackedScene = load(GOAL_SCENE)
		if goal_scene == null:
			return
		_goal = goal_scene.instantiate()
		add_child(_goal)
		_goal.body_entered.connect(_on_goal_body_entered)
	_goal.global_position = goal_position

func _spawn_player() -> void:
	var scene := player_scene
	if scene == null:
		scene = load(DEFAULT_PLAYER_SCENE)
	if scene == null:
		push_error("%s: could not load player scene" % name)
		return
	_player = scene.instantiate()
	add_child(_player)
	_player.global_position = spawn_point.global_position
	_configure_camera()

## Clamps the player's camera to the map bounds, so the view never scrolls past
## the edge of the level and show empty space.
func _configure_camera() -> void:
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	var size := _get_map_pixel_size()
	if size == Vector2.ZERO:
		return
	# The limit is the far edge; Camera2D treats it as inclusive, so subtract
	# nothing here. Positions are in global space, and the map starts at 0,0.
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)

## Returns the level's pixel dimensions, derived from the baked terrain.
func _get_map_pixel_size() -> Vector2:
	if _tile_builder == null:
		return Vector2.ZERO
	var terrain : TileMapLayer = _tile_builder.get_node_or_null("Terrain")
	if terrain == null or terrain.tile_set == null:
		return Vector2.ZERO
	var used := terrain.get_used_cells()
	if used.is_empty():
		return Vector2.ZERO
	var tile_size := terrain.tile_set.tile_size
	var min_cell := used[0]
	var max_cell := used[0]
	for cell in used:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	# Cell (0,0) covers pixels [0, tile_size), so the far edge is (max + 1).
	return Vector2((max_cell.x + 1) * tile_size.x, (max_cell.y + 1) * tile_size.y)

## Called when the player reaches the goal.
func win_level() -> void:
	if _is_completed:
		return
	_is_completed = true
	_log("won in %.3fs" % elapsed_time)
	GameState.record_level_completed(scene_file_path, elapsed_time)
	level_won.emit(next_level_path)

## Called when the player fails.
func lose_level() -> void:
	_log("lost")
	level_lost.emit()

func _process(delta : float) -> void:
	# The clock stops once the level is won so the recorded time is the run.
	if _is_completed or player_is_dead:
		return
	elapsed_time += delta
	if _player and is_instance_valid(_player) and _player.global_position.y > kill_plane_y:
		kill_player()

# --- Death and respawn -------------------------------------------------------

## Kills the player and respawns them after [member respawn_delay].
## Safe to call repeatedly; extra calls during the delay are ignored.
func kill_player() -> void:
	if player_is_dead or _is_completed:
		return
	player_is_dead = true
	if level_state:
		level_state.deaths += 1
	_log("player died, respawning at %s" % ("checkpoint" if _active_checkpoint else "spawn"))
	_respawn_player()
	await get_tree().create_timer(respawn_delay, false).timeout
	player_is_dead = false

## Moves the player to the respawn point and clears their momentum.
func _respawn_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var target := _active_checkpoint if _active_checkpoint else spawn_point
	if target == null:
		return
	_player.respawn_at(target.global_position)

## Returns the player node, or null if this level has no player.
func get_player() -> Node2D:
	return _player

## Registers a checkpoint so the player respawns there instead of at the start.
func set_checkpoint(marker : Marker2D) -> void:
	if not use_checkpoints:
		return
	_active_checkpoint = marker
	_log("checkpoint set")

# --- Signal helpers for scenes ----------------------------------------------

func _on_goal_body_entered(body : Node2D) -> void:
	if body == _player:
		win_level()

func _on_hazard_body_entered(body : Node2D) -> void:
	if body == _player:
		kill_player()
