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
var _title: Label
var _dash_status: Label
var _status: Label
var _hint: Label
var _caption: Label
var _skip: Button
var _hud_clock := 0.0
var _intro: bool = false
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

func _label(at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(label)
	return label

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 15
	add_child(_hud)
	var panel := ColorRect.new()
	panel.position = Vector2(16,16)
	panel.size = Vector2(710,88)
	panel.color = Color("202533")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	_title = _label(Vector2(30,24),24,Color(design.accent))
	_title.text = "%02d / %s" % [int(design.number),design.title]
	_status = _label(Vector2(30,57),17,Color("d8dfeb"))
	_hint = _label(Vector2(30,80),14,Color("a5b5c9"))
	_hint.text = "A / D: direction   SPACE / X: jump   S / B: crouch / air dash"
	_dash_status = _label(Vector2(770,30),20,Color("ffda86"))
	_caption = _label(Vector2(32,660),23,Color("ffda86"))
	_skip = Button.new()
	_skip.text = "Skip / Enter"
	_skip.position = Vector2(1100,24)
	_skip.pressed.connect(_finish_intro)
	_hud.add_child(_skip)
	_skip.hide()

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
	_lock_player(true)
	_skip.show()
	var floor_y := float(design.floor_row)*32.0
	_player.global_position.y = floor_y - 0.1
	_player.reset_physics_interpolation()
	var start := Vector2(_player.global_position.x+190,floor_y)
	boss.position = start
	yoo.position = start+Vector2(92,0)
	boss.show()
	yoo.show()
	yoo.worried = true
	_caption.text = "ZhangAss: Special delivery. Yoo is coming with me!"
	_tween = create_tween()
	_tween.tween_interval(0.5)
	_tween.tween_property(boss,"position:x",start.x+60,0.3)
	_tween.tween_callback(_grab_yoo)
	_tween.tween_interval(0.35)
	_tween.tween_callback(func():
		boss.running = true
		_caption.text = "Yoo: Help!    /    Chase ZhangAss!")
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
	boss.hide()
	yoo.hide()
	_skip.hide()
	_caption.text = ""
	_lock_player(false)
	intro_finished.emit()

func play_outro() -> void:
	cinematic_active = true
	_lock_player(true)
	if yoo.get_parent() != self:
		yoo.reparent(self)
	yoo.scale = Vector2.ONE
	yoo.rotation = 0.0
	boss.position = _level.get_node("Goal").position+Vector2(60,18)
	yoo.position = boss.position+Vector2(42,-8)
	boss.show()
	yoo.show()
	boss.running = false
	_caption.text = "ZhangAss: Too slow! Next shipment!"
	_tween = create_tween()
	_tween.tween_interval(0.25)
	_tween.tween_callback(_grab_yoo)
	_tween.tween_callback(func(): boss.running = true)
	if int(design.number) == 9:
		_caption.text = "Yoo breaks free. Delivery complete!"
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
	var progress := clampf((_player.position.x-float(design.spawn_x)*32.0)/((float(design.goal_x)-float(design.spawn_x))*32.0),0.0,1.0)
	var dash_ready: bool = _player._dash_available and _player._dash_cooldown_timer <= 0.0
	if dash_ready:
		_dash_status.text = "AIR DASH / READY"
		_dash_status.modulate = Color("73d6bd")
	elif not _player._dash_available:
		_dash_status.text = "AIR DASH / LAND TO RECHARGE"
		_dash_status.modulate = Color("a5b5c9")
	else:
		_dash_status.text = "AIR DASH / %.1fs" % _player._dash_cooldown_timer
		_dash_status.modulate = Color("ffda86")
	_status.text = "%s   /   %05.1fs   /   ROUTE %02d%%" % [design.subtitle,_level.elapsed_time,int(progress*100.0)]
	if int(design.number) != 1 or cinematic_active:
		return
	var x := _player.position.x / 32.0
	_hint.text = "A / D: change direction. You keep running after release."
	for beat in design.beats:
		if x >= float(beat.x)-7.0 and x <= float(beat.x)+12.0 and absf(_player.position.y-float(beat.floor)*32.0) < 110.0:
			var kind: String = beat.kind
			if kind == "dash_practice":
				_hint.text = "Safe practice: jump, then tap S / B to dash. Land to recharge."
			elif kind.begins_with("tunnel"):
				_hint.text = "Hold S / B to fold under the roof. Release after clearing it."
			elif kind.begins_with("pit"):
				_hint.text = "Hold SPACE / X to jump. Tap S / B in the air to dash once."
			else:
				_hint.text = "Jump onto the steps. Safe landings let you try again."
			break
	for tower in design.towers:
		if x > float(tower.left)-5.0 and x < float(tower.right)+2.0 and _player.position.y > float(tower.top)*32.0-64.0:
			_hint.text = "Jump at each wall to climb. Keep alternating; steer RIGHT at the top."
			break
