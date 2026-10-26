---
bump: minor
---

### Added

- **`repin.sh` re-pins several `interview-defenses.test.sh` digests in one call.** `tests/repin.sh [--test-file <path>] <pin-label>... <reason>` takes any number of labels before the one reason, resolves every label before it writes, and refuses the whole call, leaving the file unchanged, when any label matches no pin, more than one, or a pin an earlier label already named (exit 3) or names a pin whose digest already matches (exit 4). It prints one `<label>: <old> -> <new>` line per pin, reruns the suite once and ends `PASS` or `FAIL`. Pins that share a stale literal each take the digest from their own failure line.
