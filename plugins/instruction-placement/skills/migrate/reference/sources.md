# Upstream sources the cutover check reads

Every upstream fact the AGENTS.md cutover turns on, as a pointer record per the
[upstream-drift convention](../../../../../docs/conventions/upstream-drift/README.md): our decision
or our own probe result, a pointer to where the specific lives, an as-of date, and a recheck
trigger. The records are here so a reader can judge the check's verdict without re-deriving the
research, and so a firing trigger has one place to land.

Per-run output (per-condition tables, graded commit SHAs) is posted as a comment on the tracker
issue. This file holds only the current grade of each fact: per the convention's "When a trigger
fires", refreshing a date with no verdict change is no entry and no version bump.

Every page below was fetched by the convention's rung-1 route (`curl` the `.md` to a file, search
the file locally), slug confirmed against `https://code.claude.com/docs/llms.txt`, and read from
the bytes. No page text is stored here.

Contents: [The remote flag](#the-remote-flag-and-how-its-code-default-is-read) ·
[Feature-flag dependency](#the-documented-feature-flag-dependency) ·
[Minimum CLI version](#the-minimum-cli-version) ·
[`claude-code-action` releases](#claude-code-action-release-to-installed-cli-version) ·
[CI canary](#the-ci-canary) · [Canary host](#canary-host-4282) ·
[Fleet grade](#current-fleet-grade) ·
[Other loaders](#loader-behavior-of-cursor-grok-build-and-muse-code) ·
[Canary recipe](#the-canary-recipe) · [Shim removal cost](#what-shim-removal-costs) ·
[Measuring the cutover](#what-the-loss-means-for-measuring-the-cutover) ·
[Hook gap recheck](#page-recheck-of-the-hook-gap) ·
[Built-in agents-md plugin](#the-built-in-agents-md-plugin) ·
[Frontmatter hooks](#frontmatter-hooks-and-instructionsloaded) ·
[Nested path blockers](#blockers-between-the-root-and-a-nested-agentsmd)

## The remote flag, and how its code default is read

Condition 1 treats direct `AGENTS.md` reading as gated on the GrowthBook flag
`tengu_agents_md_mod` and reads the flag's code default out of the shipped bundle at run time. Our
probe of Claude Code 2.1.282 found the flag string twice. Only the second occurrence sits in a
window where the built-in plugin's `isOnByDefault` export resolves to a minifier-assigned
identifier (`W` on that build) declared `!0`, so the **code default is true**. The first
occurrence is a string in another window and ties to no `isOnByDefault` export.

- **Pointer**: our byte read of the installed bundle at
  `node_modules/@anthropic-ai/claude-code/bin/claude.exe` (`claude` on PATH), 2.1.282, sha256
  `3afe8535c0cc33f0e24f7b25dab7a1727b8b592196f8496a8bc302ba2161eed3`. The flag string occurs at
  offsets 103001528 and 225456771; only 225456771 is the code site. Offsets and the identifier are
  per build and per host, so the check resolves both at run time and hardcodes neither.
  `cutover-check.sh` on 2026-09-28 printed that same offset and identifier and a `!0` declaration.
- **As of**: 2026-09-28
- **Recheck trigger**: any Claude Code version bump, a bundle where no window around the flag string
  carries `isOnByDefault`, or a window where the captured identifier resolves ambiguously. Each of
  those is `[UNREACH]` for the check, never `[MET]`.

## The documented feature-flag dependency

Condition 1's second leg fetches the env-vars page and grades the dependency gone when the section
headed `## Features that need feature-flag fetching` no longer names `AGENTS.md`. It requires the
later subsection heading "First session after an install or upgrade" as its marker that the page
arrived whole. Our 2026-09-28 fetch found the heading and the marker, and a case-insensitive search
of the whole page for `AGENTS.md` found no line.

- **Pointer**: for which features need feature-flag fetching and which sessions skip it, see
  <https://code.claude.com/docs/en/env-vars#features-that-need-feature-flag-fetching> and
  <https://code.claude.com/docs/en/env-vars#first-session-after-an-install-or-upgrade>. Our fetch of
  `env-vars.md` on 2026-09-28 was 507,134 bytes, with the heading at line 512, its list at lines
  520-534 and the marker at line 536; the slug is in `llms.txt` and the body's first heading
  confirmed the page. The same day's `cutover-check.sh` fetch reported the heading found and the
  AGENTS.md bullet absent.
- **As of**: 2026-09-28
- **Recheck trigger**: the heading is renamed or removed, the page names `AGENTS.md` beside a flag
  again, or the AGENTS.md bullet returns to the list. A missing heading is `[UNREACH]` for the
  check, because the absence of a heading cannot be read as the absence of the dependency.

## The minimum CLI version

`cutover-check.sh` grades every pin against the CLI floor **v2.1.277**: below it the check counts no
session as reading `AGENTS.md` directly, whatever the flag says. Some session kinds need a later
version than the floor; the check does not grade that, so an operator whose fleet runs those
session kinds reads it at the pointer.

- **Pointer**: for the version that reads `AGENTS.md` directly and the sessions that lack support,
  see <https://code.claude.com/docs/en/memory#when-agents-md-support-is-unavailable> and
  <https://code.claude.com/docs/en/memory#remove-an-earlier-agents-md-workaround>. Our rung-1 fetch
  of `memory.md` on 2026-09-29 was 49,601 bytes; the slug is in `llms.txt` and the first heading
  confirmed the page.
- **As of**: 2026-09-29
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

The check maps each pin to the CLI version that `base-action/action.yml` assigns to
`CLAUDE_CODE_VERSION` at the pinned commit, in the shell step that installs Claude Code (line 150
at all five commits), and reads the table above as that mapping.

- **Pointer**: our derivation, `gh api repos/anthropics/claude-code-action/commits/<tag>` for the
  commit, then `gh api repos/anthropics/claude-code-action/contents/base-action/action.yml?ref=<tag>`,
  re-read 2026-09-28 for every row in the table. `v1.0.235` is an annotated tag whose tag object
  `f33305702e43b9f71a532e6f80aed9a399df8288` points at commit
  `756cc22e19660d20e8cc9496b4f242475a7f7790`. That commit is the `uses:` pin in
  `melodic-software/ci-workflows` `b570d97203c7973b25c14e3de91c5ff3a4aa0e82`,
  `.github/workflows/claude-review.yml:167` and `.github/workflows/claude-security-review.yml:160`,
  both commented `# v1.0.235`.
- **As of**: 2026-09-28
- **Recheck trigger**: a new pin appears in any in-scope repository, or the action stops assigning
  `CLAUDE_CODE_VERSION` in `base-action/action.yml`. A pin whose file carries no such assignment is
  `[UNREACH]`, never a pass: an unreadable map is not a satisfied floor.

## The CI canary

Condition 2's canary half rests on this observation of ours. On a GitHub-hosted `ubuntu-24.04`
runner with a genuinely fresh install (no `~/.claude` before the first step), at action `v1.0.235`
installing CLI 2.1.283, a workspace holding a lone non-empty `AGENTS.md` and no `CLAUDE.md` at any
level returned the `AGENTS.md` canary token `CI-AGENTS-51C2` with zero tool calls, on the first
session after the install and again on a second session in the same job. The arrange step deleted
the repository's own `CLAUDE.md` shim from the ephemeral workspace, and the job's instruction-file
listing showed only `AGENTS.md`. The 2026-09-19 canary at `v1.0.231` / CLI 2.1.278 returned the
same for a lone `AGENTS.md`, and there a `CLAUDE.md` carrying its own token suppressed the
`AGENTS.md` one. Separately, `claude-code-action` **refuses a `push` event**, so canaries are
started by REST dispatch
(`gh api -X POST repos/<owner>/<repo>/actions/workflows/<file>/dispatches -f ref=<branch>`).

- **Pointer**: `melodic-software/knowledge-corpus` run `36666844023`, event `workflow_dispatch`, head
  SHA `24041cf1613312c6aff31ff637d9ea4beb753302` on the throwaway branch
  `test/agents-md-ci-canary`, deleted after the run. The workflow is the 2026-09-19 canary workflow
  (knowledge-corpus `91f0285b1ba2cc7329dff0f89dbbae020171a61b`) cut to case A,
  `workflow_dispatch` only, with both action uses pinned to
  `756cc22e19660d20e8cc9496b4f242475a7f7790 # v1.0.235`. Log lines: `2.1.283 (Claude Code)`,
  reply `CI-AGENTS-51C2`, tools used `[]`, in both report steps. The earlier run `35475056935`
  (head SHA `91f0285b1ba2cc7329dff0f89dbbae020171a61b`) is recorded in the migration slice's
  `PROOF-ci-canary-knowledge-corpus-2026-09-19.md`. For the events the action accepts, see its own
  `src/github/context.ts` `parseGitHubContext` switch at the pinned commit.
- **As of**: 2026-09-30
- **Recheck trigger**: a new action release, a new CLI floor, or a runner image change. A
  repository `CLAUDE.md` shim left in the workspace turns the run into a test of the shim, so the
  arrange step must remove it. The canary does not show **why** the flag-gated feature was
  available in that job, so a later regression would not contradict this record; it would replace
  it. The check never assumes this result: it parses the first run id in this section, prints it as
  the evidence behind condition 2, and exits 2 if the record is not there to read.

## Canary host (#4282)

The CI-canary component of cutover condition 2 rests on the knowledge-corpus run recorded in
[The CI canary](#the-ci-canary), at `v1.0.235`. The owner chose one case-A run at that pin on
knowledge-corpus over accepting the 2026-09-19 run, and the run passed.

- **Pointer**: the owner decision comments on #4282 of 2026-09-29 ("Option B, run by the agent").
  `melodic-software/ci-workflows#599`, the pin half, closed COMPLETED 2026-09-20.
  `gh repo view melodic-software/claude-lane-sandbox --json isArchived` returned
  `{"isArchived":true,"name":"claude-lane-sandbox"}` on 2026-09-29, and
  `git ls-remote --heads origin` in the knowledge-corpus tree returned only `refs/heads/main` on
  2026-09-30, after the run's branch was deleted.
- **As of**: 2026-09-30
- **Recheck trigger**: a run id newer than the one in [The CI canary](#the-ci-canary), or a
  `claude-code-action` release newer than the pinned one.

## Current fleet grade

The fleet's current grade is our own run: `cutover-check.sh` graded every condition `[MET]` and
printed `remove-shims may run`, over ten repositories with none unreadable: claude-code-plugins,
medley, songwriting, claude-code-proxy, knowledge-corpus, codex-plugins, ci-runner, agent-plugins,
cursor-plugins, and provisioning. Condition 1 is `[MET]` because the bundle code default for
`tengu_agents_md_mod` is true. Condition 2 is `[MET]` on pin arithmetic: the only pin in the ten is
medley's `v1.0.231` (CLI 2.1.278), and the two ci-workflows pins, outside the ten, are `v1.0.235`
(CLI 2.1.283), all at or above 2.1.277. This grade printed the 2026-09-19 canary run at `v1.0.231`
as its CI-canary evidence. The record now names run `36666844023` at `v1.0.235` / CLI 2.1.283, the
ci-workflows pin (see [The CI canary](#the-ci-canary) and [Canary host](#canary-host-4282)); the
grade was not re-run. Condition 3 is `[MET]`: both `claude -p` legs returned the canary line from a
lone non-empty `AGENTS.md`, and it grades only on a logged-in host. Condition 4 is `[MET]`: 70
path-detection rows, every one acknowledged with a reviewed reason.

- **Pointer**: `cutover-check.sh`, no `--skip-canary`, over the ten repositories on 2026-09-29,
  Claude Code 2.1.284, exit 0. The trees were read as they stood and not fetched, so the grade is
  for those local commits, not for the current default branch. The per-repository commit table and
  the full per-condition output are in the comment on tracker issue #4281, not copied here.
- **As of**: 2026-09-29
- **Recheck trigger**: a pin move in any in-scope repository, a Claude Code release whose
  changelog touches `AGENTS.md` or instruction-file loading, the monthly due date of
  `agents-md-cutover-check` in `.github/recurring-schedule.json`, or an in-scope repository
  becoming unreadable or readable.

## Loader behavior of Cursor, Grok Build, and Muse Code

The migration plans for other tools on these observations of ours, not on docs or source. Each
tool was run headless against one recipe tree. Cursor CLI loads `AGENTS.md`, `CLAUDE.md` and
`CLAUDE.local.md` together at session start, follows symlinks, applies no size cap through 262,156
bytes, and does not expand `@path` imports. It reads no other name (`Agents.md`, `AGENT.md`,
`.claude/CLAUDE.md` are absent). `.cursor/rules/*.md` never loads; `.mdc` loads only with
frontmatter. Started at the git root, nested files attach when a file under them is read; started
in the nested directory, the ancestor chain loads (12 levels seen). In the non-git copy the attach
on read did not occur. Grok Build loads eight file names per directory, and the two `.claude/`
names are gated by `GROK_CLAUDE_AGENTS_ENABLED` (set to `false`, they vanish). No switch stops it
reading a plain `CLAUDE.md`. It does not expand `@path` imports, follows symlinks, and shows no size
cap through 262,156 bytes. In a trusted folder outside a git repository it loads the working
directory only, so the expectation that nothing loads outside a git repository does not hold; with
folder trust off nothing project-level loads. Muse Code loads one file per directory with
`AGENTS.md` first, and `CLAUDE.md` alone loads when no `AGENTS.md` exists. It does not expand
`@path` imports and follows symlinks. It skips an `AGENTS.md` over 256,000 bytes and says so on
stderr, loads one of 244,676 bytes with only the head reaching the model (65,536-byte delegation
startup limit), and skips project files unless the workspace is trusted (`--trust-workspace`). In
a git repository it loads the chain from root to working directory (12 levels seen); from the
root, a read under a nested directory attaches nothing; outside git it loads the working directory
only.

Still open, each with its reason:

- Cursor Team, Project, User precedence: needs a Team plan and the editor rules UI, not observable
  headless.
- Cursor editor against CLI, and how the editor applies an always-on rule: the editor was not run.
- Cursor `~/.cursor/rules` as a synced file: the path does not exist on the host, and sync cannot
  be observed headless.
- Grok path-only reminder text for out-of-chain files: contents stay unloaded and the model later
  read the nested files itself, but the streamed transcript carries no reminder text.
- Grok `MAX_WALK_DEPTH` of 10: a working directory at depth 12 loaded all 12 levels, so the recipe
  does not show what the constant bounds.
- Whether Muse ever opens a shadowed sibling `CLAUDE.md`: Muse names the shadowed file on stderr as
  ignored in favor of `AGENTS.md`, but whether the file is opened needs `strace`, which is not
  installed on the host.
- Muse user-rules path and its Windows resolution: no Muse-native user-rules file exists on the
  host, and the Windows path needs a Windows host.

- **Pointer**: headless runs on one Linux host with cursor-agent `2026.09.28-64d2043`
  (`cursor-agent -p --mode ask --trust`), grok `1.0.41 (4220f3b224a6)` (`grok -p --tools ""`
  with `GROK_FOLDER_TRUST=0`, and `grok inspect --json`), and Muse Code `1.4.1 (1.4.1-R4503.1)`
  (`muse exec --trust-workspace --disable-shell --disable-write`). The tree, prompt,
  invocations and expected results are in
  [`reference/verification.md`](verification.md#the-loader-recipe-for-other-tools); the raw
  transcripts are not committed. Each result is one model sample except where repeats agreed. For
  each tool's own documentation, see Cursor rules, <https://cursor.com/docs/rules>, and Grok
  Build, <https://docs.x.ai/build/overview> (both fetched 2026-09-30, HTTP 200, both naming
  `AGENTS.md`); neither states the loader semantics above, which is why they are recorded as
  observed. Muse Code: no public documentation or issue tracker was found, so its results rest on
  the recipe alone.
- **As of**: 2026-09-30
- **Recheck trigger**: a new release of any of the three tools, a host that can run the
  editor, a Team plan, a Windows host, or `strace`, which would settle the open bullets, either
  upstream page coming to state loader behavior, or any change to the recipe in
  [`reference/verification.md`](verification.md#the-loader-recipe-for-other-tools).

## The canary recipe

Not restated here. The prompt shape, where the token goes, why the token is never committed, the
Codex leg, and the rollout check are in
[`reference/verification.md`](verification.md). Read that file before running any canary.

## What shim removal costs

This is the price of the cutover, and `remove-shims` prints it before it asks.

Removing the shims costs the hook-visible load. Without a shim, the `InstructionsLoaded` hook no
longer reports the `AGENTS.md` load, so `verify-load.sh` and any hook-based audit stop seeing it
(our 2026-09-20 measurement below observed exactly that); with a shim, the load arrives as an
import and the hook reports it. The operator's way to confirm the file loaded moves to `/memory`.
We count two further differences between a direct read and a shimmed one in the price: directories
added with `--add-dir`, and external `@path` imports inside the file. Each is read live at the
pointer, never restated here.

- **Pointer**: for the hook, see <https://code.claude.com/docs/en/hooks#instructionsloaded>; for
  the differences between a direct read and a `CLAUDE.md` load, and the `/memory` listing, see
  <https://code.claude.com/docs/en/memory#where-agents-md-differs-from-claude-md> and
  <https://code.claude.com/docs/en/memory#my-agents-md-isn%E2%80%99t-loading>. Both pages fetched by
  the rung-1 route on 2026-09-29, both slugs present in `llms.txt`. `scripts/remove-shims.sh`
  prints the paragraph above this line and this pointer, and stops at the As of line.
- **As of**: 2026-09-29
- **Recheck trigger**: either page changes that table, the hook's firing rule for `AGENTS.md`, or
  the `/memory` listing.

## What the loss means for measuring the cutover

`scripts/verify-load.sh` detects a load through an `InstructionsLoaded` hook, so it **cannot
measure a directly read `AGENTS.md`**. Our measurement, in a scratch directory under home holding
only a non-empty `AGENTS.md` and a `README.md`: `verify-load.sh --trigger README.md --expect
AGENTS.md` printed one `LOADED` row for the user-scope `~/.claude/CLAUDE.md` and then
`EXPECTED AGENTS.md MISSING` / `VERDICT FAIL`, exit 1, while a headless `claude -p` run from the
same directory with `--allowedTools Read`, reading `README.md` and asked to quote back the lines of
its project instructions carrying the token, returned the token. So the file loaded and the
instrument could not see it. `verify-load.sh` stays the right instrument for a **shimmed** surface,
where the load arrives as an import and the hook fires with `load_reason` `include`.

- **Pointer**: the run above on Claude Code 2.1.278, Windows, 2026-09-20; for the hook's firing
  rule, see <https://code.claude.com/docs/en/hooks#instructionsloaded>.
- **As of**: 2026-09-20
- **Recheck trigger**: `InstructionsLoaded` starts firing for a directly read `AGENTS.md`, or
  `verify-load.sh` gains a detection path that does not depend on that hook. Either one puts the
  two instruments back together.

## Page recheck of the hook gap

The 2026-09-20 measurement above was not repeated on this pass.

A re-read of the hooks page found the hook gap unchanged, so this plugin still treats
`verify-load.sh` as blind to a direct load. What moved is the `/memory` listing, recorded under
[What shim removal costs](#what-shim-removal-costs).

- **Pointer**: the hooks and memory fetches in that cost record. This checkout's
  `claude auth status` reported `loggedIn` false, so no new `claude -p` measurement was possible.
- **As of**: 2026-09-28
- **Recheck trigger**: the same as the measurement record above.

## The built-in agents-md plugin

The record behind the skill body's `## Boundary` section for `cc-plugin-agents-md` and
[`shim-droppable.md`](shim-droppable.md) (conditions A to F and the nested-`AGENTS.md` verdicts).

- **Claim**: Claude Code ships a built-in `agents-md` plugin (ID `agents-md@builtin`) that reads
  `AGENTS.md` as the project instructions. Its **Project instructions** option
  (`instructionFiles`) takes four values: `claude-md-or-agents-md`, the default ("Your `CLAUDE.md`
  files, or your `AGENTS.md` files when you have no `CLAUDE.md` or `CLAUDE.local.md` in your
  working directory or above it"), `claude-md-and-agents-md` ("Your `CLAUDE.md` and `AGENTS.md`
  files together, each directory's `CLAUDE.md` files first and its `AGENTS.md` after them"),
  `claude-md` ("Your `CLAUDE.md` files only") and `managed-only` ("Your project, local, and user
  `CLAUDE.md` files, your `.claude/rules/` files, and every `AGENTS.md` are left out. A
  subdirectory's `CLAUDE.md` and `.claude/rules/` files, and path-scoped rules, still load when
  Claude reads a file there"). The value is read from `pluginConfigs` in "`~/.claude/settings.json`,
  a `--settings` file, or managed settings. Claude Code ignores it in project and local settings
  files." The option's first key, `projectInstructions` (`claude`, `agents-fallback`, `both`,
  `none`), is still honored while `instructionFiles` reads as its default, so an operator's mode
  can come from either key; like `instructionFiles`, it is a user, `--settings` or managed value a
  repository cannot rely on. Condition A: the files that "Count, so Claude reads them instead of `AGENTS.md`" are "a
  `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` in your working directory or any
  directory above it", the walk to the filesystem root, while "Don't count, and keep loading
  alongside `AGENTS.md`: your `~/.claude/CLAUDE.md`, your organization's managed `CLAUDE.md`, and
  `.claude/rules/` files", which is the walk's one exemption. Nested files under the default: "a
  subdirectory's `AGENTS.md`, when Claude opens a file there with the Read tool and that
  subdirectory has none of the three `CLAUDE.md` files of its own". The page states no subdirectory trigger for `claude-md-and-agents-md`, and
  does not say whether a subdirectory `CLAUDE.md`'s `@AGENTS.md` import expands under
  `managed-only`; the skill keeps the shims in both cases for that reason. Condition D: "In these
  sessions Claude reads `CLAUDE.md` files only, and **Project instructions** doesn't appear in the
  `/config` settings panel": "You're on a Claude Code version before v2.1.277", "You disabled the
  built-in `agents-md` plugin in `/plugin`", and "In some cases, it's your first session after you
  upgrade from v2.1.276 or earlier"; also "Before v2.1.281, some sessions, such as those on Amazon
  Bedrock or with telemetry disabled, read `CLAUDE.md` files only". The difference table adds that
  for "Directories you add with `--add-dir` while `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` is
  set", "Their `AGENTS.md` doesn't load"; for "An `@path` import of a file outside your working
  directory" (condition E), an `AGENTS.md` read through the setting "Loads only if you already
  approved external imports for this project, with no prompt"; and for `InstructionsLoaded` hooks
  (condition F), "Don't fire. They fire as usual for an `AGENTS.md` that a `CLAUDE.md` imports or
  symlinks to". Condition D's first question: "Share one file with other coding tools" says to put
  the `@AGENTS.md` import in a `CLAUDE.md` "when your project also has a `CLAUDE.md`, when you've
  set **Project instructions** to `claude-md`, or in sessions that can't load `AGENTS.md`". The
  `/config` sentence quoted above introduces exactly the three bullets that follow it; the
  pre-2.1.281 sentence sits outside that list, so the skill does not attach the `/config` signal to
  it. The page does not mention the Agent SDK, cloud or web sessions, or `claude-code-action`, so
  condition D asks the operator about each rather than inferring coverage. Condition E's bound:
  "Imported files can recursively import other files, with a maximum depth of four hops" (line
  104), the same limit `scripts/lib/discover.sh` `_ip_reaches` encodes. Condition F's per-session
  plugins, from [plugins/create](https://code.claude.com/docs/en/plugins/create) "Develop without
  a marketplace" (fetched 2026-10-01, 25,706 bytes, first heading "Create a Claude Code plugin",
  slug in `llms.txt`; the `plugins` page, which has no "Test your plugins locally" heading on this
  date, sends `--plugin-dir` readers there): "You can
  load a plugin for a single session in three ways: from a directory or `.zip` archive on disk
  with `--plugin-dir`, from a URL with `--plugin-url`, or from an environment variable", namely
  `CLAUDE_CODE_PLUGIN_DIRS`, and "Each plugin loads for that session only, and nothing is written
  to your settings for it", which is why no settings read finds them; and "Claude Code loads any
  folder there [`~/.claude/skills/`] that contains a `.claude-plugin/plugin.json` as a plugin in
  every session, with no flag and no install step". The user roots, from
  [env-vars](https://code.claude.com/docs/en/env-vars) (fetched 2026-10-01, 158,869 bytes):
  `CLAUDE_CONFIG_DIR` "Override the configuration directory (default: `~/.claude`). All settings,
  session history, and plugins are stored under this path. ... Set it in your shell, user
  settings, or managed settings. Ignored in project and local settings", and
  `CLAUDE_CODE_PLUGIN_CACHE_DIR` "Override the plugins root directory ... Defaults to
  `~/.claude/plugins`"; [plugins/loading](https://code.claude.com/docs/en/plugins/loading)
  (fetched 2026-10-01, 37,348 bytes) says the same root "is `~/.claude/plugins` unless you set
  `CLAUDE_CODE_PLUGIN_CACHE_DIR`". The resolution expression is the one
  `plugins/performance/skills/verify/SKILL.md` uses. The memory page names the exempt user file
  only as "your `~/.claude/CLAUDE.md`" and does not say how `CLAUDE_CONFIG_DIR` changes that, so
  the walk exempts it only at the default root. The removal procedure for an `@AGENTS.md`
  shim: "Remove
  the `CLAUDE.md` if it holds nothing else, or keep it if some of your sessions can't load
  `AGENTS.md` directly." The plugin loads files; nothing upstream says it moves content or writes
  a shim, and no page states how a disabled built-in plugin is recorded in settings, which is why
  condition C reads `enabledPlugins` for whichever ID the inventory prints rather than one spelling.
  Condition C's hook policy: under `allowManagedHooksOnly`, "Mods built into Claude Code keep
  running"; under `disableAllHooks`, "Mods built into Claude Code keep running in both cases"; and
  the mods overview's "Mods built into Claude Code" table lists `cc-plugin-agents-md`. The memory
  page's unavailable list no longer names either setting. An earlier revision did (this
  repository's `plugins/harness-config/reference/agents-md-liveness.md`, as of 2026-09-21, quotes
  "You or your organization set `disableAllHooks` or `allowManagedHooksOnly`"), and no changelog
  entry dates the change, so the skill trusts the exemption only from 2.1.287.
- **Basis**: [memory](https://code.claude.com/docs/en/memory), fetched 2026-10-01 by the rung-1
  route (50,074 bytes; slug in `llms.txt`; first heading "How Claude remembers your project"),
  sections "When Claude Code reads AGENTS.md" (line 363), "Choose which instruction files load"
  (line 381; "Add it under the built-in `agents-md` plugin's ID in `pluginConfigs`", with the
  example key `"agents-md@builtin"`), "When AGENTS.md support is unavailable" (line 406), "Where
  AGENTS.md differs from CLAUDE.md" (line 416), "Remove an earlier AGENTS.md workaround" (line
  426) and "Share one file with other coding tools" (line 435). [settings-reference](https://code.claude.com/docs/en/settings-reference), fetched
  2026-10-01, `pluginConfigs`: "Built-in plugins store their options under the same key with an
  `@builtin` suffix"; fetched again 2026-10-02 (416,824 bytes, first heading "All settings"),
  "What runs under `allowManagedHooksOnly`" (line 4008) and "`disableAllHooks`" (line 4021).
  [plugins/mods/overview](https://code.claude.com/docs/en/plugins/mods/overview), fetched
  2026-10-02 (23,269 bytes, first heading "Mods overview"), "Mods built into Claude Code" (line
  220). The
  [changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) entry for 2.1.277
  reads "Added AGENTS.md support: in a project with no CLAUDE.md, Claude Code reads AGENTS.md
  instead; change it under \"Project instructions\" in `/config`", and the 2.1.281 entry reads
  "Changed AGENTS.md support to also work on Amazon Bedrock, Google Vertex AI, Microsoft Foundry,
  LLM gateways, and sessions with telemetry disabled". The `projectInstructions` key and its value
  mapping are in the plugin's
  [README](https://github.com/anthropics/claude-code/blob/main/mods/agents-md/README.md),
  "Setting the option" (commit `2282079d6ac8`, read 2026-10-01); the memory page does not
  mention it.
- **Read at run time, not recorded here**: that the binary registers the plugin as
  `cc-plugin-agents-md` with alias `agents-md`, whether the loader requires it in this session
  type, its availability gate and the gate's default, and whether it declares any skill, agent or
  command. No upstream page states them. Read them from `/harness-ops:inventory`'s `builtin_plugins`
  lane (`builtin_plugins.cc-plugin-agents-md`: `aliases`, `in_loader`, `load`, `gated`,
  `gate_flags`, `skills`, `agents`, `commands`) on the build in hand. On 2.1.287 on 2026-10-01 a
  `--binary-only` run printed `id` `cc-plugin-agents-md@builtin`, alias `agents-md`, `in_loader`
  true, `load` `unconditional`, `gated` true on `tengu_agents_md_mod` with default true; that is
  one build's reading, not the decision's input.
- **As of**: 2026-10-01, Claude Code 2.1.287; the hook-policy exemption 2026-10-02, same build.
- **Recheck trigger**: the memory page changes the "When Claude Code reads AGENTS.md" list, the
  "Choose which instruction files load" table, the "When AGENTS.md support is unavailable" list,
  the difference table, the "Share one file with other coding tools" conditions, or the shim
  bullet under "Remove an earlier AGENTS.md workaround"; it comes to name the Agent SDK, cloud or
  web sessions, or `claude-code-action`; it changes the four-hop import limit; plugins/create
  changes the ways a plugin loads for one session or without an install; env-vars or
  plugins/loading changes what `CLAUDE_CONFIG_DIR` or `CLAUDE_CODE_PLUGIN_CACHE_DIR` relocates; it
  comes
  to state when a subdirectory's `AGENTS.md` loads under `claude-md-and-agents-md` or whether an
  import expands under `managed-only`; settings-reference documents how a built-in plugin is
  disabled; settings-reference or the mods overview changes whether built-in mods keep running
  under `disableAllHooks` or `allowManagedHooksOnly`, or stops listing `cc-plugin-agents-md` as
  one; a changelog entry names `AGENTS.md`, `instructionFiles`, `projectInstructions` or the
  `agents-md` plugin; or the README's "Setting the option" paragraph on the old key changes.

## Frontmatter hooks and `InstructionsLoaded`

The record behind condition F's frontmatter scan in [`shim-droppable.md`](shim-droppable.md).

Condition F treats any skill, command-file or subagent frontmatter that names
`InstructionsLoaded` as a hook that may depend on the shim, and scans every location the pointers
below give for those components, plus each `--add-dir` directory the operator names, scanned
whole. Anything the pointers leave unsaid (whether such a hook fires in a given session, or inside
a subagent) keeps the shim. Read the mechanics live at the pointers; this record holds only that
decision.

- **Pointer**: <https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents>,
  <https://code.claude.com/docs/en/hooks#hook-locations>,
  <https://code.claude.com/docs/en/sub-agents#hooks-in-subagent-frontmatter>,
  <https://code.claude.com/docs/en/sub-agents#choose-the-subagent-scope>,
  <https://code.claude.com/docs/en/skills#where-skills-live>,
  <https://code.claude.com/docs/en/skills#frontmatter-reference> and
  <https://code.claude.com/docs/en/permissions#additional-directories-grant-file-access-not-configuration>.
  All four pages fetched by the rung-1 route on 2026-10-02, each slug in `llms.txt`.
- **As of**: 2026-10-02
- **Recheck trigger**: any of these sections changes which components can declare hooks, which
  events they accept, when those hooks are active, where skills, command files or subagents load
  from, or what `--add-dir` loads.

## Blockers between the root and a nested `AGENTS.md`

The record behind condition A's nested path walk in [`shim-droppable.md`](shim-droppable.md).

Condition A treats a `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in any directory
between the repository root and a nested `AGENTS.md` (for example `svc/CLAUDE.local.md` above
`svc/deep/AGENTS.md`) as a blocker for that nested file. The walk is the one `scripts/lib/discover.sh`
`ip_entry_points_on_path` already runs for the reachability verdict and the wiring gate.

- **Pointer**: <https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md>, fetched by
  the rung-1 route on 2026-10-02, slug in `llms.txt`.
- **As of**: 2026-10-02
- **Recheck trigger**: that section states which directories' files stop a subdirectory's
  `AGENTS.md` from loading.
