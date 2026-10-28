---
bump: patch
---

### Fixed

- The address-feedback lane no longer stops on `feedback-untaken-threads` when the only unresolved threads are pr-verify fail notes from an older head. It clears its status instead, so ci-status can pass, pr-verify can run, and its pass resolves those notes. Before, the failing status kept pr-verify from ever running, so no pass could arrive to resolve the notes. The notes still hold the merge until they are resolved.
