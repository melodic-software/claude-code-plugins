"""MV-style animation sheet: 5 columns of 192x192 cells, one row.

Cell size and column count are the img/animations row in reference/engine-layouts.md.
The spark grows, steps down its palette ramp (bright, then dark), and ends on an empty cell,
so it fades by palette step, not alpha, and is gone before it loops.
"""
import json
import pathlib

SIZE = 192
COLUMNS = 5
# (radius, core color, rim color) per cell; radius 0 is the empty last cell
CELLS = ((6, "y", "o"), (14, "y", "o"), (28, "y", "o"), (18, "o", "r"), (0, None, None))


def frame(radius, core_key, rim_key):
    if radius == 0:
        return ["." * SIZE] * SIZE
    rows = []
    core = max(2, radius // 3)
    for y in range(SIZE):
        chars = []
        for x in range(SIZE):
            dist = (x - 96) ** 2 + (y - 96) ** 2
            if dist <= core * core:
                chars.append(core_key)
            elif dist <= radius * radius:
                chars.append(rim_key)
            else:
                chars.append(".")
        rows.append("".join(chars))
    return rows


def build():
    frames = {}
    order = []
    for index, cell in enumerate(CELLS):
        name = f"fx{index}"
        frames[name] = frame(*cell)
        order.append(name)
    return {
        "palette": {"y": "#ffe060", "o": "#e05020", "r": "#802010"},
        "frames": frames,
        "animations": {"spark": {"frames": order, "fps": 12, "direction": "forward"}},
        "sheet": {"columns": COLUMNS, "order": order},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
