---
bump: minor
---

### Changed

- `/harness-config:audit-instructions` judges a `fable-5-2` target: I10 (reasoning written into the reply), I8-c (a line asking the model to think less) and I35 (settled-answers lines) now fire on it, each on the Fable 5.2 prompting guide. On that target I35 flags a long-chat surface that carries the line with no recorded test, asking for the test rather than removal, and I8-e no longer flags the guide's own one-line update every few tool calls where a person watches the work.
- Rows scoped only to Fable 5 and Fable 5.1 (I8-d, I23, the I8 delegation-throttle instance) and I37 stay inert on `fable-5-2`, each with the reason recorded. The `fable-5` and `fable-5-1` tokens stay, since Claude Code can still put a session on either model.
- `/harness-config:audit-prompting-postures` cites the Fable 5.2 guide: P6 points at its "Finish the whole task" section and P2 adds its code-ownership section. P12's model condition stays Sonnet 5.5 after a re-check against the Fable 5.2 guide.
