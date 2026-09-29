# Fresh-context phase verifier mandate (#4259)

The current contract is stated below. Whether to add a verifier opt-out is an open owner
decision tracked at #4259.

## Decision record

- **Claim:** Orchestrated runs dispatch this plugin's `phase-verifier` before marking a phase
  `[DONE]`. Autonomous runs always dispatch it. Interactive runs dispatch it for any phase
  beyond a mechanical, behavior-preserving change. It does not substitute for
  `/implementation:implement` Step 5's end gate (`/review:quality-gate` and
  `/verification:confirm` when installed). An opt-out (`userConfig` `always` /
  `behavioral-only` / `final-only` / `off`, or making the interactive carve-out the default in
  both modes) is not implemented; adding one is an open owner decision tracked at
  [#4259](https://github.com/melodic-software/claude-code-plugins/issues/4259).
- **Basis:** this skill's "Fresh-context verifier before marking a phase `[DONE]`" paragraph
  (every mode; interactive mechanical carve-out) and `/implementation:implement` Step 5
  item 6 (whole-diff end gate).
- **As of:** 2026-09-29.
- **Recheck:** the live state of #4259, this skill's verifier paragraph gains an opt-out, or
  implement Step 5 drops the `/review:quality-gate` / `/verification:confirm` handoff.

## Options

| Option | Scope |
| --- | --- |
| **Current contract** | Per-phase fresh-context verifier as written; end gate stays mandatory and separate |
| **Alternative (not implemented)** | `always` / `behavioral-only` / `final-only` / `off`, or interactive carve-out in both modes |

## What stays in force

The per-phase verifier is an extra layer on top of Step 5, not a replacement. A phase that
looks mechanical in autonomous mode still gets a verifier. An `INCONCLUSIVE` return is still
not a verdict. Lowering verifier *effort* is a different issue
([#4253](https://github.com/melodic-software/claude-code-plugins/issues/4253)); this record
does not change the `phase-verifier` pin.
