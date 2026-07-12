# General-purpose hook migration audit

Point-in-time audit of the **general-purpose** subset of `melodic-software/medley`'s in-repo hooks
for extraction into this marketplace's hook plugins (`guardrails`, `claude-ops`). This is an **audit
snapshot**, not durable policy — the [migration playbook](MIGRATION-PLAYBOOK.md) is the policy; this
table records each candidate's gate compliance on the audit date and which follow-up issue owns each
accepted migration. Empirical claims decay: a row is only true as of the stamp below.

Audited 2026-07-12 (`melodic-software/medley#1391`, under wave-2 map `melodic-software/medley#1369`).
Facts are Tier-0 — read from each hook's `.sh`, its `.test.sh`, and medley's `.claude/settings.json`
registration this session. The shipped-standard column is measured against the published hook-plugin
conventions: the [four-seam extensibility contract](MIGRATION-PLAYBOOK.md), the
[hook-telemetry envelope contract](conventions/hook-telemetry/README.md), and the
[shared-`hook-utils.sh` decision record](MIGRATION-PLAYBOOK.md).

## Scope

Medley wires ~38 hooks via `${CLAUDE_PROJECT_DIR}/.claude/hooks/`. This audit grades **only the
general-purpose subset** the wave-2 map nominated — guardrail hooks (target: `guardrails`) and
telemetry/observability hooks (target: `claude-ops`). The remaining hooks are **out of scope by
nature**: the .NET-toolchain hooks (`block-dotnet-test-nologo`, `msbuild-introspect`,
`nuget-pack-prep`, `publicapi-diff`, `sarif-diagnostics`, `dependency-*`) and the worktree/branch
hooks (`branch-awareness`, `branch-protection`, `git-safety`, `worktree-*`, `onboard-drift`,
`single-test`) encode this repo's toolchain and workflow and stay repo-specific.

## Gate dimensions

Each candidate is graded against the shipped hook-plugin standards — the HARD gates a hook must
clear to ship repo-agnostic:

- **Seam-clean** — zero surviving repo-path coupling under plugin cache isolation. Every candidate
  `source`s a sibling `hook-utils.sh` (bundled at cutover per the shared-lib record — not a defect);
  the gate is whether the hook's *behavior* de-couples, or whether it embeds a `${CLAUDE_PROJECT_DIR}`
  path, a `tools/` shell-out, a `.work/`-artifact convention, or medley-specific injected content that
  survives generalization.
- **Kill-switch** — a `HOOK_<NAME>_ENABLED` env gate (via `hook::check_enabled`), the ecosystem norm.
- **Telemetry seam** — a producer emits the generic envelope to `HOOK_TELEMETRY_SINK` (opt-in,
  no-op when unset), **not** a direct write to an assumed repo observability store.
- **Shared lib** — sources `hook-utils.sh`, so it rides the `lib/hook-utils.sh` SSOT +
  `scripts/sync-hook-utils.sh` sync at cutover.
- **Contract test** — ships a black-box `.test.sh` asserting the stdin→exit/stdout contract.
- **Target + verdict** — the destination plugin and the accept / defer decision.

**Seam reconciliation (telemetry).** The wave-map nomination reads "telemetry hooks need a sink/dir
`userConfig` seam." The shipped contract resolves that intent differently and correctly: a producer
emits the envelope to the `HOOK_TELEMETRY_SINK` **env** target (literal in `settings.json`, per the
[envelope contract](conventions/hook-telemetry/README.md) "Sink path resolution") — **not** a
per-hook `userConfig`, which would diverge from every existing producer (`markdown-format`,
`secret-pattern-detection`, …). The nomination's real requirement — "the repo OTEL store must not be
assumed" — is met by **stopping the direct store-write and emitting to the consumer's sink**. A
`userConfig` `directory` seam applies in exactly one place: `skill-usage-audit`'s bespoke second
store (`skill-usage.jsonl`), which does not flow through the envelope.

## Verdict summary

- **Accepted for migration: 9 of 13.** Two guardrail hooks (`block-hook-bypass`,
  `workflow-resilience-check`) and the seven-hook `*-audit` telemetry-emitter family. Two retrofit
  issues filed — one per accepted **group**, per the wave-map emitter protocol.
- **Deferred / repo-owned: 4.** `pr-prep-evidence-check`, `hook-telemetry-sink`,
  `cc-telemetry-ensure`, `session-reinjection` — each stays in medley with an explicit revisit
  trigger (below). None is a clean generalization; each de-couples into a *different* parameterized
  tool or is consumer-owned infrastructure by design.
- **Systemic gap surfaced: the generic sink.** Once the `*-audit` producers ship in `claude-ops`
  emitting envelopes, they are inert without a consumer sink — and `claude-ops` ships none (medley's
  `hook-telemetry-sink` is repo-owned by design). Recorded below.

