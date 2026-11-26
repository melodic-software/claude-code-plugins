---
bump: patch
---

### Fixed

- pr-verify records a judge step that run-claude-cli stopped on its credential scan (lane class `credential-stop`) as a withheld fail, for chunk 1, the later chunks and the whole-spec judge, so the head is held for a person. Before, run-claude-cli reported that stop as `other`, the chunk-1 guard never passed, and the head got no verdict. An empty class from an older run-claude-cli still counts as the stop; every other class is still no output.
