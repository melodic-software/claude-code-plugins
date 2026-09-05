# code-tidying

A Claude Code plugin for **structure-only** codebase improvement, applying Kent
Beck's *Tidy First?* discipline agentically: small named tidyings, separated
from behavioral changes by commit and by PR, under a research-backed scope
budget (≤200 LOC / ≤8 files target; ≤400 / ≤15 hard cap).

Six skills, one capability:

- **`/code-tidying:dissolve-comments`**. Enforces self-describing, expressive
  code over a diff or target (a clean tree widens to the branch diff, then to
  the whole repository with confirmation, ranked by exposure and comment
  payload): deletes zero-information comments, dissolves code-expressible
  comments into names and structure via behavior-preserving refactoring (then
  deletes them), and keeps only terse, load-bearing comments code cannot
  express, held to a line budget. Deletions and function-local renames apply
  behind a token-level proof (`change-shape.py`, so they act on a repository
  with no test suite); additive refactors need a discovered test net;
  interface-creating ones are proposal-first. `safe` mode restricts applied
  edits to removals. Ships a comment census with a token estimate and a
  cross-language commented-out-code detector, and probes its reading layers
  (`scc`, `pygments`, `tree-sitter`, `ruff`, `ast-grep`) at run time, naming
  what each absent one costs.
- **`/code-tidying:audit-comment-residue`**. Read-only classifier for
  out-of-context comment residue (history narration, plan/session references,
  conversational antecedents, ticket/PR back-references); flags Tier 1/Tier 2
  findings for author-applied deletion, edits nothing.
- **`/code-tidying:tidy`**. Proactively hunts a rotated, glob-scoped *lane* of
  the codebase for safe structural improvements (Beck's 15 tidyings + a Fowler
  subset + prose tidyings), applies scope-budgeted edits, and ships one tight
  structure-only PR. Overflow is filed as deferred work items, never silently
  dropped.
- **`/code-tidying:batch-simplify`**. Sweeps files through grouped,
  dependency-ordered simplification waves in one of three scope modes:
  a time window (`48h` default, `7d`, ...), the current branch, or `repo`.
  Per-group verification and a fix-first deferral contract throughout:
  deferrals are resolved in the same run rather than filed as issues, and only
  items needing a human decision or a genuinely huge refactor survive to the
  report. The whole-repository mode is explicit-entry only, gates on a
  confirmed inventory, runs a mandatory per-group refutation verifier, and
  delivers one feature branch and one PR for the whole run, with per-group
  commits. Use it when you forgot to run `/simplify` after each task, or to
  sweep a repository that never had one.
- **`/code-tidying:audit-dead-code`**, a read-only, whole-repo hunt for code
  nothing reaches any more, across four labelled lanes of deliberately unequal
  confidence (knip for TS/JS, vulture for Python, gopls for Go's unexported
  symbols, and a portable grep lane for shell and other symbol languages). Every
  candidate is adjudicated against the dynamic-usage evidence static analyzers
  are blind to and lands as `dead`, `uncertain`, or `alive`. Reports in-session;
  writes nothing and deletes nothing.
- **`/code-tidying:setup`**. `check` inspects the tracked
  `.claude/tidy-lanes/<lane>.md` project lanes read-only (presence, required
  sections, leftover placeholders, tracked-not-ignored); `apply` interviews the
  repo and scaffolds those lane files from the bundled templates, so `tidy`
  resolves project-specific scope globs deterministically instead of falling back
  to the generic bundled lanes. Re-runnable to add or retune lanes.

Neither `tidy` nor `batch-simplify` is `/simplify` itself: `/simplify` refines the diff you just
wrote; `batch-simplify` catches up on a window of them; `tidy` hunts drift no
one has filed yet.

## Lanes, the extension surface

`tidy` operates on lanes. Bundled lanes cover surfaces that look the same in
most repos (`shell-tooling`, `docs-prose`); your project defines its own lanes
by dropping files into **`.claude/tidy-lanes/<lane>.md`**, which take
precedence over bundled lanes of the same name. Copy the closest scaffold from
the plugin's `skills/tidy/templates/` (dependency-root, host-wiring, apps,
polyglot-services patterns) and fill in your scope globs, watch-for patterns,
exclusions, and verification commands. This surface does not resolve user-global
or `*.local.*` overlay layers. The bundled lane is the portable baseline, and
personal variation is limited to lane names the team does not track: an uncommitted
`.claude/tidy-lanes/<lane>.md` never added to the index (see `setup` and the
[config-cascade contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/config-cascade/README.md)).

