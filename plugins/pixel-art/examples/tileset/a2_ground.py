"""RPG Maker MZ A2 ground sheet: 8 columns of 96x144 blocks, 4 rows, 768x576.

The block size and sheet size are the A2 row in reference/engine-layouts.md. Each block is the
2x3-tile quarter source the engine composes floor shapes from: top-left tile is the preview,
top-right tile carries the inner corners (lip where its four quarters meet), and the lower 96x96
carries the outer edges and corners (a lip band around a grass interior). The lip is the same
thickness everywhere so any quarter meets any partner quarter.
"""
import json
import pathlib

W, H = 96, 144
TILE, LIP = 48, 6
COLUMNS = 8
COUNT = 32  # 8 * (576 / 144)


def is_lip(x, y):
    if y < TILE:
        # inner-corner tile: a lip square centered where its quarters meet
        return x >= TILE and abs(x - (TILE + TILE // 2) + 0.5) < LIP and abs(y - TILE // 2 + 0.5) < LIP
    # edge region: a lip band along its outer border
    return x < LIP or x >= W - LIP or y < TILE + LIP or y >= H - LIP


def block(index):
    rows = []
    for y in range(H):
        chars = []
        for x in range(W):
            if is_lip(x, y):
                chars.append("L" if (x + y + index) % 7 == 0 else "l")
            else:
                chars.append("G" if (x * 3 + y + index) % 13 == 0 else "g")
        rows.append("".join(chars))
    return rows


def build():
    frames = {}
    order = []
    for index in range(COUNT):
        name = f"b{index:02d}"
        frames[name] = block(index)
        order.append(name)
    return {
        "palette": {
            "g": "#3a7a32",
            "G": "#6aaa48",
            "l": "#c2a15a",
            "L": "#9a7a3a",
        },
        "frames": frames,
        "sheet": {"columns": COLUMNS, "order": order},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
