# Defer Claude Code mods, with five go criteria and two recheck triggers

- Status: accepted
- Date: 2026-09-19

## Context

A **mod** is an ordinary Claude Code plugin whose behaviour lives in one *hooks module*: a
`register(on, options)` export that hooks engine events as functions `($, e, next)`, nested
Express-style over five tiers (`prepend`, `user`, `append`, `builtin`, `core`), with every
capability reached through `$` because the module gets no ambients. Four such mods ship inside the
2.1.278 binary (`sec-default`, `diff`, `telemetry`, `agents-md`) and `anthropics/claude-code`'s
`mods/` tree is their published source, but a mod **you** write is off by default and the feature is
named nowhere in the official documentation or the changelog.

## Decision

**Defer.** Claude Code mods are not adopted, and no plugin under `plugins/` gains a `modules` key or
depends on `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`. Defer rather than decline, in the sense
[0020-defer-three-medley-surfaces-with-explicit-recheck-triggers.md](0020-defer-three-medley-surfaces-with-explicit-recheck-triggers.md)
uses it: the question stays open behind an explicit trigger instead of being closed or silently
dropped. The surface fails the Native-first gate's second test ("is stable and works cleanly") and
stops there, on Anthropic's own wording — `mods/README.md` says the interface "may change between
releases without notice" (`SOURCE`).

