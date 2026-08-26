# Restoration verification and the three mutant-write regimes

How Phase 3 of [`../SKILL.md`](../SKILL.md) proves the tree it mutated was restored, and when that
proof can run. Which of the three regimes applies is a property of the configured tool that Phase 0
resolves from the project's config, never from the tool's reputation.

**Verify restoration against the Phase 0 snapshot, not against a clean tree.** Phase 0 rejects a
dirty *target* but permits unrelated dirty files elsewhere, so an unconditional "tree is clean" probe
would report a restoration failure on a repo that merely has unrelated work in progress. And, worse,
would teach the reader to ignore that line. Compare the after-state against that snapshot: equality
is success, and any difference in a **tracked** path is a failed restore. Tracked, not merely
mutated, a run that leaves an adjacent tracked file modified has broken the same invariant, and
untracked scratch output is not tracked source and does not trip it.

**When that comparison can run depends on where the mutant is written, a property of the configured
tool that Phase 0 resolves from the project's config, never from the tool's reputation.** One axis,
three regimes:

- **Out-of-tree**. Every established tool in its default configuration: the mutant goes to a
  sandbox, a temporary file, or memory, and tracked source is only ever read. There is no revert to
  verify because there was no write. The gate is a **Phase 0 precondition that the out-of-tree mode
  is actually in effect**, the setting is user-changeable, so read it, plus **one end-of-run
  comparison** as a backstop against crash paths no tool documents. Where a tool has no in-place
  option at all, that precondition is a constant rather than a check.
- **In-tree, whole-file**, a tool that rewrites the working file once and restores it itself. One
  write and one tool-owned restore, so an **end-of-run comparison** is right and sufficient. Run it
  in a `finally`, not on the return path: "end of run" here means **however the run ends**, including
  a tool that is killed and never returns. This is the regime with a real in-tree write and a restore
  nobody controls, so an abnormal exit is exactly when the comparison matters most, and it is the
  one path where a missing check would be silent rather than loud. Phase 0 says plainly that the
  restore is best-effort: signal coverage is undocumented, and a second interrupt can abort it
  mid-move.
- **In-tree, per mutant**. `tool: manual`, and any tool that applies and reverts the working file
  once per mutant. This is the only regime where pile-on is real, and the in-loop rule applies in
  full: **compare after every revert**, because a failed revert means the trap itself failed, the
  next mutant lands on unrestored source, and every verdict after that describes a tree nobody wrote.
  Guarantee the revert on every exit path. Apply as a patch reverted in a trap or `finally`, never
  an edit depending on a later step, and run the comparison on those paths too: a trap fires outside
  the loop, so the loop's own comparison never sees a crashed run, and a revert that merely *ran* is
  not a revert that *worked*. Where such a tool offers neither per-mutant observability nor interrupt
  safety, Phase 0 **refuses** rather than gates: a check that cannot run is not a check.

**Do not go hunting for a per-mutant revert on the first two regimes.** Under mutant schemata. The
architecture the established tools use. Every mutant is written once and selected at run time by an
environment variable or switch, so there is no Nth write and no Nth revert to observe, and the
per-mutant hooks those tools expose report a *result*, not a filesystem event. An end-of-run
comparison loses nothing there: the in-loop check buys localisation and pile-on prevention across
many write/revert cycles, and where there was one write neither exists. Never substitute the tool's
own exit status for the comparison, a harness that restores by writing the file back reports success
for a write it never re-read.

**The first failed restore ends the run**, identically in all three regimes. Only *when* the
comparison can run varies. It is terminal, not a finding reported beside the others:

- Apply no further mutants, which bites only where mutants are applied one at a time; the remaining
  two carry the rule everywhere else.
- Enter no later phase. No triage, no ranked report, and **no findings file, `--persist-findings`
  or not**.
- Return a **failure** verdict naming every unrestored path and the recovery command. The failure is
  the whole report; nothing may push it off the screen.

Stopping rather than reporting is what `docs/conventions/liveness-assertion/README.md` "Core
contract" item 1 requires of a surface that cannot vouch for its own outcome, and continuing would
produce both false-green shapes that doc names at once. The ranked report would read exactly like a
normal run while tracked source sits mutated; and under `--persist-findings` the run would hand an
apply relay a conforming findings file whose every `Location` asserts a restored tree. Findings
measured against a state that no longer exists, fenced onto source that is now corrupt.
