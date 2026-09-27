"""Procedural RPG Maker MZ '$' single-character sheet: 3 patterns x 4 directions (down, left, right, up), 48x48.

Writes hero_mz.json beside this file; render it with scripts/render.py, and build scene.html with
scripts/embed.py. Pattern shown: materials with color ramps, one draw(direction, step) function,
a shading pass lit from the top-left, and a selective outline taken from each material's line color.
"""
import json
import pathlib

W = H = 48
# material -> [highlight, base, shadow, line]
RAMPS = {
    "skin": ["#ffe0c0", "#f4b88c", "#d08860", "#7a3c2c"],
    "ear": ["#f4b88c", "#f4b88c", "#d08860", "#7a3c2c"],
    "hair": ["#e08850", "#b85a30", "#84381c", "#3c1810"],
    "tunic": ["#6ca0e8", "#3c6cc8", "#28449a", "#141e50"],
    "cape": ["#e05050", "#b02c3c", "#781c30", "#3a0c1c"],
    "sleeve": ["#6ca0e8", "#3c6cc8", "#28449a", "#141e50"],
    "pants": ["#8c7058", "#6a5040", "#4a3428", "#221612"],
    "pants_back": ["#6a5040", "#4a3428", "#342418", "#221612"],
    "boot": ["#6a4a34", "#4c3222", "#342016", "#140a06"],
    "belt": ["#f0d070", "#c8a040", "#8c6a24", "#3c2a0c"],
    "eye": ["#20202c", "#20202c", "#20202c", "#20202c"],
    "white": ["#ffffff", "#ffffff", "#ffffff", "#ffffff"],
}
MATS = list(RAMPS)


class Canvas:
    def __init__(self):
        self.m = [[None] * W for _ in range(H)]

    def put(self, x, y, mat):
        if 0 <= x < W and 0 <= y < H:
            self.m[y][x] = mat

    def rect(self, x0, y0, w, h, mat):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.put(x, y, mat)

    def ellipse(self, cx, cy, rx, ry, mat, clip=None):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1 and (clip is None or clip(x, y)):
                    self.put(x, y, mat)

    def mirrored(self):
        c = Canvas()
        c.m = [row[::-1] for row in self.m]
        return c

    def to_rows(self, char_of):
        """Shade (light from top-left), then sel-out outline from the neighboring material's line color."""
        m = self.m

        def get(x, y):
            return m[y][x] if 0 <= x < W and 0 <= y < H else None

        out = [["."] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                mat = m[y][x]
                if mat is None:
                    nb = [get(x + dx, y + dy) for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1))]
                    nb = [n for n in nb if n]
                    if nb:
                        # bottom-heavy: prefer the material above (we are below it) for its line color
                        out[y][x] = char_of[(nb[0], 3)]
                    continue
                if mat in ("eye", "white"):
                    out[y][x] = char_of[(mat, 1)]
                    continue
                shade = 1
                if get(x + 1, y) != mat or get(x, y + 1) != mat or get(x + 1, y + 1) != mat:
                    shade = 2
                elif get(x - 1, y) != mat or get(x, y - 1) != mat:
                    shade = 0
                out[y][x] = char_of[(mat, shade)]
        return ["".join(r) for r in out]


def draw(direction, step):
    """direction: down/left/up; step: -1, 0, 1 (MZ patterns 0, 1, 2)."""
    c = Canvas()
    bob = 0 if step == 0 else 1
    top = 6 + bob
    side = direction == "left"
    # cape behind body (visible from back and side)
    if direction == "up":
        c.rect(15, top + 21, 18, 13, "cape")
    if side:
        c.rect(24, top + 21, 7, 12 - abs(step), "cape")
    # legs
    if side:
        fx, bx = 21 - 4 * step, 21 + 4 * step
        for lx, mat in ((bx, "pants_back"), (fx, "pants")):
            c.rect(lx, top + 31, 5, 7 - bob, mat)
            c.rect(lx - 1, top + 38 - bob, 6, 2, "boot")
    else:
        for i, lx in enumerate((18, 25)):
            lift = (step == -1 and i == 0) or (step == 1 and i == 1)
            c.rect(lx, top + 31, 5, 6 - 2 * lift, "pants")
            c.rect(lx, top + 37 - 2 * lift - bob, 5, 3, "boot")
    # torso
    tx = 18 if side else 16
    c.rect(tx, top + 21, 12 if side else 16, 11, "tunic")
    c.rect(tx, top + 28, 12 if side else 16, 2, "belt")
    # arms
    if side:
        ax = 22 + 2 * step
        c.rect(ax, top + 22, 4, 8, "sleeve")
        c.rect(ax, top + 30, 4, 2, "skin")
    else:
        for i, ax in enumerate((12, 32)):
            swing = step * (1 if i == 0 else -1)
            c.rect(ax, top + 22 + max(0, swing), 4, 7, "sleeve")
            c.rect(ax, top + 29 + max(0, swing), 4, 2, "skin")
    # head
    c.ellipse(24, top + 11, 11.5, 11, "skin")
    if direction == "down":
        c.ellipse(24, top + 8, 12.5, 9, "hair", clip=lambda x, y: y < top + 8 or x < 15 or x > 32)
        c.rect(15, top + 7, 18, 3, "hair")  # bangs
        for x in (19, 28):
            c.rect(x, top + 12, 2, 4, "eye")
            c.put(x, top + 12, "white")
    elif direction == "up":
        c.ellipse(24, top + 10, 12.5, 11.5, "hair")
    else:
        c.ellipse(26, top + 9, 11.5, 10, "hair", clip=lambda x, y: y < top + 8 or x > 25)
        c.rect(14, top + 6, 11, 3, "hair")
        c.put(12, top + 15, "skin")  # nose
        c.ellipse(25, top + 13, 1.6, 2.5, "ear")
        c.rect(15, top + 12, 2, 4, "eye")
        c.put(15, top + 12, "white")
    return c


def build():
    palette, char_of = {}, {}
    letters = iter("abcdefghijmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    for mat in MATS:
        for i, color in enumerate(RAMPS[mat]):
            if color not in palette.values():
                palette[next(letters)] = color
            char_of[(mat, i)] = next(k for k, v in palette.items() if v == color)
    frames, order = {}, []
    for direction in ("down", "left", "right", "up"):
        for pattern, step in enumerate((-1, 0, 1)):
            src = "left" if direction == "right" else direction
            canvas = draw(src, step)
            if direction == "right":
                canvas = canvas.mirrored()
            name = f"{direction}{pattern}"
            frames[name] = canvas.to_rows(char_of)
            order.append(name)
    anims = {f"walk_{d}": {"frames": [f"{d}0", f"{d}1", f"{d}2", f"{d}1"], "durations_ms": [150] * 4}
             for d in ("down", "left", "right", "up")}
    return {"palette": palette, "frames": frames, "animations": anims, "sheet": {"columns": 3, "order": order}}


if __name__ == "__main__":
    out = pathlib.Path(__file__).with_name("hero_mz.json")
    out.write_text(json.dumps(build()))
    print(out)