**Converting this repository's guard hooks to mods is off the table** until all three hold:
issue [anthropics/claude-code#92533](https://github.com/anthropics/claude-code/issues/92533) is
fixed, Anthropic settles throw and timeout semantics, and mods leave early access. The three are
conjunctive because each removes a different defect. #92533 is that registering *any* `tool.call`
hook on Bash — a pure passthrough `next(e)` suffices — breaks `Agent(isolation: "worktree")`, the
isolation this repository's own worktree flow uses; it is OPEN, filed 2026-09-06, with one
independent Windows reproduction in the thread, a second Windows reproduction run here on 2026-09-19
at 2.1.278, and no staff reply (`COMMUNITY` `OBSERVED`). Throw and timeout semantics are fail-open:
a hook that throws, overruns its 10 s `HookBudget`, or answers a wrong shape is skipped and the chain
beneath runs in its place, so a guard without `.catch(() => ({ deny }))` is strictly weaker than the
classic command hook it would replace (`SOURCE` `OBSERVED`). That mechanism *is* stated, in the
generated `mods/types/claude-code.d.ts` JSDoc — the per-event doc and `Registration.catch` both say
it (`SOURCE`) — so it is documented inside the early-access tree, under the same "may change without
notice" warning, and nowhere on `code.claude.com`. What is genuinely unsettled is the engine's
*default* on an uncaught throw: the maintainer's position moved four times across #91870 between
2026-09-03 and 2026-09-08 and landed on "construct fail-closed yourself" rather than on a default
(`STAFF`).

**No CI or script enforcement of this stance.** `scripts/check-hook-exec-form.sh` is unchanged. The
check was considered and rejected as overengineering; this record and the "Recorded gate runs" row
are the stance. Revisit only if a `modules` key ever ships by accident. Note the standing
consequence either way — that gate selects hook objects satisfying both
`has("command")` and `has("args")`, and a hook entry naming a TypeScript module carries neither, so a
mod-shaped `hooks.json` passes it vacuously.

**A throwaway spike is authorised, and stays under `.work/`.** It runs on Claude Code 2.1.278 with
the version recorded per observation, closes six locally answerable unknowns (whether a `hooks.json`
carrying both `hooks` and `modules` fires both layers, #92533 against this repository's own worktree
flow, `/plugin-types` end to end, `claude plugin validate` on a mod-shaped manifest, whether a
handler sees `CLAUDE.md`, and one latency measurement), and ships nothing. A `Wait`-shaped stance is
itself a shipping prohibition, so `.work/` is the only place a spike can live. The Claude Code pin
in `package.json` is not changed by this work.

**No reusable feature-deep-dive skill is built.** Five of the six steps in this deep dive were
already owned by existing skills; the one unowned step is arbitration into the philosophy tables.
A dated run record of the procedure is written instead, and the skill decision is taken on the
second or third example, following the default-REJECT posture of
[0021-reject-the-three-unused-official-plugin-components.md](0021-reject-the-three-unused-official-plugin-components.md).

## The five go criteria

All five must hold. Any one failing is no-go. Exact commands and their 2026-09-19 outputs are in
[go-no-go.md](../upstream/claude-code-mods/go-no-go.md); the recorded experiments behind them are in
[experiments.md](../upstream/claude-code-mods/experiments.md).

1. A test mod loads with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` unset.
2. The official documentation mentions the feature.
3. Issue [#92533](https://github.com/anthropics/claude-code/issues/92533) is closed.
4. Anthropic's official documentation states the throw and timeout semantics, and the engine's
   default on an uncaught throw is settled upstream. The generated `.d.ts` JSDoc already states the
   mechanism, so a JSDoc hit does not meet this.
5. The "may change between releases without notice" warning is gone from `mods/README.md`.

Criterion 1 is the only one that answers the question consumers actually face, because the enable
variable is an override (`??`) over a rollout gate named `tengu_plugin_hooks_modules` whose default
is `false` (`BINARY`); that the gate's lookup is server-side is `INFERRED` from the binary's
GrowthBook provenance strings, not observed. Criteria 2 and 5 are first-mention detectors, never
availability checks: `/diff` and AGENTS.md are documented features whose implementations are mods
and whose documentation never names the mechanism.

## Recheck triggers

- **Any pull request bumping the `@anthropic-ai/claude-code` pin in `package.json`** runs criteria
  1 to 3, the quick check, owned by whoever bumps the pin.
- **On demand** runs the full runbook: all five criteria plus the recorded experiments.

No calendar date is set. A standing rule governs both runs: a readiness check based on
`claude plugin --help` or on a documentation grep returns a **false negative**. `claude plugin test`
is a working but hidden, gate-registered command, and the documentation has never named the feature.
Probe behaviour, not help text.

## Consequences

- The stance rests on review, not on a gate. `scripts/check-hook-exec-form.sh` reports a clean tree
  over a `modules` key, so a mod arriving by accident is caught by a reader, not by CI.
- No `Wait` row is added to "Component stances", so the migration playbook's step 7 ("wait-listed
  components absent") does not bind here. The binding constraint is the plain one recorded above:
  while mods are deferred, nothing under `plugins/` depends on `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`.
- A performance argument for mods does not survive this repository's hook budget, which is
  max-shaped: Claude Code runs matching hooks in parallel, so removing cost from every hook except
  the slowest moves the budgeted wall by zero
  ([docs/conventions/hook-budget/README.md](../conventions/hook-budget/README.md)). Only replacing
  the `guardrails` dispatcher would move it, and `guardrails` is Class A under
  [0028-classify-a-plugin-s-hooks-by-packaging-before-proposing-a-split.md](0028-classify-a-plugin-s-hooks-by-packaging-before-proposing-a-split.md),
  which never splits.
- Mods cannot take per-repository configuration: a project's `.claude/settings.json` is not read for
  plugin options (`SOURCE`), so the extensibility contract's first seam has no path here. That
  misfit is structural and survives every version bump until upstream changes it.
- The built-in `agents-md` mod has no effect on this repository. All six `AGENTS.md` files have a
  `CLAUDE.md` beside them, and the default mode `claude-md-or-agents-md` loads none of them
  (`SOURCE`).
- **#92533 reproduces here.** 2026-09-19 at 2.1.278 on Windows: a mod whose only `tool.call` hook is
  a bare `next(e)` matched to Bash left every shell exec inside an agent worktree refused, against an
  otherwise identical control that ran the same command (`OBSERVED`). The parent session's cwd did
  not move, so the report's `EnterWorktree` recovery path stays untested. Commands:
  [experiments.md](../upstream/claude-code-mods/experiments.md), experiment E2.
- **A third-party mod is a data-exposure surface, not only a behaviour one.** Same date and version:
  one `prompt.context` hook received the full text of every instruction file, including the user's
  private global `CLAUDE.md`, plus the account email block, on the first prompt of the session and
  before the model was called (`OBSERVED`). Any review posture for a mod written elsewhere starts
  there.
- One probe stays open and one is now partly answered. No Team or Enterprise account was available
  for a rollout-switch probe, so the rollout-switch question stays unanswered; revisit it if such an
  account becomes available. **Claude Desktop loads a user-authored mod.** 2026-09-19 on Windows 11,
  Desktop build `app-2.2553.1` whose bundled Claude Code is 2.1.275: a probe plugin installed at user
  scope, with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1` supplied to the app process only, fired its
  `session.start` hook in a local Code tab session (`OBSERVED`). That the flag is what enabled it is
  `INFERRED` — the flag-unset arm was not run in Desktop. Still untested: that unset arm, cloud
  sessions, Cowork, and mods that draw UI. Commands and the exact route:
  [experiments.md](../upstream/claude-code-mods/experiments.md), under the Desktop probe. None of
  this moves the verdict: Desktop loading is in no go criterion.

## Links

The evidence trail, the runbook, and the cited source index live in
[docs/upstream/claude-code-mods/](../upstream/claude-code-mods/), beside this repository's other
records about external upstream sources. Read that folder's `README.md` for the reading order. Its
file names follow
[0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md](0034-name-docs-files-lower-kebab-case-with-conventional-exceptions.md).
The raw per-lane research stayed machine-local; only the verified synthesis is committed, as a dated
snapshot. ADRs are cited here by full filename because `0018`, `0025`, and `0028` each name two
records.
