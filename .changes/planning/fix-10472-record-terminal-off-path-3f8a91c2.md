---
bump: patch
---

### Fixed

- **`round.sh record-terminal` refuses a decision on a superseded or archived question** ([#10472](https://github.com/melodic-software/claude-code-plugins/issues/10472)). On a superseded question it exits non-zero with `refused: <id> is superseded; answer <id> instead`, naming the end of the `supersededBy` chain as the page server's 409 does. On an archived question it exits with `refused: <id> is archived`. Before, the decision was written and then counted nowhere, because `status` and `export-ledger` read the question as withdrawn. The interview skill's surface contract documents the refusal beside the server's 409.
