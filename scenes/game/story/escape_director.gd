extends Node2D
## Shared by all generated levels. Cinematics never contribute to the run timer.
signal intro_finished
var cinematic_active := false
var intro_has_finished := false
var design: Dictionary
var _level: Node2D
var _player: Node2D
var _tween: Tween
var _hud: CanvasLayer
var _timer: Label
var _pause_menu: Control
var _hud_clock := 0.0
var _intro: bool = false
var _waiting_at_exit := false
@onready var boss: Node2D = $ZhangAss
@onready var yoo: Node2D = $Yoo

func configure(level: Node2D, data: Dictionary) -> void:
	_level = level
	_player = level.get_player()
	design = data
	_build_hud()
	var backdrop := Node2D.new()
	backdrop.set_script(load("res://scenes/game/story/stage_backdrop.gd"))
	level.add_child(backdrop)
	backdrop.configure(data)
	boss.hide()
	yoo.hide()
	if level.play_intro:
		play_intro.call_deferred()
	else:
		intro_has_finished = true
		_place_exit_waiters()

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 15
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_timer = Label.new()
	_timer.name = "RunTimer"
	_timer.text = "00:00.0"
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer.add_theme_font_size_override("font_size",32)
	_timer.add_theme_color_override("font_color",Color("fff4d6"))
	_timer.add_theme_color_override("font_outline_color",Color("302536"))
	_timer.add_theme_constant_override("outline_size",4)
	_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_timer)
	_timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer.offset_left = -120
	_timer.offset_right = 120
	_timer.offset_top = 20
	_timer.offset_bottom = 84
	var pause_button := Button.new()
	pause_button.name = "PauseButton"
	pause_button.add_to_group("gameplay_pointer_blocker")
	pause_button.icon = preload("res://assets/ui/pause.svg")
	pause_button.tooltip_text = "Pause / Esc"
	pause_button.theme_type_variation = &"BlueButton"
	pause_button.position = Vector2(20,20)
	pause_button.custom_minimum_size = Vector2(64,64)
	root.add_child(pause_button)
	for state in ["normal","hover","pressed","disabled"]:
		var style := pause_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_left = 16
		style.content_margin_right = 16
		pause_button.add_theme_stylebox_override(state,style)
	pause_button.pressed.connect(_pause_game)

func _pause_game() -> void:
	var controller := get_tree().current_scene.find_child("PauseMenuController",true,false)
	if controller:
		controller.pause()
		return
	# Standalone level previews use the same pause menu as the full game.
	if not is_instance_valid(_pause_menu):
		_pause_menu = load("res://scenes/windows/pause_menu.tscn").instantiate()
		_pause_menu.hide()
		_level.add_child(_pause_menu)
	_pause_menu.show()

func _lock_player(locked: bool) -> void:
	if not is_instance_valid(_player):
		return
	_player.set_input_enabled(not locked)
	_player.set_physics_process(not locked)
	_player.velocity = Vector2.ZERO
	if locked:
		_player.get_node("Sprite2D").set_pose("idle",false)

func play_intro() -> void:
	cinematic_active = true
	_intro = true
	_waiting_at_exit = false
	if yoo.get_parent() != self:
		yoo.reparent(self)
	yoo.scale = Vector2.ONE
	yoo.rotation = 0.0
	boss.running = false
	_lock_player(true)
	var floor_y := float(design.floor_row)*32.0
	_player.global_position.y = floor_y - 0.1
	_player.reset_physics_interpolation()
	var start := Vector2(_player.global_position.x+190,floor_y)
	boss.position = start
	yoo.position = start+Vector2(92,0)
	boss.show()
	yoo.show()
	yoo.worried = true
	_tween = create_tween()
	_tween.tween_interval(0.5)
	_tween.tween_property(boss,"position:x",start.x+60,0.3)
	_tween.tween_callback(_grab_yoo)
	_tween.tween_interval(0.35)
	_tween.tween_callback(func(): boss.running = true)
	_tween.tween_property(boss,"position",start+Vector2(1050,-90),1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_finish_intro)

func _grab_yoo() -> void:
	if yoo.get_parent() != boss:
		yoo.reparent(boss)
	yoo.scale = Vector2.ONE
	yoo.position = Vector2(33,-10)
	yoo.rotation = -0.22

func _finish_intro() -> void:
	if not _intro:
		return
	if _tween and _tween.is_running():
		_tween.kill()
	_intro = false
	cinematic_active = false
	intro_has_finished = true
	_place_exit_waiters()
	_lock_player(false)
	intro_finished.emit()

## The kidnappers are already visible when the player approaches the exit.
## Death/retry leaves them here; reaching the goal starts their escape in place.
func _place_exit_waiters() -> void:
	if _waiting_at_exit:
		return
	boss.position = _level.get_node("Goal").position + Vector2(88,16)
	boss.running = false
	_grab_yoo()
	yoo.worried = true
	yoo.queue_redraw()
	boss.show()
	yoo.show()
	_waiting_at_exit = true

func play_outro() -> void:
	if _intro:
		_finish_intro()
	_place_exit_waiters()
	_waiting_at_exit = false
	cinematic_active = true
	_lock_player(true)
	_tween = create_tween()
	_tween.tween_interval(0.25)
	_tween.tween_callback(func(): boss.running = true)
	if int(design.number) == 9:
		_tween.tween_interval(0.25)
		_tween.tween_callback(func():
			yoo.reparent(self)
			yoo.rotation = 0.0
			yoo.worried = false)
		_tween.tween_property(yoo,"global_position",_player.global_position+Vector2(35,0),0.35)
	_tween.tween_property(boss,"position",boss.position+Vector2(360,-210),0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _tween.finished
	boss.hide()
	if int(design.number) != 9:
		yoo.hide()
	cinematic_active = false

func _process(delta: float) -> void:
	if design.is_empty():
		return
	if _intro and Input.is_action_just_pressed("ui_accept"):
		_finish_intro()
	_hud_clock += delta
	if _hud_clock < 0.1:
		return
	_hud_clock = 0.0
	var seconds: float = _level.elapsed_time
	_timer.text = "%02d:%04.1f" % [int(seconds / 60.0),fmod(seconds,60.0)]
