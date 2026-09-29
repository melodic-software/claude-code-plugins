# Upstream sources the cutover check reads

Every upstream fact the AGENTS.md cutover turns on, as a four-part record: claim, basis, as-of date,
recheck trigger, per the
[upstream-drift convention](../../../../../docs/conventions/upstream-drift/README.md). The records
are here so a reader can judge the check's verdict without re-deriving the research, and so a
firing trigger has one place to land.

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

## Canary host decision (#4282)

**Decision.** Do not unarchive `melodic-software/claude-lane-sandbox`. Do not add
the canary workflow to this marketplace repository. Do not create a throwaway
host from this checkout.

- **Option A (taken):** cutover condition 2's CI-canary component continues to
  rest on the knowledge-corpus record in [The CI canary](#the-ci-canary). The
  two-pin three-case matrix named in #4282 (repo pin `v1.0.222` vs latest pin
  `v1.0.231`, cases A/B/C) is not built here.
- **Option B (declined here):** unarchive the sandbox, or stand up a new private
  throwaway with an org-visible Anthropic secret, and run that matrix. That
  remains a maintainer action in a repository they choose.

- **Claim:** this marketplace does not host the #4282 canary infrastructure;
  condition 2 stays on the existing knowledge-corpus run id until a maintainer
  records a replacement run in [The CI canary](#the-ci-canary). On 2026-09-28 the
  only direct pin in the accessible fleet is ci-workflows `v1.0.235` (CLI 2.1.283),
  newer than that canary's `v1.0.231` / CLI 2.1.278. The canary record's recheck
  trigger fired. The run id was not replaced from this checkout.
- **Basis:** #4282 (sandbox archived, `git push` refused). [The CI canary](#the-ci-canary)
  already records run `35475056935` on `melodic-software/knowledge-corpus` as of
  2026-09-19. Building the matrix in this repo would add a live
  `claude-code-action` workflow and a secret this checkout does not own. The newer
  pin is the `v1.0.235` row in the release map above, read from ci-workflows
  `b570d97203c7973b25c14e3de91c5ff3a4aa0e82`.
- **As of:** 2026-09-28.
- **Recheck trigger:** a maintainer names a live host and records a new run id
  in [The CI canary](#the-ci-canary), or `claude-lane-sandbox` is unarchived.

## Accessible fleet graded 2026-09-28

`gh repo list melodic-software` on this host returned the nine live repositories below, plus
archived `claude-lane-sandbox` (not cloned; #4282 keeps it archived). `cutover-check.sh --repo`
named each live tree. `medley`, `songwriting`, `claude-code-proxy`, `knowledge-corpus`, and
`provisioning` answered repository-not-found and were not graded. Those five are part of the
historical ten on #4281, so this run does not cover that list.

| Repository | Commit graded |
|---|---|
| claude-code-plugins (this branch) | the tip that contains this record |
| standards | `849678b5e59d20b50ec39b4dd587d70756417727` |
| ci-runner | `ac7ac20af851ca93f7d636cee5425bde032e04eb` |
| ci-workflows | `b570d97203c7973b25c14e3de91c5ff3a4aa0e82` |
| claude-code-account-rotation | `af6541e4ff2a4d12400310b21a7203bfff1013f8` |
| cursor-plugins | `9cb950e62443300764ee81537df8bbb19931880a` |
| agent-plugins | `03260bb8a4fdda42809e4f9dbd42409f96b47f59` |
| codex-plugins | `be421d0a7ae900fa5cdefe17343110be412b5a64` |
| .github | `5bc36c9492720dedfd922ec82355dfe95125920e` |

- **Claim**: with the `v1.0.235` row in the release map, that invocation grades condition 1
  `[MET]` (bundle code default true on CLI 2.1.282), condition 2 `[MET]` (two pins, both
  `756cc22e19660d20e8cc9496b4f242475a7f7790`, install CLI 2.1.283, at or above 2.1.277; CI
  canary run `35475056935` remains the recorded run), condition 3 `[UNREACH]` (`claude auth
  status` reports `loggedIn: false`; both `claude -p` legs exit 1 and stdout is `Not logged
  in · Please run /login`), and condition 4 `[MET]` (68 acknowledged rows, all in this
  marketplace; the other eight trees report no path detection). Before the `v1.0.235` row,
  condition 2 was `[UNREACH]` on those two pins. Nothing is removed. The
  `user-scope.sh:136` acknowledgement is on `main` via #5160.
- **Basis**: `cutover-check.sh` on 2026-09-28 against the commits above, CLI `2.1.282 (Claude
  Code)`, bundle offset 225456771 `var W=!0`, env-vars fetch with the AGENTS.md bullet absent.
  The pre-map run is the same command before this row existed.
- **As of**: 2026-09-28.
- **Recheck trigger**: fired the same day at 12:31 UTC. The grade from that run is
  [Standing refresh (#5163)](#standing-refresh-5163). A pin move or a previously unread
  repository becoming readable is that section's trigger.

## Standing refresh (#5163)

`cutover-check.sh` again, 2026-09-28 12:31 UTC, without `--skip-canary`, against the nine
live repositories `gh repo list melodic-software` returned. Archived `claude-lane-sandbox`
was not cloned (#4282). `gh repo view` for `medley`, `songwriting`, `claude-code-proxy`,
`knowledge-corpus`, and `provisioning` returned repository-not-found, so those five of the
historical ten on #4281 were not graded. Nothing was removed. #5163 stays open.

| Repository | Commit graded |
|---|---|
| claude-code-plugins | `5e6eade117ec3e6737840434602dbfb930f5ab3e` (origin/main at run time) <!-- portability-ok: graded commit table records origin/main SHA at cutover-check run time --> |
| standards | `849678b5e59d20b50ec39b4dd587d70756417727` |
| ci-runner | `ac7ac20af851ca93f7d636cee5425bde032e04eb` |
| ci-workflows | `b570d97203c7973b25c14e3de91c5ff3a4aa0e82` |
| claude-code-account-rotation | `af6541e4ff2a4d12400310b21a7203bfff1013f8` |
| cursor-plugins | `9cb950e62443300764ee81537df8bbb19931880a` |
| agent-plugins | `03260bb8a4fdda42809e4f9dbd42409f96b47f59` |
| codex-plugins | `be421d0a7ae900fa5cdefe17343110be412b5a64` |
| .github | `5bc36c9492720dedfd922ec82355dfe95125920e` |

- **Claim**: Condition 1 is `[MET]`. The bundle code default for `tengu_agents_md_mod` is
  true (`var W=!0` at offset 225456771 on CLI 2.1.282). The env-vars fetch in the same run
  found the feature-flag heading and no `AGENTS.md` bullet. Condition 2 is `[MET]`. The only
  pins are the two in ci-workflows (`claude-review.yml:167` and
  `claude-security-review.yml:160`), both `756cc22e19660d20e8cc9496b4f242475a7f7790`, which
  the release map installs as CLI 2.1.283, at or above 2.1.277. CI canary run `35475056935`
  stays the recorded run. Condition 3 is `[UNREACH]`. The home scratch root was
  `<user>/.cache` and the second path was `/tmp`. Each `claude -p` exited 1. A separate
  probe, `claude -p "say hi" --model haiku --tools ""`, printed `Not logged in · Please run
  /login` and exited 1. `claude auth status` reported `loggedIn` false and `authMethod` none.
  Condition 4 is `[MET]`: 68 acknowledged rows, all in this marketplace; the other eight
  trees report no path detection. The verdict is NOT MET. `agents-md-cutover-check` in
  `.github/recurring-schedule.json` stays `last_checked` 2026-09-20 and `next_due`
  2026-10-20. Shim removal stays blocked.
- **Basis**: `cutover-check.sh` stdout from this host on 2026-09-28 12:31 UTC (conditions 1,
  2, and 4 `[MET]`, condition 3 `[UNREACH]`, exit 1); `claude auth status`; the login probe
  above; `gh repo list` and the five `gh repo view` not-found results; the commits in the
  table.
- **As of**: 2026-09-28.
- **Recheck trigger**: the next cutover-check run, a named repository moving its pin, one of
  the five unread repositories becoming readable, or a host where `claude auth status`
  reports `loggedIn` true so condition 3 can measure.

## Install-dependent loader tests parked (#4283)

Claude Code and Codex loading behavior is backed by empirical tests. Cursor,
Grok Build, and Muse Code were not installed in the environment that did the
AGENTS.md migration research, so every claim about their loader stays at docs
or source grade.

- **Option A (taken):** do not install those tools from this checkout. Do not
  add CI that assumes they are present. Claims remain graded below empirical
  until a maintainer host runs the loader recipe named in #4283.
- **Option B (declined):** install Cursor, Grok Build, and Muse Code here or
  in a throwaway host from this PR.

- **Claim:** empirical loader tests for Cursor, Grok Build, and Muse Code are
  not run from this marketplace; cutover evidence for those tools stays docs
  or source grade.
- **Basis:** #4283 (install explicitly out of scope for the migration; the gap
  tracked as its own item). This cloud checkout does not ship those binaries.
- **As of:** 2026-09-28.
- **Recheck trigger:** a maintainer names a host with the tool installed and
  records empirical results (whether each tool reads AGENTS.md / CLAUDE.md,
  import expansion, precedence) into this file, replacing the docs/source grade.

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
- **Basis**: `https://code.claude.com/docs/en/hooks.md`, "InstructionsLoaded" (330,813 bytes, the
  quoted paragraph at line 1290) and `https://code.claude.com/docs/en/memory.md`, "Where AGENTS.md
  differs from CLAUDE.md" (54,922 bytes, table at line 412) and "My AGENTS.md isn't loading" (lines
  581 and 583). Both fetched by the rung-1 route on 2026-09-28, both slugs present in `llms.txt`.
- **As of**: 2026-09-28.
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

## This-repo cutover run (#4281)

`cutover-check.sh --repo` this checkout on 2026-09-28, without `--skip-canary`, against Claude
Code 2.1.282. The other nine in-scope repositories were not in this checkout. Nothing was removed.

- **Claim**: Condition 1 is `[MET]` because the bundle code default for `tengu_agents_md_mod` is
  true (`var W=!0` at offset 225456771). The env-vars feature-flag list also has no `AGENTS.md`
  bullet; either fact is enough, and the check returned on the code default. Condition 2 is
  `[MET]` for this one named repository: the plan's `ACTION` row is `NONE` (no
  `claude-code-action` pin), and the CI canary run `35475056935` is still the run
  [The CI canary](#the-ci-canary) names, as of 2026-09-19. The check also printed that a fleet
  verdict needs every in-scope repository named, and that a lane delegating to a reusable
  workflow is not an `ACTION` row. Condition 3 is `[UNREACH]`. Both legs ran. The home scratch
  root was `<user>/.cache` and the second path was `/tmp` (this host has no `/d` drive, so
  the script's own fallback applied). Each `claude -p` exited 1. A separate probe,
  `claude -p "say hi" --model haiku --tools ""`, printed `Not logged in · Please run /login` and
  exited 1. `claude auth status` reported `loggedIn` false and `authMethod` none.   An unmeasured
  canary is not a pass. Condition 4 is `[MET]`: 68 path-detection rows, every one acknowledged,
  including one new row:
  `plugins/ai-slop/skills/audit/scripts/user-scope.sh` lists `$root/CLAUDE.md` only when that
  user-scope file exists under `CLAUDE_CONFIG_DIR` or `$HOME/.claude`. The verdict is NOT MET
  because condition 3 is `[UNREACH]`. `agents-md-cutover-check` in
  `.github/recurring-schedule.json` stays `last_checked` 2026-09-20 and `next_due` 2026-10-20.
  Shim removal stays blocked until every graded condition is `[MET]` on all ten repositories,
  including a condition-3 canary that returns the line.
- **Basis**: `cutover-check.sh` stdout from this checkout on 2026-09-28 (conditions 1, 2, and 4
  `[MET]`, condition 3 `[UNREACH]`, exit 1); `claude auth status`; the login probe above; the
  bundle and page fetches in the records above; `.github/recurring-schedule.json` item
  `agents-md-cutover-check`.
- **As of**: 2026-09-28.
- **Recheck trigger**: the monthly due date 2026-10-20, a Claude Code release whose changelog
  touches `AGENTS.md` or instruction-file loading, a logged-in host that can run the condition-3
  canary, or any of the ten in-scope repositories becoming available to name on `--repo`.
