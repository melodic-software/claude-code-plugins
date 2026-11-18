---
bump: patch
---

### Fixed

- **`reference/evidence.md`, the leak scan.** Step 5 states the text normalization and the
  credential pattern itself instead of sending the reader to `/app-control:drive`, whose files a
  session without that plugin cannot read. Step 4 says to read the comment template with the Read
  tool.
- **The four `pull-request-evidence-*` eval cases.** Each prompt names the pull-request skill, and
  the fixture's `gh` answers `repo set-default --view`. The content graders read the posted
  comment, so a body written another way is judged on what it holds, and a new
  `body-written-with-write` grader checks that the body file was written with the Write tool, as
  step 4 says.