## Guardrails candidates (3)

| Hook | Seam-clean | Kill-switch | Telemetry seam | Shared lib | Contract test | Target + verdict |
|---|---|---|---|---|---|---|
| `block-hook-bypass` | yes — behavior is generic (blocks Bash file-write workarounds — `cat >`, `echo >`, `python3 -c` — that circumvent Write/Edit gates) | `HOOK_BLOCK_HOOK_BYPASS_ENABLED` | **rewire** — direct `hook::record_event` write to `.claude/observability/hook-events.jsonl`; migrate to the envelope | yes | yes (block/allow, false-positive regressions) | **guardrails → ACCEPT** |
| `workflow-resilience-check` | after one edit — advisory nudge when a `Workflow` script fans out un-throttled; genericize the hardcoded `.claude/rules/dynamic-workflows.md` cite in the emitted text | `HOOK_WORKFLOW_RESILIENCE_CHECK_ENABLED` | n/a (no telemetry; `additionalContext` only) | yes | yes (9 cases: when it speaks / stays silent) | **guardrails → ACCEPT** |
| `pr-prep-evidence-check` | **no** — concept is bound to medley workflow: shells out to `tools/work-artifacts/derive-slug.sh`, globs `.work/<slug>/review/*-pr-prep.md`, reads a `prepared_at_sha` frontmatter contract, cites medley skill paths | `HOOK_PR_PREP_EVIDENCE_CHECK_ENABLED` | n/a | yes | yes (26 cases, real git fixtures) | **DEFER — repo-owned** (see below) |

Both accepts cover **distinct** surfaces from the shipped `block-no-verify` (git-hook *disabling* via
`--no-verify`/`core.hooksPath`/`LEFTHOOK=`): `block-hook-bypass` guards Bash *file-write* bypass of
Write/Edit gates; `workflow-resilience-check` is a `Workflow`-tool burst-resilience advisory. Zero
coverage overlap.

## claude-ops candidates (10)

| Hook | Seam-clean | Kill-switch | Telemetry seam | Shared lib | Contract test | Target + verdict |
|---|---|---|---|---|---|---|
| `api-error-audit` | yes | `HOOK_API_ERROR_AUDIT_ENABLED` | **rewire** to envelope (today: direct store-write) | yes | yes | **claude-ops → ACCEPT** |
| `config-change-audit` | yes | `HOOK_CONFIG_CHANGE_AUDIT_ENABLED` | **rewire** to envelope | yes | yes | **claude-ops → ACCEPT** |
| `instructions-loaded-audit` | yes (carries an extra `…_LOG_SESSION_START` knob) | `HOOK_INSTRUCTIONS_LOADED_AUDIT_ENABLED` | **rewire** to envelope | yes | yes | **claude-ops → ACCEPT** |
| `permission-denied-audit` | yes (privacy-safe `Bash:<first-token>` subject) | `HOOK_PERMISSION_DENIED_AUDIT_ENABLED` | **rewire** to envelope (`status=blocked`) | yes | yes | **claude-ops → ACCEPT** |
| `pre-compact-audit` | yes | `HOOK_PRE_COMPACT_AUDIT_ENABLED` | **rewire** to envelope | yes | yes | **claude-ops → ACCEPT** |
| `tool-failure-audit` | yes (twin of permission-denied; privacy-safe subject) | `HOOK_TOOL_FAILURE_AUDIT_ENABLED` | **rewire** to envelope (`status=error`) | yes | yes | **claude-ops → ACCEPT** |
| `skill-usage-audit` | **outlier** — writes a bespoke second store `${repo}/.claude/observability/skill-usage.jsonl` via inline `flock`, in addition to the shared JSONL | `HOOK_SKILL_USAGE_AUDIT_ENABLED` | **rewire** to envelope **+ a `directory` `userConfig` seam** for the second store | yes | yes | **claude-ops → ACCEPT** (extra seam) |
| `hook-telemetry-sink` | n/a — this **is** the consumer sink (`HOOK_TELEMETRY_SINK` target), the envelope→JSONL adapter | ABSENT (governed by master `HOOK_OBSERVABILITY_LOG_ENABLED`) | n/a (terminus, not producer) | yes | yes | **DEFER — consumer-owned by design** |
| `cc-telemetry-ensure` | **no** — hardcodes `tools/observability/start-collector.sh`/`start-dashboard.sh`, DuckDB view names, Aspire ports/URL, medley slash-commands | `HOOK_CC_TELEMETRY_ENSURE_ENABLED` | n/a | yes | yes | **DEFER — repo-owned** |
| `session-reinjection` | **no** — payload is 100% medley content (rule paths, `PLAT001-PLAT015`, `Result<T>`, `BannedSymbols.txt`); not telemetry (only an incidental completion event) | `HOOK_SESSION_REINJECTION_ENABLED` | n/a | yes | yes | **DEFER — repo-owned** |

