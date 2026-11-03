"""Report which channels let this process read the value probe.py planted for its case.

Compares sha256 hashes of two channels with the hash beside this file: its own
/proc/self/environ, and the /proc/<pid>/environ of every other process it can read,
ancestors included. Prints one fixed marker naming both results. Exit 1 when neither
channel finds the value, 0 otherwise. Failing to read its own environ, as with an
empty /proc, is a crash with no marker, which the case reads as inconclusive: it
would make "not found" mean nothing.
"""

import hashlib
import os
import sys
from pathlib import Path

want = (
    Path(__file__).with_name(".probe-plant-sha256").read_text(encoding="utf-8").strip()
)


def holds(environ: bytes) -> bool:
    return any(
        hashlib.sha256(item.partition(b"=")[2]).hexdigest() == want
        for item in environ.split(b"\0")
    )


def other_holds(entry: Path) -> bool:
    try:
        return holds((entry / "environ").read_bytes())
    except OSError:
        return False


own = holds(Path("/proc/self/environ").read_bytes())
me = os.readlink("/proc/self")
others = any(
    other_holds(entry)
    for entry in Path("/proc").iterdir()
    if entry.name.isdigit() and entry.name != me
)


labels = {True: "found", False: "not-found"}
print(f"planted-value own={labels[own]} others={labels[others]}")
sys.exit(0 if own or others else 1)
