# Upstream sources the cutover check reads

Every upstream fact the AGENTS.md cutover turns on, as a four-part record: claim, basis, as-of date,
recheck trigger, per the
[upstream-drift convention](../../../../../docs/conventions/upstream-drift/README.md). The records
are here so a reader can judge the check's verdict without re-deriving the research, and so a
firing trigger has one place to land.

Per-run output (per-condition tables, graded commit SHAs) is posted as a comment on the tracker
issue. This file holds only the current grade of each fact: per the convention's "When a trigger
fires", refreshing a date with no verdict change is no entry and no version bump.

Every page below was fetched by the convention's rung-1 route (`curl` the `.md` to a file, search
the file locally), slug confirmed against `https://code.claude.com/docs/llms.txt`, and quoted from
the bytes rather than paraphrased.

## The remote flag, and how its code default is read

- **Claim**: reading `AGENTS.md` directly is gated on the GrowthBook flag `tengu_agents_md_mod`. In
  the shipped bundle the built-in plugin exports `isOnByDefault`, whose value is a minifier-assigned
  identifier declared once nearby as `!0` (true) or `!1` (false). In Claude Code 2.1.282 that
  identifier is `W` and the window around the second flag-string occurrence reads
  `isOnByDefault:()=>W` and `var W=!0;var B=()=>oi("tengu_agents_md_mod",W)`, so the **code
  default is true**. The first occurrence is a string in another window and does not tie to an
  `isOnByDefault` export.
- **Basis**: the installed bundle at `node_modules/@anthropic-ai/claude-code/bin/claude.exe`
  (`claude` on PATH), 2.1.282, sha256
  `3afe8535c0cc33f0e24f7b25dab7a1727b8b592196f8496a8bc302ba2161eed3`, read as bytes. The flag
  string occurs twice, at offsets 103001528 and 225456771. Only 225456771 is the code site.
  Offsets and the identifier are per build and per host, so the check resolves both at run time and
  hardcodes neither. `cutover-check.sh` on 2026-09-28 printed that same offset, identifier, and
  `var W=!0`.
- **As of**: 2026-09-28.
- **Recheck trigger**: any Claude Code version bump, a bundle where no window around the flag string
  carries `isOnByDefault`, or a window where the captured identifier resolves ambiguously. Each of
  those is `[UNREACH]` for the check, never `[MET]`.

## The documented feature-flag dependency

- **Claim**: `env-vars` still carries the section `## Features that need feature-flag fetching`.
  Fetching is still skipped for a session setting `DISABLE_GROWTHBOOK`, `DISABLE_TELEMETRY`,
  `DO_NOT_TRACK` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, a session on a third-party provider,
  and a Claude apps gateway session. The same page's subsection "First session after an install or
  upgrade" still states a flag-gated feature can be missing in that first session. The "With
  fetching off, you can't" list under that heading does not mention `AGENTS.md`. The page does not
  mention `AGENTS.md` at all.
- **Basis**: `https://code.claude.com/docs/en/env-vars.md`, fetched 2026-09-28, 507,134 bytes. The
  heading is at line 512, the list is lines 520-534, and "First session after an install or
  upgrade" is at line 536. A case-insensitive search of the file for `AGENTS.md` returned no line.
  The slug appears in `llms.txt` and the body's first heading is "Environment variables", so the
  page is the one requested. The same day's `cutover-check.sh` fetch reported the heading found
  and the AGENTS.md bullet absent.
- **As of**: 2026-09-28.
- **Recheck trigger**: the heading is renamed or removed, the page names `AGENTS.md` beside a flag
  again, or the AGENTS.md bullet returns to the list. A missing heading is `[UNREACH]` for the
  check, because the absence of a heading cannot be read as the absence of the dependency.

## The minimum CLI version

- **Claim**: Claude Code reads `AGENTS.md` as project instructions from **v2.1.277**, verbatim:
  "Reading `AGENTS.md` directly requires Claude Code v2.1.277 or later." The same page lists
  "You're on a Claude Code version before v2.1.277" among the cases where support is unavailable,
  and its removal procedure step 2 is "Run `claude --version` and confirm v2.1.277 or later."
  That step continues: "Before v2.1.281, some sessions, such as those on Amazon Bedrock or with
  telemetry disabled, couldn't load `AGENTS.md` either, so on those versions update to v2.1.281
  or later." Below v2.1.277 no session reads it, whatever the flag says. The Bedrock and
  telemetry-disabled gap is stated for versions before v2.1.281, not as a limit of v2.1.282.
