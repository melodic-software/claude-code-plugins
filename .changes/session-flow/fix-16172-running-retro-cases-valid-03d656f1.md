---
bump: patch
---

### Fixed

- `/session-flow:running-retro`: the checkpoint confirms the session transcript with one read of
  the resolved file, the configuration-directory override applied, and never lists or globs for
  it; when that read fails it passes `transcript: unreadable` to the analysis subagent, which then
  does not look for the file, and the checkpoint still writes its ledger. A request to write a
  learning into `CLAUDE.md`, rules or memory is answered with the codify route and leaves those
  files untouched, and the memory root's self-ignore guard links its procedure, read with the
  Read or Grep tool. A skill-fit gap's owner comes from the transcript, the user's account or the
  session's skill listing, never from a filesystem search for a skill file.
- The `rr-skill-fit-names-owner` eval case loads an `implementation` stand-in, so the skill the
  user says they bypassed is in the skill listing, and its `names-skill-and-plugin` grader
  accepts the owner named in markdown (bold label, backticks, an Owner table column) while still
  failing a reply that says no owner was found.
