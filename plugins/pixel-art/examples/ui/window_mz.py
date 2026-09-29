"""RPG Maker MZ Window.png as one 192x192 frame.

Region positions are the Window.png row in reference/engine-layouts.md. They match
rmmz_core.js Window._refreshBack, _refreshFrame, _refreshCursor, _refreshArrows,
_refreshPauseSign, and ColorManager.textColor, fetched 2026-09-28. render.py uses one
frame size per spec, so the regions are drawn into that single frame.
"""
import json
import pathlib

W = H = 192
TEXT = "0123456789ABCDEFGHIJKLMNOPQRSTUV"


def text_hex(index):
    red = (40 + index * 19) % 256
    green = (20 + index * 37) % 256
    blue = (80 + index * 11) % 256
    return f"#{red:02x}{green:02x}{blue:02x}"


def blank():
    return [["."] * W for _ in range(H)]


def fill(grid, x, y, w, h, color):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if 0 <= xx < W and 0 <= yy < H:
                grid[yy][xx] = color


def build():
    grid = blank()
    fill(grid, 0, 0, 95, 95, "b")  # background, stretched
    fill(grid, 0, 96, 96, 96, "p")  # pattern, tiled
    fill(grid, 96, 0, 96, 96, "e")  # 9-slice frame
    fill(grid, 120, 24, 48, 48, "f")  # frame center, 24px corners remain
    fill(grid, 132, 24, 24, 12, "n")  # up arrow
    fill(grid, 132, 60, 24, 12, "n")  # down arrow
    fill(grid, 96, 96, 48, 48, "c")  # cursor
    fill(grid, 144, 96, 24, 24, "s")  # pause sign
    for index, key in enumerate(TEXT):
        fill(grid, 96 + (index % 8) * 12, 144 + (index // 8) * 12, 12, 12, key)
    palette = {
        "b": "#201838",
        "p": "#483868",
        "e": "#f0e8d0",
        "f": "#282038",
        "n": "#f8f0c0",
        "c": "#f8f8f8",
        "s": "#e8d060",
    }
    palette.update({key: text_hex(index) for index, key in enumerate(TEXT)})
    return {
        "palette": palette,
        "frames": {"window": ["".join(row) for row in grid]},
        "sheet": {"columns": 1, "order": ["window"]},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
