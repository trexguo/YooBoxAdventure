@tool
extends Node2D
## Square paper box, resting on its bottom edge at local y=0.
var flip_h := false
var pose := "idle"
var crouched := false
var _height := 35.0
var _motion_ratio := 0.0
var _lean := 0.0
const HALF_WIDTH := 17.5
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
	_motion_ratio = 0.0
	_lean = 0.0
	queue_redraw()

func set_pose(value: String, is_crouched: bool) -> void:
	if value == "dead" and pose != "dead":
		_death_time = 0.0
	pose = value
	crouched = is_crouched

## Use actual velocity so a reversal retains its previous lean until momentum
## changes. Drawing-only shear keeps collision and physics interpolation stable.
func set_motion(horizontal_speed: float, speed_limit: float = 300.0) -> void:
	_motion_ratio = clampf(horizontal_speed / maxf(speed_limit, 1.0), -1.0, 1.0)

func _process(delta: float) -> void:
	var degrees := 4.0
	if pose == "dash":
		degrees = 6.0
	elif crouched:
		degrees = 2.0
	elif pose == "jump" or pose == "fall":
		degrees = 3.0
	var target := deg_to_rad(degrees) * _motion_ratio
	if pose == "idle" or pose == "dead" or pose == "wall_slide":
		target = 0.0
	_lean = lerpf(_lean, target, 1.0 - exp(-10.0 * delta))
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
	draw_set_transform(Vector2.ZERO)
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
			draw_line(Vector2(behind*21.0,y),Vector2(behind*(32.0+float(i)*5.0),y),Color("ffda86"),1.5,true)
	var h := _height
	# Shear around the bottom edge: x shifts with height, while every point's
	# y stays unchanged. Both bottom corners remain planted at y=0.
	var body_transform := Transform2D(Vector2.RIGHT, Vector2(-tan(_lean), 1.0), Vector2.ZERO)
	draw_set_transform_matrix(body_transform)
	_polygon(PackedVector2Array([Vector2(-HALF_WIDTH,-h),Vector2(HALF_WIDTH,-h),Vector2(HALF_WIDTH,0),Vector2(-HALF_WIDTH,0)]), CARD)
	_polygon(PackedVector2Array([Vector2(HALF_WIDTH-3,-h),Vector2(HALF_WIDTH,-h),Vector2(HALF_WIDTH,0),Vector2(HALF_WIDTH-3,0)]), SHADE)

	draw_line(Vector2(-HALF_WIDTH+2,-h+2),Vector2(HALF_WIDTH-4,-h+2),LIGHT,2.0,true)
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
	draw_line(Vector2(-11,-8),Vector2(-8,-9),SHADE,1.0,true)
	if crouched:
		draw_line(Vector2(-HALF_WIDTH,-h),Vector2(-HALF_WIDTH-4,-h+3),INK,2.0,true)
		draw_line(Vector2(HALF_WIDTH-3,-h),Vector2(HALF_WIDTH+3,-h+2),INK,2.0,true)

	draw_set_transform(Vector2.ZERO)

var _mouth: StyleBoxFlat
func _mouth_style() -> StyleBoxFlat:
	if _mouth == null:
		_mouth = StyleBoxFlat.new()
		_mouth.bg_color = INK
		_mouth.set_corner_radius_all(2)
	return _mouth
