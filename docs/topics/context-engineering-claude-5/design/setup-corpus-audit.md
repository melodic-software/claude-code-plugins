---
outcome: audited
tier: B
date: 2026-07-24
---

# Phase 7 — the setup-skill corpus against its owner doc

Task #29, **reclassified before it ran.** The original framing — extract a new SSOT across the
`setup` skills — is plugin-form-illegal: any single home is either a repo-level doc unreachable from
an installed plugin's cache, or a sibling-plugin file the design boundary forbids. The shared thing
is the *shape*, and the shape already has an owner: `docs/PLUGIN-PHILOSOPHY.md`, "Setup is explicit
and repeatable". This is a conformance audit against that owner doc, not a second source.

Audited at `cbf27e88a9` by a fenced read-only worker. **43 setup skills across 60 plugins.**

## Result

**41 conforming, 2 partial, 0 fully non-conforming.** Every one of the 43 passes the naming and
`disable-model-invocation: true` requirements, and every one is a single plugin-level skill at
`plugins/<plugin>/skills/setup` — no per-skill setup exists anywhere in the tree.

The two partials:

- **`github` — misses the state-assessing `apply` contract.** Its `apply` says it "never blindly
  rewrites" and carries an idempotency check, but two clauses have no line to cite: nothing
  preserves keys it does not recognize, and nothing reports rather than silently rewrites a value it
  cannot reconcile. `discovery`'s setup is the model — "Offer every schema key and preserve every key
  an existing file carries — a re-run never drops one."
- **`rate-limit-guard` — claims the check-only carve-out without its premise.** The carve-out
  requires that native `userConfig` is the *entire* configuration surface. Its statusline wiring
  lives in the user's own `settings.json` — neither `userConfig` nor tracked project config — and the
  skill itself frames that as configuration it must not write.

## The finding that is an owner-doc gap, not a plugin defect

`context-guard` and `rate-limit-guard` have the **same** configuration shape: the user's own
`settings.json` plus a plugin-owned machine file. They resolved it two different ways — a
narrow-write `apply` scoped to `zones.json` versus a check-only setup — and the owner doc sanctions
neither, because its carve-out is written only for a surface that is nothing but `userConfig`.
`context-guard`'s manifest `userConfig` is `null`, so it never had a carve-out to claim and correctly
offers the narrow `apply`; `rate-limit-guard` claimed one it does not qualify for. One shape, two
resolutions, no doctrine — that is a gap in the doc, and fixing the doc fixes both plugins.

A second gap: **"non-trivial `userConfig`" is used by the requirement gate and never defined.** Three
plugins without a setup skill turn entirely on it — `education`, `repo-hygiene`, `visualization` —
and their `userConfig` shapes are indistinguishable from those of plugins that *do* ship one
(a directory key like `bug-report.output_dir`, a boolean kill switch like `disk_hygiene_enabled`, a
defaulted string enum like `planning.use_ask_user_question`). On the fleet's operative reading all
three meet the gate and lack the skill; on the doc's literal text the question is unanswerable.
Grading them against what the fleet happens to do would quietly move the audit's owner from the doc
to the corpus, so they are reported undetermined and the definition is the fix.

## Duplication

Verified by byte-identity on raw line ranges, not by similarity scoring.

**One block worth a decision: 61 lines shared by `discovery` and `verification`'s setup skills** —
about two thirds of each file, spanning the whole `check`, `apply`, and `Output` bodies. Both
implement the same topic-docs concern, so this is convergent implementation of one shared seam
rather than accidental copy-paste, which is what makes extraction plausible.

**It cannot ride the existing cluster registry as-is.** `scripts/cross-plugin-source-registry.txt`
documents "one path-within-plugin per line" and all three of its entries are whole files. A fragment
inside a `SKILL.md` is not registrable. Two options: extract the shared body to a per-plugin
`reference/topic-docs-setup.md` that each `SKILL.md` points at — making it a whole file and
registrable under the sanctioned mechanism — or leave it duplicated and accept the drift.

Two further blocks of 11–13 lines (`biome-format`/`ruff-format`, `actionlint`/`powershell-format`)
cost more to extract than they save. Left alone deliberately.

## Design-boundary check

