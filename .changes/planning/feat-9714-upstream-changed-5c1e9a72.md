---
bump: minor
---

### Added

- **A changed or reopened interview answer reaches every direct dependent.** When a counted decision changes value (another decision, alternative key or answer text, or an accept of a revised recommendation) or is reopened, each direct dependent that holds a decision goes `stale` and each one without goes to the new `upstream-changed` state, with `changedBy` naming the changed questions. Re-answering a stale question with a different value marks its own dependents the same way, one hop per change; the automatic transitive cascade stays parked ([#9714](https://github.com/melodic-software/claude-code-plugins/issues/9714)).
- **An `upstream-changed` question waits on Claude.** Under `frontierLock` `confirm` or `hard` the page keeps its Save locked and marks it `Upstream changed, not handled yet` on its rail card and detail pane, and the server answers its decisions 409 `upstream-changed`; accept-all leaves it out in every mode. The new `reconfirm` op (`round.sh reconfirm <id> --why ...`) clears it when the question stands as asked, and a `revise` of the question clears it too. `round.sh status` lists each one on an `upstream changed:` line (`upstreamChanged` in `--json`).

### Changed

- Answering an interview question again with the same value no longer marks its decided dependents stale.
