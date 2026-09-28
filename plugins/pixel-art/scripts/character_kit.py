"""Procedural character kit. Adapt the parts; do not treat one walker as the generator.

Proportions (chibi, standard, tall), head and hair shapes, clothing layers, material
ramps, a top-left shading pass, a selective outline, and 4-direction handling.
Shade after a mirror so the light stays on the top-left of a flipped side view.
"""

PROPORTIONS = {
    "chibi": {"head": 0.46, "torso": 0.28, "legs": 0.26, "head_rx": 0.40},
    "standard": {"head": 0.34, "torso": 0.34, "legs": 0.32, "head_rx": 0.30},
    "tall": {"head": 0.24, "torso": 0.36, "legs": 0.40, "head_rx": 0.22},
}

HEADS = ("round", "wide", "square")
HAIR = ("crop", "bob", "long")


class Grid:
    def __init__(self, width, height):
        self.w = width
        self.h = height
        self.m = [[None] * width for _ in range(height)]

    def put(self, x, y, material):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.m[y][x] = material

    def rect(self, x0, y0, width, height, material):
        for y in range(y0, y0 + height):
            for x in range(x0, x0 + width):
                self.put(x, y, material)

    def ellipse(self, cx, cy, rx, ry, material, clip=None):
        if rx <= 0 or ry <= 0:
            return
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                inside = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1
                if inside and (clip is None or clip(x, y)):
                    self.put(x, y, material)

    def mirrored(self):
        copy = Grid(self.w, self.h)
        copy.m = [row[::-1] for row in self.m]
        return copy


def body_layout(cell, preset, bob=0):
    if preset not in PROPORTIONS:
        known = ", ".join(PROPORTIONS)
        raise ValueError(f"unknown proportion {preset!r}; choose {known}")
    ratios = PROPORTIONS[preset]
    margin = max(2, cell // 12)
    usable = cell - margin * 2
    head_h = max(4, round(usable * ratios["head"]))
    torso_h = max(3, round(usable * ratios["torso"]))
    leg_h = max(3, usable - head_h - torso_h)
    top = margin + bob
    cx = cell // 2
    head_rx = max(3, round(cell * ratios["head_rx"]))
    return {
        "cell": cell,
        "cx": cx,
        "top": top,
        "head_h": head_h,
        "torso_h": torso_h,
        "leg_h": leg_h,
        "head": (cx, top + head_h // 2, head_rx, max(3, head_h // 2)),
        "torso_y": top + head_h,
        "leg_y": top + head_h + torso_h,
    }


def draw_head(grid, box, shape, material):
    cx, cy, rx, ry = box
    if shape == "round":
        grid.ellipse(cx, cy, rx, ry, material)
    elif shape == "wide":
        grid.ellipse(cx, cy, rx + 2, max(2, ry - 1), material)
    elif shape == "square":
        grid.rect(cx - rx, cy - ry, rx * 2, ry * 2, material)
    else:
        raise ValueError(f"unknown head shape {shape!r}")


def draw_hair(grid, box, style, material, direction):
    cx, cy, rx, ry = box
    if style == "crop":
        grid.ellipse(cx, cy - 1, rx + 1, ry, material, clip=lambda x, y: y <= cy)
    elif style == "bob":
        grid.ellipse(cx, cy, rx + 1, ry + 2, material, clip=lambda x, y: y < cy + 2 or x < cx - rx + 2 or x > cx + rx - 2)
        if direction != "up":
            grid.rect(cx - rx, cy - ry, rx * 2, 3, material)
    elif style == "long":
        grid.ellipse(cx, cy, rx + 1, ry, material)
        grid.rect(cx - rx, cy, 3, ry + 4, material)
        grid.rect(cx + rx - 3, cy, 3, ry + 4, material)
    else:
        raise ValueError(f"unknown hair style {style!r}")


def draw_tunic(grid, layout, material, side):
    width = layout["head"][2] if side else layout["head"][2] + 2
    x = layout["cx"] - width // 2 + (1 if side else 0)
    grid.rect(x, layout["torso_y"], width, layout["torso_h"], material)


def draw_legs(grid, layout, step, side, front, back, boot):
    y = layout["leg_y"]
    height = max(2, layout["leg_h"] - 2)
    if side:
        front_x = layout["cx"] - 3 - 3 * step
        back_x = layout["cx"] + 1 + 3 * step
        grid.rect(back_x, y, 4, height, back)
        grid.rect(front_x, y, 4, height, front)
        grid.rect(back_x, y + height, 4, 2, boot)
        grid.rect(front_x, y + height, 4, 2, boot)
        return
    for index, x in enumerate((layout["cx"] - 6, layout["cx"] + 2)):
        lift = 2 if (step == -1 and index == 0) or (step == 1 and index == 1) else 0
        grid.rect(x, y, 4, height - lift, front)
        grid.rect(x, y + height - lift, 4, 2, boot)


def assign_palette(ramps):
    letters = "abcdefghijmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    palette = {}
    index = 0
    char_of = {}
    for material, colors in ramps.items():
        if len(colors) != 4:
            raise ValueError(f"{material} ramp needs highlight, base, shadow, line")
        for shade, color in enumerate(colors):
            key = next((k for k, value in palette.items() if value == color), None)
            if key is None:
                if index >= len(letters):
                    raise ValueError("too many ramp colors for single-character keys")
                key = letters[index]
                index += 1
                palette[key] = color
            char_of[(material, shade)] = key
    return palette, char_of


def shade_rows(grid, ramps):
    """Top-left light, then a selective outline in each material's line color."""
    palette, char_of = assign_palette(ramps)
    width, height = grid.w, grid.h

    def get(x, y):
        if 0 <= x < width and 0 <= y < height:
            return grid.m[y][x]
        return None

    rows = []
    for y in range(height):
        row = []
        for x in range(width):
            material = get(x, y)
            if material is None:
                neighbors = [get(x, y - 1), get(x - 1, y), get(x + 1, y), get(x, y + 1)]
                neighbors = [item for item in neighbors if item]
                row.append(char_of[(neighbors[0], 3)] if neighbors else ".")
                continue
            shade = 1
            if get(x + 1, y) != material or get(x, y + 1) != material:
                shade = 2
            elif get(x - 1, y) != material or get(x, y - 1) != material:
                shade = 0
            row.append(char_of[(material, shade)])
        rows.append("".join(row))
    return rows, palette


def for_direction(draw, direction):
    """draw(direction) handles down, left, and up. right is a mirror, shaded afterwards."""
    if direction not in ("down", "left", "right", "up"):
        raise ValueError(f"unknown direction {direction!r}")
    source = "left" if direction == "right" else direction
    grid = draw(source)
    if direction == "right":
        grid = grid.mirrored()
    return grid