- **Basis**: `https://code.claude.com/docs/en/memory.md`, fetched 2026-09-29 by the rung-1 route,
  49,601 bytes; the floor sentence is at line 352, the unavailable bullet at 402, and step 2 at
  578. The slug is in `llms.txt` and the first heading is "How Claude remembers your project".
- **As of**: 2026-09-29.
- **Recheck trigger**: the memory page states a different floor, or a release note moves it.

## `claude-code-action` release to installed CLI version

The pin in a workflow decides which CLI CI installs, and so whether CI can read `AGENTS.md` at all.
Each row was re-derived on 2026-09-28 by resolving the tag to its commit and reading
`base-action/action.yml` at that commit; none was copied forward. The four rows through
`v1.0.231` match the 2026-09-20 derivation. `v1.0.235` is new: it is the pin
`melodic-software/ci-workflows` carries on `main`.

| Release | Commit | `CLAUDE_CODE_VERSION` | At or above 2.1.277 |
|---|---|---|---|
| `v1.0.213` | `8251c103ac8c1d761882c86aba1412c7f583c844` | `2.1.258` | no |
| `v1.0.222` | `56cf60fde42f7b19c3abfd5c9c48b69a1288461f` | `2.1.269` | no |
| `v1.0.228` | `2261fcfc88e7de1b55f179edd588805e12de71f2` | `2.1.275` | no |
| `v1.0.231` | `cfc3eb22bfed5c26ef66e3223c982af27e4524de` | `2.1.278` | yes |
| `v1.0.235` | `756cc22e19660d20e8cc9496b4f242475a7f7790` | `2.1.283` | yes |

- **Claim**: the table above, and the general rule that the value is assigned in
  `base-action/action.yml` as a shell line `CLAUDE_CODE_VERSION="<version>"` immediately before the
  `Installing Claude Code v${CLAUDE_CODE_VERSION}...` echo (line 150 at all five commits).
- **Basis**: `gh api repos/anthropics/claude-code-action/commits/<tag>` for the commit, then
  `gh api repos/anthropics/claude-code-action/contents/base-action/action.yml?ref=<tag>`,
  re-read 2026-09-28 for every row in the table. `v1.0.235` is an annotated tag whose tag object
  `f33305702e43b9f71a532e6f80aed9a399df8288` points at commit
  `756cc22e19660d20e8cc9496b4f242475a7f7790`. That commit is the `uses:` pin in
  `melodic-software/ci-workflows` `b570d97203c7973b25c14e3de91c5ff3a4aa0e82`,
  `.github/workflows/claude-review.yml:167` and `.github/workflows/claude-security-review.yml:160`,
  both commented `# v1.0.235`.
- **As of**: 2026-09-28.
- **Recheck trigger**: a new pin appears in any in-scope repository, or the action stops assigning
  `CLAUDE_CODE_VERSION` in `base-action/action.yml`. A pin whose file carries no such assignment is
  `[UNREACH]`, never a pass: an unreadable map is not a satisfied floor.

## The CI canary

- **Claim**: on a GitHub-hosted `ubuntu-24.04` runner with a genuinely fresh install (no
  `~/.claude` before the first step), at action `v1.0.231` installing CLI 2.1.278, a workspace
  holding a lone non-empty `AGENTS.md` and no `CLAUDE.md` at any level returned the `AGENTS.md`
  canary token with zero tool calls, on the first session after the install and again on a second
  session in the same job. A `CLAUDE.md` carrying its own token suppressed the `AGENTS.md` one, the
  documented precedence. Separately, `claude-code-action` **rejects the `push` event**
  (`Unsupported event type: push`); the run was started by REST dispatch
  (`gh api -X POST repos/<owner>/<repo>/actions/workflows/<file>/dispatches -f ref=<branch>`).
