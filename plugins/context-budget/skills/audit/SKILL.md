---
description: "Measure a Claude Code session's fixed startup context payload per item, on this machine at a pinned binary — including per-tool attribution of the built-in tool pools that /context reports only as lump sums, derived live by A/B deny differencing, with a per-project before/after ledger for every lever toggled. Reports only measured numbers; ships none. Use when: 'what is eating my context window at startup', 'measure my startup payload', 'which built-in tools cost the most', 'what would denying this tool save', 'context budget audit', 'baseline my context before trimming', 'did that settings change actually save tokens'. Read-only — measures and reports; changes no configuration."
argument-hint: "[--full-sweep] every live tool | [--tools T1,T2] chosen tools | [--ledger] history"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Measure the startup context payload per item and ledger every lever's real delta
---

## Purpose

`/context` itemises skills, agents, and MCP tools natively — for those, run it and read the tables.
What it structurally cannot itemise is the built-in tool pool: `System tools` and
`System tools (deferred)` are lump sums, and together they are typically the largest single
contributor to the fixed startup payload. This skill measures that attribution on the consumer's
own machine by A/B differencing — a baseline session versus one session per candidate tool with
that tool denied by bare name — which is compositional (deltas add), so a basket of trims can be
priced from its members.

Two rules govern everything this skill says, per the plugin's
[`reference/engine.md`](reference/engine.md):

1. **Only measured numbers are reported.** No token figure, tool inventory, or threshold ships in
   this skill; values drift with every CLI release. If a number was not produced by a run on this
   machine in this audit, it is not stated.
2. **Every report is stamped** with the measured binary path and version, the measurement mode
   (`sdk` exact vs `cli-parse` display-rounded), and the session kind (headless). Machines with
   two CLI installs produce different answers per binary; the stamp is what makes the answer a
   claim instead of a guess.

## Scope boundary (route out)

- Unused skills/plugins/MCP servers by usage history → the bundled `/doctor` (it is
  `disableModelInvocation: true`, so tell the operator to run it themselves; never reimplement
  its checks).
- Per-skill / per-agent / per-MCP-tool attribution → `/context` natively.
- Live in-session occupancy over time → the `context-guard` plugin, if installed.
- Settings correctness, permission-rule state → the `claude-config` plugin, if installed.

## Declared scope

This skill measures **the local Claude Code CLI, in a headless session**. On cloud or web surfaces
(where the container's binary and settings are not the operator's own), the numbers describe the
container, not the operator's machine — say so in the report. Interactive sessions can differ from
headless ones (deferral eligibility is partly server-decided); the stamp's `sessionKind: headless`
is the honest boundary of the claim.

## Prerequisites

- `node` — required for correctness. Absent: stop and report the gap; do not estimate.
- The Claude Code CLI (`claude` on PATH, or a `--binary` path the operator names).
- `@anthropic-ai/claude-agent-sdk` — required for exact mode only. Absent, the engine degrades to
  parsing headless `/context` output (display-rounded, and undocumented as a `-p` surface — the
  record carries both caveats). To enable exact mode, offer the operator this one-time install
  into the plugin's own data directory (network access; their call):

  ```shell
  mkdir -p "${CLAUDE_PLUGIN_DATA}/sdk" && npm install --prefix "${CLAUDE_PLUGIN_DATA}/sdk" @anthropic-ai/claude-agent-sdk
  ```

## Workflow

### 1. Derive the per-project data directory

```shell
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

The audit's artifacts live under `${CLAUDE_PLUGIN_DATA}/audit/<state-key>/` — keyed by project so
one machine's many checkouts never share a ledger. Pass this resolved absolute path wherever
`<data-dir>` appears below. Note near the ledger that uninstalling the plugin from its last scope
deletes this directory unless `--keep-data` is passed.

### 2. Take the baseline snapshot

```shell
node "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs" snapshot \
  --sdk-dir "${CLAUDE_PLUGIN_DATA}/sdk" --out <data-dir>/baseline.json
