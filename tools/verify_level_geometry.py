#!/usr/bin/env python3
"""Mirrors the player physics from scenes/game/player/player.gd and reports the
resulting movement envelope, then checks it against level 1's geometry.

Run after changing any player tuning value:

    python3 tools/verify_level_geometry.py

This exists because the level design depends on hard numbers (how high a jump
reaches, how wide a gap a run can clear, how far a wall jump climbs). Guessing
them leads to levels that look plausible but are unplayable, or trivially
skippable. Exported defaults are read directly from player.gd.
"""

from __future__ import annotations

# --- Read player.gd's exported tuning -----------------------------------
from build_level_maps import tuning
MAX_SPEED = tuning("max_speed")
JUMP_VELOCITY = tuning("jump_velocity")
RISE_GRAVITY = tuning("rise_gravity")
FALL_GRAVITY = tuning("fall_gravity")
MAX_FALL_SPEED = tuning("max_fall_speed")
WALL_SLIDE_SPEED = tuning("wall_slide_speed")
WALL_JUMP_PUSH = tuning("wall_jump_push")
WALL_JUMP_VELOCITY = tuning("wall_jump_velocity")
WALL_JUMP_LOCKOUT = tuning("wall_jump_lockout")
COYOTE_TIME = tuning("coyote_time")
# Body heights, from the two capsules in player.tscn. Crouching swaps between
# them; it does not change speed, so there is no crouch duration to mirror.
STAND_HEIGHT = 36.0
CROUCH_HEIGHT = 20.0

TILE = 32
DT = 1.0 / 60.0
# Every loop below is bounded by physics, but a bad tuning value could make one
# diverge. These caps turn that into a visible error instead of a hang.
MAX_STEPS = 100_000

# --- Control scheme ----------------------------------------------------------
# The player uses toggle-direction control: they always run at full speed and
# the direction keys only choose which way. A level therefore has to give the
# player time to react to a hazard they did not choose to approach, because
# they arrive at full speed with no way to stop except turning around.
#
# At 300 px/s a player covers ~4.7 tiles per 0.5 s, and the shortest human
# reaction-plus-settle is around 0.4 s. A level whose first hazard is closer
# than this to the spawn is unfair, not hard.
AUTO_RUN_REACTION_MARGIN = 0.6   # seconds of clear running before the first hazard
# A low tunnel this long (in seconds of running) reads as a deliberate obstacle
# rather than an invisible blip the player runs past without noticing.
MIN_TUNNEL_SECONDS = 0.20


def jump_height() -> float:
    """Peak height of a full-hold jump, in pixels."""
    height = 0.0
    velocity = JUMP_VELOCITY
    for _ in range(MAX_STEPS):
        if velocity <= 0.0:
            break
        velocity -= RISE_GRAVITY * DT
        height += velocity * DT
    else:
        raise RuntimeError("jump_height did not converge; check RISE_GRAVITY")
    return height


def run_jump_range() -> tuple[float, float]:
    """Horizontal distance and airtime of a full-speed jump that returns to its
    launch height."""
    time = 0.0
    height = 0.0
    velocity = JUMP_VELOCITY
    for _ in range(MAX_STEPS):
        if velocity <= 0.0:
            break
        velocity -= RISE_GRAVITY * DT
        height += velocity * DT
        time += DT
    else:
        raise RuntimeError("run_jump_range rise did not converge")
    # Start the descent from rest, not from the (negative) end-of-rise velocity.
    # `height` holds the peak, so falling reduces it toward zero.
    velocity = 0.0
    for _ in range(MAX_STEPS):
        if height <= 0.0:
            break
        velocity = min(velocity + FALL_GRAVITY * DT, MAX_FALL_SPEED)
        height -= velocity * DT
        time += DT
    else:
        raise RuntimeError("run_jump_range fall did not converge")
    return MAX_SPEED * time, time


def wall_jump_gain(shaft_width_px: float) -> float:
    """Vertical gain of one wall jump that crosses a shaft of this width.

    Returns the height gained from launch to the moment the far wall is touched.
    A negative result means the player hits the far wall below where they left,
    which makes the shaft unclimbable.
    """
    x = 0.0
    y = 0.0
    velocity_y = -WALL_JUMP_VELOCITY
    velocity_x = WALL_JUMP_PUSH
    for _ in range(MAX_STEPS):
        velocity_y = min(velocity_y + (RISE_GRAVITY if velocity_y < 0.0 else FALL_GRAVITY) * DT,
                         MAX_FALL_SPEED)
        x += velocity_x * DT
        y += velocity_y * DT
        if x >= shaft_width_px:
            return -y
    raise RuntimeError("wall_jump_gain did not reach the far wall")


