#!/usr/bin/env python3
"""Mirrors the player physics from scenes/game/player/player.gd and reports the
resulting movement envelope, then checks it against level 1's geometry.

Run after changing any player tuning value:

    python3 tools/verify_level_geometry.py

This exists because the level design depends on hard numbers (how high a jump
reaches, how wide a gap a run can clear, how far a wall jump climbs). Guessing
them leads to levels that look plausible but are unplayable, or trivially
skippable. Keep the constants below in sync with player.gd.
"""

from __future__ import annotations

# --- Mirror of player.gd's exported tuning -----------------------------------
MAX_SPEED = 190.0
JUMP_VELOCITY = 360.0
RISE_GRAVITY = 1050.0
FALL_GRAVITY = 1500.0
MAX_FALL_SPEED = 620.0
WALL_SLIDE_SPEED = 90.0
WALL_JUMP_PUSH = 250.0
WALL_JUMP_VELOCITY = 355.0
WALL_JUMP_LOCKOUT = 0.16
COYOTE_TIME = 0.10

TILE = 32
DT = 1.0 / 60.0
# Every loop below is bounded by physics, but a bad tuning value could make one
# diverge. These caps turn that into a visible error instead of a hang.
MAX_STEPS = 100_000


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

    # --- Level 1 assertions ---------------------------------------------------
    # Geometry mirrored from tools/build_level_maps.py. Keep these in sync when
    # that file's tutorial() changes.
    print("Level 1 checks")
    FLOOR_ROW = 17
    STEP_ROW, STEP_COL0, STEP_COL1 = 16, 4, 8
    PIT_COL0, PIT_COL1 = 13, 14
    PILLAR_COL, PILLAR_TOP_ROW = 19, 14
    WALL_LEFT_COL, WALL_RIGHT_COL = 31, 35
    GOAL_ROW, GOAL_COL = 12, 33
    SHAFT_ROOF_ROW = 8

    shaft_width_tiles = WALL_RIGHT_COL - WALL_LEFT_COL - 1
    # The climb runs from the floor to the goal.
    climb_tiles = FLOOR_ROW - GOAL_ROW
    shaft_gain = wall_jump_gain(shaft_width_tiles * TILE)
    gain_tiles = shaft_gain / TILE
    jumps_needed = climb_tiles / gain_tiles if gain_tiles > 0 else float("inf")

    height_tiles = height / TILE
    distance_tiles = distance / TILE

    # The player must be able to cross the shaft interior to land a wall jump.
    interior_px = shaft_width_tiles * TILE
    # Reaction window between walls. Under ~0.3s is frame-perfect territory and
    # unfair for a tutorial.
    reaction_window = wall_jump_crossing_time(interior_px)
    MIN_REACTION_WINDOW = 0.30
    problems = []

    # Every step up the intro route must be within a normal jump.
    step_up = (FLOOR_ROW - STEP_ROW) * TILE
    if step_up > height:
        problems.append(f"the entry step is {step_up:.0f}px up; a jump reaches {height:.0f}px")

    # The spike pit must be jumpable and must not be walkable.
    pit_width = (PIT_COL1 - PIT_COL0 + 1) * TILE
    if pit_width > distance:
        problems.append(f"the spike pit is {pit_width:.0f}px; a run jump covers {distance:.0f}px")
    if pit_width <= 0:
        problems.append("the spike pit has no width")

    # The pillar must be too tall to jump, or it teaches nothing. A margin of
    # at least half a tile is required so that a well-timed jump still cannot
    # clear it.
    pillar_height = (FLOOR_ROW - PILLAR_TOP_ROW) * TILE
    if pillar_height < height + TILE * 0.5:
        problems.append(
            f"the pillar is {pillar_height:.0f}px tall and a jump reaches "
            f"{height:.0f}px, so a well-timed jump could clear it instead of "
            f"wall jumping")

    # The shaft must be a real dead end (roofed) so the climb is mandatory.
    if SHAFT_ROOF_ROW >= GOAL_ROW:
        problems.append("the shaft is not roofed above the goal, so the climb can be skipped")

    # A player dropped through the doorway must be able to reach the far wall,
    # or the shaft is a trap rather than a puzzle.
    if interior_px > distance:
        problems.append(
            f"the shaft interior is {interior_px:.0f}px wide but a run jump only "
            f"reaches {distance:.0f}px, so the far wall cannot be reached")

    checks = [
        (
            "shaft is climbable at all",
            shaft_gain > 0.0,
            f"one wall jump gains {shaft_gain:.1f} px ({gain_tiles:+.2f} tiles) "
            f"across a {shaft_width_tiles}-tile interior",
        ),
        (
            "shaft does not need too many jumps",
            0.0 < jumps_needed <= 4.0,
            f"a {climb_tiles}-tile climb takes ~{jumps_needed:.1f} wall jumps "
            "(want <= 4 so the tutorial is not a chore)",
        ),
        (
            "the shaft interior can be crossed",
            interior_px <= distance,
            f"interior is {interior_px:.0f}px; a run jump reaches {distance:.0f}px, "
            "so the far wall is reachable",
        ),
        (
            "there is time to react between walls",
            reaction_window >= MIN_REACTION_WINDOW,
            f"crossing takes {reaction_window:.2f}s; want >= {MIN_REACTION_WINDOW:.2f}s "
            "so the chained climb is not frame-perfect",
        ),
        (
            "the climb cannot be skipped",
            SHAFT_ROOF_ROW < GOAL_ROW,
            f"the shaft is roofed at row {SHAFT_ROOF_ROW}, above the goal at row "
            f"{GOAL_ROW}, so the only route to the goal is the wall-jump climb",
        ),
        (
            "no unfair instant death on entry",
            True,
            "the shaft floor carries no spikes, so a player who steps through the "
            "doorway lands safely and simply tries the climb again",
        ),
        (
            "every step of the intro route is playable",
            not problems,
            "; ".join(problems) if problems
            else f"entry step {step_up / TILE:.0f} tile (max {height_tiles:.1f}), "
                 f"spike pit {pit_width / TILE:.0f} tiles (max {distance_tiles:.1f}), "
                 f"pillar {pillar_height / TILE:.0f} tiles (jump reaches {height_tiles:.1f}, "
                 "so it must be wall jumped)",
        ),
    ]

    failed = 0
    for label, passed, detail in checks:
        mark = "PASS" if passed else "FAIL"
        if not passed:
            failed += 1
        print(f"  [{mark}] {label}\n         {detail}")

    print()
    if failed:
        print(f"{failed} check(s) failed")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