## Safety model

- **Structure-only, always.** A "tidying" that breaks a test was secretly
  behavioral. It gets backed out, not shipped.
- **Hard/soft exclusions** gate every run: agent and CI configuration, hook
  chains, and lint configs are never touched; unverifiable areas (browser UI,
  auth flows, DB migrations) are deferred, not edited. Your project's own
  `CLAUDE.md` / rules extend both lists.
- **Backlog throttle**: ≥3 open `chore/tidy-*` PRs stops the run instead of
  piling on (bundled `open-pr-count.sh`, network access via your own `gh`
  auth).
- **No auto-merge.** Tidy PRs are always merged by a human.

## Works in any repo

- Self-contained: taxonomy, scope-budget research, exclusion lists, lane
  templates, and the throttle script all ship inside the plugin under
  `${CLAUDE_PLUGIN_ROOT}`. The bundled scripts require **Bash 4.3+** (they use
  `mapfile`, case-conversion expansions, and namerefs). On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)
  so they run under Git Bash; the scripts already handle CRLF and
  drive-letter paths.
- Graceful degrade: if the `discovery` plugin is installed, explore/research
  phases use `/discovery:explore` + `/discovery:research`; if `work-items` is
  installed, deferrals file through `/work-items:track add`; if
  `pr-review-toolkit` is installed, batch-simplify uses its `code-simplifier`
  agent. Absent any of them, the skills fall back to inline
  exploration/research, `gh issue create`, and general-purpose agents.
- Reads your conventions, assumes none: canonical build/test/lint commands,
  protected paths, and unverifiable areas come from your own project context.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install code-tidying@melodic-software
```

## Configuration

Three `userConfig` options, all for `dissolve-comments`; none loosens a gate:

| Option | Default | Effect |
|---|---|---|
| `comment_posture` | `strict` | `strict` rewrites an over-budget kept comment terser and stages the removed narrative; `balanced` reports it instead; `conservative` applies class-A deletions only and proposes everything else. Doubt keeps the comment in every posture. |
| `class_c_max_lines` | `2` | Line budget for a kept (class-C) comment before it is rewritten. |
| `apply_local_renames` | `true` | Apply a function-local rename that `change-shape.py` certifies as RENAME-ONLY even with no test net; `false` proposes it. |

Everything else routes through
`.claude/tidy-lanes/` lane files and your project's own `CLAUDE.md` /
`.claude/rules` (protected paths, verification commands). Run
**`/code-tidying:setup apply`** to interview your repo and scaffold those lane files
from the bundled templates (or `check` to inspect existing lanes read-only). It is
idempotent and safe to re-run to add or retune lanes.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `comment_posture` | string | `"strict"` | `CLAUDE_PLUGIN_OPTION_COMMENT_POSTURE` | How dissolve-comments treats a kept comment. strict (default): every kept comment is held to class_c_max_lines and rewritten terser when over it, with the removed narrative staged for the commit message; balanced: the same triage, but an over-budget comment is reported instead of rewritten; conservative: class-A deletions only, every class-B item and class-C rewrite is proposed. Doubt keeps the comment in every posture. Any other value is read as strict. |
| `class_c_max_lines` | number<br>*min 1, max 40* | `2` | `CLAUDE_PLUGIN_OPTION_CLASS_C_MAX_LINES` | Lines a kept (class-C) comment may run before dissolve-comments rewrites it terser, staging any removed narrative for the commit message. A genuinely load-bearing multi-line contract may exceed it when the report says why. |
| `apply_local_renames` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_APPLY_LOCAL_RENAMES` | When true (default), a function-local Rename Variable whose edit change-shape.py certifies as RENAME-ONLY is applied and reported with its identifier mapping even when no test net is discovered. When false, such renames are proposed. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure code-tidying@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install code-tidying@<marketplace> -s <scope> --config comment_posture=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "code-tidying@<marketplace>": {
         "options": {
           "comment_posture": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