```

Each measurement spawns a short-lived headless session against the pinned binary (the `/context`
prompt is handled by the CLI itself, so no model API call is made) and records: per-category
tokens, the live tool list, per-agent tokens, the skill-listing signature, and the binary stamp.
Exit 3 means measurement is unavailable — the JSON record names the remediation; relay it and
stop. Never substitute an estimate.

### 3. Attribute the built-in tool pools

Candidates come from the **live tool list in the baseline record** (`tools`) — never from a
memorised inventory. Ask the operator (or take from arguments) which to measure:

- A **chosen set** (fast; one ~5–60 s run per tool):

  ```shell
  node "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs" attribute \
    --tools <T1,T2,...> --verify-additivity --sdk-dir "${CLAUDE_PLUGIN_DATA}/sdk" \
    --out <data-dir>/attribution.json
  ```

- The **full sweep** (`--tools from-baseline`) prices every live tool; warn that it is one run per
  tool and let the operator opt in.

Report the ranked `perTool` table with the binary stamp, and each row's `comparable` flag: a row
the engine marked incomparable (skill listing shifted, version changed mid-run) is reported as
such, not as a number. Note which bucket moved — a deny that empties a *deferred* tool's schema
reduces request weight without changing the context-usage headline, so present `prefixDelta` and
`deferredDelta` separately, never merged into one figure.

### 4. Present levers from the catalogue

Levers come from the catalogue at
[`${CLAUDE_PLUGIN_ROOT}/skills/audit/reference/levers.json`](reference/levers.json) — data rows,
each carrying its honesty category, category basis, posture, detection, measurement route,
emitted config, official citations, verified date, and recheck trigger. Rules, from the
catalogue's own meta:

- **Every lever presented carries its category and at least one official citation.** A lever
  whose category cannot be determined for this consumer's configuration is not offered.
- **Resolve conditions by measurement, not assumption.** A row whose `conditions` names a
  configuration dependency (cap saturation, model default, surface) is measured here before its
  category is asserted — a condition-dependent lever presented without resolving the condition is
  the exact failure this plugin exists to prevent.
- **Respect postures.** `never-recommend` rows (net-negative) are disclosed with their price,
  never offered as actions; `disclose-only` rows are explained, not pushed; `report-only` rows
  (vendor weight) appear as the honest unaddressable floor.
- **Honor recheck triggers.** A row whose trigger has plausibly fired (version jump past the
  catalogue's `verifiedAgainst`, upstream page moved) is re-verified against a fresh fetch of its
  citations before being offered — and a measured result always outranks the catalogue's stored
  expectation.
- **Keep the two ledgers apart** (the catalogue's `dualLedger` note): context-window occupancy
  versus per-request weight. Deferral moves weight between them; only removal clears both.

### 5. Ledger any before/after the operator produces

When the operator toggles a lever (a `permissions.deny` entry, a settings change) and wants the
real delta: re-run the snapshot, then

```shell
node "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs" compare \
  --before <data-dir>/baseline.json --after <after.json> \
  --lever "<what changed>" --emitted-config "<the exact config text>" --out <row.json>
node "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/measure.mjs" ledger --append <row.json> --dir <data-dir>
```

The ledger keeps one file per run plus an appended history line, so a same-day rerun never erases
an earlier point. `--ledger` in the arguments means: list the history (`ledger --list`) and report
it.

## Reading the numbers honestly

- **A scoped deny saves nothing.** Only a bare tool name removes a schema from the request; a
  scoped rule is a runtime guard whose schema still ships. Citations in
  [`reference/engine.md`](reference/engine.md).
- **A deferred tool is out of the context window but still in every request.** Do not present the
  deferred bucket as already-saved weight.
- **`System tools` deltas are valid only between runs with identical skill listings** — the engine
  enforces this via the listing signature; relay its verdict rather than overriding it.
- **Zero is a finding.** A lever that measures zero here is reported as measuring zero here, at
  this version — not as broken, and not silently dropped.

## Gotchas

Observed failures, each of which produced a confidently wrong number before the engine guarded it:

- **Removing skills makes `System tools` rise.** Listed skill-frontmatter tokens are subtracted
  from that bucket, so a run that changes the skill listing shifts `System tools` with no tool
  changing state — this once misread a safe-mode run as "safe mode loads deferred tools". The
  signature check exists because of it; never hand-compare two snapshots the engine marked
  incomparable.
- **Unredirected stdin prepends a warning line** to headless output, which breaks naive parsing.
  The engine redirects and strips; if you capture `/context` by hand for `parse-context`, redirect
  stdin or expect the leading line.
- **Two CLI installs on one machine answer differently** — category lists differ across versions.
  The stamp is the guard; when the operator's interactive `claude` is not the binary on PATH, ask
  which to pin with `--binary`.
- **The measured machine's numbers are not this repo's research numbers.** Never quote a figure
  from any document — including this plugin's own development history — as if it were the
  consumer's; the drift is the whole reason the engine exists.

## Report-only

This skill changes no configuration. When a measured result suggests a trim, print the exact
config the operator would apply (for persistent denies: a `permissions.deny` entry — there is no
`disallowedTools` settings key) and let them apply it; offer the ledger loop above to verify the
result. A guided fix path is planned as a separate, explicitly-invoked override and does not exist
in this version.
