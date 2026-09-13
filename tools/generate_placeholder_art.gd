extends SceneTree
## Generates the placeholder art used until real assets exist.
##
## Run it from a terminal:
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/generate_placeholder_art.gd
##
## Delete this file once real sprites are in place; nothing at runtime depends
## on it. Re-running overwrites the PNGs in res://assets/placeholder/.

const OUTPUT_DIR := "res://assets/placeholder/"
const TILE_SIZE := 32

# Palette.
const COLOR_PLAYER := Color("e8483f")
const COLOR_PLAYER_DARK := Color("a32b25")
const COLOR_TERRAIN := Color("3d4257")
const COLOR_TERRAIN_TOP := Color("6ee7a8")
const COLOR_TERRAIN_EDGE := Color("272b3d")
const COLOR_SPIKE := Color("d9e0f2")
const COLOR_GOAL := Color("ffd166")
const COLOR_GOAL_DARK := Color("b3903f")
const COLOR_BACKGROUND := Color("14161f")

func _initialize() -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	_save("player", _make_player())
	_save("terrain", _make_terrain())
	_save("spike", _make_spike())
	_save("goal", _make_goal())
	_save("background", _make_background())
	print("Placeholder art written to %s" % OUTPUT_DIR)
	quit()

func _save(basename : String, image : Image) -> void:
	var path := OUTPUT_DIR + basename + ".png"
	var absolute_path := ProjectSettings.globalize_path(path)
	var err := image.save_png(absolute_path)
	if err != OK:
		push_error("Failed to write %s: %d" % [path, err])
	else:
		print("  wrote %s" % path)

func _new_image(width : int, height : int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	return image

## A 20x36 body: dark outline, bright core, eye pixels so facing is readable.
func _make_player() -> Image:
	var image := _new_image(20, 36)
	image.fill(Color(0, 0, 0, 0))
	for y in 36:
		for x in 20:
			# Rounded top, flat bottom.
			var inset := 3 - y / 2 if y < 6 else 0
			if y < 6 and (x < inset or x > 19 - inset):
				continue
			var edge := x < 1 or x > 18 or y < 1 or y > 34
			image.set_pixel(x, y, COLOR_PLAYER_DARK if edge else COLOR_PLAYER)
	# Eyes, offset to the right so the default facing reads correctly.
	for y in range(10, 14):
		for x in range(9, 12):
			image.set_pixel(x, y, Color.WHITE)
		image.set_pixel(10, y, Color("1b1d29"))
	return image

## A 32x32 block with a bright top lip, so the standable surface is obvious.
func _make_terrain() -> Image:
	var image := _new_image(TILE_SIZE, TILE_SIZE)
	image.fill(COLOR_TERRAIN)
	for x in TILE_SIZE:
		for y in range(0, 3):
			image.set_pixel(x, y, COLOR_TERRAIN_TOP)
		# Subtle interior grid so tile boundaries are visible while building.
		image.set_pixel(x, 0, COLOR_TERRAIN_EDGE)
	for y in TILE_SIZE:
		image.set_pixel(0, y, COLOR_TERRAIN_EDGE)
		image.set_pixel(TILE_SIZE - 1, y, COLOR_TERRAIN_EDGE)
	return image

## A 32x32 upward spike, so the kill zone reads as dangerous.
func _make_spike() -> Image:
	var image := _new_image(TILE_SIZE, TILE_SIZE)
	image.fill(Color(0, 0, 0, 0))
	# Four teeth across the tile.
	var teeth := 4
	var tooth_width := TILE_SIZE / teeth
	var half_tooth := tooth_width / 2
	for tooth in teeth:
		var base_x := tooth * tooth_width
		for y in TILE_SIZE:
			# Each tooth is a triangle narrowing toward the top.
			var progress := float(TILE_SIZE - 1 - y) / float(TILE_SIZE - 1)
			var half_width := int(round(progress * (half_tooth - 1.0)))
			var center_x := base_x + tooth_width / 2
			for x in range(center_x - half_width, center_x + half_width + 1):
				if x >= 0 and x < TILE_SIZE:
					image.set_pixel(x, y, COLOR_SPIKE)
	return image

## A 32x32 flag marker for the level exit.
func _make_goal() -> Image:
	var image := _new_image(TILE_SIZE, TILE_SIZE)
	image.fill(Color(0, 0, 0, 0))
	# Pole down the left edge.
	for y in TILE_SIZE:
		for x in range(2, 5):
			image.set_pixel(x, y, COLOR_GOAL_DARK)
	# Flag triangle at the top.
	for y in range(2, 20):
		var width : int = 20 - absi(y - 11)
		for x in range(5, 5 + width):
			if x < TILE_SIZE:
				image.set_pixel(x, y, COLOR_GOAL)
	return image

## A 1x1 flat background color, stretched by the level's ColorRect.
func _make_background() -> Image:
	var image := _new_image(1, 1)
	image.set_pixel(0, 0, COLOR_BACKGROUND)
	return image
