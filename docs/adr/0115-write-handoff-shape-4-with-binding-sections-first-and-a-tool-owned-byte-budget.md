# Write handoff shape 4 with binding sections first and a tool-owned byte budget

- Status: accepted
- Date: 2026-11-21
- Supersedes: decision 3 of
  [ADR 0084](0084-ship-handoff-shape-3-on-measured-size-and-leave-accuracy-to-the-resume-eval.md)
  (shape 3 is the written shape) and, in part, decision 1 of
  [ADR 0091](0091-bound-the-handoff-core-by-relevance-and-amend-late-events.md) (size is the
  writer's judgment alone)
- Related: [#17677](https://github.com/melodic-software/claude-code-plugins/pull/17677) (the
  change), [#17838](https://github.com/melodic-software/claude-code-plugins/issues/17838) (its
  spec), [#17874](https://github.com/melodic-software/claude-code-plugins/issues/17874) (eval
  follow-up)

## Context

The owner wants a handoff to work as a lossless compaction: the next session gets what was just
done and what comes next, plus pointers to everything older (owner, 2026-11-18). Shape 3 put next
actions after history. Its size verdict was `UNVALIDATED`, so an oversized slot passed. And
`fill` printed nothing about the budget, so writers fit the file by hand and retried. Owner-reported
reads of handoff chains cost up to 250,000 tokens.

## Decision

1. **Shape 4 is a new stored shape.** Handoffs are written as `handoff_shape: 4` with their own
   section table. Shapes 2 and 3 stay readable and writable (`save_point.py` `WRITABLE_SHAPES`).
   The validator and every reader accepted shape 4 before any writer emitted it. Once a shape-4
   file exists, the change is fixed forward, never reverted.
2. **Binding sections come first and never move.** In order: Original goal, Resumption brief,
   Remaining actions, Completion criteria, Open questions, Current rules, Standing preferences,
   Decisions in force, Pending commands, Environment to re-establish, This session, Review before
   you continue. Direction changes, Observations and Suggested skills are movable. Prior sessions
   and Resume prompt are carried by the tool.
3. **`new` and `fill` own the byte budget, the fit and the verdict.** `new` prints the remaining
   budget under the 24,600-byte hot-file cap. When the file is over the cap, `fill` moves whole
   movable sections to this hop's file in the order Observations, Suggested skills, then Direction
   changes lines older than the last 3 hops. Each move leaves a pointer in Review before you
   continue, and `validate` fails a pointer whose file or heading does not exist. `fill` validates
   in memory, writes both files in one guarded write, and prints the verdict and the resume prompt.
4. **Binding content over the cap is reported, not failed.** When the binding and carried sections
   alone exceed the cap, `fill` still writes both files and the resume prompt, exits 0, and prints
   one `OVER-CAP:` line naming the section and how to shrink it. To shrink, retire entries per ADR
   0091 decision 1. Shape 4 has no `UNVALIDATED` verdict.

## Alternatives considered

- **Reorder shape 3 in place.** An old validator reading a reordered file would fail it on
  section order, which looks like a broken handoff and invites a rewrite. Every check would also
  have to branch on two orders under one shape number. Rejected by the owner (design Q1).
- **A new `write` command that fits the file.** That adds a seventh subcommand and leaves two
  routes to a filled file, one with fit and one without. Rejected by the owner (design Q2).
- **Ship only after a statistical A/A and a four-arm comparison.** Stopped at 44% of the week's
  usage. The owner set the ship gate to a deterministic content check plus a paired before/after
  smoke test (owner Q64, Q65). The content check passed 17 of 17 seeded cases with no authored fact
  lost. The two section-moving smoke cases passed every probe on both arms. The statistical
  comparison stays an optional follow-up.

## Consequences

- Writers hold two calls and no fit rules. Size classes, order and the move policy live in the
  script, not in the skill's prose.
- A reader reaches moved history through the pointers in Review before you continue.
- The 24,600-byte cap stays fixed until a passing eval justifies another number.
- Resume-eval runs keep the owner's guardrails hooks loaded. #17874 counts hook-blocked runs per
  arm, so a format that leads readers into a hook shows up apart from accuracy.
