# Claude Code "mods" — verified research hub

Single aligned report. Every later agent (planning interview, devil's advocate,
implementers) and the human maintainer reads this as ground truth.

## Pin

| Field | Value |
|---|---|
| Report date | 2026-09-19 |
| Claude Code under test | **2.1.278** (GitHub release `v2.1.278` published 2026-09-19T03:10:40Z; npm publish 2026-09-19T01:48:59Z; `latest` on npm and the newest repo tag) |
| `anthropics/claude-code` `mods/` | commit **`92ec78f2`**, `mods` subtree `c37231235cb1194d509d8c0b211f187ef93272fb` |
| Repo `main` at read time | **`bf7d404e`** — `mods/` is **unchanged** between the two; the one commit ahead touches `CHANGELOG.md` and `feed.xml` only |
| Declarations read | `mods/types/claude-code.d.ts`, 12,990 lines, first line `// Written by Claude Code 2.1.277.` |
| This repo's CLI pin | **2.1.276** on `origin/main` (2.1.268 on local `main`) |
| First `mods/` commit | `d9c456d7`, 2026-09-09T22:30:08Z; 83 commits at `92ec78f2`; proposal issue #91870 opened 2026-09-03 |

**Basis labels** on every claim: `OBSERVED` (run on 2.1.278 on this machine) ·
`SOURCE` (the `mods/` tree or the `.d.ts`) · `BINARY` (readable string or
export-map-anchored minified code in the shipped binary) · `STAFF` · `COMMUNITY`
· `INFERRED`. When lanes disagreed, the precedence applied was: **locally
observed behaviour on 2.1.278 > source tree / `.d.ts` > binary readable string >
staff statement > minified-code inference > community**. Where a lane's prose and
its own `VERIFICATION.md` disagreed, `VERIFICATION.md` won. No confidence a
verifier lowered has been raised here.

## What mods are, what is supported now, what is planned

1. A **mod** is an ordinary Claude Code plugin whose behaviour lives in one
   *hooks module*: a `register(on, options)` export registering hooks
   `($, e, next)` against engine events. `SOURCE`
2. Hooks nest as Express/Koa middleware over five tiers, outermost first:
   `prepend`, `user`, `append`, `builtin`, `core`. `next(e)` descends; `{ deny }`
   returned **instead of** `next(e)` refuses. `core` is a tier and the base of
   the fold (`.d.ts:9530`, `:9547`); a plugin seats only in the four
   `PluginTier` values `prepend | user | append | builtin` — why the CLI's
   invalid-tier error and a 2026-09-19 maintainer comment list four. `SOURCE` `OBSERVED`
3. Every capability (`fs`, `http`, `process`, `clock`, `ui`, …) is a `$` call, so
   all but one are hookable: `$.ui.ask` is declared with no `ui.ask` event and
   is the single asymmetry. There are no ambients: no `require`, no Node, no
   DOM, no ambient timers (`$.clock` provides them). `SOURCE`
4. The surface is real and shipping in 2.1.278: **92 statically-named events**
   (38 engine + 54 op), 33 `classic.*` bridge events, 19 `$` nouns. `SOURCE`
5. Four mods ship inside the binary — `sec-default`, `diff`, `telemetry`,
   `agents-md` — and `mods/` is their published source. AGENTS.md support in
   2.1.277 is `agents-md`. `SOURCE` `OBSERVED`
6. A mod **you** write is off by default: the GrowthBook rollout gate
   `tengu_plugin_hooks_modules` defaults `false`;
   `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` is a per-process override of it, so
   activation can also happen with no user action. Built-in mods use a separate
   predicate that never consults the flag. `BINARY` `OBSERVED` (that the gate's
   lookup is *server-side* is `INFERRED` from the binary's GrowthBook
   provenance strings; the remote lookup was not observed)
7. Authoring and testing work today: `claude plugin test`, `claude plugin
   validate`, `--plugin-dir`, `claude-code/testing` — verified green on
   Windows 11. `claude plugin test` is hidden from `--help` and unregistered
   without the flag. `/plugin-types` is named by `mods/README.md` as a slash
   command but was **never run end to end by any lane**. `OBSERVED`
8. **Nothing is documented.** Zero hits across all 197 pages of
   `code.claude.com/docs` and all 7,158 lines of `CHANGELOG.md`. `OBSERVED`
9. **Distribution is the blocker, not capability.** No marketplace listing, no
   signing change, and a consumer without the gate loads the module **silently
   not at all** — no warning, no stderr, nothing. `OBSERVED` `SOURCE` `STAFF`
10. Planned, stated by staff and undated: "shipping in N weeks" (self-dated
    2026-09-09 in an issue body edited in place; GitHub exposes no body-edit
    time, so the date is unverifiable from metadata), product name "Claude
    Mods", intent to migrate more built-in features to mod form, user-authored
    project-instruction mods. No GA date exists. `STAFF`

## Reading guide

Every sidecar sits beside this file. Read the hub, then one sidecar.

