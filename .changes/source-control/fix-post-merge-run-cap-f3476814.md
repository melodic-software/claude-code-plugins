---
bump: patch
---

### Fixed

- `babysit_postmerge.py` reads a workflow-run listing past GitHub's 1,000-run search cap in halves of its `created` range, so a post-merge floor more than about a week old no longer makes every check unreadable. A range of a day or less still at the cap stays unreadable.
- The unattended merge gate runs the post-merge check at most once per main head in a pr-merge run: once a check at that head, floor, identity and lane comes back unreadable, including the merge job's own check, each later candidate is refused with the same reason without running it again. An unreadable answer still never passes.
