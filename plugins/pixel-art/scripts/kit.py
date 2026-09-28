#!/usr/bin/env python3
"""Procedural character kit for humanoid walkers.

Presets (chibi, standard, tall), head and hair shapes, clothing layers, material
ramps, a top-left shading pass, and a selective outline. Direction handling draws
down, left, and up, then mirrors left for right before shading so the light stays
put. Adapt it: pass ramps, a preset, shapes, and extra(canvas, layout, direction, step)
for props. It is a library, not a fixed character.
"""
import json

PRESETS = {
    # fractions of the frame. head_cy is the head center; the rest are boxes.
    "chibi": {
        "head_rx": 0.30, "head_ry": 0.26, "head_cy": 0.30,
        "torso": (0.30, 0.52, 0.40, 0.16),
        "legs": (0.34, 0.68, 0.14, 0.16),
        "boots": 0.08,
    },
    "standard": {
        "head_rx": 0.22, "head_ry": 0.20, "head_cy": 0.32,
        "torso": (0.32, 0.50, 0.36, 0.20),
        "legs": (0.36, 0.70, 0.12, 0.16),
        "boots": 0.08,
    },
    "tall": {
        "head_rx": 0.15, "head_ry": 0.14, "head_cy": 0.20,
        "torso": (0.34, 0.36, 0.32, 0.24),
        "legs": (0.38, 0.60, 0.11, 0.26),
        "boots": 0.08,
    },
}

HEADS = ("round", "oval", "square")
HAIRS = ("bangs", "swept", "short", "bald")

DEFAULT_RAMPS = {
    "skin": ["#ffe0c0", "#f4b88c", "#d08860", "#7a3c2c"],
    "hair": ["#e08850", "#b85a30", "#84381c", "#3c1810"],
    "tunic": ["#6ca0e8", "#3c6cc8", "#28449a", "#141e50"],
    "sleeve": ["#6ca0e8", "#3c6cc8", "#28449a", "#141e50"],
    "pants": ["#8c7058", "#6a5040", "#4a3428", "#221612"],
    "pants_back": ["#6a5040", "#4a3428", "#342418", "#221612"],
    "boot": ["#6a4a34", "#4c3222", "#342016", "#140a06"],
    "belt": ["#f0d070", "#c8a040", "#8c6a24", "#3c2a0c"],
    "cape": ["#e05050", "#b02c3c", "#781c30", "#3a0c1c"],
    "eye": ["#20202c", "#20202c", "#20202c", "#20202c"],
    "white": ["#ffffff", "#ffffff", "#ffffff", "#ffffff"],
}
FLAT = {"eye", "white"}


def _px(size, frac):
    return max(1, int(round(size * frac)))


class Canvas:
    def __init__(self, size):
        self.size = size
        self.m = [[None] * size for _ in range(size)]

    def put(self, x, y, mat):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.m[y][x] = mat

    def rect(self, x0, y0, w, h, mat):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.put(x, y, mat)

    def ellipse(self, cx, cy, rx, ry, mat, clip=None):
        rx = max(rx, 0.5)
        ry = max(ry, 0.5)
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1 and (clip is None or clip(x, y)):
                    self.put(x, y, mat)

    def mirrored(self):
        other = Canvas(self.size)
        other.m = [row[::-1] for row in self.m]
        return other

    def shade(self, char_of):
        """Top-left light, then a selective outline in the neighbor material's line color."""
        size = self.size
        m = self.m

        def get(x, y):
            return m[y][x] if 0 <= x < size and 0 <= y < size else None

        out = [["."] * size for _ in range(size)]
        for y in range(size):
            for x in range(size):
                mat = m[y][x]
                if mat is None:
                    neighbors = [get(x + dx, y + dy) for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1))]
                    neighbors = [n for n in neighbors if n]
                    if neighbors:
                        out[y][x] = char_of[(neighbors[0], 3)]
                    continue
                if mat in FLAT:
                    out[y][x] = char_of[(mat, 1)]
                    continue
                if get(x + 1, y) != mat or get(x, y + 1) != mat or get(x + 1, y + 1) != mat:
                    shade = 2
                elif get(x - 1, y) != mat or get(x, y - 1) != mat:
                    shade = 0
                else:
                    shade = 1
                out[y][x] = char_of[(mat, shade)]
        return ["".join(row) for row in out]


