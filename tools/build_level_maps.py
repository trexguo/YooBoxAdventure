#!/usr/bin/env python3
"""Author the nine-stage chase campaign; regenerate before generate_levels.gd.

Each route has a conservative >=20s displacement bound including running and dash. Cinematics,
deaths and wall-climbing add time but are never used to satisfy that bound.
"""
from __future__ import annotations
import json
import re
from pathlib import Path

PLAYER_SOURCE = (Path(__file__).resolve().parents[1]/"scenes/game/player/player.gd").read_text()
def tuning(name):
    match = re.search(r"@export(?:_[^\s]+(?:\([^\n]*\))?)? var " + name + r"\s*:\s*float\s*=\s*([0-9.]+)", PLAYER_SOURCE)
    if not match:
        raise ValueError(f"Missing exported player tuning: {name}")
    return float(match.group(1))

BASE_SPEED = max(tuning("max_speed"), tuning("wall_jump_push"))
DASH_BONUS = max(0.0,tuning("dash_speed")-BASE_SPEED)*tuning("dash_duration")
TRAVEL_SPEED_BOUND = BASE_SPEED+DASH_BONUS/tuning("dash_cooldown")

TILE = 32
HEIGHT = 24
FLOOR = 20
# Individually paced obstacle sequences, not random variants of one template.
DESIGNS = [
    ("First Delivery", "Learn to chase", 235, 3, 4, "#73d6bd", ["step", "tunnel", "pit2", "step", "pit2", "tunnel", "stair", "pit2"]),
    ("Broken Conveyor", "Find your jump rhythm", 245, 3, 5, "#78b9ee", ["pit2", "step", "pit3", "stair", "pit2", "pit3", "step", "pit3", "pit2"]),
    ("Folded Passage", "Stay low, then jump", 255, 3, 5, "#b4a0ec", ["tunnel", "pit2", "tunnel_long", "step", "combo", "tunnel_long", "pit3", "combo", "tunnel"]),
    ("Loading Docks", "Control your landing", 265, 3, 6, "#eca66d", ["stair", "pit3", "step2", "pit2", "stair", "pit3", "step2", "double", "stair", "pit3"]),
    ("Fragile Freight", "Land on the small shelves", 275, 3, 7, "#ee8baa", ["pit3", "bridge", "step2", "double", "combo", "bridge", "stair", "pit3", "bridge", "double"]),
    ("Compression Line", "Change pose between hazards", 285, 3, 8, "#e8c972", ["combo", "tunnel_long", "double", "stair", "combo", "bridge", "tunnel_long", "double", "combo", "bridge", "pit3"]),
    ("High Priority", "Longer climb, tighter rhythm", 295, 4, 8, "#82b9dd", ["double", "bridge", "combo", "step2", "double", "pit3", "bridge", "combo", "stair", "double", "pit3"]),
    ("Return to Sender", "Link every move", 305, 4, 9, "#a99bea", ["bridge", "combo", "double", "stair", "bridge", "tunnel_long", "double", "combo", "bridge", "step2", "double", "combo"]),
    ("Last Dispatch", "The final pursuit", 315, 4, 10, "#ef7f81", ["combo", "bridge", "double", "step2", "combo", "double", "bridge", "tunnel_long", "double", "bridge", "combo", "double", "pit3"]),
]

class Grid:
    def __init__(self, width, height=HEIGHT):
        self.w, self.h = width, height
        self.rows = [["."] * width for _ in range(height)]
    def rect(self, x0, y0, x1, y1, char="#"):
        for y in range(max(0,y0), min(self.h-1,y1)+1):
            for x in range(max(0,x0), min(self.w-1,x1)+1):
                self.rows[y][x] = char
    def put(self, x,y,char):
        self.rows[y][x] = char
    def text(self):
        return "\n".join("".join(row) for row in self.rows)


def obstacle(g, kind, x, floor, ceiling):
    if kind in ("step", "step2"):
        height = 1 if kind == "step" else 2
        g.rect(x, floor-height, x+2, floor-1)
    elif kind == "stair":
        g.rect(x, floor-1, x+2, floor-1)
        g.rect(x+3, floor-2, x+5, floor-1)
    elif kind.startswith("pit"):
        width = int(kind[-1])
        g.rect(x,floor,x+width-1,floor+1,".")
        g.rect(x,floor+2,x+width-1,floor+2,"^")
    elif kind in ("tunnel", "tunnel_long"):
        width = 3 if kind == "tunnel" else 5
        g.rect(x,ceiling,x+width-1,floor-2)
    elif kind == "combo":
        g.rect(x,floor-1,x+1,floor-1,"^")
        g.rect(x+9,ceiling,x+11,floor-2)
    elif kind == "double":
        g.rect(x,floor-1,x+1,floor-1,"^")
        g.rect(x+8,floor-1,x+9,floor-1,"^")
    elif kind == "bridge":
        g.rect(x,floor-1,x+7,floor-1,"^")
        g.rect(x,floor-2,x+2,floor-2)
        g.rect(x+5,floor-2,x+7,floor-2)
    else:
        raise ValueError(kind)


