---
bump: minor
---

### Added

- Intake splits an issue admission parked as Size Large into native sub-issues before any run takes it (owner Q93). The refine model returns only item numbers: the parts over the issue's task-list lines and the order between them. Each part becomes a sub-issue holding those lines as written, the order becomes native blocked-by edges, and intake triages each sub-issue. An invalid split leaves the issue parked, with the reason in the step summary.
- Admission and pr-verify count the body of such a sub-issue as the text of the listed human who filed its parent when every line in it is one of the parent's and nobody edited it, or when a listed human last edited it (ticking a task box is an edit). An edit by any other account makes it untrusted. Admission does not park or refuse such a sub-issue for Size Large, since it never splits again.
- Admission waits on an issue while any of its sub-issues is open, and work-unblock closes a split issue as completed once every sub-issue is closed by a listed human or a merge.
