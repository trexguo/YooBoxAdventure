@tool
extends SceneTree
## Rebuild the shared, portable cartoon Theme without changing vendored UI.
const INK := Color("302536")
const CREAM := Color("fff4d6")
const YELLOW := Color("ffce45")
const MINT := Color("39d6a4")
const BLUE := Color("53baff")
const CORAL := Color("ff806d")

func _box(fill: Color, radius: int = 18, margin: Vector2 = Vector2(24,12)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(3)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	box.shadow_color = INK
	box.shadow_size = 0
	box.shadow_offset = Vector2(0,4)
	return box

func _icon(content: String, size: int = 32) -> Texture2D:
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 32 32">%s</svg>' % [size,size,content]
	var image := Image.new()
	image.load_svg_from_string(source)
	return ImageTexture.create_from_image(image)

func _buttons(theme: Theme, type: String, fill: Color) -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var color := fill
		if state == "hover": color = fill.lightened(0.18)
		if state == "pressed": color = fill.darkened(0.08)
		if state == "disabled": color = Color("ddd1b9")
		var style := _box(color)
		if state == "pressed": style.shadow_offset = Vector2.ZERO
		theme.set_stylebox(state,type,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		theme.set_color(state,type,INK)
	theme.set_color("font_disabled_color",type,Color("786c72"))
	var focus := _box(Color.TRANSPARENT)
	focus.draw_center = false
	focus.border_color = Color("1262ae")
	focus.set_border_width_all(5)
	focus.expand_margin_left = 4
	focus.expand_margin_right = 4
	focus.expand_margin_top = 4
	focus.expand_margin_bottom = 4
	theme.set_stylebox("focus",type,focus)
	theme.set_font_size("font_size",type,28)
	theme.set_constant("outline_size",type,0)
	theme.set_constant("h_separation",type,12)

func _initialize() -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next","Nunito","Noto Sans","DejaVu Sans"])
	font.font_weight = 700
	theme.default_font = font
	theme.default_font_size = 26
	_buttons(theme,"Button",YELLOW)
	_buttons(theme,"OptionButton",BLUE)
	_buttons(theme,"MenuButton",BLUE)
	for entry in [["MintButton",MINT],["BlueButton",BLUE],["CoralButton",CORAL],["HUDButton",YELLOW]]:
		theme.set_type_variation(entry[0],"Button")
		_buttons(theme,entry[0],entry[1])
	theme.set_font_size("font_size","HUDButton",22)
	for type in ["Label","RichTextLabel","CheckButton","CheckBox"]:
		theme.set_color("font_color",type,INK)
		theme.set_font_size("font_size",type,24)
	theme.set_color("default_color","RichTextLabel",INK)
	for name in ["normal_font_size","bold_font_size","italics_font_size","bold_italics_font_size","mono_font_size"]:
		theme.set_font_size(name,"RichTextLabel",24)
	for type in ["VBoxContainer","HBoxContainer","BoxContainer"]:
		theme.set_constant("separation",type,14)
	theme.set_constant("h_separation","GridContainer",20)
	theme.set_constant("v_separation","GridContainer",14)
	for type in ["Panel","PanelContainer","PopupPanel"]:
		theme.set_stylebox("panel",type,_box(CREAM,24,Vector2(24,20)))
	for type in ["LineEdit","TextEdit","SpinBox"]:
		theme.set_color("font_color",type,INK)
		theme.set_color("font_selected_color",type,INK)
		theme.set_color("selection_color",type,MINT)
		theme.set_stylebox("normal",type,_box(Color("fffdfa"),14,Vector2(16,10)))
		theme.set_stylebox("focus",type,theme.get_stylebox("focus","Button"))
		theme.set_font_size("font_size",type,26)
	var tick := '<rect x="2" y="2" width="28" height="28" rx="8" fill="#39d6a4" stroke="#302536" stroke-width="3"/><path d="M8 16L14 22L25 10" fill="none" stroke="#302536" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>'
	var empty := '<rect x="2" y="2" width="28" height="28" rx="8" fill="#fffdfa" stroke="#302536" stroke-width="3"/>'
	var tick_texture := _icon(tick)
	var empty_texture := _icon(empty)
	for type in ["CheckBox","CheckButton"]:
		for name in ["checked","checked_disabled","on","on_disabled"]: theme.set_icon(name,type,tick_texture)
		for name in ["unchecked","unchecked_disabled","off","off_disabled"]: theme.set_icon(name,type,empty_texture)
		theme.set_constant("h_separation",type,14)
		theme.set_stylebox("normal",type,_box(Color.TRANSPARENT,12,Vector2(8,10)))
		theme.set_stylebox("focus",type,theme.get_stylebox("focus","Button"))
	var knob := _icon('<circle cx="16" cy="16" r="13" fill="#ffce45" stroke="#302536" stroke-width="3"/>')
	for type in ["HSlider","VSlider"]:
		theme.set_icon("grabber",type,knob)
		theme.set_icon("grabber_highlight",type,knob)
		var track := _box(Color("e4d7bb"),7,Vector2(0,7))
		track.shadow_offset = Vector2.ZERO
		theme.set_stylebox("slider",type,track)
		theme.set_stylebox("grabber_area",type,_box(MINT,7,Vector2(0,7)))
		theme.set_stylebox("grabber_area_highlight",type,_box(BLUE,7,Vector2(0,7)))
	for type in ["TabContainer","TabBar"]:
		for entry in [["tab_selected",YELLOW],["tab_unselected",Color("ffdf87")],["tab_hovered",MINT],["tab_disabled",Color("ddd1b9")]]:
			theme.set_stylebox(entry[0],type,_box(entry[1],14,Vector2(20,12)))
		for name in ["font_selected_color","font_unselected_color","font_hovered_color"]: theme.set_color(name,type,INK)
		theme.set_font_size("font_size",type,26)
	theme.set_stylebox("panel","TabContainer",_box(CREAM,18,Vector2(24,20)))
	for name in ["font_color","font_selected_color","font_hovered_color","font_hovered_selected_color"]: theme.set_color(name,"ItemList",INK)
	theme.set_color("font_disabled_color","ItemList",Color("80716e"))
	theme.set_font_size("font_size","ItemList",26)
	theme.set_stylebox("panel","ItemList",_box(CREAM,22,Vector2(20,16)))
	for name in ["selected","selected_focus","hovered"]: theme.set_stylebox(name,"ItemList",_box(MINT if name != "hovered" else YELLOW,12,Vector2(10,8)))
	theme.set_stylebox("focus","ItemList",theme.get_stylebox("focus","Button"))
	theme.set_constant("v_separation","ItemList",18)
	for type in ["VScrollBar","HScrollBar"]:
		var track := _box(Color("e4d7bb"),8,Vector2(9,9))
		track.shadow_offset = Vector2.ZERO
		theme.set_stylebox("scroll",type,track)
		for name in ["grabber","grabber_highlight","grabber_pressed"]: theme.set_stylebox(name,type,_box(BLUE,8,Vector2(9,9)))
	for type in ["Tree","PopupMenu"]:
		theme.set_stylebox("panel",type,_box(CREAM,16,Vector2(16,12)))
		for name in ["selected","selected_focus","hover","hovered"]: theme.set_stylebox(name,type,_box(MINT,10,Vector2(8,6)))
		for name in ["font_color","font_selected_color","font_hover_color"]: theme.set_color(name,type,INK)
		theme.set_font_size("font_size",type,24)
		theme.set_constant("v_separation",type,12)
	theme.set_icon("arrow","OptionButton",_icon('<path d="M8 12L16 21L24 12" fill="none" stroke="#302536" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>',24))
	theme.set_stylebox("panel","TooltipPanel",_box(YELLOW,12,Vector2(16,12)))
	theme.set_color("font_color","TooltipLabel",INK)
	theme.set_font_size("font_size","TooltipLabel",22)
	var error := ResourceSaver.save(theme,"res://resources/themes/cartoon_box.tres")
	print("Cartoon theme saved: ",error)
	quit(error)
