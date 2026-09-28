"""Drawings that land the woodcut-ink residuals in band.

straight_border is measured in inkstats (a ring side whose inner edge touches
subject ink is left out). These two drawings are the caption and boil rules
the check was missing: a few short enclosed slits, and a frame that is recut
by 2 px on about a third of its length and by 1 px on the rest.
"""

import numpy as np

H, W = 400, 600
BH, BW = 240, 360
PAPER = 230
INK = 8


def _rgb(ink):
    rgb = np.full((*ink.shape, 3), PAPER, np.uint8)
    rgb[ink] = INK
    return rgb


def caption(holes):
    """Ink field, a paper caption panel, and enclosed paper holes in the letter."""
    ink = np.ones((H, W), bool)
    ink[30:90, 40:220] = False
    ink[42:78, 55:200] = True
    for y0, y1, x0, x1 in holes:
        ink[y0:y1, x0:x1] = False
    return _rgb(ink)


def caption_short_slits():
    """A few short counters. sliver_caption sits in the woodcut band."""
    return caption((
        (50, 70, 70, 78),
        (50, 70, 100, 108),
        (50, 70, 130, 138),
        (50, 70, 160, 168),
    ))


def caption_thin_strip():
    """Long thin counters. sliver_caption sits above the band."""
    return caption((
        (48, 72, 70, 74),
        (48, 72, 100, 104),
        (48, 72, 130, 134),
    ))


def boil_pair(frac=0.35):
    """Two frame drawings. `frac` of each side is recut by 2 px, the rest by 1 px.

    frac 0.35 lands in the woodcut boil band. 0 is the 1 px recut (below the
    band) and 1 is a 2 px recut of the whole frame (above it).
    """
    a = np.zeros((BH, BW), bool)
    a[2:4, 15:BW - 15] = True
    a[BH - 4:BH - 2, 15:BW - 15] = True
    a[15:BH - 15, 2:4] = True
    a[15:BH - 15, BW - 4:BW - 2] = True
    b = np.zeros_like(a)
    b[3:5, 15:BW - 15] = True
    b[BH - 3:BH - 1, 15:BW - 15] = True
    b[15:BH - 15, 3:5] = True
    b[15:BH - 15, BW - 3:BW - 1] = True
    cut = int(frac * (BW - 30))
    b[3:5, 15:15 + cut] = False
    b[4:6, 15:15 + cut] = True
    b[BH - 3:BH - 1, 15:15 + cut] = False
    b[BH - 2:BH, 15:15 + cut] = True
    cuty = int(frac * (BH - 30))
    b[15:15 + cuty, 3:5] = False
    b[15:15 + cuty, 4:6] = True
    b[15:15 + cuty, BW - 3:BW - 1] = False
    b[15:15 + cuty, BW - 2:BW] = True
    return _rgb(a), _rgb(b)
