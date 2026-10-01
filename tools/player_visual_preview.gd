extends Node2D
## Run player_visual_preview.tscn to inspect the mascot without playing a level.
const VISUAL := preload("res://scenes/game/player/box_visual.gd")
var _elapsed := 0.0
var _demo: Node2D
var _phase := -1

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("171923"))
	_label("YOO / BOX", Vector2(75,65), 40, Color("ffda86"))
	_label("CARDBOARD COURAGE", Vector2(78,118), 17, Color("9294aa"))
	for i in range(4):
		var box := Node2D.new()
		box.set_script(VISUAL)
		box.position = Vector2(220 + i * 280,420)
		box.scale = Vector2(5,5)
		add_child(box)
		var baseline := Line2D.new()
		baseline.points = PackedVector2Array([Vector2(115+i*280,422),Vector2(325+i*280,422)])
		baseline.width = 1.5
		baseline.default_color = Color("465066")
		add_child(baseline)
		var labels := ["RUN", "CROUCH", "BREAK", "ANIMATION"]
		_label(labels[i],Vector2(155+i*280,480),22,Color("ffda86"))
		match i:
			0:
				box.pose = "run"
				box.set_motion(300.0)
			1:
				box.crouched = true
				box._height = 16.0
			2:
				box.pose = "dead"
				box._death_time = 0.18
				box.set_process(false)
			3: _demo = box
	_label("Box base   /   Gentle inertia   /   Fold to crouch   /   Break apart",Vector2(78,595),20,Color("b8b9cc"))

func _label(text: String, at: Vector2, size: int, tint: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",tint)
	add_child(label)

func _process(delta: float) -> void:
	_elapsed += delta
	var phase := int(_elapsed / 1.2) % 5
	if phase == _phase:
		return
	_phase = phase
	match phase:
		0:
			_demo.reset()
			_demo.flip_h = false
			_demo.set_pose("run",false)
			_demo.set_motion(300.0)
		1:
			_demo.flip_h = true
			_demo.set_motion(-300.0)
		2:
			_demo.set_pose("idle",false)
			_demo.set_motion(0.0)
		3: _demo.set_pose("crouch",true)
		4: _demo.set_pose("dead",false)
