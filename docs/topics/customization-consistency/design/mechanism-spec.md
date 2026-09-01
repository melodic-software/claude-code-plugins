# Candidate B — per-plugin retirement manifest + shared deterministic helper

Shape: each plugin that has ever retired a consumer-facing convention ships one structured manifest
(`retirements.yaml` at plugin root) recording every retirement it has ever made; one shared bash
helper (`lib/check-retirements.sh`, canonical at the marketplace repo root, materialized
byte-identical into each consuming plugin per the `parse-concern-value.sh` / `state-key.sh`
sync-and-registry precedent) evaluates that manifest against the consumer repo. Setup `check`
invokes the helper and reports its findings; setup `apply` gates cleanup per finding and uses the
helper for the mechanical deletions. The helper is dumb — it tests existence and pattern matches
and deletes exactly what a record names; every piece of knowledge (what was retired, when, where it
went, how to migrate) lives in the manifest.

## Manifest schema and location

`plugins/<plugin>/retirements.yaml` — referenced at runtime as
`${CLAUDE_PLUGIN_ROOT}/retirements.yaml`, so it ships inside the plugin and nothing lands in
consumer repos. Format: a deliberately constrained YAML subset — records separated by `---`, flat
scalar keys only, no nesting. Justification over JSON: the fleet's shared-lib doctrine is jq-free
by design ("the most common missing prerequisite is jq itself" — `lib/hook-utils.sh`), and the
flat-key quote-aware parse is an already-solved, already-tested problem (`parse-concern-value.sh`);
full-strength validation does not need a runtime parser because CI validates the file with a Node
schema check (`scripts/validate-plugin-contracts.mjs` precedent), where real YAML tooling exists.
YAML also diffs and reviews as prose, which suits an append-only history file.

Record fields: `id` (stable, `<plugin>-rNNN`, never reused), `retired` (date), `plugin_version`
(version that retired it), `kind` (`file` | `dir` | `line`), `path` (repo-relative path or glob,
validated: no absolute, no `..`, no `~` — the same validate-don't-trust posture as `state-key.sh`),
`match` (ERE, required for `line`), `content_match` (optional ERE for `file` — guards against a
consumer legitimately reusing the path for something else), `action` (`delete` | `remove-line` |
`migrate`), `successor` (prose: where the convention went and what to carry), `note` (one report
line). Append-only; records stay indefinitely by default (each costs one stat or grep), pruned only
when a path is deliberately re-adopted, with the prune recorded in the plugin CHANGELOG.

Realistic example — testing plugin retiring `.claude/testing/e2e.md` in favor of the consumer's
convention doc:

```yaml
---
id: testing-r001
retired: 2026-09-15
plugin_version: 0.9.0
kind: file
path: .claude/testing/e2e.md
content_match: '^##[[:space:]]*(recording|browser_mode)\b'
action: migrate
successor: "e2e conventions now live in the consumer's convention home (resolved from the AGENTS.md pointer line); carry the `recording` and `browser_mode` values into that doc's testing section, then clean"
note: "retired e2e config file; values move to the convention doc"
---
id: testing-r002
retired: 2026-09-15
plugin_version: 0.9.0
kind: line
path: .gitignore
match: '^\.claude/testing/e2e\.local\.md$'
action: remove-line
successor: "superseded by the recursive `.claude/**/*.local.*` line config-cascade recommends"
note: "narrow overlay gitignore line superseded"
```

## Helper CLI contract

`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest <path> [--root <repo>]` —
detection. Semantics per kind: `file` = path exists and (no `content_match` or it greps); `dir` =
directory exists; `line` = file exists and `match` greps. Output: one TSV row per leftover found —
`id \t kind \t path \t action \t note` — plus a human summary on stderr. Exit 0 = clean; 1 =
leftovers found; 2 = usage error, unreadable manifest, or an invalid record (a bad record fails the
whole run loudly — liveness-assertion doctrine, never a silent skip). Paths are emitted
repo-relative only, sidestepping the Git Bash → native path boundary (windows-path-emit).

`... --clean <id> [--i-migrated]` — cleanup of exactly one record's artifact: `delete` unlinks the
file/dir, `remove-line` deletes only matching lines (temp file + mv, unrelated content preserved).
A `migrate` record refuses `--clean` without `--i-migrated`, a cheap deterministic backstop; the
real gate is the skill's. Exit 0 cleaned, 1 nothing present, 2 error.

## Setup integration (no new verb)

Every setup `check` whose plugin ships a manifest adds one fixed step: run detection; exit 0 → one
PASS line; exit 1 → report each TSV row as a finding (severity from `action`: `migrate` FAIL,
others WARN) with remediation `apply`; exit 2 → visible FAIL, never silent. `apply` re-runs
detection after normal convergence, then per finding, individually gated by the user: `delete` /
`remove-line` → confirm, then `--clean <id>`, report what was removed; `migrate` → the model
carries content per the record's `successor` (convention prose from the consumer repo treated as
untrusted input), user confirms the migrated result, then `--clean <id> --i-migrated`. Re-run
detection last and report the final state — the evidence-bearing readback the setup contract
already requires. Repeated declines route to the finding-suppression convention rather than a new
consumer-side file.

