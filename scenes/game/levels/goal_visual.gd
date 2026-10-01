@tool
extends Node2D
## Four-tile exit bay, bottom aligned with the terrain (goal center + 16px).
func _draw() -> void:
	var mint := Color("73d6bd")
	draw_rect(Rect2(-20,-112,40,128), Color("202c35"))
	draw_rect(Rect2(-15,-106,30,120), Color("17252c"))
	draw_line(Vector2(-18,16),Vector2(-18,-110),mint,3.0,true)
	draw_line(Vector2(18,16),Vector2(18,-110),mint,3.0,true)
	draw_line(Vector2(-18,-110),Vector2(18,-110),mint,3.0,true)
	draw_line(Vector2(-24,15),Vector2(24,15),mint,3.0,true)
	for y in range(-92,0,24):
		draw_polyline(PackedVector2Array([Vector2(-6,y-4),Vector2(0,y),Vector2(-6,y+4)]),mint.darkened(0.3),1.5,true)
	draw_string(ThemeDB.fallback_font,Vector2(-18,-120),"EXIT",HORIZONTAL_ALIGNMENT_LEFT,-1,11,mint)
