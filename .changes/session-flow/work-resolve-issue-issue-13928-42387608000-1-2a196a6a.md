---
bump: patch
---

### Fixed

- A shape-3 handoff's Original goal no longer grows without bound. It keeps the newest five dated amendments (`- **Amended (verbatim, <YYYY-MM-DD>):** "<quote>"` bullets) verbatim. `save_point.py new` moves each older one, verbatim, to the new hop file under `## Earlier amendments` and leaves one `- **Earlier amendments:**` pointer bullet; the pointers chain back through the hop files. `validate` fails a hot file whose moved amendments are missing from that section (#13928).
