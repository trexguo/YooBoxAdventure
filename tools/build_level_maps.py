#!/usr/bin/env python3
"""Builds the ASCII maps for tools/generate_levels.gd and rewrites them in place.

Keeping the maps as a grid of characters is what makes them reviewable, but
hand-counting 60-column rows is error-prone. This script is the authoring tool:
edit the drawing functions below, run it, and it rewrites the GDScript literals
with every row padded to a uniform width.

    python3 tools/build_level_maps.py
"""

from __future__ import annotations
import pathlib
import re

WIDTH = 60
HEIGHT = 20

EMPTY = "."
SOLID = "#"
SPIKE = "^"
SPAWN = "P"
GOAL = "G"


class Grid:
    def __init__(self, width=WIDTH, height=HEIGHT):
        self.w, self.h = width, height
        self.rows = [[EMPTY] * width for _ in range(height)]

    def rect(self, x0, y0, x1, y1, ch=SOLID):
        """Fills an inclusive rectangle."""
        for y in range(max(0, y0), min(self.h - 1, y1) + 1):
            for x in range(max(0, x0), min(self.w - 1, x1) + 1):
                self.rows[y][x] = ch

    def border(self, thickness=1):
        self.rect(0, 0, self.w - 1, thickness - 1)
        self.rect(0, self.h - thickness, self.w - 1, self.h - 1)
        self.rect(0, 0, thickness - 1, self.h - 1)
        self.rect(self.w - thickness, 0, self.w - 1, self.h - 1)

    def put(self, x, y, ch):
        self.rows[y][x] = ch

    def row(self, y):
        return "".join(self.rows[y])

    def validate(self, name):
        problems = []
        for y, r in enumerate(self.rows):
            if len(r) != self.w:
                problems.append(f"{name}: row {y} width {len(r)} != {self.w}")
        spawns = [(y, r.index(SPAWN)) for y, r in enumerate(self.rows) if SPAWN in r]
        goals = [(y, r.index(GOAL)) for y, r in enumerate(self.rows) if GOAL in r]
        if len(spawns) != 1:
            problems.append(f"{name}: expected 1 spawn, found {len(spawns)}")
        if len(goals) != 1:
            problems.append(f"{name}: expected 1 goal, found {len(goals)}")
        for (y, x) in spawns:
            if SOLID not in [self.rows[m][x] for m in range(y + 1, self.h)]:
                problems.append(f"{name}: spawn at ({x},{y}) has no ground beneath it")
        return problems


def tutorial() -> Grid:
    """Level 1: five beats, each forcing the verb it teaches.

    The level is a dead end. The player runs right along a floor, clears a spike
    pit, meets a pillar too tall to jump, and finds the floor stops at a shaft.
    The shaft's only opening is the doorway at floor level; it is roofed over and
    the goal sits at the top of it. The only way up is alternating wall jumps
    between its two facing walls.

    Every dimension is derived from the measured movement envelope in
    tools/verify_level_geometry.py, not by eye:

      full jump height  ~1.8 tiles   -> never step up more than 1 tile
      run jump range    ~3.7 tiles   -> never leave a gap wider than 3 tiles
      wall jump gain    ~1.7 tiles   per jump in a 3-tile shaft
                        (a 4-tile shaft drops to 1.0, a 5-tile shaft is
                         impossible, so the shaft is 3 tiles wide)

    Beats, left to right:
      1. run and a small hop        floor, then a 1-tile step
      2. jump across a spike pit    a 2-tile gap over spikes
      3. a pillar too tall to jump  3 tiles high, so it forces a wall jump
      4. drop into the shaft        the floor ends at the shaft doorway
      5. climb out                  ~2.4 wall jumps up to the goal
    """
    g = Grid()
    g.border()

    g.rect(0, 17, WIDTH - 1, 17)          # the floor runs the whole width
    g.rect(0, 18, WIDTH - 1, 18)          # bedrock

    # Beat 1: a 1-tile step, to establish that jumping is available.
    g.rect(4, 16, 8, 16)

    # Beat 2: a 2-tile spike pit. Spikes sit on the floor row, so the gap is
    # clearable with a run jump and lethal if walked into.
    for x in range(13, 15):
        g.put(x, 17, SPIKE)

    # Beat 3: a pillar 3 tiles tall. A jump reaches under 2 tiles, so hopping it
    # is impossible and the only way past is wall sliding on its face and wall
    # jumping off it. This is where the level stops being a walk.
    g.rect(19, 14, 19, 16, SOLID)

    # Beats 4 and 5: the shaft, which is the wall-jump climb.
    #
    # The shaft interior is 3 tiles wide. Widths were measured, not guessed:
    #
    #   interior | time to cross | gain per jump | 0.4s climb
    #   2 tiles  | 0.27 s        | +1.72 tiles   | 3 jumps
    #   3 tiles  | 0.40 s        | +1.68 tiles   | 3 jumps
    #   4 tiles  | 0.52 s        | +1.00 tiles   | 5 jumps
    #   5 tiles  | cant reach    | -0.57 tiles   | impossible
    #
    # A 2-tile interior climbs just as fast but leaves only 0.27s to react
    # between walls, which is too tight to teach on. A 4-tile interior more than
    # doubles the work for the same height. 3 tiles is the sweet spot: nearly
    # the same speed as 2 with a reaction window over twice as forgiving.
    #
    # There are deliberately NO spikes inside: a player stepping through the
    # doorway at floor level has no chance to react, so spiking the floor would
    # be an unfair instant death rather than difficulty. Missing a wall jump
    # drops them back to the floor and they try again.
    g.rect(31, 1, 31, 17, SOLID)
    g.rect(35, 1, 35, 17, SOLID)
    g.rect(31, 8, 35, 8, SOLID)           # roof, so the goal must be jumped to
    g.rect(32, 9, 34, 16, EMPTY)          # the interior to climb
    g.rect(31, 16, 31, 16, EMPTY)         # doorway in, at floor level

    g.put(33, 12, GOAL)
    g.put(5, 15, SPAWN)
    return g


