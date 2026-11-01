---
bump: patch
---

### Fixed

- The README's verifier-verdict section states the pr-merge gate's one exception to a refusal standing on the run's saved listing: a candidate's `verify:missing` there reads the head's two pass names by exact name (`pr-verify-<pr>-<head>-pass` and `-pass-notes`), two requests and no listing, so a pass uploaded after that listing is seen in the same run. Its allow is judged again on a listing of the gate's own, and a failed read or no pass that counts leaves `verify:missing`.
