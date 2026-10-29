"""Geometry of produce.py's click ring, standard library only so the tests exercise it where numpy, Pillow and
ffmpeg are absent.

The ring is drawn as a rounded band: an accent stroke on the line `gap` px outside the clicked box, and a white
halo HALO strokes wide that starts half a stroke outside that line and reaches inward. The band's inner edge is
therefore (HALO - 0.5) strokes inside the line, and the gap keeps CLEAR px more so the halo stays off the box.
"""
from collections import namedtuple

HALO = 1.8              # halo width, in strokes
CLEAR = 1.0             # output px kept between the halo and the box, for resampling bleed
SMALL_TARGET = 120      # page px at zoom 1.0: a box whose longer side is below this is small
SMALL_SCALE = 2.5       # gap and stroke multiplier for a small box at zoom 1.0
SMALL_ZOOM_END = 1.1    # the smallest zoomed shot; the multiplier eases to 1 between zoom 1.0 and this

Ring = namedtuple('Ring', 'stroke gaps line outer bbox')


def small_scale(box, z):
    """Gap and stroke multiplier: SMALL_SCALE for a small box in an unzoomed shot, 1 from SMALL_ZOOM_END up."""
    if max(box[2], box[3]) / z >= SMALL_TARGET:
        return 1.0
    k = min(max((SMALL_ZOOM_END - z) / (SMALL_ZOOM_END - 1.0), 0.0), 1.0)
    return 1.0 + (SMALL_SCALE - 1.0) * k


def ring(box, grow, z, W, H):
    """The ring around `box` (x, y, w, h in output px) at eased growth `grow` (0 to 1) and zoom `z`, in a W x H
    frame, or None when none of it is on screen.

    stroke: accent width. gaps: (left, top, right, bottom) from the box to the accent line. Each side shrinks
    only to keep its own band inside the frame, and never below the gap that keeps the halo off the box; past
    that the side crosses the frame edge and is clipped. line: the accent line's rectangle (x0, y0, x1, y1).
    outer: the band's bounds clipped to the frame. bbox: the band's unclipped bounds, for the render log.
    """
    k = small_scale(box, z)
    stroke = 3.0 * z * k
    gap = (3 + 9 * grow) * z * k
    floor = (HALO - 0.5) * stroke + CLEAR
    x, y, w, h = box
    dist = (x, y, W - x - w, H - y - h)
    gaps = tuple(max(min(gap, d - stroke - 1), floor) for d in dist)
    line = (x - gaps[0], y - gaps[1], x + w + gaps[2], y + h + gaps[3])
    outer = (max(line[0] - stroke, 1), max(line[1] - stroke, 1), min(line[2] + stroke, W - 1), min(line[3] + stroke, H - 1))
    if int(outer[2] - outer[0]) <= 0 or int(outer[3] - outer[1]) <= 0:
        return None
    bbox = [round(line[0] - stroke, 1), round(line[1] - stroke, 1), round(line[2] + stroke, 1), round(line[3] + stroke, 1)]
    return Ring(stroke, gaps, line, outer, bbox)
