#!/usr/bin/env python3
"""Drawings that land inside the frozen woodcut-ink bands the scene rounds missed.

The check is not retuned. These constructions are the measured answers to the two
authoring residuals: caption slits between a chunky cut and a cream strip, and a
frame stroke whose 4 px tail is large enough to boil inside the band.
"""
import cv2
import numpy as np

CREAM = (243, 234, 215)
INK = (20, 17, 14)


def _blank(h, w):
    img = np.empty((h, w, 3), np.uint8)
    img[:] = CREAM
    return img


def _ring(h, w, outer, thick):
    img = _blank(h, w)
    img[outer:outer + thick, :] = INK
    img[h - outer - thick:h - outer, :] = INK
    img[:, outer:outer + thick] = INK
    img[:, w - outer - thick:w - outer] = INK
    return img


def caption_panel(length=5, thick=2, n=4):
    """A top-quarter caption panel with n enclosed cream slits.

    length 5 and thick 2 (the default) is a few short slits: sliver_caption 2.5,
    inside the woodcut band 2.02-3.28. length 4 is the chunky cut at 2.0, below
    the band. length 8 is the cream strip at 4.0, above it.
    """
    img = _blank(300, 400)
    x, y, pw, ph = 30, 16, 120, 36
    cv2.rectangle(img, (x, y), (x + pw, y + ph), INK, 8)
    cv2.rectangle(img, (x + 16, y + 12), (x + pw - 16, y + ph - 10), INK, -1)
    for i in range(n):
        sx = x + 24 + i * 18
        sy = y + 16
        img[sy:sy + length, sx:sx + thick] = CREAM
    return img


def frame_pair(mode='tail'):
    """Two drawings of a 10 px frame stroke on an 800x1000 field.

    'one': the whole stroke moves 1 px. Boil is about 1.00, below the band
    (the scene rounds that redrew the frame by a pixel).
    'two': the whole stroke moves 2 px. Boil is about 2.00, above the band
    (re-cutting every facet).
    'tail': 14% of the stroke moves 4 px and the rest moves 1 px. Boil is
    about 1.41, inside 1.30-1.48. 8% of the same stroke at 4 px is still
    below the band; 16% sits on the top edge of it.
    """
    h, w, thick = 800, 1000, 10
    a = _ring(h, w, 2, thick)
    if mode == 'one':
        return a, _ring(h, w, 3, thick)
    if mode == 'two':
        return a, _ring(h, w, 4, thick)
    if mode != 'tail':
        raise ValueError(f'unknown frame mode {mode!r}')
    b = _ring(h, w, 3, thick)
    n = int(np.all(a == INK, axis=2).sum())
    cols = min(w, int(round(0.14 * n)) // thick)
    b[3:3 + thick, :] = CREAM
    b[6:6 + thick, :cols] = INK
    b[3:3 + thick, cols:] = INK
    return a, b
