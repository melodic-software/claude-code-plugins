"""4-direction walker built by adapting character_kit, not by drawing from scratch.

Writes walker.json beside this file. Render it with scripts/render.py.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import character_kit as kit  # noqa: E402

CELL = 48
RAMPS = {
    "skin": ["#ffe0c0", "#f4b88c", "#d08860", "#7a3c2c"],
    "hair": ["#e8d070", "#c8a040", "#8c6820", "#3c2c0c"],
    "tunic": ["#8ec0f0", "#3c78d0", "#204888", "#101830"],
    "pants": ["#8c7058", "#5c4030", "#3c2818", "#1c1008"],
    "pants_back": ["#5c4030", "#3c2818", "#2c1c10", "#1c1008"],
    "boot": ["#6a4a34", "#4c3222", "#2c1c12", "#140c08"],
    "eye": ["#20202c", "#20202c", "#20202c", "#20202c"],
}


def draw(direction, step):
    grid = kit.Grid(CELL, CELL)
    layout = kit.body_layout(CELL, "standard", bob=0 if step == 0 else 1)
    side = direction == "left"
    kit.draw_legs(grid, layout, step, side, "pants", "pants_back", "boot")
    kit.draw_tunic(grid, layout, "tunic", side)
    kit.draw_head(grid, layout["head"], "round", "skin")
    kit.draw_hair(grid, layout["head"], "bob", "hair", direction)
    cx, cy, _rx, _ry = layout["head"]
    if direction == "down":
        grid.rect(cx - 5, cy, 2, 3, "eye")
        grid.rect(cx + 3, cy, 2, 3, "eye")
    elif direction == "left":
        grid.rect(cx - 6, cy, 2, 3, "eye")
    return grid


def build():
    frames = {}
    order = []
    palette = None
    for direction in ("down", "left", "right", "up"):
        for pattern, step in enumerate((-1, 0, 1)):
            grid = kit.for_direction(lambda facing, step=step: draw(facing, step), direction)
            rows, palette = kit.shade_rows(grid, RAMPS)
            name = f"{direction}{pattern}"
            frames[name] = rows
            order.append(name)
    animations = {
        f"walk_{direction}": {
            "frames": [f"{direction}0", f"{direction}1", f"{direction}2", f"{direction}1"],
            "durations_ms": [150, 150, 150, 150],
        }
        for direction in ("down", "left", "right", "up")
    }
    return {
        "palette": palette,
        "frames": frames,
        "animations": animations,
        "sheet": {"columns": 3, "order": order},
    }


if __name__ == "__main__":
    path = Path(__file__).with_name("walker.json")
    path.write_text(json.dumps(build()))
    print(path)