**No setup skill reads or discovers a sibling plugin's files.** The per-plugin-by-construction claim
holds at the tier that matters. Two near-misses were checked and cleared: `songwriting` and
`source-control` both use `../../` from `skills/setup/`, which resolves to their own plugin root.

Three lower-tier findings are real and ranked below:

- **A repo-level doc cited from inside a plugin**, which does not resolve from an installed plugin's
  cache — `context-guard` and `rate-limit-guard` both cite `docs/PLUGIN-PHILOSOPHY.md`.
- **A hardcoded publisher and repository name in a runtime-consulted URL** — `discovery` and
  `verification` both fetch a schema from `raw.githubusercontent.com/melodic-software/...`.
- **A hardcoded platform-internal path where an anchor exists** — `machine-health` writes
  `$HOME/.claude/plugins/data/machine-health` rather than using `${CLAUDE_PLUGIN_DATA}`.

## Exception list — legitimately check-only

Four skills offer `check` only and conform under the carve-out. Premises were settled from each
plugin's manifest, not from the skill's own prose about itself, because a file asserting its own
conformance is not evidence.

| Plugin | Why it qualifies |
|---|---|
| `bug-report` | one optional non-sensitive directory key; no MCP, hooks, scripts, or bin |
| `dometrain` | one sensitive key collected natively; a remote MCP server, so no prerequisite `apply` could resolve |
| `miro` | same shape as `dometrain`, with a bundled server |
| `re-anchor` | four non-sensitive defaulted string keys; nothing else |

`dometrain` and `miro` hold *despite* a service-plus-credential prerequisite, because the credential
is collected through Claude Code's native prompt and the server is remote or bundled — precisely
what the carve-out's third clause permits.

The formatter and linter plugins whose `apply` is guidance-only with no write path are measured
against the thin check-centric requirement rather than the converging-`apply` one. All conform.

## Teardown trigger — checked, not fired

The owner doc says a *second* plugin needing teardown graduates a shared teardown shape into an owner
doc before that second adopter. There is one adopter: `songwriting`'s `apply remove <name>`, deleting
plugin-owned template overrides. `machine-health`'s inventory mutations are ordinary `apply` surface
by the doc's own distinction. The graduation step is not yet owed.

## What the evidence cannot reach

The manifest has **no field for declaring an external prerequisite**, and a consumer-project
configuration surface is not manifest-visible at all. So the "should this plugin have a setup skill"
direction is gradable through proxies (`mcpServers`, `hooks.json`, `scripts/`, `bin/`), while the
"should this plugin *not* have one" direction is not — 15 of the 43 rest their gate entirely on the
invisible criterion. That is a bound on the audit, recorded rather than papered over. One plugin,
`prototype`, is reported undetermined for the same reason: it ships a detect-ecosystems script whose
external needs are not manifest-visible.

## Ranked fixes

Owner-doc first, because two plugin-level findings dissolve once the doc is fixed.

1. Widen the carve-out so it admits a configuration surface that is neither `userConfig` nor tracked
   project config and that `apply` must not write. Resolves `context-guard` and `rate-limit-guard`
   together.
2. Define "non-trivial `userConfig`". Resolves `education`, `repo-hygiene`, and `visualization` at
   once.
3. `rate-limit-guard` — replace the carve-out claim with the accurate reason, pending fix 1.
4. `discovery` + `verification` — decide the 61-line block: extract and register, or accept drift.
5. `github` — add the two missing `apply` clauses.
6. `ai-briefing` — document the reconfiguration path for its `userConfig` key.
7. `session-flow`, `rate-limit-guard` — add the headless `--config` note beside the existing
   `/plugin configure` guidance.
8. `context-guard` — rename the `apply reset` argument so it stops colliding with the token the doc
   defines as teardown-plus-apply.
9. `discovery` + `verification` — make the schema URL publisher-neutral.
10. `context-guard` + `rate-limit-guard` — drop the repo-level doc citation that cannot resolve from
    an installed cache.
11. `machine-health` — use the data-directory anchor instead of a hardcoded home path.

**Sanity Check — passes.** Every `plugins/*/skills/setup/SKILL.md` is graded above: 41 conforming,
2 partial with the missed requirement named, 4 in the exception list with reasons, and the
undetermined cases named with the reason the evidence cannot reach them. No fragment was promoted to
a shared cluster, so no registry entry or drift check is owed.