- **Basis**: `melodic-software/knowledge-corpus` run `35475056935`, event `workflow_dispatch`, head
  SHA `91f0285b1ba2cc7329dff0f89dbbae020171a61b`; log lines quoted in the migration slice's
  `PROOF-ci-canary-knowledge-corpus-2026-09-19.md`. The event list is the action's own
  `src/github/context.ts` `parseGitHubContext` switch at the pinned commit.
- **As of**: 2026-09-19.
- **Recheck trigger**: a new action release, a new CLI floor, or a runner image change. The canary
  does not show **why** the flag-gated feature was available in that job, so a later regression
  would not contradict this record; it would replace it. The check never assumes this result: it
  parses the run id out of this record, prints it as the evidence behind condition 2, and exits 2
  if the record is not there to read.

## Canary host (#4282)

- **Claim**: the CI-canary component of cutover condition 2 rests on the knowledge-corpus run
  recorded in [The CI canary](#the-ci-canary). No canary run exists at `v1.0.235`. Which host runs a
  new canary, and whether one is required, is pending an owner decision on #4282.
- **Basis**: the maintainer comment on #4282 of 2026-09-19 (canary half passed, run
  `35475056935`) and the `v1.0.235` row in the release map above.
  `melodic-software/ci-workflows#599`, the pin half, closed COMPLETED 2026-09-20. On 2026-09-29,
  `gh repo view melodic-software/claude-lane-sandbox --json isArchived` returned
  `{"isArchived":true,"name":"claude-lane-sandbox"}`, and `git ls-remote --heads origin` in the
  knowledge-corpus tree returned only `refs/heads/main`, so the `test/agents-md-ci-canary` branch
  the 2026-09-19 comment described as left in place no longer exists.
- **As of**: 2026-09-29.
- **Recheck trigger**: the owner's decision on #4282, a new run id recorded in
  [The CI canary](#the-ci-canary), or a `claude-code-action` release newer than the pinned one.

## Current fleet grade

- **Claim**: `cutover-check.sh` graded every condition `[MET]` and printed
  `remove-shims may run`, over ten repositories with none unreadable: claude-code-plugins, medley,
  songwriting, claude-code-proxy, knowledge-corpus, codex-plugins, ci-runner, agent-plugins,
  cursor-plugins, and provisioning. Condition 1 is `[MET]` because the bundle code default for
  `tengu_agents_md_mod` is true. Condition 2 is `[MET]` on pin arithmetic, and provisional: the
  only pin in the ten is medley's `v1.0.231` (CLI 2.1.278), and the two ci-workflows pins, outside
  the ten, are `v1.0.235` (CLI 2.1.283), all at or above 2.1.277. Its CI-canary component rests on
  run `35475056935` at `v1.0.231` / CLI 2.1.278. [The CI canary](#the-ci-canary) recheck trigger,
  a new action release, has fired and the run was not replaced. Whether a re-run is required is an
  open owner decision on #4282 (see [Canary host](#canary-host-4282)). Condition 3 is `[MET]`:
  both `claude -p` legs returned the canary line from a lone non-empty `AGENTS.md`, and it grades
  only on a logged-in host. Condition 4 is `[MET]`: 70 path-detection rows, every one
  acknowledged with a reviewed reason.
- **Basis**: `cutover-check.sh`, no `--skip-canary`, over the ten repositories on 2026-09-29,
  Claude Code 2.1.284, exit 0. The trees were read as they stood and not fetched, so the grade is
  for those local commits, not for the current default branch. The per-repository commit table and the
  full per-condition output are in the comment on tracker issue #4281, not copied here.
- **As of**: 2026-09-29.
- **Recheck trigger**: a pin move in any in-scope repository, a Claude Code release whose
  changelog touches `AGENTS.md` or instruction-file loading, the monthly due date of
  `agents-md-cutover-check` in `.github/recurring-schedule.json`, or an in-scope repository
  becoming unreadable or readable.

## Install-dependent loader tests (#4283)

- **Claim**: empirical loader tests for Cursor, Grok Build, and Muse Code have not been run.
  Claims about those tools stay at docs or source grade.
- **Basis**: #4283's acceptance criteria are unmet and no run exists on main. The tools were not
  installed in the environment that did the migration research, an environment limit and not a
  decision. Whether and where to install them is pending an owner decision on #4283.
- **As of**: 2026-09-29.
- **Recheck trigger**: the owner's decision on #4283, or a host that records results for a named
  tool into this file.

## The canary recipe

Not restated here. The prompt shape, where the token goes, why the token is never committed, the
Codex leg, and the rollout check are in
[`reference/verification.md`](verification.md). Read that file before running any canary.

## What shim removal costs

This is the price of the cutover, and `remove-shims` prints it before it asks.

- **Claim**: `InstructionsLoaded` hooks **do not fire** for an `AGENTS.md` Claude reads directly
  through the Project instructions setting. hooks.md, verbatim: "This event doesn't fire when
  Claude reads `AGENTS.md` directly through the **Project instructions** setting. It does fire when
  a `CLAUDE.md` imports your `AGENTS.md`, with `load_reason` set to `include` as for any other
  imported file, and when `CLAUDE.md` is a symlink to it, as a normal `CLAUDE.md` load." The memory
  page's difference table says the same hook row as "Don't fire" for `AGENTS.md` read through the
  setting. Two further rows of that table: a directory added with `--add-dir` under
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` loads its `CLAUDE.md` and not its `AGENTS.md`, and
  an external `@path` import loads with no prompt only where external imports were already approved
  for that project. `/memory` **does** list a directly read `AGENTS.md` on the current page,
  verbatim: "To check whether Claude read your `AGENTS.md`, run `/memory` and look for its path in
  the list." The same page says "Before v2.1.280, `/memory` and `/context` didn't list an
  `AGENTS.md` that Claude read directly."
- **Basis**: `https://code.claude.com/docs/en/hooks.md`, "InstructionsLoaded" (246,601 bytes, the
  quoted paragraph at line 1290) and `https://code.claude.com/docs/en/memory.md`, "Where AGENTS.md
  differs from CLAUDE.md" (49,601 bytes, table at line 412) and "My AGENTS.md isn't loading" (lines
  581 and 583). Both fetched by the rung-1 route on 2026-09-29, both slugs present in `llms.txt`.
