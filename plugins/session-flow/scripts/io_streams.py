# -*- coding: utf-8 -*-
"""Shared stdout/stderr UTF-8 reconfiguration for the session-flow scripts.

`save_point.py` and `harness/hop_chain.py` both print the U+2500 rails, and
both reconfigure their streams so those bytes survive a cp1252 pipe on Windows.
The harness drives `save_point.py` only as a subprocess and neither imports the
other, so the one helper they share lives here. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import io
import sys


def utf8_streams() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", newline="\n")
