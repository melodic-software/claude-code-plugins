# -*- coding: utf-8 -*-
"""Shared stdout/stderr UTF-8 reconfiguration for the session-flow scripts.

The entry-point scripts that call it do so before printing, so non-ASCII output
such as the U+2500 rails survives a cp1252 pipe on Windows. Stdlib only;
Python 3.10+.
"""

from __future__ import annotations

import io
import sys


def utf8_streams() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", newline="\n")
