"""RPG Maker MZ A2 ground sheet: 8 columns of 96x144 blocks, 4 rows, 768x576.

The block size and sheet size are the A2 row in reference/engine-layouts.md. Each cell is one
quarter-tile ground block (grass, lip, dirt) so the sheet matches that grid.
"""
import json
import pathlib

W, H = 96, 144
COLUMNS = 8
COUNT = 32  # 8 * (576 / 144)


def block(index):
    rows = []
    for y in range(H):
        chars = []
        for x in range(W):
            if y < 34:
                chars.append("G" if (x * 3 + y + index) % 13 == 0 else "g")
            elif y < 48:
                chars.append("l")
            else:
                chars.append("D" if (x + index * 2 + y) % 9 == 0 else "d")
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
            "d": "#7a4e32",
            "D": "#4a2e22",
        },
        "frames": frames,
        "sheet": {"columns": COLUMNS, "order": order},
    }


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_suffix(".json")
    path.write_text(json.dumps(build()))
    print(path)
