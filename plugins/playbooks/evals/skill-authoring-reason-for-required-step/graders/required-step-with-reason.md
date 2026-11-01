---
type: llm
arm: both
---
PASS only if the rewritten section (1) states running `npm run build:api-index` as a required step that comes before `scripts/publish.sh`, with no wording that leaves it optional (such as "if you like", "optionally", "consider"), and (2) gives, next to that step, the reason it is required: publish.sh uploads the current dist/api-index.json, so without the build a stale or previous index gets published. Any wording that carries that cause passes. FAIL if the step still reads as optional, if the reason is missing or is a generic one ("to be safe", "best practice"), if the reason sits only in a separate note away from the step, or if the build step is dropped.
