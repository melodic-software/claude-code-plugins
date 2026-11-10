---
bump: minor
---

### Removed

- `merge.verify-cache` and the verifier-answers cache behind it. enable-auto-merge reads each pull request's verifier verdict in full, as it did under `shadow`, without the key probe each read paid first, and logs no `verify-cache` line; cost lines no longer carry `cached=`. The `pr-merge-verify-answers` artifact now carries only the arm step's skip records (`eam-skip.json`), and every scheduled or hand-started reader run keeps one, empty when it keeps no records, so the next run never skips on an older run's records.
