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
  identifier declared once nearby as `!0` (true) or `!1` (false). In Claude Code 2.1.278 that
  identifier is `W` and the window around the flag string reads
  `isOnByDefault:()=>W` and `var W=!1;var B=()=>oX()&&Gl("tengu_agents_md_mod",W)`, so the **code
  default is false**.
- **Basis**: the installed bundle at `~/.local/bin/claude`, 2.1.278, read as bytes: the flag string
  occurs twice, and the second occurrence (byte offset 226701892 on this build) is the code site.
  Offsets and the identifier are per build and per host, so the check resolves both at run time and
  hardcodes neither.
- **As of**: 2026-09-20.
- **Recheck trigger**: any Claude Code version bump, a bundle where no window around the flag string
  carries `isOnByDefault`, or a window where the captured identifier resolves ambiguously. Each of
  those is `[UNREACH]` for the check, never `[MET]`.

## The documented feature-flag dependency

- **Claim**: `env-vars` carries the section `## Features that need feature-flag fetching`, and one
  of its bullets is the AGENTS.md one, verbatim: "Have Claude Code
  [read `AGENTS.md` files](/docs/en/memory#agents-md) as project instructions; it loads `CLAUDE.md`
  files only". Fetching is skipped for a session setting `DISABLE_GROWTHBOOK`, `DISABLE_TELEMETRY`,
  `DO_NOT_TRACK` or `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, a session on a third-party provider,
  and a Claude apps gateway session. The same page's subsection "First session after an install or
  upgrade" states a flag-gated feature can be missing in that first session.
- **Basis**: `https://code.claude.com/docs/en/env-vars.md`, fetched 2026-09-20, 496,249 bytes, the
  section at line 502. The slug appears in `llms.txt` and the body's first heading is
  "Environment variables", so the page is the one requested.
- **As of**: 2026-09-20.
- **Recheck trigger**: the heading is renamed or removed, or the AGENTS.md bullet leaves the list.
  A missing heading is `[UNREACH]` for the check, because the absence of a heading cannot be read as
  the absence of the dependency.

## The minimum CLI version

- **Claim**: Claude Code reads `AGENTS.md` as project instructions from **v2.1.277**, verbatim:
  "Reading `AGENTS.md` directly requires Claude Code v2.1.277 or later." The same page lists
  "You're on a Claude Code version before v2.1.277" among the cases where support is unavailable,
  and its removal procedure step 2 is "Run `claude --version` and confirm v2.1.277 or later."
  Below that version no session reads it, whatever the flag says.
- **Basis**: `https://code.claude.com/docs/en/memory.md`, fetched 2026-09-20 by the rung-1 route,
  52,465 bytes; the three quoted lines are at 332, 382 and 559.
- **As of**: 2026-09-20.
- **Recheck trigger**: the memory page states a different floor, or a release note moves it.

## `claude-code-action` release to installed CLI version

The pin in a workflow decides which CLI CI installs, and so whether CI can read `AGENTS.md` at all.
Each row was re-derived this session by resolving the tag to its commit and reading
`base-action/action.yml` at that commit; none was copied forward.

| Release | Commit | `CLAUDE_CODE_VERSION` | At or above 2.1.277 |
|---|---|---|---|
| `v1.0.213` | `8251c103ac8c1d761882c86aba1412c7f583c844` | `2.1.258` | no |
| `v1.0.222` | `56cf60fde42f7b19c3abfd5c9c48b69a1288461f` | `2.1.269` | no |
| `v1.0.228` | `2261fcfc88e7de1b55f179edd588805e12de71f2` | `2.1.275` | no |
| `v1.0.231` | `cfc3eb22bfed5c26ef66e3223c982af27e4524de` | `2.1.278` | yes |

- **Claim**: the table above, and the general rule that the value is assigned in
  `base-action/action.yml` as a shell line `CLAUDE_CODE_VERSION="<version>"` immediately before the
  `Installing Claude Code v${CLAUDE_CODE_VERSION}...` echo (line 150 at all four commits).
- **Basis**: `gh api repos/anthropics/claude-code-action/commits/<tag>` for the commit, then
  `gh api repos/anthropics/claude-code-action/contents/base-action/action.yml?ref=<tag>`.
- **As of**: 2026-09-20.
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

## The canary recipe

Not restated here. The prompt shape, where the token goes, why the token is never committed, the
Codex leg, and the rollout check are in
[`reference/verification.md`](verification.md). Read that file before running any canary.

## What shim removal costs

This is the price of the cutover, and `remove-shims` prints it before it asks.

- **Claim**: an `AGENTS.md` Claude reads directly is **not listed** in `/memory` or in the
  **Memory files** list in `/context`, verbatim: "Not listed. To confirm Claude read it, look for
  the `AGENTS.md loaded` line under the default value, or ask Claude what its project instructions
  say". `InstructionsLoaded` hooks **do not fire** for it, verbatim: "This event doesn't fire when
  Claude reads `AGENTS.md` directly through the **Project instructions** setting. It does fire when
  a `CLAUDE.md` imports your `AGENTS.md`, with `load_reason` set to `include` as for any other
  imported file". Two further rows of the same table: a directory added with `--add-dir` under
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` loads its `CLAUDE.md` and not its `AGENTS.md`, and
  an external `@path` import loads with no prompt only where external imports were already approved
  for that project.
- **Basis**: `https://code.claude.com/docs/en/memory.md`, "Where AGENTS.md differs from CLAUDE.md"
  (52,465 bytes, table at line 391) and `https://code.claude.com/docs/en/hooks.md`,
  "InstructionsLoaded" (329,656 bytes, line 1306). Both fetched by the rung-1 route on 2026-09-20,
  both slugs present in `llms.txt`.
- **As of**: 2026-09-20.
- **Recheck trigger**: either page changes that table or that paragraph.

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