- **As of**: 2026-09-29.
- **Recheck trigger**: either page changes that table, that paragraph, or the `/memory` listing
  sentence.

## What the loss means for measuring the cutover

- **Claim**: `scripts/verify-load.sh` detects a load through an `InstructionsLoaded` hook, so it
  **cannot measure a directly read `AGENTS.md`**. Measured this session in a scratch directory under
  home holding only a non-empty `AGENTS.md` and a `README.md`: `verify-load.sh --trigger README.md
  --expect AGENTS.md` printed one `LOADED` row for the user-scope `~/.claude/CLAUDE.md` and then
  `EXPECTED AGENTS.md MISSING` / `VERDICT FAIL`, exit 1, while a headless `claude -p` run from the
  same directory with `--allowedTools Read`, reading `README.md` and asked to quote back the lines
  of its project instructions carrying the token, returned the token. So the file loaded and the
  instrument could not see it. `verify-load.sh` stays the right instrument for a **shimmed**
  surface, where the load arrives as an import and the hook fires with `load_reason` `include`.
- **Basis**: the run above on Claude Code 2.1.278, Windows, 2026-09-20; corroborated by the
  hooks.md quotation in the previous record.
- **As of**: 2026-09-20.
- **Recheck trigger**: `InstructionsLoaded` starts firing for a directly read `AGENTS.md`, or
  `verify-load.sh` gains a detection path that does not depend on that hook. Either one puts the
  two instruments back together.

## Page recheck of the hook gap

The 2026-09-20 measurement above was not repeated on this pass.

- **Claim**: hooks.md still says `InstructionsLoaded` does not fire for a directly read
  `AGENTS.md`, so `verify-load.sh` still cannot see that load. What changed is the `/memory`
  listing, recorded under [What shim removal costs](#what-shim-removal-costs): the memory page
  says that before v2.1.280 `/memory` and `/context` did not list a directly read `AGENTS.md`,
  and that the check now is to look for its path in `/memory`.
- **Basis**: the hooks.md and memory.md fetches in that cost record. This checkout's
  `claude auth status` reported `loggedIn` false, so no new `claude -p` measurement was possible.
- **As of**: 2026-09-28.
- **Recheck trigger**: the same as the measurement record above.