| Sidecar | One-line abstract | Read this when |
|---|---|---|
| [`research-what-mods-are.md`](research-what-mods-are.md) | Definition, the fold/chain model, the five tiers and seating, and exactly what a third-party (`user`-tier) mod may and may not do. | You need the mental model before anything else. |
| [`research-api-surface.md`](research-api-surface.md) | Event and noun counts, matcher forms, UI primitives per `RenderSurface`, options, limits, the static source scan, the one-module rule. | You are designing against the API and need to know what exists. |
| [`research-enablement-and-distribution.md`](research-enablement-and-distribution.md) | The two gates, silent-inert and silent-active, install path, marketplace absence, docs and changelog silence. | You are deciding whether a consumer could ever run this. |
| [`research-authoring-and-testing.md`](research-authoring-and-testing.md) | File layout, `claude plugin test`, the testing kit, `/plugin-types`, `--plugin-dir`, the patterns in `diff` and `agents-md`, Windows notes. | You are about to write or test a mod. |
| [`research-security-and-semantics.md`](research-security-and-semantics.md) | Deny, throw, overrun, the fail-open trap, `sec-default`, managed tiers, isolation, supply chain, issue #92533. | You are weighing a guard-shaped mod or the risk of shipping one. |
| [`research-surfaces.md`](research-surfaces.md) | Per-surface matrix: plugins vs mods, documented / demoed / unknown, for CLI, Desktop Code, Cowork, Chat, web, IDE, SDK. | You are asking "who would this reach?". |
| [`research-roadmap-and-staff-statements.md`](research-roadmap-and-staff-statements.md) | Verbatim dated staff quotes, stated plans, explicit non-goals, and what is this corpus's inference rather than a statement. | You need a quote, or need to know whether a "commitment" is one. |
| [`research-repo-fit.md`](research-repo-fit.md) | The maintainers' own adoption gate, hook counts and the max-shaped budget, the blind exec-form gate, `npm ci` placement, pilot candidate, ADR numbering, the per-repo-config conflict, the reusable-skill recommendation. | You are writing the decision, the ADR, or the plan. |
| [`research-contradictions-and-corrections.md`](research-contradictions-and-corrections.md) | Every claim that was wrong at some stage, its resolution, and what remains unresolved between lanes. | Before you assert anything that "sounds obvious". |
| [`research-recheck-triggers.md`](research-recheck-triggers.md) | What to re-verify, the exact command or URL for each, and a decay date per claim class. | The report is more than a few days old. |

## Top risks

1. **Silent-active.** The env var is an override (`??`) over a server-side gate.
   With the var unset, a rollout can activate hooks modules with no user action.
   A shipped mod can therefore run on an untested path. `BINARY` `COMMUNITY`
2. **Silent-inert.** Without the gate, a plugin's `hooks.json` is read, the
   plugin is discovered, and the module is skipped with no warning anywhere but
   `--debug`. An installed-and-enabled mod doing nothing is indistinguishable
   from a healthy one. `OBSERVED`
3. **Fail-open by default.** A hook that throws, overruns its 10 s budget, or
   returns a malformed shape is skipped and the chain beneath runs in its place.
   A guard without `.catch(() => ({ deny }))` is strictly weaker than the classic
   command hook it replaces. `OBSERVED` `SOURCE` `COMMUNITY` (throw and overrun
   observed locally; the malformed-shape arm is `.d.ts:3209-3211` plus one community measurement)
4. **Issue #92533.** Registering *any* `tool.call` hook on Bash breaks
   `Agent(isolation: "worktree")`; a passthrough `next(e)` is enough. OPEN,
   unacknowledged, independent Windows repro at 2.1.272. This repo uses worktree
   isolation. `COMMUNITY`
5. **Pre-contract API.** "May change between releases without notice"; a `$`
   affordance was renamed mid-thread and a public return type was loosened on
   day 9. Anything built now is pinned to a moving surface. `SOURCE` `STAFF`
6. **No distribution story.** Not marketplace-listed, no signing change, and no
   per-repository configuration channel (plugin options are never read from a
   project's `.claude/settings.json`). `SOURCE` `STAFF`

## Open unknowns

- Whether `tengu_plugin_hooks_modules` is on for any segment today. Checked:
  this machine (off). Unchecked: any other account, tier, or org.
- The identity of the two remaining minified predicates in
  `canLoadBuiltinHooksModules` (`kS`, `mg`), and therefore exactly what turns a
  **built-in** mod off. The `/plugin` toggle is the one settled off-switch.
- Whether any surface other than the terminal honours the gate. The gate itself
  reads no surface, host, or client type, but that is not an answer.
- Whether both layers of a `hooks.json` carrying `hooks` **and** `modules`
  reliably fire (issue #92675, OPEN, 0 comments).
- Performance. 50 µs p99 is a vendor claim about the dispatch primitive; 1.4 s
  is one community cold render. No independent benchmark exists.
- Whether a mod's in-process handler inherits the classic-hook restriction that
  hook scripts do not see `CLAUDE.md`.

## Decision inputs

Read beside this hub: `DEVILS-ADVOCATE.md` (ship-now /
Wait+spike / reusable-skill / incumbent verdicts, 8 interview questions),
`BLINDSPOTS.md` (13 ranked blindspot cards, experiment-only
gaps), `VERIFICATION.md` (synthesis faithfulness, 2026-09-19).

**Verification:** 149 claims graded — 141 FAITHFUL, 7 STRONGER-THAN-EVIDENCE, 1 WRONG.

## Lane directories

Primary material, each with its own `VERIFICATION.md`. Where a lane's prose and
its `VERIFICATION.md` disagree, `VERIFICATION.md` wins.

| Lane | What it holds |
|---|---|
| `repo-primary/` | The spec, read off the `mods/` source tree and the 2.1.278 binary. 74 verified rows. |
| `official-docs-changelog/` | Docs and changelog silence, the gate, and a live-session `--plugin-dir` load probe. |
| `x-threads/` | Verbatim staff statements from X and issue #91870, re-fetched and graded. |
| `community-falsification/` | Field evidence, failure reports, supply chain, and the missed risk M1. |
| `surfaces-desktop/` | CLI vs Desktop Code / Cowork / Chat / web / IDE / SDK. |
| `plugins-repo-explore/` | This repository's own landscape, gates, and hook fleet. |
| `architecture-pdf/` | The 10-page Anthropic design PDF extraction, and the deny/error semantics that supersede part of it. |