def build_campaign():
    result = []
    # Successive loading bays ascend through the warehouse. Narrow shafts teach
    # alternation; later widths vary, and taller lifts demand sustained chains.
    climbs = [[4,6,8], [6,7,6,8], [5,8,6,9], [6,8,10,7,9],
              [8,10,7,11,9], [7,10,8,12,9,11], [8,11,9,13,10,12],
              [9,12,10,14,11,13,10], [10,13,11,15,12,14,16]]
    for number, (name, subtitle, width, _, _, color, kinds) in enumerate(DESIGNS,1):
        heights = climbs[number-1]
        floor = 20 + sum(heights)
        g = Grid(width, floor+4)
        g.rect(0,0,width-1,0)
        g.rect(0,0,0,g.h-1)
        g.rect(width-1,0,width-1,g.h-1)
        g.put(4,floor-1,"P")
        spawn_floor = floor
        towers, bays, beats = [], [], []
        starts = [round((width-18)*(i+1)/(len(heights)+1)) for i in range(len(heights))]
        bay_start, beat_index = 1, 0
        for i in range(len(heights)+1):
            left = starts[i] if i < len(heights) else width-2
            g.rect(bay_start,floor,left-1,g.h-1)
            ceiling = 2 if i == 0 else max(2,floor-7)
            bays.append({"start":bay_start,"end":left-1,"floor":floor})
            # Leave space to read the next shaft and recover from the last jump.
            first = max(bay_start+6,20 if i == 0 else bay_start+6)
            slots = [first] if first+12 <= left-4 else []
            if first+34 <= left-4:
                slots.append(first+22)
            for x in slots:
                kind = kinds[beat_index % len(kinds)]
                obstacle(g,kind,x,floor,ceiling)
                beats.append({"kind":kind,"x":x,"floor":floor})
                beat_index += 1
            if i == len(heights):
                break
            shaft_width = 3 if number < 7 or i % 2 == 0 else 4
            right = left+shaft_width+1
            upper = floor-heights[i]
            # Bottom entrance is two tiles high. The right wall ends at the
            # upper bay floor, so cresting it leads naturally to the next bay.
            g.rect(left,upper-4,left,floor-3)
            g.rect(left,floor,right,g.h-1)
            g.rect(right,upper,right,g.h-1)
            g.rect(left,upper-4,right,upper-4)
            towers.append({"left":left,"right":right,"width":shaft_width,
                           "bottom":floor,"top":upper,"climb":heights[i]})
            bay_start, floor = right+1, upper
        goal_x = width-7
        g.put(goal_x,floor-1,"G")
        if number == 1:
            # Safe flat runway: practice jumping and dashing without a death pit.
            beats.insert(0,{"kind":"dash_practice","x":10,"floor":spawn_floor})
        lower_bound = ((goal_x-4)*TILE - 52.0 - DASH_BONUS)/TRAVEL_SPEED_BOUND
        assert lower_bound >= 20.0
        result.append({"number":number,"title":name,"subtitle":subtitle,"accent":color,
            "width":width,"height":g.h,"floor_row":spawn_floor,"spawn_x":4,
            "goal_x":goal_x,"goal_y":floor-1,"shaft_left":towers[-1]["left"],
            "shaft_width":towers[-1]["width"],"climb_tiles":sum(heights),
            "minimum_travel_seconds":lower_bound,"towers":towers,"bays":bays,
            "beats":beats,"map":g.text()})
    return result


def main():
    path = Path(__file__).resolve().parents[1]/"resources"/"campaign.json"
    levels = build_campaign()
    path.write_text(json.dumps(levels,indent=2)+"\n")
    for level in levels:
        print(f'{level["number"]}. {level["title"]}: {level["width"]} tiles, minimum travel {level["minimum_travel_seconds"]:.1f}s')

if __name__ == "__main__":
    main()
