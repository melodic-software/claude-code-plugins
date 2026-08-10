---
outcome: early-exit
tier: B
date: 2026-08-09
---

# Design resolution — permission-model

`/planning:plan`'s design gate, resolved as a **Tier B early exit**. No `/planning:design` session is
owed. This file records the classification, its evidence, and the type sketch the tier requires.

## Why Tier B and not Tier A

Tier A asks whether the work introduces new types/contracts, a new module, a package-topology change,
or cross-module integration whose shape is still open. Most of that surface is **already closed** —
by the Brief, or by repository precedent strong enough that inventing an alternative would itself be
the defect.

| Design axis | Status | Closed by |
|---|---|---|
| Packaging / module boundary | Closed | Brief `### Constraints` → Packaging: a sibling skill under `claude-config`, not a new plugin. Basis is hard: the flat `renames` map and the `audit-pass/SKILL.md:36` cross-plugin reference. |
| Component topology | Closed by precedent | Every skill in this marketplace is `SKILL.md` + `reference/*.md` + `scripts/*.sh` + `evals/evals.json`. Verified against `plugins/claude-config/skills/audit-permission-grants/`, which is the nearest sibling and the direct template. |
| Read strategy | Closed | Brief: compute the merge, bounded by a per-item decidability criterion with a stated basis. |
| Output vocabulary | Closed | Brief: the `review` plugin's `severity.md`. |
| Finding-line format | Closed by precedent | `<severity> [<check>] <source>: <detail>`, from `audit-permission-grants/reference/criteria.md`. |
| External contracts consumed | Closed | The measured CLI defensive contract in the Brief; no new external surface is introduced. |
| Cross-module integration | Closed by precedent | Registration as an `audit-pass` lane follows that skill's documented lane rule; no new integration mechanism is invented. |

What genuinely remains open is **script decomposition** (how many scripts, where the seam between
them falls) and the **criteria-row schema** for the new checks. Both are localized, both are
single-file-ish decisions, and both are resolved inside the plan body rather than needing a design
session. That is the Tier B signature.

## Type sketch

No programming-language type system is involved — the artifacts are shell scripts and markdown. The
"types" are the data shapes the scripts pass and the report consumes.

**Scope record** — one per settings file discovered.

- `scope`: one of `managed` | `user` | `project` | `local` | `startdir-local`
- `path`: absolute path as read
- `present`: whether the file exists and parsed
- `arrays`: the `permissions.allow` / `.ask` / `.deny` entries found

`startdir-local` is a distinct member, not a variant of `local`: acceptance criterion 7 requires the
pre-v2.1.211 start-directory copy to be read **alongside** the repository-root copy, because rules
from both stay in effect.

**Merged rule** — one per rule in the effective set.

- `rule`: the verbatim pattern
- `bucket`: `allow` | `ask` | `deny`
- `origin`: the `scope` it came from
- `precedence_basis`: the documented mechanic the placement follows from (criterion 1 requires this
  per rule, so it is a field, not prose)
- `auto_mode_drop`: whether auto mode discards it on entry, plus which criterion-3 class

**Finding** — one per detected problem, matching the existing line format.

- `severity`, `check`, `source`, `detail`
- `caveat`: optional; populated when the basis is an open upstream discrepancy (criterion 10 makes
  this mandatory-when-applicable, so it is a field rather than an ad-hoc sentence)

**Oracle observation** — only if the debug-channel candidate ships (see the plan's open decision).

- `rule`, `source_path`, `reason` parsed from the harness's own drop narration
- `agrees_with_prediction`: the cross-check result against `auto_mode_drop`

## What this early exit does not cover

- **Skill naming.** Still owed against `MIGRATION-PLAYBOOK.md` §Naming, with the live constraint that
  `PLUGIN-PHILOSOPHY.md:41-46` requires the namespace noun to be true of every skill under it. Naming
  is not a design thread in the Tier A sense; it is resolved in the plan.
- **The runtime prerequisite.** A non-strict JSON parser implies Python or Node, which
  `PLUGIN-PHILOSOPHY.md:387-397` and `:436-447` govern. Decided in the plan, not here.
