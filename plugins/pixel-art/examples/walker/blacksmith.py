"""A 4-direction walker built on scripts/kit.py: standard proportions, short hair, an apron.

Copy this folder and <plugin>/scripts/kit.py somewhere writable, side by side, then:

    python3 blacksmith.py
    python3 <plugin>/scripts/render.py blacksmith.json --out out --scale 4
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
# kit.py beside this file (a copied example) wins; in the plugin tree it lives in ../../scripts.
sys.path[:0] = [str(HERE), str(HERE.parent.parent / "scripts")]

import kit  # noqa: E402

RAMPS = dict(kit.DEFAULT_RAMPS)
RAMPS["apron"] = ["#d8d0c4", "#b0a494", "#887868", "#3c342c"]
RAMPS["hair"] = ["#6a6a72", "#4a4a52", "#2c2c34", "#141418"]


def apron(canvas, lay, direction, step):
    tx, ty, tw, th = lay["torso"]
    if direction == "left":
        canvas.rect(tx + tw // 4, ty + 2, max(3, tw // 3), th - 3, "apron")
    elif direction != "up":
        canvas.rect(tx + 1, ty + 2, tw - 2, th - 3, "apron")


def build():
    walker = kit.Walker(size=48, preset="standard", ramps=RAMPS, hair="short", head="round", extra=apron)
    return walker.spec()


if __name__ == "__main__":
    out = Path(__file__).with_name("blacksmith.json")
    kit.dump(build(), out)
    print(out)
