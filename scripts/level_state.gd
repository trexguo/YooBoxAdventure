class_name LevelState
extends Resource

## Save data for a single level. One instance per level scene path, stored in
## [GameState].level_states and persisted through [GlobalState].

## Whether the player has finished this level at least once.
@export var completed : bool = false
## Whether the player has ever reached this level, used to gate level select.
@export var reached : bool = false
## Fastest completion time in seconds, or 0.0 if never completed.
@export var best_time : float = 0.0
## Total deaths accumulated across all attempts.
@export var deaths : int = 0
## Whether the level's tutorial popup has been shown.
@export var tutorial_read : bool = false
## Player-chosen accent color, kept from the template.
@export var color : Color

## Records a completion, keeping the fastest time.
func record_completion(time : float) -> void:
	completed = true
	if time > 0.0 and (best_time <= 0.0 or time < best_time):
		best_time = time


## Formats [member best_time] as M:SS.mmm, or "--:--" when never completed.
func get_best_time_text() -> String:
	if best_time <= 0.0:
		return "--:--"
	var minutes := int(best_time) / 60
	var seconds := int(best_time) % 60
	var milliseconds := int(fmod(best_time, 1.0) * 1000.0)
	return "%d:%02d.%03d" % [minutes, seconds, milliseconds]
