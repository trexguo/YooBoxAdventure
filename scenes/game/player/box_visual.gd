@tool
extends Node2D
## Small, code-drawn mascot: stable silhouette, feet anchored at local y=0.
var flip_h := false
var pose := "idle"
var crouched := false
var _height := 35.0
var _clock := 0.0
var _death_time := 0.0
const INK := Color("302536")
const CARD := Color("edaa52")
const LIGHT := Color("ffda86")
const SHADE := Color("bd733c")

func reset() -> void:
	pose = "idle"
	crouched = false
	_height = 35.0
	_death_time = 0.0
	_clock = 0.0
	queue_redraw()

func set_pose(value: String, is_crouched: bool) -> void:
	if value == "dead" and pose != "dead":
		_death_time = 0.0
	pose = value
	crouched = is_crouched

func _process(delta: float) -> void:
	_clock += delta
	_height = move_toward(_height, 16.0 if crouched else 35.0, delta * 160.0)
	if pose == "dead":
		_death_time += delta
	queue_redraw()

func _polygon(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, INK, 1.6, true)

func _draw() -> void:
	if pose == "dead" and _death_time > 0.07:
		var t := _death_time - 0.07
		for i in range(7):
			var angle := -PI + float(i) * TAU / 7.0
			var center := Vector2(cos(angle) * 90.0 * t, -18.0 + sin(angle) * 75.0 * t + 170.0 * t * t)
			draw_set_transform(center, angle + t * (float(i) - 3.0) * 7.0)
			var tint := LIGHT if i % 2 == 0 else CARD
			tint.a = clampf(1.0 - t / 0.28, 0.0, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(-3,-3), Vector2(4,-2), Vector2(2,4), Vector2(-3,2)]), tint)
		draw_set_transform(Vector2.ZERO)
		return
	if pose == "dash":
		var behind := 1.0 if flip_h else -1.0
		for i in range(3):
			var y := -10.0 - float(i) * 7.0
			draw_line(Vector2(behind*18.0,y),Vector2(behind*(29.0+float(i)*5.0),y),Color("ffda86"),1.5,true)
	var h := _height
	var step := sin(_clock * 22.0) * 2.0 if pose == "run" or crouched else 0.0
	# Only the feet cycle. The box never breathes, bobs, or changes scale.
	draw_line(Vector2(-7,-4), Vector2(-8 + step,-1.5), INK, 3.0, true)
	draw_line(Vector2(7,-4), Vector2(8 - step,-1.5), INK, 3.0, true)
	_polygon(PackedVector2Array([Vector2(-12,-h),Vector2(8,-h),Vector2(12,-h+4),Vector2(12,-5),Vector2(-12,-5)]), CARD)
	_polygon(PackedVector2Array([Vector2(8,-h),Vector2(12,-h+4),Vector2(12,-5),Vector2(8,-7)]), SHADE)
	draw_line(Vector2(-10,-h+2),Vector2(7,-h+2),LIGHT,2.0,true)
	# Packing tape and folded lid identify the character as a cardboard box.
	draw_rect(Rect2(-3,-h,5,6 if not crouched else 3),LIGHT)
	draw_line(Vector2(-0.5,-h),Vector2(-0.5,-h+4),SHADE,1.0)
	var face_y := -h + (10.0 if not crouched else 5.0)
	var look := -1.0 if flip_h else 1.0
	if pose == "dead":
		for x in [-6.0, 3.0]:
			draw_line(Vector2(x-2,face_y-2),Vector2(x+2,face_y+2),INK,2.0,true)
			draw_line(Vector2(x+2,face_y-2),Vector2(x-2,face_y+2),INK,2.0,true)
	else:
		for x in [-6.0, 3.0]:
			draw_circle(Vector2(x,face_y),3.1,INK)
			draw_circle(Vector2(x+look,face_y-0.6),1.1,Color("fff4dc"))
		if crouched or pose == "wall_slide":
			draw_line(Vector2(-9,face_y-4),Vector2(-3,face_y-2),INK,1.7,true)
			draw_line(Vector2(0,face_y-2),Vector2(6,face_y-4),INK,1.7,true)
	var mouth_y := face_y + (4.0 if crouched else 7.0)
	draw_style_box(_mouth_style(),Rect2(-6,mouth_y,11,2 if crouched else 5))
	draw_line(Vector2(-4,mouth_y+1),Vector2(3,mouth_y+1),Color("fff4dc"),1.7,true)
	# Small shipping-label slash on the cheek.
	draw_line(Vector2(-9,-8),Vector2(-6,-9),SHADE,1.0,true)
	if crouched:
		draw_line(Vector2(-12,-h),Vector2(-16,-h+3),INK,2.0,true)
		draw_line(Vector2(8,-h),Vector2(14,-h+2),INK,2.0,true)

var _mouth: StyleBoxFlat
func _mouth_style() -> StyleBoxFlat:
	if _mouth == null:
		_mouth = StyleBoxFlat.new()
		_mouth.bg_color = INK
		_mouth.set_corner_radius_all(2)
	return _mouth
