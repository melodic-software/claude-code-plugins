---
bump: patch
---

### Fixed

- **A pre-existing red full run stops holding the post-merge report.** A red full run charged to no merge (red again on its re-run, failing only checks already failing before the merge) left the report's `unattributed` list only when the floor moved. It now stops counting once a full run passes after it on a newer commit of the default branch. A pass on the same commit leaves it counting, and a newly failing check is still a failure.
- **`babysit_verify_evidence.py settle --idle-tick --probe-unmoved`.** A report that would stand but for its unattributed runs, with nothing else moved since, is refused as `idle tick unattributed-unmoved`. Without the flag that refusal reads nothing, as before.