## Uniformity across ~51 setups

Setups carry no logic — two fixed lines (the invocation and the reporting rule), whose canonical
text lives in a new owner doc `docs/conventions/retired-conventions/README.md` (convention-registry
row). Mechanical enforcement, both directions: CI fails when `retirements.yaml` exists but the
plugin's setup SKILL.md does not reference `check-retirements.sh` or the plugin lacks the synced
helper copy; and the helper is registered in `scripts/cross-plugin-source-registry.txt` with a
sync script and drift gate, so the 8 formerly-bespoke implementations cannot re-diverge — the exact
failure mode context-guard/rate-limit-guard's twin-but-drifted prose already exhibits. Plugins with
no retirements ship no manifest and add nothing: zero cost until first retirement.

## Versioning and window

The manifest is the plugin-owned retirement history the Brief requires, as a diffable artifact. New
helper behavior reaches consumers only via the ordinary plugin version bump (the only delivery
vehicle), and since detection re-runs on every future `check`, a consumer who skips ten versions
still gets every accumulated record evaluated — no window to miss. Record edits are defect fixes
only; retirement of a record is itself a changelog-recorded event.

## Failure modes and mitigations

- **No bash (PowerShell-only session):** the invocation is specified as a Bash-tool call, which
  Claude Code provides on Windows; if bash genuinely cannot run, `check` reports the retirement
  step UNKNOWN with remediation — degraded visibly, never green (liveness-assertion).
- **Path reuse false positive:** `content_match` fingerprints the old convention's content.
- **Malicious/broken manifest:** plugin-authored, but still path-validated (no traversal or
  absolute paths); consumer file content is only ever grep-matched, never executed.
- **jq absence:** irrelevant by construction — the runtime parse is the flat-key bash parser.
- **Glob explosion on huge repos:** kinds are all single-path or single-file greps; no repo walk.

## Effort

Mechanism PR: helper + `.test.sh` (shell-test-helpers convention) ~1 day; owner doc + registry row
~0.5 day; CI schema validator + wiring check + sync script ~1 day. Then one PR per plugin
converting the 8 bespoke implementations to manifests (~1–2 h each; guardrails' hook-rename
chaining stays bespoke — it is provisioning, not retirement detection). Roughly 3–4 focused days
plus the per-plugin PRs the Brief already budgets.

## Why this shape wins

The observed drift is knowledge drift wearing prose clothing: eight plugins each restated "what did
we retire and how do we detect it" in free text, and the twins diverged. Splitting knowledge
(manifest, schema-validated, diffable, append-only) from mechanism (one synced, tested,
deterministic script) puts each half where the repo already knows how to keep it honest — CI gates
code and schema; review gates records. Detection is exactly the work the fleet's own
script-the-deterministic-work discipline says never to leave to model judgment, while the genuinely
judgment-bearing step (carrying content to a successor) stays with the model, gated. Per-setup cost
is two fixed lines and zero always-loaded context; per-plugin adoption cost is one small YAML file;
and the manifest doubles as the retirement history the Brief demands, with no second artifact to
keep in sync.
