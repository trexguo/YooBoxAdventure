extends Node2D
var design: Dictionary
var accent := Color("73d6bd")

func configure(data: Dictionary) -> void:
	design = data
	accent = Color(data.accent)
	z_index = -2
	queue_redraw()

func _draw() -> void:
	if design.is_empty():
		return
	var floor_y := float(design.floor_row)*32.0
	# Opaque, static warehouse panels. No shaders or transparent full-screen effects.
	for x in range(0,int(design.width)*32,320):
		draw_rect(Rect2(x+12,68,296,floor_y-128),Color("191e2a"))
		draw_line(Vector2(x+12,68),Vector2(x+308,68),accent.darkened(0.72),2.0)
		for y in range(120,int(floor_y)-100,320):
			draw_rect(Rect2(x+36,y,12,26),accent.darkened(0.7))
			draw_line(Vector2(x+54,y+13),Vector2(x+274,y+13),Color("252b39"),1.0)
	var font := ThemeDB.fallback_font
	for i in design.beats.size():
		var beat: Dictionary = design.beats[i]
		var x := float(beat.x)*32.0
		floor_y = float(beat.floor)*32.0
		var kind: String = beat.kind
		var text := "JUMP"
		if kind == "dash_practice":
			text = "JUMP > TAP S / B / SAFE"
		elif kind.begins_with("tunnel"):
			text = "HOLD S / B"
		elif kind == "combo":
			text = "JUMP > CROUCH"
		elif kind == "bridge":
			text = "USE THE SHELVES"
		elif kind == "double":
			text = "JUMP > LAND > JUMP"
		draw_rect(Rect2(x-180,floor_y-110,210,30),Color("252b39"))
		draw_string(font,Vector2(x-168,floor_y-89),"%02d / %s" % [i+1,text],HORIZONTAL_ALIGNMENT_LEFT,-1,13,accent)
	for tower in design.towers:
		var shaft_x := float(tower.left)*32.0
		var bottom := float(tower.bottom)*32.0
		draw_string(font,Vector2(shaft_x-170,bottom-115),"WALL JUMP / ALTERNATE",HORIZONTAL_ALIGNMENT_LEFT,-1,14,accent)
		for row in range(int(tower.top)+1,int(tower.bottom)-2,3):
			var center := Vector2((float(tower.left)+float(tower.right)+1.0)*16.0,float(row)*32.0)
			draw_polyline(PackedVector2Array([center+Vector2(-8,5),center+Vector2(0,-3),center+Vector2(8,5)]),accent.darkened(0.3),2.0)
		draw_string(font,Vector2(float(tower.right)*32.0+36,float(tower.top)*32.0-65),"EXIT >",HORIZONTAL_ALIGNMENT_LEFT,-1,14,accent)
