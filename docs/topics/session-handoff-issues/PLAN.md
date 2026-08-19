# session-handoff-issues

## Brief

### TLDR

Two user-reported defects, two plugins: (1) context-guard's zone-transition operator message is
overly verbose; (2) session-flow's handoff skill sometimes writes the handoff file correctly but
never emits the copy/paste rails resume prompt, leaving the operator nothing to paste after
`/clear`. Fix (1) by compressing both hook message channels, and (2) by restructuring the skill so
the rails block (plus its below-rail re-arm notes) is the mandated final text of the turn — with a
documented escalation to a deterministic Stop-hook validator only if the failure recurs.

### Goal

Original goal (user, 2026-08-19, verbatim): "FYI I noticed this is overly verbose" (the
context-guard zone-crossing operator message) and "sometimes the /session-flow:handoff skill,
particularly when invoked after 20% or higher context usage, does not return a copy pasteable
prompt for me to paste after clear. Why is that? What can we do to fix this so it does it 100% of
the time?" Amended: None.

Observed failure shape (user-confirmed): the handoff file is written and its content is correct;
only the rails prompt emission is missing — a turn-termination failure, not a content failure.

### Constraints

- No Stop hook in this change (Q8 decision: escalation ladder). Two fresh-context validators
  challenged the hook on necessity (single observed occurrence, recoverable via
  `/session-flow:find-handoff` rung 1, cheaper fix untried) and cost (hook-budget/hook-precision
  conventions; false-positive blocks at degraded occupancy).
- context-guard's two-channel contract holds: continuation menu on the operator channel only;
  model channel keeps the I23 counter-steer with the test-pinned literals "Do not volunteer" and
  "operator's call", and never carries menu tokens or delivery claims.
- Operator message keeps the test-pinned literal "yours to choose" and a short "(if installed)"
  hedge on skill mentions (context-guard installs standalone).
- The handoff reorder must mandate "rails block PLUS below-rail `/loop` re-arm notes last" — plain
  "rails last" would contradict save-point.md's below-rail note placement and drop the re-arm.
- find-handoff's detection contract (rails, copy instruction, `Read @…` directive) is untouched.
- Each touched plugin's commit carries its CHANGELOG.md entry and `.claude-plugin/plugin.json`
  version bump (repo precedent); conventional-commit scoped subjects; no PR until the user asks.

### Acceptance criteria

- `plugins/context-guard/hooks/zone-crossing-inject.test.sh` passes with the compressed messages.
- Operator message is roughly ≤450 chars pre-interpolation (from ~900) and still names all four
  continuation options with their one-clause conditions, `zones.json`, and the workflow router.
- Model-channel guidance is measurably shorter with all four semantics intact
  (measurement-not-instruction, don't volunteer, operator's call, dumb-zone durable-notes rider).
- `plugins/session-flow/skills/handoff/SKILL.md` mandates the rails block + below-rail re-arm
  notes as the final text of the response, with checklist ticks emitted before the rails.
- The STOP gate itself states what STOP means and the one thing it never means (it ends the
  underlying task, never the response before the prompt is on screen), grounded in the engine's
  "A resume prompt is ALWAYS emitted" — the prompt is the mandatory half of a save-point, the file
  the optional one. The gate's emit box is marked as never satisfied by having written the file.
- The failure pattern and its `find-handoff` recovery are recorded in `context/gotchas.md`, and
  eval 12 pins rails-as-final-text under the high-occupancy condition the existing evals missed.
- The escalation ladder is recorded (session-flow CHANGELOG + follow-up work item): recurrence
  after the reorder triggers a lightweight Stop-hook validator (`last_assistant_message` regex +
  PostToolUse skill-ran marker, one bounded block, fail-open) — design named so it is a small step
  later, not a rediscovery.
- A tracked follow-up work item exists for compressing save-point.md / structure.md / SKILL.md
  (docs-hygiene:compress pass), which also re-reviews whether the hook is still warranted.

### Captured assumptions

- The rails-emission failure is salience/turn-termination at degraded occupancy; the reorder and
  the STOP-semantics fix target that cause. Efficacy remains unproven in the field — eval 12 now
  exercises the high-occupancy condition, but an eval is not production evidence — hence the
  escalation ladder rather than a guarantee claim.
- Failure frequency is unknown (owner report only; no telemetry) — proportionality of the
  no-hook decision rests on this.

### Out of scope

- The Stop-hook validator itself (escalation only).
- Compressing the session-flow reference docs (follow-up item).
- Any change to find-handoff or the detection contract.

### Deferred questions

- Q4-followup | arbiter: /planning:plan (of the follow-up item) — compress save-point.md
  (~30KB) / structure.md (~23KB) / handoff SKILL.md (~12KB) without breaking the detection
  contract, redaction rules, or `/loop` re-arm delimiting; then re-review the hook escalation.
