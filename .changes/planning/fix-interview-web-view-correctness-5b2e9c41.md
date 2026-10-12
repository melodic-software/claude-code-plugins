---
bump: patch
---

### Fixed

- `/planning:interview` page: arrow keys in the Decide list keep focus on the picked radio instead of dropping it to the page or moving it into the note box.
- `/planning:interview` page: once the interview is finished or the connection is lost, the choices, Save, Rephrase, Research and Send note are disabled and the dock says why; they come back on reconnect. A network failure on Save no longer shows the browser's raw error text.
- `/planning:interview` page: the focus ring on the View switcher is no longer clipped.
- `/planning:interview` page: a withheld question (its `recommendation` starts with `Withheld:`) shows no Rec, Accept with note or Hedged row, reads "Recommendation withheld", and is left out of Accept all.
- `/planning:interview` page: while no watcher has polled the server yet, as when the first wake waits on a permission prompt, the header says to approve any prompt in the terminal or type `next`, instead of only `type next`.
- `/planning:interview` page: text pasted while no text box has focus, as dictation tools insert it, goes into the current question's note box.
- `round.sh apply` removes the ops file after a successful write and does nothing when the file is absent, so re-running a wake no longer applies the same replies twice.
- `round.sh add`, `add-round`, `import-ledger`, `doctor`, `sync-ledger`, `export-brief` and `export-ledger` refuse a missing or malformed input file with a one-line message instead of a Python traceback.
- `surface/deferred.md` marks #5472 and #5473 built and #5474 dropped.
