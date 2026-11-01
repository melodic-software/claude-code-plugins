---
bump: patch
---

### Fixed

- The pr-merge gate's verdict read (`babysit_verify_evidence.py` `Reader.evidence`, provisional) no longer refuses `verify:missing` for a pass uploaded after the run's saved artifact listing was read. When that refusal still stands on the saved listing, the reader reads the head's two pass names by exact name (`pr-verify-<pr>-<head>-pass` and `-pass-notes`), two requests and no listing. A pass found there is judged with the saved listing in memory, and an allow stays provisional, so the gate judges it again on a listing of its own that must hold the live count. A failed read, a pass whose run does not count, or none found leaves `verify:missing`. Each find prints one `babysit-late-pass` line.
