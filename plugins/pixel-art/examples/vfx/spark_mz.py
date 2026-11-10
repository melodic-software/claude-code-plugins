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
    center = SIZE // 2
    core_sq, rim_sq = max(2, radius // 3) ** 2, radius ** 2

    def pixel(x, y):
        dist = (x - center) ** 2 + (y - center) ** 2
        if dist <= core_sq:
            return core_key
        return rim_key if dist <= rim_sq else "."

    return ["".join(pixel(x, y) for x in range(SIZE)) for y in range(SIZE)]


def build():
    order = [f"fx{index}" for index in range(len(CELLS))]
    frames = {name: frame(*cell) for name, cell in zip(order, CELLS)}
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
