@tool
extends Node2D
@export_enum("ZhangAss", "Yoo") var character := "ZhangAss"
var running := false
var worried := true
var _clock := 0.0

func _process(delta: float) -> void:
	_clock += delta
	if running:
		queue_redraw()

func _draw() -> void:
	var ink := Color("282433")
	var stride := sin(_clock*20.0)*3.0 if running else 0.0
	if character == "ZhangAss":
		# A heavy purple shipping crusher, with a jetpack and grabber arm.
		draw_rect(Rect2(-22,-33,11,24),ink)
		draw_rect(Rect2(-21,-31,7,19),Color("748091"))
		if running:
			draw_colored_polygon(PackedVector2Array([Vector2(-21,-12),Vector2(-28-stride,-4),Vector2(-16,-12)]),Color("ffb35b"))
		draw_rect(Rect2(-16,-39,32,34),ink)
		draw_rect(Rect2(-13,-36,26,27),Color("8170ac"))
		draw_rect(Rect2(-13,-36,26,5),Color("b0a0d1"))
		draw_rect(Rect2(-16,-29,33,9),ink)
		draw_line(Vector2(-9,-24),Vector2(-2,-24),Color("ff7582"),2.5,true)
		draw_line(Vector2(5,-24),Vector2(12,-24),Color("ff7582"),2.5,true)
		draw_line(Vector2(1,-15),Vector2(10,-12),ink,3.0,true)
		draw_line(Vector2(-7,-7),Vector2(-9+stride,-1),ink,5.0,true)
		draw_line(Vector2(8,-7),Vector2(10-stride,-1),ink,5.0,true)
		draw_line(Vector2(13,-15),Vector2(32,-12),ink,6.0,true)
		draw_circle(Vector2(32,-12),4.0,Color("b0a0d1"))
	else:
		# Pink parcel with a ribbon, a bow and a readable worried expression.
		draw_rect(Rect2(-12,-30,24,25),ink)
		draw_rect(Rect2(-10,-28,20,21),Color("f19db5"))
		draw_rect(Rect2(-10,-28,20,4),Color("ffd0db"))
		draw_rect(Rect2(-2,-29,4,7),Color("fff0bd"))
		draw_colored_polygon(PackedVector2Array([Vector2(0,-29),Vector2(-8,-36),Vector2(-8,-27)]),Color("f872a7"))
		draw_colored_polygon(PackedVector2Array([Vector2(0,-29),Vector2(8,-36),Vector2(8,-27)]),Color("f872a7"))
		draw_circle(Vector2(0,-30),2.2,Color("fff0bd"))
		for x in [-5.0,5.0]:
			draw_circle(Vector2(x,-19),2.7,ink)
			draw_circle(Vector2(x+0.7,-19.8),0.8,Color.WHITE)
		if worried:
			draw_circle(Vector2(0,-11),2.2,ink)
			draw_line(Vector2(-8,-24),Vector2(-3,-25),ink,1.0,true)
		else:
			draw_arc(Vector2(0,-14),4,0,PI,12,ink,1.5,true)
		draw_line(Vector2(-5,-6),Vector2(-7,-1),ink,2.5,true)
		draw_line(Vector2(5,-6),Vector2(7,-1),ink,2.5,true)