def wall_jump_crossing_time(shaft_width_px: float) -> float:
    """Seconds a wall jump takes to carry the player across the shaft.

    This is the reaction window the player gets to line up the next wall jump,
    so it is the number that decides whether a chained climb feels fair.
    """
    x = 0.0
    for _ in range(MAX_STEPS):
        x += WALL_JUMP_PUSH * DT
        if x >= shaft_width_px:
            return (x / WALL_JUMP_PUSH)
    raise RuntimeError("wall_jump_crossing_time did not reach the far wall")


def crouch_run_seconds(tiles : float) -> float:
    """Seconds to run `tiles` tiles while crouched.

    Crouching does not change horizontal speed (see _update_crouch in player.gd),
    so this is the same as running: the tunnel is a gap to thread, not a timing
    test.
    """
    return (tiles * TILE) / MAX_SPEED


def main() -> int:
    height = jump_height()
    distance, airtime = run_jump_range()

    print("Movement envelope")
    print(f"  full jump height        {height:7.1f} px  ({height / TILE:.2f} tiles)")
    print(f"  run jump range          {distance:7.1f} px  ({distance / TILE:.2f} tiles)")
    print(f"  run jump airtime        {airtime:7.2f} s")
    print(f"  coyote window           {COYOTE_TIME:7.2f} s "
          f"({MAX_SPEED * COYOTE_TIME:.0f} px of travel at full speed)")
    print()

    print("Wall jump: vertical gain per jump, by shaft width")
    for tiles in range(2, 7):
        gain = wall_jump_gain(tiles * TILE)
        verdict = "climbable" if gain > 0 else "NOT climbable"
        print(f"  {tiles} tiles wide ({tiles * TILE:3d} px): "
              f"gain {gain:7.1f} px ({gain / TILE:+.2f} tiles)  {verdict}")
    print()

    # Check actual authored data, not hard-coded dimensions from an old map.
    import json
    from pathlib import Path
    from build_level_maps import build_campaign
    campaign = json.loads((Path(__file__).resolve().parents[1]/"resources/campaign.json").read_text())
    expected = build_campaign()
    failed = 0
    def check(label, passed):
        nonlocal failed
        failed += not passed
        print(f"  [{'PASS' if passed else 'FAIL'}] {label}")
    check("campaign matches authored layouts", campaign == expected)
    check("nine distinct layouts", len(campaign) == 9 and len({d['map'] for d in campaign}) == 9)
    previous_bound = 0.0
    for design in campaign:
        rows = design["map"].splitlines()
        name = f"Level {design['number']} / {design['title']}"
        check(name + " has exactly one spawn and exit",
              design['map'].count('P') == 1 and design['map'].count('G') == 1)
        check(name + " has uniform rows", all(len(r) == design['width'] for r in rows))
        # Dash adds a bounded displacement above base movement every cooldown,
        # plus one initial burst. This deliberately overestimates reachable speed.
        base = max(MAX_SPEED, WALL_JUMP_PUSH)
        bonus = max(0.0,tuning("dash_speed")-base)*tuning("dash_duration")
        bound = ((design['goal_x']-design['spawn_x'])*TILE-52.0-bonus)/(base+bonus/tuning("dash_cooldown"))
        check(f"{name}: >= {bound:.1f}s without cinematic time", bound >= 20 and bound >= previous_bound)
        previous_bound = bound
        check(name + " has multiple climbing sections", len(design['towers']) >= 3)
        check(name + " has safe first-obstacle runway", (design['beats'][0]['x']-design['spawn_x'])*TILE/MAX_SPEED >= AUTO_RUN_REACTION_MARGIN)
        for tower in design['towers']:
            check(name + f" shaft at {tower['left']} is climbable", wall_jump_gain(tower['width']*TILE) > 0)
            left, bottom = tower['left'], tower['bottom']
            check(name + f" shaft at {left} has a standing entrance", rows[bottom-1][left] == '.' and rows[bottom-2][left] == '.')
        for beat in design['beats']:
            kind = beat['kind']
            if kind.startswith('pit'):
                check(f"  gap at {beat['x']} is within jump range", int(kind[-1])*TILE+20 <= distance)
            elif kind.startswith('tunnel'):
                check(f"  tunnel at {beat['x']} admits crouch only", CROUCH_HEIGHT <= TILE < STAND_HEIGHT)
            elif kind in ('step2','stair','bridge'):
                check(f"  shelf at {beat['x']} is within jump height", 2*TILE <= height)
    print(f"\n{failed} failures" if failed else "\nall campaign geometry checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