def layout(size, preset, step):
    """Pixel boxes for one frame. step is -1, 0, or 1."""
    p = PRESETS[preset]
    bob = 0 if step == 0 else max(1, size // 48)
    torso = (
        _px(size, p["torso"][0]),
        _px(size, p["torso"][1]) + bob,
        _px(size, p["torso"][2]),
        _px(size, p["torso"][3]),
    )
    leg_w = _px(size, p["legs"][2])
    legs = (
        _px(size, p["legs"][0]),
        _px(size, p["legs"][1]) + bob,
        leg_w,
        _px(size, p["legs"][3]),
    )
    return {
        "bob": bob,
        "cx": size // 2,
        "head": (size // 2, _px(size, p["head_cy"]) + bob, size * p["head_rx"], size * p["head_ry"]),
        "torso": torso,
        "legs": legs,
        "gap": max(1, size // 24),
        "boot_h": _px(size, p["boots"]),
        "arm": max(2, size // 12),
    }


def _head(canvas, box, shape):
    cx, cy, rx, ry = box
    if shape == "square":
        canvas.rect(int(cx - rx), int(cy - ry), int(2 * rx), int(2 * ry), "skin")
    elif shape == "oval":
        canvas.ellipse(cx, cy, rx * 0.82, ry, "skin")
    elif shape == "round":
        canvas.ellipse(cx, cy, rx, ry, "skin")
    else:
        raise ValueError(f"unknown head shape {shape!r}")


def _hair(canvas, box, style, direction):
    if style == "bald":
        return
    cx, cy, rx, ry = box
    top = cy - ry
    if style == "short":
        canvas.ellipse(cx, cy - ry * 0.15, rx * 0.95, ry * 0.72, "hair", clip=lambda x, y: y < cy)
        return
    if style == "swept":
        canvas.ellipse(cx + rx * 0.15, cy - ry * 0.1, rx, ry * 0.85, "hair", clip=lambda x, y: y < cy + 1 or x > cx)
        return
    # bangs
    canvas.ellipse(cx, cy - ry * 0.05, rx * 1.05, ry * 0.8, "hair",
                   clip=lambda x, y: y < cy or x < cx - rx * 0.6 or x > cx + rx * 0.6)
    if direction == "down":
        canvas.rect(int(cx - rx), int(top + ry * 0.35), int(2 * rx), max(2, int(ry * 0.25)), "hair")


def _body(canvas, lay, direction, step):
    side = direction == "left"
    tx, ty, tw, th = lay["torso"]
    lx, ly, lw, lh = lay["legs"]
    if direction == "up":
        canvas.rect(tx, ty, tw, th + lh // 2, "cape")
    if side:
        canvas.rect(tx + tw // 2, ty, max(2, tw // 4), th, "cape")
    gap = lay["gap"]
    if side:
        back = lx + step * gap
        front = lx - step * gap
        for x, mat in ((back, "pants_back"), (front, "pants")):
            canvas.rect(x, ly, lw, lh - lay["bob"], mat)
            canvas.rect(x, ly + lh - lay["bob"], lw + 1, lay["boot_h"], "boot")
    else:
        for i, x in enumerate((lx, lx + lw + gap)):
            lift = gap if ((step == -1 and i == 0) or (step == 1 and i == 1)) else 0
            canvas.rect(x, ly, lw, lh - lift, "pants")
            canvas.rect(x, ly + lh - lift, lw, lay["boot_h"], "boot")
    body_w = tw // 2 + 2 if side else tw
    canvas.rect(tx if not side else tx + tw // 4, ty, body_w, th, "tunic")
    canvas.rect(tx if not side else tx + tw // 4, ty + th - max(2, th // 5), body_w, max(2, th // 5), "belt")
    arm = lay["arm"]
    if side:
        ax = tx + tw // 3 + step
        canvas.rect(ax, ty + 1, arm, th // 2 + 2, "sleeve")
        canvas.rect(ax, ty + th // 2 + 2, arm, max(2, arm // 2), "skin")
    else:
        for i, ax in enumerate((tx - arm, tx + tw)):
            swing = step * (1 if i == 0 else -1)
            canvas.rect(ax, ty + max(0, swing), arm, th // 2 + 2, "sleeve")
            canvas.rect(ax, ty + th // 2 + 1 + max(0, swing), arm, max(2, arm // 2), "skin")


def _face(canvas, box, direction):
    cx, cy, rx, ry = box
    eye_w = max(1, int(rx * 0.18))
    eye_h = max(2, int(ry * 0.28))
    if direction == "down":
        for x in (int(cx - rx * 0.45), int(cx + rx * 0.2)):
            canvas.rect(x, int(cy - eye_h // 2), eye_w, eye_h, "eye")
            canvas.put(x, int(cy - eye_h // 2), "white")
    elif direction == "left":
        canvas.rect(int(cx - rx * 0.7), int(cy - eye_h // 2), eye_w, eye_h, "eye")
        canvas.put(int(cx - rx * 0.7), int(cy - eye_h // 2), "white")
        canvas.put(int(cx - rx), int(cy), "skin")


class Walker:
    def __init__(self, size=48, preset="standard", ramps=None, hair="bangs", head="round", extra=None):
        if preset not in PRESETS:
            raise ValueError(f"unknown preset {preset!r}")
        if hair not in HAIRS:
            raise ValueError(f"unknown hair {hair!r}")
        if head not in HEADS:
            raise ValueError(f"unknown head {head!r}")
        if size < 16:
            raise ValueError("size must be at least 16")
        self.size = size
        self.preset = preset
        self.ramps = dict(DEFAULT_RAMPS if ramps is None else ramps)
        self.hair = hair
        self.head = head
        self.extra = extra

    def materials(self, direction, step):
        """Material grid for one pose. direction is down, left, up, or right."""
        src = "left" if direction == "right" else direction
        lay = layout(self.size, self.preset, step)
        canvas = Canvas(self.size)
        _body(canvas, lay, src, step)
        if self.extra:
            self.extra(canvas, lay, src, step)
        _head(canvas, lay["head"], self.head)
        if src != "up":
            _face(canvas, lay["head"], src)
        if src == "up" and self.hair != "bald":
            cx, cy, rx, ry = lay["head"]
            canvas.ellipse(cx, cy, rx * 1.05, ry, "hair")
        else:
            _hair(canvas, lay["head"], self.hair, src)
        if direction == "right":
            canvas = canvas.mirrored()
        return canvas

    def _chars(self):
        palette, char_of = {}, {}
        letters = iter("abcdefghijmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        for mat, ramp in self.ramps.items():
            for index, color in enumerate(ramp):
                if color not in palette.values():
                    key = next(letters, None)
                    if key is None:
                        raise ValueError("ramps use more distinct colors than the spec has palette keys")
                    palette[key] = color
                char_of[(mat, index)] = next(key for key, value in palette.items() if value == color)
        return palette, char_of

    def spec(self):
        palette, char_of = self._chars()
        frames, order = {}, []
        for direction in ("down", "left", "right", "up"):
            for pattern, step in enumerate((-1, 0, 1)):
                name = f"{direction}{pattern}"
                try:
                    frames[name] = self.materials(direction, step).shade(char_of)
                except KeyError as exc:
                    raise ValueError(f"material {exc.args[0][0]!r} has no ramp; add it to ramps") from exc
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


def dump(spec, path):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(spec, fh)
    return path
