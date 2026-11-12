# audit-automation-gaps: observed failure modes

Each entry is a failure this skill produced on a real repository, not an imagined hazard. Read
before Phase 1 when the run will end in verdicts a human acts on.

## Contents

- [A partial inventory anchors every later verdict](#a-partial-inventory-anchors-every-later-verdict)
- [A keyword count is a ceiling, never a frequency](#a-keyword-count-is-a-ceiling-never-a-frequency)
- [`PostToolUse` cannot block, so no `PostToolUse` candidate is a gate](#posttooluse-cannot-block-so-no-posttooluse-candidate-is-a-gate)
- [An `exit 2` gate on `PermissionRequest` is silently inert](#an-exit-2-gate-on-permissionrequest-is-silently-inert)
- [A hook that exits 1 lets the action through](#a-hook-that-exits-1-lets-the-action-through)
- [The candidate generator reaches a handful of the documented events](#the-candidate-generator-reaches-a-handful-of-the-documented-events)
- [Upstream records](#upstream-records)

## A partial inventory anchors every later verdict

Observed on 2026-09-13: the pre-computed inventory reported 3 hook scripts for a repository that
carried 143 of them, and every candidate generated afterwards was shaped by the small number. The
model did not re-derive the count; it reasoned from the figure it was handed, and produced
"this repo has almost no hook automation" candidates against a repository dense with it.

The failure class is the pre-computed number, not the particular bug. A count injected before
Phase 1 is an anchor, and later reading does not correct a wrong one because nothing in the
procedure asks for the count again. Before generating candidates, re-derive any count the verdicts
will lean on with your own command, and where it disagrees with the injected one, say both in the
report and use yours. A count and a wired mechanism are also different facts: a hook script on disk
that no settings file or manifest registers is not an active hook, and counting the two together
overstates coverage in the opposite direction.

## A keyword count is a ceiling, never a frequency

Observed on 2026-09-13 against this marketplace at merged main `49912c63`:
`git log --oneline -E --grep='markdownlint|lint'` returns 1128 of 2202 commits, about 51 percent,
and `git log --oneline -E --grep='secret|gitleaks'` returns 209, about 9 percent. Reading the first
15 of those 209 shows dependency bumps, component syncs and CI pins. Not one is a leaked secret.

Two gates read those numbers directly. **Zero incidents** treats a count as incidents that
happened, and **YAGNI** treats a count as a frequency. A `--grep` count is neither: it is the number
of commits whose message mentions a word, an upper bound on the incidents and usually a loose one.
Cite a frequency only after reading a sample of the matching commits and saying how many of them
were the concern.

The asymmetry keeps this cheap. A ceiling already below the **YAGNI** threshold settles the gate on
its own: if at most 4 percent of commits could be the
concern, the frequency is under 4 percent whatever the sample says, and no sample is needed. Only a
PASS, or an affirmative claim that the concern is frequent, has to pay for a sample.

## `PostToolUse` cannot block, so no `PostToolUse` candidate is a gate

A candidate phrased as "a `PostToolUse` hook that rejects the edit when the formatter finds a
problem" cannot exist: the tool has already run by the time the event fires, so the hook has
nothing left to prevent (the event's exit-code row is read live, per the record below). Such a
candidate is not a REJECT
at **Too slow** or **Already enforced**; it is malformed. A report-only check is never re-stated
as an advisory per-edit hook: flag it with its check-placement home (a git `pre-commit` hook on
changed lines, `pre-push` when its measured run is over the commit budget but within 60 s, CI
beyond), the same placement the shift-left carve-out's second conjunct requires.

## An `exit 2` gate on `PermissionRequest` is silently inert

The same shape one rung worse, because it fails without any signal. A `PermissionRequest` hook
denies through its decision control, read live per the record below, not through an exit code. A
hook written as `exit 2` there is no gate at all; it reports nothing,
and the repository keeps a row in its enforcement inventory for a mechanism that never fires. Any candidate whose mechanism is a per-event exit code gets its event's
exit-code semantics confirmed against the hooks reference in the Phase 2.2 mandatory batch, before
the verdict, not after.

## A hook that exits 1 lets the action through

A gate candidate whose script exits 1 to refuse is no gate: exit 1 is a non-blocking error and the
action goes ahead, on most events, unless the hook sets `"onFailure": "block"` (Claude Code
v2.1.295 or later), which also blocks when the script crashes, times out or cannot start. Our rule:
a blocking gate refuses through exit 2 or its event's decision control and sets
`"onFailure": "block"` when a crash must not let the action through. `WorktreeCreate` is the
documented exception, where any non-zero exit fails the creation. The semantics are read live from
the hooks reference, [Exit code output](https://code.claude.com/docs/en/hooks#exit-code-output) and
[Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails),
in the Phase 2.2 mandatory batch.

## The candidate generator reaches a handful of the documented events

The hooks documentation names many events (count them live, per the record below). This skill's
own candidate guidance names four of them:
`context/gap-analysis.md` asks about formatters and report-only checks on `PostToolBatch`,
`PostToolUse` and git hooks, and `context/hook-timing.md` prices `PreToolUse`, `PostToolUse`,
`PostToolBatch` and `PermissionRequest`. Everything else, session lifecycle,
compaction, subagent and task boundaries, file and config change, model switch, elicitation, is
absent from the questions the skill asks, so a genuine gap on one of those events cannot surface as
a candidate. That recall ceiling is invisible in the output: a clean bill of health reads the same
whether the events were considered and dismissed or never considered. When a run reports no gaps in the hooks category, say which events were actually
examined.

## Upstream records

Each row states our decision and points at the section that holds the specific, per the
upstream-drift convention. Re-fetch the pointer before acting on any row; the date is not
authority.

| Decision | Pointer | As of | Recheck trigger |
|---|---|---|---|
| No `PostToolUse` candidate is treated as a gate | When judging whether a hook can block, fetch the event's row of [hooks: exit code 2 behavior per event](https://code.claude.com/docs/en/hooks#exit-code-2-behavior-per-event) live | 2026-11-10 | That event's row changes its `Can block?` cell |
| An `exit 2` gate on `PermissionRequest` is reported as no gate | When judging a `PermissionRequest` hook, fetch [hooks: PermissionRequest decision control](https://code.claude.com/docs/en/hooks#permissionrequest-decision-control) live | 2026-11-10 | That section changes how the event honors exit codes or names its deny field |
| A run that reports no hook gaps names the events it examined, against the full documented list | When counting the documented events, read the headings under [hooks: hook events](https://code.claude.com/docs/en/hooks#hook-events) live | 2026-11-10 | That section adds or removes an event |
| We leave hook enumeration to the native `/hooks` menu, which lists the resolved set with each hook's source; when you need its exact contents, read the section live | [The /hooks menu](https://code.claude.com/docs/en/hooks#the-/hooks-menu) | 2026-10-11 | That section stops showing each hook's source, or the menu stops listing the resolved set of configured hooks |
