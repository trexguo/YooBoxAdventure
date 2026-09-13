extends Control
## Level select menu.
##
## Lists every level in the level list, not just the ones the player has
## reached, so they can see what is ahead and re-challenge anything they have
## already unlocked. Locked levels are shown greyed out and cannot be activated.
##
## State comes from two places:
## [br]- [code]SceneLister.files[/code] supplies the full ordered level list.
## [br]- [GameState] supplies per-level progress ([LevelState.reached],
##   [LevelState.completed], [LevelState.best_time]).
##
## An ItemList item's index matches its index in [member level_paths], which is
## how an activated row is mapped back to a scene path.

signal level_selected

@onready var level_buttons_container: ItemList = %LevelButtonsContainer
@onready var scene_lister: SceneLister = $SceneLister

## Parallel to the ItemList's rows: the scene path for each row.
var level_paths : Array[String] = []

func _ready() -> void:
	populate()

## Rebuilds the list from scratch. Safe to call whenever the menu is shown.
func populate() -> void:
	level_buttons_container.clear()
	level_paths.clear()

	for file_path in scene_lister.files:
		var level_state := GameState.get_level_state(file_path)
		var reached := level_state != null and level_state.reached
		var completed := level_state != null and level_state.completed

		var index := level_buttons_container.add_item(_format_row(file_path, level_state, reached, completed))
		level_buttons_container.set_item_metadata(index, file_path)
		# A level the player has never reached cannot be selected. The first
		# level is always open, so a fresh save still has somewhere to go.
		level_buttons_container.set_item_disabled(index, not reached and index > 0)
		level_paths.append(file_path)

	# Start on the furthest level reached, so "continue" reads naturally.
	var start_index := _get_starting_index()
	if start_index >= 0 and start_index < level_buttons_container.item_count:
		level_buttons_container.select(start_index)

## Builds a row label like "3. Level 3   [done]  0:42.115" or "3. Level 3   (locked)".
func _format_row(file_path : String, level_state : LevelState, reached : bool, completed : bool) -> String:
	var number := level_paths.size() + 1
	var label := "%d. %s" % [number, _prettify(file_path)]

	if not reached:
		return label + "   (locked)"

	var status := "[done]" if completed else "reached"
	if completed and level_state != null and level_state.best_time > 0.0:
		status += "   " + level_state.get_best_time_text()
	return "%s   %s" % [label, status]

## Turns "res://scenes/game/levels/level_3.tscn" into "Level 3".
func _prettify(file_path : String) -> String:
	var file_name := file_path.get_file().trim_suffix(".tscn")
	return file_name.replace("_", " ").capitalize()

## Index of the level to highlight: the furthest one reached, else the first.
func _get_starting_index() -> int:
	var furthest := -1
	for index in level_paths.size():
		var level_state := GameState.get_level_state(level_paths[index])
		if level_state != null and level_state.reached:
			furthest = index
	return maxi(furthest, 0)

func _on_level_buttons_container_item_activated(index : int) -> void:
	if index < 0 or index >= level_paths.size():
		return
	if level_buttons_container.is_item_disabled(index):
		return
	# Selecting a level replays it from the start, which is the point of letting
	# players re-challenge levels.
	GameState.set_checkpoint_level_path(level_paths[index])
	level_selected.emit()
