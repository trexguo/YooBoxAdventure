extends MainMenu
## Main menu extension that adds options.
## The scene adds a 'Continue' button if a game is in progress.

## Optional scene to open when the player clicks a 'Level Select' button.
@export var level_select_packed_scene: PackedScene
## If true, have the player confirm before starting a new game if a game is in progress.
@export var confirm_new_game : bool = true

@onready var continue_game_button = %ContinueGameButton
@onready var level_select_button = %LevelSelectButton
@onready var new_game_confirmation = %NewGameConfirmation

func load_game_scene() -> void:
	GameState.start_game()
	super.load_game_scene()

func new_game() -> void:
	# Confirm whenever there is progress to lose, not merely when the Continue
	# button happens to be showing. A player mid-progress who has not yet
	# finished a level would otherwise wipe their save with one click.
	if confirm_new_game and GameState.has_progress():
		new_game_confirmation.show()
	else:
		GameState.reset()
		load_game_scene()

## The level select menu is always offered: locked rows show the player what is
## ahead, and replaying an already-unlocked level is a supported flow.
func _add_level_select_if_set() -> void:
	if level_select_packed_scene == null:
		return
	level_select_button.show()

## The Continue button appears whenever there is progress to resume. It checks
## the checkpoint rather than the last-played level, so finding a level by its
## checkpoint (and replaying from it) both count as being in progress.
func _show_continue_if_set() -> void:
	if not GameState.has_progress():
		return
	continue_game_button.show()

func _ready() -> void:
	super._ready()
	_add_level_select_if_set()
	_show_continue_if_set()

func _on_continue_game_button_pressed() -> void:
	GameState.continue_game()
	load_game_scene()

func _on_level_select_button_pressed() -> void:
	var level_select_scene := _open_sub_menu(level_select_packed_scene)
	if level_select_scene.has_signal("level_selected"):
		level_select_scene.connect("level_selected", load_game_scene)

func _on_new_game_confirmation_confirmed() -> void:
	GameState.reset()
	load_game_scene()
