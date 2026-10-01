# YooBoxAdventure chase campaign

The nine-stage campaign follows Yoo's kidnapping by ZhangAss, a purple shipping
crusher with a jetpack. The player is the cardboard-box hero. Yoo is a pink
parcel with a bow. All characters are drawn in Godot; no external character
assets are required.

| Stage | Main progression | Shafts / total climb | Automated clean route |
| --- | --- | --- | --- |
| 1 | Safe air dash practice, steps, crouch, three progressively taller climbs | 3 / 18 tiles | 27.38s |
| 2 | Jump rhythm between four lifts | 4 / 27 tiles | 30.32s |
| 3 | Low passages between varying climbs | 4 / 28 tiles | 30.82s |
| 4 | Shelves and stairs between sustained climbs | 5 / 40 tiles | 34.27s |
| 5 | Narrow landings and longer vertical chains | 5 / 45 tiles | 35.85s |
| 6 | Crouch, jump and climb combinations | 6 / 57 tiles | 38.77s |
| 7 | Alternating three- and four-tile shafts | 6 / 63 tiles | 42.70s |
| 8 | Seven varied lifts with mixed approaches | 7 / 79 tiles | 47.62s |
| 9 | Tallest chains, seven lifts, Yoo's rescue | 7 / 91 tiles | 51.95s |

Times come from `tools/campaign_playthrough.gd`, which drives the actual player
and terrain physics. They establish a playable route, not a speedrun record or
a prediction of a new player's completion time. Deaths, intro and outro are
excluded. Every route additionally has a conservative geometric minimum above 20 seconds,
including air dash. Base speed is bounded by 300px/s; dash at 620px/s for 0.16s
adds at most 51.2px every 1.6s, plus one initial burst. The check also allows 52px
of early goal contact. Thus `(horizontal distance - 52 - 51.2) / 332` is a lower
bound on completion time (21.3–29.0s across the campaign).
There is no timed exit lock or forced wait to pad the level duration.

## Flow

Each generated scene instances `scenes/game/story/escape_director.tscn`. On
entry ZhangAss approaches Yoo, grabs her, and leaves with her using his jetpack.
The player is held in place and the run timer remains stopped until the intro
finishes. Enter or the Skip button skips the intro. Deaths do not replay it.

At the goal the run time is recorded and player control is held while the boss
escapes again. Completion is emitted after the short outro. In stage nine Yoo
breaks free and joins the hero before the existing final-game flow continues.

The HUD shows the chapter, current attempt time, horizontal route progress and air dash readiness (ready, land to recharge, or cooldown seconds). Death resets the attempt clock and snaps the camera to spawn, while `total_play_time` keeps cumulative active play. Best times use the successful attempt. Stage one changes
its tutorial hint according to the nearby obstacle. Signs mark safe dash practice, jump, crouch, shelf and wall-jump sections. Arrows inside shafts point upward; exits indicate where to steer right. Warehouse backgrounds are static vector drawings.

## Authoring and verification

```sh
python3 tools/build_level_maps.py
python3 tools/verify_level_geometry.py
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --script res://tools/generate_levels.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --script res://tools/smoke_test_levels.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --fixed-fps 60 --script res://tools/campaign_playthrough.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --fixed-fps 60 --script res://tools/test_campaign_story.gd
```

Edit the recipes in `build_level_maps.py`, regenerate `campaign.json`, then
regenerate the nine scenes. Do not hand-edit generated level layouts. The
story template remains shared; each chapter's map and metadata remain unique.
Campaign traversal and story tests restore the original save on completion.

## Air dash

Tap S / B while airborne to dash horizontally at 620px/s for 0.16s (99.2px,
3.1 tiles). Gravity pauses during the burst, and terrain and hazards still
collide normally. Each airtime allows one dash; landing restores the charge,
but launches remain at least 1.6s apart. Holding crouch on the ground does not
automatically dash on walking off a ledge. Death and respawn clear dash state.

## Vertical route structure

Each map climbs through several loading bays rather than reserving wall jumps
for the exit. Shafts have two-tile entrances, three or four tiles of clear width,
and an upper exit onto the next bay. Heights start at 4, 6 and 8 tiles in the
teaching level and reach 16 tiles in the finale. Width and height vary across
later shafts. Horizontal bays give breathing room between vertical chains.
The map-derived kill plane and camera limits support the full height.

These physics checks establish reachability, collision behavior and timing.
They do not establish human difficulty or guarantee every later stage takes
longer than the previous one under every strategy. Human playtesting is still needed to tune challenge and fatigue.

## Pace and screen scale

Run speed is 300px/s (previously 230), wall push is 300px/s, and dash is
620px/s. Ground/turn acceleration is 1900px/s² for a responsive reversal.
Ground jump height remains unchanged; faster horizontal motion increases
full run-jump range to approximately 210px. Maps are 235–315 tiles wide to
preserve the minimum duration under faster movement.

Camera zoom is 1.5: a 32px world tile displays at 48px and the 35px standing
box silhouette at approximately 53px in the base 1280×720 viewport. Yoo and
ZhangAss share the same scale. World tile size, collision shapes and shaft
widths stay proportional. The camera leads by 96 world pixels horizontally
and 48 upward, with faster smoothing. Lead direction eases on the ground;
wall jumps retain it to prevent the camera swaying between walls.

## Smooth rendering

Physics interpolation is enabled. Player motion, camera lead and Camera2D
smoothing update on physics ticks; rendered frames interpolate between them.
Spawn, respawn and intro repositioning reset interpolation to prevent streaks.
The escape director disables interpolation for its frame-driven cinematic
actors. Keep interpolated transforms out of `_process()`.
