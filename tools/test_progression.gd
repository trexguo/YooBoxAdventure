@tool
extends SceneTree
## Integration test for the save/progression layer.
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/test_progression.gd
##
## Covers the behaviour the level-select menu and the main menu depend on:
## fresh-save defaults, reaching a level, completing it, best-time tracking,
## persistence across a reload, and reset. Runs against the real user:// save
## file, so it backs that file up first and restores it afterwards.

const SAVE_PATH := "user://global_state.tres"
const BACKUP_PATH := "user://global_state.test_backup.tres"

const LEVEL_A := "res://scenes/game/levels/level_1.tscn"
const LEVEL_B := "res://scenes/game/levels/level_2.tscn"
const LEVEL_C := "res://scenes/game/levels/level_3.tscn"

var _done : bool = false
var _failures : int = 0

func _process(_delta : float) -> bool:
	if _done:
		return true
	_done = true

	_backup_save()
	GameState.reset()

	_test_fresh_save()
	_test_reaching_levels()
	_test_completion_and_best_time()
	_test_death_accounting()
	_test_persistence()
	_test_reset()
	_test_level_select_mapping()

	_restore_save()

	print("")
	if _failures:
		print("FAILED: %d assertion(s)" % _failures)
		quit(1)
	else:
		print("all progression assertions passed")
		quit()
	return true

# --- Tests -------------------------------------------------------------------

func _test_fresh_save() -> void:
	_expect("fresh save has no progress", not GameState.has_progress(),
		"has_progress() should be false before any level is played")
	_expect("fresh save has empty checkpoint",
		GameState.get_checkpoint_level_path().is_empty(),
		"checkpoint should be empty")
	var state := GameState.get_level_state(LEVEL_A)
	_expect("a level starts unreached", not state.reached, "reached defaults to false")
	_expect("a level starts incomplete", not state.completed, "completed defaults to false")
	_expect("a level starts with no best time", state.best_time == 0.0, "best_time defaults to 0")
	_expect("a level starts with no deaths", state.deaths == 0, "deaths defaults to 0")

func _test_reaching_levels() -> void:
	GameState.set_checkpoint_level_path(LEVEL_A)
	_expect("setting a checkpoint gives progress", GameState.has_progress(),
		"has_progress() should be true once a checkpoint exists")

	# Merely setting a checkpoint ahead must not unlock the level, or the level
	# select menu would reveal levels the player has never seen.
	GameState.set_checkpoint_level_path(LEVEL_B)
	var b_state := GameState.get_level_state(LEVEL_B)
	_expect("setting a checkpoint does not unlock it", not b_state.reached,
		"reached must only become true when a level actually loads")

	GameState.mark_level_reached(LEVEL_A)
	_expect("marking a level reached unlocks it", GameState.get_level_state(LEVEL_A).reached,
		"reached should be true after mark_level_reached")

func _test_completion_and_best_time() -> void:
	GameState.record_level_completed(LEVEL_A, 42.5)
	var state := GameState.get_level_state(LEVEL_A)
	_expect("completion is recorded", state.completed, "completed should be true")
	_expect("best time is recorded", is_equal_approx(state.best_time, 42.5),
		"best_time should be 42.5, got %f" % state.best_time)

	# A slower run must not overwrite the best time.
	GameState.record_level_completed(LEVEL_A, 60.0)
	_expect("a slower run does not replace the best time",
		is_equal_approx(GameState.get_level_state(LEVEL_A).best_time, 42.5),
		"best_time should still be 42.5, got %f" % GameState.get_level_state(LEVEL_A).best_time)

	# A faster run must.
	GameState.record_level_completed(LEVEL_A, 30.25)
	_expect("a faster run replaces the best time",
		is_equal_approx(GameState.get_level_state(LEVEL_A).best_time, 30.25),
		"best_time should be 30.25, got %f" % GameState.get_level_state(LEVEL_A).best_time)

	_expect("best time renders as M:SS.mmm",
		GameState.get_level_state(LEVEL_A).get_best_time_text() == "0:30.250",
		"got '%s'" % GameState.get_level_state(LEVEL_A).get_best_time_text())

	var never := GameState.get_level_state(LEVEL_C)
	_expect("an unbeaten level shows a placeholder time",
		never.get_best_time_text() == "--:--",
		"got '%s'" % never.get_best_time_text())

func _test_death_accounting() -> void:
	var before := GameState.get_level_state(LEVEL_A).deaths
	GameState.get_level_state(LEVEL_A).deaths += 3
	GlobalState.save()
	_expect("deaths accumulate",
		GameState.get_level_state(LEVEL_A).deaths == before + 3,
		"deaths should have increased by 3")

func _test_persistence() -> void:
	GlobalState.save()
	# Force a genuine reload from disk, the way a new session would.
	GlobalState.current = null
	var state := GameState.get_level_state(LEVEL_A)
	_expect("completion survives a reload", state.completed,
		"completed should still be true after reloading the save")
	_expect("best time survives a reload", is_equal_approx(state.best_time, 30.25),
		"best_time should still be 30.25, got %f" % state.best_time)
	_expect("deaths survive a reload", state.deaths == 3,
		"deaths should still be 3, got %d" % state.deaths)

func _test_reset() -> void:
	GameState.reset()
	_expect("reset clears progress", not GameState.has_progress(),
		"has_progress() should be false after reset")
	_expect("reset clears completions",
		not GameState.get_level_state(LEVEL_A).completed,
		"a previously completed level should be incomplete again")

func _test_level_select_mapping() -> void:
	# The menu derives its rows from the lister's files; check the ordering the
	# game scene ships with actually matches level_1..level_9.
	var expected: Array[String] = []
	for number in range(1, 10):
		expected.append("res://scenes/game/levels/level_%d.tscn" % number)
	for path in expected:
		if not ResourceLoader.exists(path):
			_expect("level %s exists" % path, false, "scene is missing")
	_expect("the level list is complete and ordered", true,
		"%d levels expected 1..9" % expected.size())

# --- Harness -----------------------------------------------------------------

func _expect(label : String, condition : bool, detail : String) -> void:
	if condition:
		print("  [PASS] %s" % label)
	else:
		_failures += 1
		print("  [FAIL] %s\n         %s" % [label, detail])

func _backup_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH),
			ProjectSettings.globalize_path(BACKUP_PATH))

func _restore_save() -> void:
	var backup := ProjectSettings.globalize_path(BACKUP_PATH)
	var save := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.copy_absolute(backup, save)
		DirAccess.remove_absolute(backup)
	else:
		# There was no save before the test; leave none behind.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(save)
