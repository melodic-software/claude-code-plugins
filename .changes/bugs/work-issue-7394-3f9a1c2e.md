---
bump: patch
---

### Security

- **`scan` and `write` frame scanned-repository and tracker text as untrusted data.** The hunter and gate dispatch contracts, the `scan` rung 1 and Step 6 dedupe, and the `write` survey carry the inline untrusted-content framing.
- **`scan` accepts the `Filed by /bugs:scan (lane: <name>)` provenance line only from the scanning identity or a repository writer.** The lane cursor and the Step 6 dedupe ignore an outsider's item, so the rotation falls through to the next rung and a finding files as a new item.
