"""MV-style animation sheet: 5 columns of 192x192 cells, one row.

Cell size and column count are the img/animations row in reference/engine-layouts.md.
"""
import json
import pathlib

SIZE = 192
COLUMNS = 5
RADII = (6, 14, 28, 18, 8)


def frame(radius):
    rows = []
    core = max(2, radius // 3)
    for y in range(SIZE):
        chars = []
        for x in range(SIZE):
            dist = (x - 96) ** 2 + (y - 96) ** 2
            if dist <= core * core:
                chars.append("y")
            elif dist <= radius * radius:
                chars.append("o")
            else:
                chars.append(".")
        rows.append("".join(chars))
    return rows


def build():
    frames = {}
    order = []
    for index, radius in enumerate(RADII):
        name = f"fx{index}"
        frames[name] = frame(radius)
        order.append(name)
    return {
        "palette": {"y": "#ffe060", "o": "#e05020"},
        "frames": frames,
        "animations": {"spark": {"frames": order, "fps": 12}},
        "sheet": {"columns": COLUMNS, "order": order},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
