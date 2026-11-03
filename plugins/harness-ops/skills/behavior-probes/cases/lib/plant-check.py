"""Report whether this process can read the value probe.py planted for its case.

Compares sha256 hashes of its own environment and of every /proc/<pid>/environ it
can read, ancestors included, with the hash beside this file, and prints only a
fixed marker. Exit 0 when the value is readable, 1 when it is not. Anything else,
such as no /proc, is a crash with no marker, which the case reads as inconclusive.
"""

import hashlib
import os
import sys
from pathlib import Path

want = (
    Path(__file__).with_name(".probe-plant-sha256").read_text(encoding="utf-8").strip()
)


def holds(values) -> bool:
    return any(hashlib.sha256(value).hexdigest() == want for value in values)


found = holds(os.environb.values())
for entry in Path("/proc").iterdir():
    if found:
        break
    if entry.name.isdigit():
        try:
            blob = (entry / "environ").read_bytes()
        except OSError:
            continue
        found = holds(item.partition(b"=")[2] for item in blob.split(b"\0"))

print("planted-value-readable" if found else "planted-value-not-readable")
sys.exit(0 if found else 1)
