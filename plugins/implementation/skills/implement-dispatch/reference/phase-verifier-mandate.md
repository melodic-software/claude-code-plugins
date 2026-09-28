# Fresh-context phase verifier mandate (#4259)

Option A: keep the mandate. Document that it does not replace Step 5. Park an opt-out.

## Decision record

- **Claim:** Orchestrated runs dispatch this plugin's `phase-verifier` before marking a phase
  `[DONE]`. Autonomous runs always dispatch it. Interactive runs dispatch it for any phase
  beyond a mechanical, behavior-preserving change. That mandate stays. It does not substitute
  for `/implementation:implement` Step 5's end gate (`/review:quality-gate` and
  `/verification:confirm` when installed). An opt-out (`userConfig` `always` /
  `behavioral-only` / `final-only` / `off`, or making the interactive carve-out the default in
  both modes) is unpaid and parked.
- **Basis:** Issue [#4259](https://github.com/melodic-software/claude-code-plugins/issues/4259)
  and this skill's "Fresh-context verifier before marking a phase `[DONE]`" paragraph (every
  mode; interactive mechanical carve-out). Implement Step 5 item 6 already mandates the
  whole-diff end gate. PR
  [#4758](https://github.com/melodic-software/claude-code-plugins/pull/4758) left
  `implement_phase_verifier` to this issue. Origin/main still has no verifier opt-out key.
- **As of:** 2026-09-28.
- **Recheck:** a maintainer funds a `userConfig` verifier mode, the Agent tool or this skill
  grows an opt-out, or implement Step 5 drops the `/review:quality-gate` /
  `/verification:confirm` handoff.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A: Keep mandate (taken)** | Per-phase fresh-context verifier as written; end gate stays mandatory and separate | Current contract |
| **B: Opt-out (parked)** | `always` / `behavioral-only` / `final-only` / `off`, or interactive carve-out in both modes | Quality trade; unpaid |

## What stays in force

The per-phase verifier is an extra layer on top of Step 5, not a replacement. A phase that
looks mechanical in autonomous mode still gets a verifier. An `INCONCLUSIVE` return is still
not a verdict. Lowering verifier *effort* is a different issue
([#4253](https://github.com/melodic-software/claude-code-plugins/issues/4253)); this record
does not change the `phase-verifier` pin.
