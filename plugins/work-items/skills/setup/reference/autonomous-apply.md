# Autonomous `apply` (no interactive user)

How `apply` resolves each of its decisions when no user is present to answer one. The
"`apply` (idempotent)" section of [`../SKILL.md`](../SKILL.md) owns the flow itself; this file owns
what that flow does at every point it would otherwise ask.

When `apply` runs in an unattended or loop-driven context there is nobody to answer any of its
questions, and blocking on one strands the run. This rule governs **every** decision in `apply`, not
only the seeding offer, the seeding offer is the last question in the flow, and the bind and
role-label passes above it ask their own:

- **A decision whose RECOMMENDED answer is safe resolves to it silently.** Do not present it. Say in
  the summary which defaults were taken so the operator can revisit them.
- **A decision with no safe default is never guessed.** Stop and report it as a named blocker, with
  the one command that resolves it. Writing an invented binding is worse than not binding: every seam
  verb then resolves a provider the repo did not choose.

Applied to the three passes:

| pass | unattended resolution |
| --- | --- |
| Provider binding (`apply` step 1, which runs the "Provider binding" procedure) | **Binding already present and valid. Keep it, and re-bind nothing.** That is the procedure's own read-first RECOMMENDED answer, so this rule resolves to it silently: a repo bound to `local-markdown`, `jira`, or a consumer-local provider stays on it, and a working `gh` never switches it to `github`. Re-binding is a switch-providers decision, which no default can stand in for. (A present binding the probe already FAILs never reaches here. `apply` runs `check` first, and that probe FAILs a malformed shape, a provider resolving to no adapter, a missing required config key, and a `github` binding this checkout cannot derive a repo for.) **Binding absent**. Bind `github` with `config.lease_ttl_hours: 24`, both RECOMMENDED, **only when `gh` is installed AND `gh repo view --json owner,name` resolves in this checkout**. `gh repo view` is the adapter's own derivation and the operative test; `gh auth status` is not — [`providers.md`](providers.md) owns the rationale for why the account-level check is the wrong gate. Report the resolved `owner/repo` in the summary alongside the other defaults taken. Otherwise stop: `local-markdown` and `jira` need `storage_dir` / `config.jira` values that have no defaults and cannot be inferred, so there is no provider left to choose safely. Report "tracker binding needs a provider decision; run `/work-items:setup apply` with a user present". |
| Role labels (step 2) | Keep the defaults, the RECOMMENDED answer, and the one that writes nothing. The pass runs and completes as a no-op: `config.role_labels` is left absent, so every role resolves to its documented fallback. A remap is a repo-vocabulary decision no default can stand in for. |
| Work-class labels (step 3) | When any canonical member is missing: if the repo declares a label-as-code owner, stop, name the missing labels and point remediation at that owner. Otherwise stop: "work-class axis needs provisioning; run `/work-items:setup apply` with a user present". Never create labels ad hoc unattended. |
| Capability-tier labels (step 4) | When `capability-tier: frontier` is missing: if the repo declares a label-as-code owner, stop. Name the missing label and point remediation at that owner. Otherwise stop: "capability-tier axis needs provisioning; run `/work-items:setup apply` with a user present". Never create labels ad hoc unattended. |
| Legacy capability-tier backfill (step 5) | Unattended: run `backfill-capability-tier-labels.sh check` only and report candidates with the apply command for a user-present run. Never mutate item labels without confirmation. |
| Schedule seeding (before step 7) | Skip, the RECOMMENDED answer. Write the empty `{"items": []}` skeleton and go to step 10. **Exception:** when the invocation carries both `--seed-schedule` and `--accept-recommended`, run steps 7–8 using each inferred candidate's recommended values without per-item interviews (unattended bulk seed). |

So an autonomous first-time bind on a `gh`-ready repo produces the binding, the role-label pass, and
the empty skeleton, and nothing else; an autonomous re-run against a repo that is already bound leaves
that binding exactly as it found it. Absent an opt-in, never infer and never interview.
`--seed-schedule` carries the opt-in decision without the offer prompt, but the pass it selects is
step 7's per-item interview, so it is not a non-interactive seeding path unless `--accept-recommended`
is also present. Pairing both flags tells step 8 to accept every inferred candidate with its
recommended cadence/title fields and write the schedule without blocking on questions (#1302).
