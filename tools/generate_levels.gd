@tool
extends SceneTree
## Generates the nine level scenes.
##
## Run from a terminal:
##
##     /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
##         --script res://tools/generate_levels.gd
##
## Each level is written as a standalone .tscn holding the full node tree, with
## its own ASCII map baked in. Levels deliberately do NOT instance a shared
## template scene: Godot cannot override a property on a child of an instanced
## scene (only on the instance root), so a map stored on the TileBuilder child
## could never be customised per level that way. The node structure is therefore
## emitted from one place here, which keeps the nine files consistent.
##
## Re-running overwrites the level scenes. Edit tools/build_level_maps.py to
## change a layout, then run that followed by this.
##
## ---------------------------------------------------------------------------
## All nine routes are authored in build_level_maps.py and campaign.json.
## Each has a >=20s displacement bound and an instanced escape cutscene.
## ---------------------------------------------------------------------------

const LEVELS_DIR := "res://scenes/game/levels/"
const LEVEL_COUNT := 9
const TILE_SIZE := 32

# Resource paths used by every generated level.
const LEVEL_SCRIPT := "res://scenes/game/levels/level.gd"
const BUILDER_SCRIPT := "res://scenes/game/levels/level_tile_builder.gd"
const TILESET := "res://resources/tilesets/placeholder_terrain.tres"

func _initialize() -> void:
	var campaign = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaign.json"))
	if not campaign is Array or campaign.size() != LEVEL_COUNT:
		push_error("Generate resources/campaign.json with build_level_maps.py first")
		quit(1)
		return
	for design in campaign:
		_write_level(int(design.number), design.map)
	print("Wrote %d complete campaign levels" % LEVEL_COUNT)
	quit()

func _write_level(number : int, map : String) -> void:
	var map_text := _clean_map(map)
	var path := "%slevel_%d.tscn" % [LEVELS_DIR, number]
	var root := _build_level_tree(number, map_text)

	var scene := PackedScene.new()
	# Every node must have its owner set to the scene root, or PackedScene.pack
	# silently drops it and the saved scene comes out empty.
	_assign_owners(root, root)
	var pack_error := scene.pack(root)
	if pack_error != OK:
		push_error("Failed to pack level %d: %d" % [number, pack_error])
		root.free()
		return
	var save_error := ResourceSaver.save(scene, path)
	if save_error != OK:
		push_error("Failed to save %s: %d" % [path, save_error])
	else:
		print("  wrote %s" % path)
	root.free()

## Builds the level's node tree in memory. Mirrors level_template.tscn; if the
## node structure changes, change it here.
func _build_level_tree(number : int, map_text : String) -> Node2D:
	var root := Node2D.new()
	root.name = "Level%d" % number
	root.set_script(load(LEVEL_SCRIPT))
	root.set("level_number", number)
	# Levels progress linearly through the SceneLister, so next_level_path is
	# only meaningful as the open-world hand-off and stays empty on the last.
	if number < LEVEL_COUNT:
		root.set("next_level_path", "%slevel_%d.tscn" % [LEVELS_DIR, number + 1])

	# Background canvas layer, so the play area reads clearly against the window.
	var background := CanvasLayer.new()
	background.name = "Background"
	background.layer = -10
	root.add_child(background)
	var color_rect := ColorRect.new()
	color_rect.name = "ColorRect"
	color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	color_rect.color = Color("14161f")
	background.add_child(color_rect)

	# The tile builder and the containers it writes into.
	var builder := Node.new()
	builder.name = "TileBuilder"
	builder.set_script(load(BUILDER_SCRIPT))
	builder.set("map", map_text)
	root.add_child(builder)

	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = load(TILESET)
	builder.add_child(terrain)

	# Solid terrain collision is built into this StaticBody2D. It must be a
	# physics body: CollisionShape2D nodes parented to a plain Node2D are inert.
	var collision := StaticBody2D.new()
	collision.name = "TerrainCollision"
	collision.collision_layer = 1
	collision.collision_mask = 0
	builder.add_child(collision)

	var hazards := Node2D.new()
	hazards.name = "Hazards"
	builder.add_child(hazards)

	# The spawn marker the level moves to the map's P cell.
	# unique_name_in_owner lets level.gd reach it with %SpawnPoint.
	var spawn := Marker2D.new()
	spawn.name = "SpawnPoint"
	spawn.unique_name_in_owner = true
	root.add_child(spawn)

	var story = load("res://scenes/game/story/escape_director.tscn").instantiate()
	root.add_child(story)
	return root

func _assign_owners(node : Node, owner : Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owners(child, owner)

## Trims the leading newline the GDScript multiline literals introduce and any
## trailing blank lines, so the map is exactly the rows of play space.
func _clean_map(map : String) -> String:
	var lines := map.split("\n")
	while lines.size() > 0 and lines[0].strip_edges().is_empty():
		lines.remove_at(0)
	while lines.size() > 0 and lines[lines.size() - 1].strip_edges().is_empty():
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines)