def skeleton(seed: int) -> Grid:
    """Levels 2-9: a floor, a few platforms, a hazard and a goal.

    Intentionally simple. Each level is meant to be replaced wholesale once it
    gets a real design; these exist so progression and level select have targets.
    """
    g = Grid()
    g.border()
    g.rect(0, 17, WIDTH - 1, 17)                # ground
    g.rect(0, 18, WIDTH - 1, 18)

    # Spawn ledge on the left.
    g.put(5, 14, SPAWN)
    g.rect(4, 15, 8, 15)

    # A staggered platform run, with the spacing shifted per level by the seed.
    shift = (seed * 3) % 7
    g.rect(12 + shift, 13, 16 + shift, 13)
    g.rect(21 + shift, 11, 25 + shift, 11)
    g.rect(30 + shift, 9, 34 + shift, 9)

    # Goal shelf on the right.
    g.rect(42, 8, 48, 8)
    g.put(45, 7, GOAL)

    # A spike patch on the ground, away from the spawn.
    spike_x = 18 + (seed * 2) % 12
    for x in range(spike_x, spike_x + 3):
        if x < WIDTH - 2:
            g.put(x, 16, SPIKE)

    return g


def to_gdscript_literal(text: str, indent: str = '"""') -> str:
    return text


def format_map(g: Grid) -> str:
    body = "\n".join(g.row(y) for y in range(g.h))
    return f'"""\n{body}\n"""'


def main() -> int:
    path = pathlib.Path(__file__).resolve().parent / "generate_levels.gd"
    if not path.exists():
        print(f"cannot find {path}")
        return 1
    src = path.read_text()

    problems = []
    g1 = tutorial()
    problems += g1.validate("level_1")
    grids = [g1]
    for n in range(2, 10):
        g = skeleton(n)
        problems += g.validate(f"level_{n}")
        grids.append(g)

    if problems:
        for p in problems:
            print("  !!", p)
        print("aborting: fix the maps above")
        return 1

    literals = [format_map(g) for g in grids]
    # Replace the nine existing triple-quoted map literals, in order.
    pattern = re.compile(r'"""\n.*?\n"""', re.S)
    matches = pattern.findall(src)
    if len(matches) != 9:
        print(f"expected 9 map literals in the GDScript, found {len(matches)}")
        return 1

    def replacer(_m, counter=[0]):
        out = literals[counter[0]]
        counter[0] += 1
        return out

    src = pattern.sub(replacer, src)
    path.write_text(src)
    print(f"rewrote {len(literals)} maps in {path.name} ({WIDTH}x{HEIGHT} each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