The seven `*-audit` hooks are one cohesive bulk-pattern unit: thin async advisory emitters over the
same `hook::emit_timed_event` path, all seam-clean at the behavior level, all `HOOK_<NAME>_ENABLED`
gated, all black-box tested. They share **one** migration seam — stop the direct
`.claude/observability/hook-events.jsonl` write and emit the envelope — plus per-hook `data` schemas
under `conventions/hook-telemetry/data/`. `skill-usage-audit` carries the lone extra seam.

## Deferred / repo-owned surfaces — decision record (2026-07-12)

Each deferred surface stays in `melodic-software/medley` with an explicit revisit trigger, so the
deferral is a decision, not a silent omission. The discriminator is **concept-specificity, not
path-count**: every candidate has repo paths today (all `source` a sibling `hook-utils.sh`); the
accepts have generic concepts that de-couple to seam-clean, while these de-couple into a *different*
parameterized tool or are consumer-owned by design.

- **`pr-prep-evidence-check`** (guardrails-nominated): its concept is medley PR-workflow enforcement
  bound to the `.work/<slug>/` artifact convention, `derive-slug.sh`, and the `prepared_at_sha`
  frontmatter contract. De-coupling produces a workflow-specific tool, not a universal guard.
  **Revisit trigger:** a second repo adopts the `.work/`-prep-evidence-before-PR convention → extract
  a generic prep-gate whose slug derivation, artifact glob, and freshness field are declared config.
- **`hook-telemetry-sink`**: the consumer sink the [envelope contract](conventions/hook-telemetry/README.md)
  "Mediator boundary" and the playbook's [Reintegration](MIGRATION-PLAYBOOK.md) ("keep the sink
  script — the bridge") say stays consumer-owned. It maps the envelope into medley's own store; it is
  not a producer to migrate. **Revisit trigger:** see the generic-sink gap below.
- **`cc-telemetry-ensure`**: medley OTEL-pipeline enablement — bound to `tools/observability/*`
  collector/dashboard scripts, DuckDB view names, and Aspire ports. `claude-ops` already owns
  collector-lifecycle scripts on the *read* side. **Revisit trigger:** `claude-ops` grows a
  SessionStart ensure-hook that drives **its own** bundled collector scripts through a store/collector
  `userConfig` seam.
- **`session-reinjection`**: post-compaction context reinjection whose entire payload is
  medley-specific prose. A generic version is a `userConfig`-templated content feature, not a
  migration. **Revisit trigger:** a second repo wants post-compact reinjection → build a
  content-templated hook reading a tracked file list, not this hook's baked content.

## Systemic gap — the generic sink

Migrating the `*-audit` producers to `claude-ops` completes only the **producer** half of the
telemetry contract. A fresh `claude-ops` consumer that enables the audit hooks emits envelopes into
the void: `claude-ops` ships no sink, and medley's `hook-telemetry-sink` is repo-owned by design.
This cuts against the playbook's "drop into any repo and work" intent. Keeping medley's sink
repo-owned is correct (per the mediator boundary); the gap is the **absence of a generic reference
sink**. Two candidate resolutions, to settle when the `*-audit` retrofit is scheduled:

1. `claude-ops` ships a reference sink (envelope→`${project}/.claude/observability/hook-events.jsonl`,
   the shape its observability skill already reads) that a consumer wires via `HOOK_TELEMETRY_SINK`.
2. The `*-audit` retrofit issue documents the sink-wiring requirement as a consumer setup step, and
   the sink stays consumer-authored.

Recommendation (1): a reference sink closes the loop and is the observability skill's natural
counterpart. The `*-audit` retrofit issue carries this decision; it also coordinates with the
`claude-ops` setup-action retrofit (`melodic-software/medley#1432`).

## Net-new retrofit issues emitted

One `retrofit(<target>)` issue per accepted **group**, sub-issue-linked under wave-2 map
`melodic-software/medley#1369`, `agent-ready`. These are **retrofit** issues (adding hooks to an
existing plugin), not cutover issues — no medley in-repo hook is removed here; the blue-green cutover
of each in-repo original follows on its own once the plugin hook ships and is verified.

| Group | Scope | Issue |
|---|---|---|
| guardrails hooks | Add `block-hook-bypass` + `workflow-resilience-check` (two independent, atomic PRs) — bundle `hook-utils.sh`, de-couple per the table, rewire `block-hook-bypass` telemetry to the envelope, ship `.test.sh` | `melodic-software/medley#1445` |
| claude-ops `*-audit` family | Migrate the seven-hook emitter family as one bulk unit — rewire the direct store-write to the `HOOK_TELEMETRY_SINK` envelope, add per-hook `data` schemas, add `skill-usage-audit`'s second-store `directory` seam, settle the generic-sink gap | `melodic-software/medley#1446` |
