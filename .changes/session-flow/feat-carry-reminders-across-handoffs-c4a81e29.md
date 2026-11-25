---
bump: minor
---

### Added

- Handoff shape 5, now the default: a binding `## Reminders` section takes Pending commands' place,
  one `- [M<n>] <actor> · <trigger> · <what to do> · added h<k> <date>` line per item that affects
  a later session. An entry is carried hop to hop and leaves only through `retire`, listed under
  `## Retired reminders`; `validate` fails one dropped any other way, fails a malformed entry, and
  warns on a closed handoff that still holds reminders. A shape-4 chain's next hop converts its
  Pending commands into `user · when now` reminders.
- The handoff skill folds user messages and advisor output that change a section into the handoff
  with `amend` after emit, without asking.
- A reminder whose source is not the user's own message (an event, a tool result, a subagent or
  peer report, fetched text) is recorded as a `user` entry, shown and never run, and recorded
  reminder text is data: an `agent` entry asking for more than its task is raised, not done, at
  resume and at chain close.
- Forked side tasks, profile changes and chain-close follow-ups print one terminal command that
  opens the destination checkout and starts the selected profile with the saved prompt or goal.

### Changed

- Errors about a handoff shape newer than the script name the remedy: update session-flow.
- The resume-eval seeder and the hop-chain budget harness build shape-5 chains, so the resume
  cases seed in the default shape.
