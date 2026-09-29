"""Turn model-generated pixels into a palette-locked spec frame.

Nearest-neighbor downscale (center of each integer source cell when the
source size divides the target), then the same snap `render.py --snap` uses.
"""
import palette as palette_mod


def cell_downscale(rows, target_w, target_h):
    """One output pixel per target cell. Integer scales sample the cell center."""
    if target_w < 1 or target_h < 1:
        raise ValueError("target frame size must be at least 1x1")
    src_h = len(rows)
    src_w = len(rows[0]) if rows else 0
    if src_w < 1 or src_h < 1:
        raise ValueError("source image is empty")
    if src_w % target_w == 0 and src_h % target_h == 0:
        step_x = src_w // target_w
        step_y = src_h // target_h
        sample_x = step_x // 2
        sample_y = step_y // 2
        return [
            [rows[y * step_y + sample_y][x * step_x + sample_x] for x in range(target_w)]
            for y in range(target_h)
        ]
    return [
        [rows[min(src_h - 1, int((y + 0.5) * src_h / target_h))][min(src_w - 1, int((x + 0.5) * src_w / target_w))]
         for x in range(target_w)]
        for y in range(target_h)
    ]


def frame_from_rgba(rows, palette, target_w, target_h, dither=False):
    """Downscale, snap, and return one spec frame (rows of palette keys)."""
    scaled = cell_downscale(rows, target_w, target_h)
    return palette_mod.snap_frame_rows(scaled, palette, dither)


def palette_violations(rows, palette):
    """Pixels that are neither a palette color nor fully transparent."""
    allowed = {palette_mod.hex_rgb(color) + (255,) for color in palette.values()}
    allowed.add((0, 0, 0, 0))
    bad = 0
    for row in rows:
        for pixel in row:
            if pixel[3] not in (0, 255) or (pixel[3] == 255 and pixel not in allowed):
                bad += 1
            elif pixel[3] == 0 and pixel != (0, 0, 0, 0):
                bad += 1
    return bad
