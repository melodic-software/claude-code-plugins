# Classify a plugin's hooks by packaging before proposing a split

- Status: accepted
- Date: 2026-09-04

## Decision

Decided during the PreToolUse guard audit (#3712), when a fleet-wide "split the hooks out of every
plugin that has them" was described as existing policy and turned out to be unwritten. Before any
such split is proposed, the plugin is placed in one of three classes, and only one of them is a
candidate:

- **Class A — the hooks ARE the plugin.** Removing them leaves a shell. Twelve plugins:
  `actionlint`, `bash-format`, `biome-format`, `desktop-notification`, `eol-normalizer`,
  `go-format`, `guardrails`, `markdown-format`, `powershell-format`, `rate-limit-guard`,
  `ruff-format`, `typos-format`. Each carries exactly one skill and that skill is `setup` — the
  thing that installs and configures the hooks. Splitting hooks out of these produces an empty
  plugin and a hook bundle, which is the same plugin under two names. **Never split.**

- **Class B — the hook IS the feature mechanism.** The plugin's advertised capability is delivered
  BY the hook, so a split severs the feature from its own implementation. Three plugins:
  `autonomy` (the Ralph-loop `Stop` gate is what makes a lane continue or halt), `context-guard`
  (the zone mechanism is the `PreToolUse` gate plus its injection hooks), `disk-hygiene` (the
  `PreToolUse` guard polices that plugin's OWN delete engine — split apart, the guard and the
  engine version independently and the guard can be installed without what it guards, or worse, the
  engine without its guard). **Must not split.**

- **Class C — hooks adjunct to a skill surface.** The plugin's substance is its skills, and the
  hooks reinforce them. Five plugins: `claude-ops` (12 skills), `session-flow` (14),
  `source-control` (7), `instruction-placement` (5), `context-budget` (2). A consumer who wants the
  skills may not want the always-on hooks, and today cannot have one without the other except
  through the per-hook kill switches. **Genuine candidates — and a candidate is not a decision.**

A Class C split still has to earn itself on its own evidence: a consumer who wants one half without
the other, weighed against a second plugin to install, a second version to keep in step, and a
second entry in the catalog. The class only says the question is worth asking.

Alternatives weighed:

- **The fleet-wide split, as originally described — rejected.** It cannot survive contact with
  Class A: twelve of the twenty hook-carrying plugins would become empty shells. Stating the policy
  fleet-wide made it sound uniform when it applies to a quarter of the fleet.
- **No taxonomy, decide case by case — rejected as the status quo that produced this.** The
  fleet-wide rule was believed to be policy precisely because nothing was written down. A rule that
  lives only in recollection is re-litigated at every audit, and the re-litigation is the cost.
- **Split by hook EVENT rather than by plugin — not viable.** A plugin's hooks routinely span
  events that belong to the same feature: `context-guard` alone wires `PreToolUse`,
  `UserPromptSubmit`, `PostToolBatch` and `PostCompact` to deliver one zone mechanism. Cutting by
  event cuts through the feature.

## Consequences

The classification is a gate on the PROPOSAL, not a mandate to execute. No split is executed by the
change that records this ADR; the five Class C candidates are filed as separate agent-ready issues,
each of which must make its own case.

The counts above are a snapshot of 2026-09-04 and are load-bearing only as evidence for the shape
of the classes. A new hook-carrying plugin is classified when it lands, by the same question in
each class's first sentence — not by matching it to a list.

The per-hook `<name>_enabled` userConfig booleans stay regardless of class. They are the mechanism
that already lets a consumer take a Class C plugin's skills and turn its hooks off, which is why no
Class C split is urgent, and they remain the only such lever for Class A and B.

## References

- [ADR 0003](0003-verification-guards-earn-default-on-by-measured-precision.md) — the sibling rule
  for whether a guard is default-on. This ADR governs where a hook LIVES; 0003 governs whether it
  FIRES by default.
- [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) — the packaging
  analogue: how code is shared across plugins once they are separate.
- [`docs/PLUGIN-PHILOSOPHY.md` § Classifying a hook](../PLUGIN-PHILOSOPHY.md#classifying-a-hook) —
  the complementary axes. That rubric asks what a hook DOES (mechanism) and why it EXISTS (class);
  this one asks where it belongs. A hook can be pure policy by that rubric and still sit in a Class
  C plugin.
