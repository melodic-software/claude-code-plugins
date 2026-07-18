---
name: setup
description: "Configure the autonomy plugin for this repository: discover the adopting org's state (role homes, substrate availability, budget posture), interview where discovery cannot infer, and write the schema-versioned binding under .claude/autonomy/. Use when: 'set up autonomy', 'autonomy setup', 'configure autonomy', 'bind the autonomy contracts', or another autonomy capability reports a missing binding. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply [--org-policy-home <locator>|none] [--budget-posture free|paid-opt-in]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Discovery phase of autonomy adoption (v0). Maps the roles in
[`${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md`](${CLAUDE_PLUGIN_ROOT}/reference/role-topology.md) to this org's real instances
and records the result as the schema-versioned binding the resolution ladder in
[`${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/binding-seam.md) reads at rung 1. Never assumes
any org, repo, tracker, or fleet shape — discovery reads what exists, the interview fills what
it cannot infer, and every landed change is reviewable per
[`${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md`](${CLAUDE_PLUGIN_ROOT}/reference/wiring-vs-advisor.md).

## Actions

- **`check`** (read-only): resolve the effective binding across ALL rungs of the binding-seam
  resolution ladder — user-global (`~/.claude/autonomy/`) → project (`.claude/autonomy/`) →
  local overlay (`.claude/autonomy/**/*.local.*`), additive, PLUS the org rung when the merged
  layers carry an `org_policy_home` pointer: fetch the org binding via the host CLI with the
  consumer's own auth and fold it in at its ladder position. Report what is bound, what is
  missing, and which layer or rung contributes each value; an unreachable org-policy home is
  WARNED as not-considered, never silently omitted. No writes.
- **`apply`** (idempotent): run discovery, then write or update the project binding. Re-running
  reads the existing binding and proposes deltas; it never overwrites blind and never touches
  unrelated user content. All project paths anchor at the PROJECT ROOT — resolve
  `${CLAUDE_PROJECT_DIR}` (fall back to the repository toplevel) before writing; invoking the
  skill from a subdirectory must never create a nested `.claude/autonomy/`.

## Argument surface (enumerated)

| Argument | Values | Headless default |
|---|---|---|
| action | `check` \| `apply` | — (required) |
| `--org-policy-home` | repository locator \| `none` | `none` |
| `--budget-posture` | `free` \| `paid-opt-in` | `free` |

`apply` with every argument supplied runs non-interactively — no prompts — so automation and
headless use work. With arguments missing, discovery infers first and interviews only the
gaps (convention ladder: config present → use it; absent → infer and persist; cannot infer →
ask and offer to persist; otherwise → safe free-tier default).

## Discovery (apply)

1. **Role homes**: inspect the repository and, when a host CLI with the consumer's own auth is
   available, the org — which repositories hold the CI-orchestration, settings-as-code, and
   org-policy roles. A solo/no-org adopter terminates at the binding-seam contract's terminal
   default: the repo-local binding is the whole binding, free-tier defaults throughout.
2. **Substrate availability**: what execution surfaces exist (local machine, CI runners,
   self-run infrastructure) — recorded as declared posture, not probed destructively.
3. **Budget posture**: `free` unless the user explicitly opts into `paid-opt-in`; anything
   paid is advisory + explicit opt-in with cost surfaced first (wiring-vs-advisor).

## Written binding

`apply` writes `.claude/autonomy/binding.json`, carrying `schema_version` (from `"1.0"`),
the role→instance map, `org_policy_home` pointer (or `null`), `budget_posture`, and declared
substrate. The file is tracked (team-shared); personal overrides go in
`.claude/autonomy/binding.local.json`. Recommend the consumer `.gitignore` line:
`.claude/autonomy/**/*.local.*`. Layers resolve user-global → project → local overlay,
additively.

## What this skill does NOT do

- Wire any capability slice (telemetry, capture, adapters) — those land with their own work
  packages and extend this skill when they ship.
- Mutate platform settings, user settings, or `pluginConfigs`.
- Assume the shape of any particular org or fleet — a run against an unknown repo asks or
  defaults; it never guesses silently.
