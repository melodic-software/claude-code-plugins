---
bump: minor
---

### Added

- The notes host page pins a note to a text selection (Note on selected text, T) or to a region
  the person drags or moves with the arrow keys (Mark a region, R), as well as to an element. A
  text note carries the selection as a quote with a little visible text either side; a region
  note carries its box and the test-id elements it crosses.
- Every note carries the view a reload loses: the data controls pressed since load (`data.log`)
  and the frame's viewport. Re-locating a note sets the viewport, replays the log, and adds a
  text-quote rung after the structural path; a text note whose quote is gone is not confirmed.
- When the notes server stops answering, the host page says so, keeps the notes written after
  that, and Copy all notes makes one `prototype-notes` block. `notes-bridge.sh import --file`
  takes a pasted block written to a file, checking every note against the note contract.
- `reference/data-controls.md`: Seed is deterministic, record *i* from index *i*, and each data
  control carries `data-data-control` so notes can log and replay it.
- Eval case `ed-notes-copyout-import`.
