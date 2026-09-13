# audit-automation-gaps: observed failure modes

Every entry below is a failure this skill actually produced when it was run against a real
repository, not a hazard imagined for the list. Read before Phase 1 when the run will end in
verdicts a human acts on.

## Contents

- [A partial inventory anchors every later verdict](#a-partial-inventory-anchors-every-later-verdict)
- [A keyword count is a ceiling, never a frequency](#a-keyword-count-is-a-ceiling-never-a-frequency)
- [`PostToolUse` cannot block, so no `PostToolUse` candidate is a gate](#posttooluse-cannot-block-so-no-posttooluse-candidate-is-a-gate)
- [An `exit 2` gate on `PermissionRequest` is silently inert](#an-exit-2-gate-on-permissionrequest-is-silently-inert)
- [The candidate generator reaches a handful of the documented events](#the-candidate-generator-reaches-a-handful-of-the-documented-events)
- [Upstream records](#upstream-records)

## A partial inventory anchors every later verdict

Observed on 2026-09-13: the pre-computed inventory reported 3 hook scripts for a repository that
carried 143 of them, and every candidate generated afterwards was shaped by the small number. The
model did not re-derive the count; it reasoned from the figure it had been handed, and produced
"this repo has almost no hook automation" candidates against a repository that is dense with it.

The failure class is the pre-computed number, not the particular bug. A count injected before
Phase 1 is an anchor, and a wrong anchor is not corrected by later reading because nothing in the
procedure asks for the count again. So: before generating candidates, re-derive any count the
verdicts will lean on with your own command, and where the re-derived number disagrees with the
injected one, say both in the report and use yours. A count and a wired mechanism are also
different facts. A hook script present on disk that no settings file or manifest registers is not
an active hook, and counting the two together overstates coverage in the opposite direction.

## A keyword count is a ceiling, never a frequency

Observed on 2026-09-13 against this marketplace at merged main `49912c63`:
`git log --oneline -E --grep='markdownlint|lint'` returns 1128 of 2202 commits, about 51 percent,
and `git log --oneline -E --grep='secret|gitleaks'` returns 209, about 9 percent. Reading the first
15 of those 209 shows dependency bumps, component syncs and CI pins. Not one is a leaked secret.

Two gates read those numbers directly, so the error is not cosmetic. **Zero incidents** treats a
count as incidents that happened, and **YAGNI** treats a count as a frequency. A `--grep` count is
neither. It is the number of commits whose message mentions a word, which is an upper bound on the
incidents and usually a loose one. Cite a frequency only after reading a sample of the matching
commits and saying how many of them were the concern.

The asymmetry is what makes this cheap rather than onerous. A ceiling that already sits below the
**YAGNI** threshold settles the gate on its own: if at most 4 percent of commits could be the
concern, the frequency is under 4 percent whatever the sample says, and no sample is needed. Only a
PASS, or an affirmative claim that the concern is frequent, has to pay for a sample.

## `PostToolUse` cannot block, so no `PostToolUse` candidate is a gate

A candidate phrased as "a `PostToolUse` hook that rejects the edit when the formatter finds a
problem" cannot exist. The tool has already run by the time the event fires, and exit code 2 there
shows the hook's stderr to Claude rather than preventing anything. Such a candidate is not a REJECT
at **Too slow** or **Already enforced**; it is malformed, and the right response is to re-state it
on a blocking event or to accept it as advisory before running it past any gate.

## An `exit 2` gate on `PermissionRequest` is silently inert

This is the same shape one rung worse, because it fails without any signal. `PermissionRequest`
does not honor exit code 2 at all: the permission flow proceeds unchanged and denial goes through a
JSON `decision` object instead. A hook written as `exit 2` there is not a weak gate or a slow gate.
It is no gate, it reports nothing, and the repository keeps a row in its enforcement inventory for a
mechanism that never fires. Any candidate whose mechanism is a per-event exit code gets its event's
exit-code semantics confirmed against the hooks reference in the Phase 2.2 mandatory batch, before
the verdict, not after.

## The candidate generator reaches a handful of the documented events

The hooks documentation names 33 events. This skill's own candidate guidance names three of them:
`context/gap-analysis.md` asks only about a `PostToolUse` formatter, and `context/hook-timing.md`
prices `PreToolUse`, `PostToolUse` and `PermissionRequest`. Everything else, session lifecycle,
compaction, subagent and task boundaries, file and config change, model switch, elicitation, is
absent from the questions the skill asks, so a genuine gap on one of those events cannot surface as
a candidate at all. That is a recall ceiling in the generator, and it is invisible in the output: a
clean bill of health is reported the same way whether the events were considered and dismissed or
never considered. When a run reports no gaps in the hooks category, say which events were actually
examined.

## Upstream records

Each row restates a volatile upstream specific, so it carries the four parts the upstream-drift
convention requires. Re-fetch the basis before acting on any row; the date is a ceiling on how
current the claim is, not authority.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `PostToolUse` cannot block: the tool has already run, and exit code 2 shows the hook's stderr to Claude as a system reminder | [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), exit-code-2 behavior per event | 2026-09-13 | A re-fetch finds the per-event exit-code table no longer matching this row |
| `PermissionRequest` does not honor exit code 2: "the permission flow proceeds unchanged. Deny through the `decision` object instead" | [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), `PermissionRequest` exit-code behavior | 2026-09-13 | A re-fetch finds `PermissionRequest` honoring exit code 2, or the `decision` object renamed or removed |
| The hooks reference documents 33 hook events | [Claude Code hooks reference](https://code.claude.com/docs/en/hooks), the hook-events section headings, counted 2026-09-13 | 2026-09-13 | A re-fetch returns a different number of documented events |
| `/hooks` opens a read-only browser, and selecting a hook "shows its details: the event, matcher, type, source file, and command" | [Automate actions with hooks](https://code.claude.com/docs/en/hooks-guide), the hooks-browser step | 2026-09-13 | A re-fetch finds the browser no longer read-only, or showing a different detail set |
