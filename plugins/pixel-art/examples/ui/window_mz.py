"""RPG Maker MZ Window.png as one 192x192 frame.

Region positions are the Window.png row in reference/engine-layouts.md. render.py uses one frame
size per spec, so the regions are drawn into that single frame.
"""
import json
import pathlib

W = H = 192


def blank():
    return [["."] * W for _ in range(H)]


def fill(grid, x, y, w, h, color):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                grid[yy][xx] = color


def build():
    grid = blank()
    fill(grid, 0, 0, 95, 95, "b")          # background
    fill(grid, 0, 96, 96, 96, "p")         # pattern
    fill(grid, 96, 0, 96, 96, "e")         # frame edge
    fill(grid, 120, 24, 48, 48, "f")       # frame center, 24px corners remain
    fill(grid, 96, 96, 48, 48, "c")        # cursor
    fill(grid, 144, 96, 24, 24, "a")       # pause sign
    for i, color in enumerate("0123"):
        fill(grid, 96 + i * 12, 144, 12, 12, color)
    rows = ["".join(row) for row in grid]
    return {
        "palette": {
            "b": "#201838",
            "p": "#483868",
            "e": "#f0e8d0",
            "f": "#282038",
            "c": "#f8f8f8",
            "a": "#e8d060",
            "0": "#f8f8f8",
            "1": "#e07050",
            "2": "#70b0e0",
            "3": "#88c058",
        },
        "frames": {"window": rows},
        "sheet": {"columns": 1, "order": ["window"]},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
