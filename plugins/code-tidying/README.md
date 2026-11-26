# code-tidying

A Claude Code plugin for **structure-only** codebase improvement, applying Kent
Beck's *Tidy First?* discipline agentically: small named tidyings, separated
from behavioral changes by commit and by PR, under the shared PR scope budget
shipped as [`reference/pr-scope-budget.md`](reference/pr-scope-budget.md).

Seven skills, one capability:

- **`/code-tidying:remove-comments`**. Removes the comments in a diff or target
  that do not earn their keep (a clean tree widens to the branch diff, then to
  the whole repository in safe mode, ranked by exposure and comment
  payload), under a posture: `necessary` (the default) keeps only machine-read
  directives, license headers, `TODO(#issue)` markers, paired comment-and-test
  records and a keep list (shipped: public-API doc comments, verified
  outside-constraint comments, one-line ADR pointers and a script header's
  exit-code list; a repository can
  supply its own), turning every other warning into a reshape flag;
  `explanatory` (opt-in) keeps every terse,
  load-bearing comment code cannot express; `none` (opt-in) keeps only the
  first four and public-API doc comments.
  Zero-information comments are deleted, code-expressible ones dissolve into
  names and structure via behavior-preserving refactoring first. Deletions and
  function-local renames apply behind a token-level proof (`change-shape.py`, so
  they act on a repository with no test suite); additive refactors need a
  discovered test net; interface-creating ones are proposal-first. `safe`
  restricts applied edits to removals, `report` applies nothing, and no
  posture loosens a gate. The triage and the comment-only edits run in the
  `code-tidying:comment-reviewer` agent, a fresh reader; the skill checks its
  diff and applies any code moves. Its `audit` action is the read-only
  classifier for out-of-context comment residue (history narration, plan and
  session references, conversational antecedents, ticket and PR
  back-references, origin notes, workarounds with no link or removal
  condition). Ships a comment census with a token estimate and a
  cross-language commented-out-code detector, and probes its reading layers
  (`scc`, `pygments`, `tree-sitter`, `pwsh`, `ruff`, `ast-grep`) at run time,
  naming what each absent one costs.
- **`/code-tidying:audit-comment-residue`**. Flags out-of-context comment residue
  and edits nothing, by running `remove-comments`' `audit` action.
- **`/code-tidying:tidy`**. Proactively hunts a rotated, glob-scoped *focus area* of
  the codebase for safe structural improvements (Beck's 15 tidyings + a Fowler
  subset + prose tidyings), applies scope-budgeted edits, and ships one tight
  structure-only PR. Scope is a rotated focus area or an ad hoc glob
  (`tidy [dry-run] <glob>...`). `in-place` skips the branch and PR and leaves the
  edits staged; `in-place=commit` makes one commit. Overflow is filed as deferred work items, never silently
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
  sweep a repository that never had one. `in-place` (repo mode) runs on the
  current branch with no new branch or PR and leaves the edits staged, or
  `in-place=commit` makes one commit.
- **`/code-tidying:tidy-diff`**. Tidies one change's own lines before its
  commit, scoped by a file-and-line list the caller writes (no branch or base
  ref, so it runs on a detached head): a behavior-preserving simplify pass,
  proven class-A comment deletions and a generated-code residue pass (swallowed
  errors, silent fallbacks, silencing casts, debug logs; a fix that changes
  behavior comes back as a proposal) on code, then `/docs-hygiene:write-for-agents`
  or `write-for-humans` and `/ai-slop:audit fix` on markdown, within an
  optional turn budget. It stages and commits nothing. The issue lane runs it
  on a small single-area change before its one push.
- **`/code-tidying:audit-dead-code`**, a read-only, whole-repo hunt for code
  nothing reaches any more, across four labeled lanes of deliberately unequal
  confidence (knip for TS/JS, vulture for Python, gopls for Go's unexported
  symbols, and a portable grep lane for shell and PowerShell symbols, JS/TS
  symbols outside a `package.json` root, C# declarations read as text, plus
  unreferenced source files with a recognized extension). Every
  candidate is adjudicated against the dynamic-usage evidence static analyzers
  are blind to and lands as `dead`, `uncertain`, or `alive`. Reports in-session;
  writes nothing and deletes nothing.
- **`/code-tidying:setup`**. `check` inspects the tracked
  `.claude/tidy-areas/<area>.md` project focus areas read-only (presence, required
  sections, leftover placeholders, tracked-not-ignored), validates the optional
  `.claude/code-tidying/exclusion-overrides.md`, and reports the stored
  `hard_exclusions` posture; `apply` interviews the
  repo and scaffolds those focus area files from the bundled templates, so `tidy`
  resolves project-specific scope globs deterministically instead of falling back
  to the generic bundled focus areas. Re-runnable to add or retune focus areas.

Neither `tidy` nor `batch-simplify` is `/simplify` itself: `/simplify` refines the diff you just
wrote; `batch-simplify` catches up on a window of them; `tidy` hunts drift no
one has filed yet.

## Focus areas, the extension surface

`tidy` operates on focus areas. Bundled focus areas cover surfaces that look the same in
most repos (`shell-tooling`, `docs-prose`); your project defines its own focus areas
by dropping files into **`.claude/tidy-areas/<area>.md`**, which take
precedence over bundled focus areas of the same name. Copy the closest scaffold from
the plugin's `skills/tidy/templates/` (dependency-root, host-wiring, apps,
polyglot-services patterns) and fill in your scope globs, watch-for patterns,
exclusions, and verification commands. This surface does not resolve user-global
layers or `*.local.*` personal overrides. The bundled focus area is the portable baseline, and
personal variation is limited to focus area names the team does not track: an uncommitted
`.claude/tidy-areas/<area>.md` never added to the index (see `setup` and the
[config-cascade contract](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/config-cascade/README.md)).

## Safety model

- **Structure-only, always.** A "tidying" that breaks a test was secretly
  behavioral. It gets backed out, not shipped.
- **Hard/soft exclusions** gate every run: agent and CI configuration, hook
  chains, and lint configs are not touched by default; unverifiable areas
  (browser UI, auth flows, DB migrations) are deferred, not edited. Your
  project's own `CLAUDE.md` / rules extend both lists.
- **The hard path list is overridable**, through three channels that only ever
  subtract from it: an `override` argument on `tidy`, `remove-comments`, and
  `batch-simplify` (this run), the `hard_exclusions` option below (this
  operator), and a tracked `.claude/code-tidying/exclusion-overrides.md` of
  root-relative globs (this repository), resolved per path in that order. So
  `/code-tidying:remove-comments override ruff.toml` triages a file the list
  would otherwise drop. Every lifted path is named in the run's report beside
  the channel that lifted it. What no channel lifts: the behavioral guards
  (structure-only is the skills' contract, not a path limit), the work-tracking
  exclusions, and the self-update focus area's protection of this plugin's own
  contract surface.
- **Backlog throttle**: open `chore/tidy-*` PRs at the `upkeep_max_open` limit
  (default 3, [reference/config.md](reference/config.md)) stop the run instead
  of piling on (bundled `open-pr-count.sh`, network access via your own `gh`
  auth).
- **The skill never merges.** The repository's merge lane, where it has one, or
  a person merges a tidy PR.

## Works in any repo

- Self-contained: taxonomy, scope budget, exclusion lists, focus area
  templates, and the throttle script all ship inside the plugin under
  `${CLAUDE_PLUGIN_ROOT}`. The bundled scripts require **Bash 4.3+** (they use
  `mapfile`, case-conversion expansions, and namerefs). On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)
  so they run under Git Bash; the scripts already handle CRLF and
  drive-letter paths.
- Graceful degrade: if the `discovery` plugin is installed, explore/research
  phases use `/discovery:explore` + `/discovery:research`; if `work-items` is
  installed, deferrals file through `/work-items:track add`; if
  `code-simplifier` (or legacy `pr-review-toolkit`) is installed, batch-simplify uses its
  `code-simplifier` agent. Absent any of them, the skills fall back to inline
  exploration/research, `gh issue create`, and general-purpose agents.
- Reads your conventions, assumes none: canonical build/test/lint commands,
  protected paths, and unverifiable areas come from your own project context.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install code-tidying@melodic-software
```

## Configuration

Seven `userConfig` options. Six tune `remove-comments`, and none of them
loosens a gate: they set what a run removes, never what it may apply without a
proof. They also read from the team file `<home>/code-tidying.yaml` (schema:
`schemas/code-tidying.schema.json`) and its personal override
`<home>/code-tidying.local.yaml`, `<home>` being the bound convention home, else
`docs/conventions`; these win over `userConfig` in that order. The seventh, `hard_exclusions`, is `userConfig` only: it is the
personal-posture channel of the exclusion override above, and loosening is its
whole job:

| Option | Default | Effect |
|---|---|---|
| `hard_exclusions` | `enforce` | `enforce` keeps every GLOBAL HARD **path** entry blocking; `advisory` reports each match and blocks nothing, so runs may reach lint config, agent config, CI workflows, and hook chains. Path entries only: the behavioral guards, the work-tracking entries, and the self-update protections hold at either value. |
| `comment_posture` | `auto` | `auto` is `necessary`; `none`, `necessary` and `explanatory` fix it. The per-run tokens `safe`, `none`, `necessary` and `explanatory` beat this value, `safe` first. |
| `comment_keep_list` | `default` | What `necessary` keeps above the floor. `default` is the shipped `skills/remove-comments/reference/keep-list.md`; a repository-relative path to your own criteria file replaces it. The floor stays under every list, and a run names a non-shipped list in its report. |
| `comment_edit_scope` | `diff` | `diff` triages only the comments on lines a change adds; `files` triages every comment in each changed file. |
| `encode_constraints_unattended` | `false` | `true` lets an unattended run encode a constraint comment as a test, assertion or lint rule without asking; `false` offers it in the report. |
| `class_c_max_lines` | `2` | Line budget for a kept (class-C) comment before it is rewritten. |
| `apply_local_renames` | `true` | Apply a function-local rename that `change-shape.py` certifies as RENAME-ONLY even with no test net; `false` proposes it. |

Everything else routes through
`.claude/tidy-areas/` focus area files, the optional
`.claude/code-tidying/exclusion-overrides.md`, and your project's own `CLAUDE.md` /
`.claude/rules` (protected paths, verification commands). Run
**`/code-tidying:setup apply`** to interview your repo and scaffold those focus area files
from the bundled templates (or `check` to inspect existing focus areas, validate the
overrides file, and report the stored `hard_exclusions` posture read-only). It is
idempotent and safe to re-run to add or retune focus areas.

### Option details

**`hard_exclusions`.** The GLOBAL HARD path list lives in `skills/tidy/reference/exclusions.md`.
`advisory` is the standing form of the per-run override argument and is lifted for path entries
only: the behavioral guards, the work-tracking entries, and the SELF-UPDATE EXTRA HARD list hold
under every value. A skill that reads an empty, unexpanded, or unrecognized value treats it as
`enforce`.

**`comment_posture`.** `explanatory` holds every kept comment to the earn-its-keep test and
`class_c_max_lines`, rewriting one over the budget terser; `necessary`, the default, keeps only the
floor (machine-read directives, suppression justifications, license headers, `TODO(#issue)` markers,
paired records) and the `comment_keep_list` list, deleting every other comment with
its narrative staged and a reshape flag naming the symbol; `none` keeps only the floor and public-API
doc comments. Old values still resolve: `strict` and `balanced` as `explanatory`, `conservative` as
`explanatory` with `safe`, `aggressive` as `necessary`. No posture loosens a gate: every applied
deletion still carries the token proof and every tier-2 or tier-3 move still needs a test net. A
value outside the set is named and its layer dropped.

### Comment lint (git hook and CI)

A `pre-commit` git-hook entry, `comment-lint`, fails a comment a change adds outside the comment
posture. It detects and never edits; `/code-tidying:remove-comments` is the fix. Four team-file
settings drive it, all read from `<home>/code-tidying.yaml` only, with no personal override and no
`userConfig` option:

| Setting | Default | Effect |
|---|---|---|
| `comment_lint` | `off` | `off` runs nothing; `report` prints the findings and exits 0; `block` prints them and fails the commit. `off` is the kill switch. |
| `comment_lint_allow` | `[]` | Extended regular expressions (matched with `grep -E`) for the repository's own comment markers, such as a gate's `# silent-skip-ok:`, and for a tool directive the built-in list lacks. A comment whose text matches one passes. |
| `comment_lint_exclude` | `[]` | Repository-relative path globs of files the lint skips, each skip named on stderr; no other check reads it. `*` and `?` match within one path segment, `**` spans segments (`**/` also matches none), and every other character is literal. For files whose comments are not the repository's own, such as vendored copies kept byte-identical; keep each entry as narrow as those files need and state its justification in a comment beside it. |
| `comment_adr_dir` | `docs/adr` | Repository-relative folder of the decision records. A one-line ADR pointer (`ADR-0042`, or a path into the folder) passes only when its record exists there. A value outside the repository is ignored and the default applies. |

The posture comes from `comment_posture` in the team file and its personal override. A git hook
runs outside Claude Code, so a `userConfig` posture never reaches it; unset reads as `auto`, which
is `necessary`. Under `explanatory` (and `strict`, `balanced`, `conservative`) the lint does not
run.

A comment is a comment token of the pygments lexer for the file's name. The lint judges files whose
extension `scripts/code-extensions.txt` lists, skips a file whose first 10 lines match a line of
`scripts/generated-marker.ere`, and judges only the lines the change adds. That file counts
`sync-managed` and `@generated` anywhere, and `do not edit` only as a whole-file notice: at the
end of the line, before punctuation or `this file`, `this copy`, `by hand`, `manually` or
`directly`, or on a line that also says `generated`. A hand-written `# do not edit the order
below` is judged. Under
`necessary` these pass:

1. A shebang on line 1, an encoding cookie on line 1 or 2.
2. A tool directive: lint, type-checker, coverage and scanner pragmas, editor modelines, region
   markers.
3. A comment run with a license or copyright cue.
4. `TODO(#issue)`.
5. A trailing comment on a `uses:` line pinned to a full commit id.
6. A line carrying `remove-comments-ignore`.
7. A structured doc comment: a docstring, `///`, `/** */`, PowerShell comment-based help, a Go
   comment directly above an exported declaration. A script's opening `#` header is not one.
8. A comment paragraph holding a URL or an RFC number, when it runs at most `class_c_max_lines`
   lines (team file or personal override, default 2), and the blank lines (only comment markers)
   of the same comment. A paragraph is the consecutive comment lines holding a word character,
   less any line that passes by its own shape above; the other paragraphs of that comment, and a
   punctuation-only line such as `// ----`, are judged on their own.
9. The line after a `remove-comments-ignore` or `dissolve-comments-ignore` marker, the
   `dissolve-comments-ignore` line itself, `FIXME(#issue)`, PowerShell `#Requires` and the
   signature block, and a suppression's reason on the waiver's line or the line before it.
10. In a script's opening `#` comment block (the comment lines that start the file, after any
    shebang), an `Exit`, `Exit codes` or `Exits` heading line and its entries: a line starting
    with a status number then text, and that entry's continuation lines, indented deeper than the
    number. The heading line may hold the first entry, as in `# Exit 2: usage`. The rest of that
    header still fails.

Under `none`, all but 8 and 10 pass. Any other added comment prints
`<path>:<line>: comment outside the <posture> posture: delete it, move the reason into the code or
the commit message, or link the outside constraint; /code-tidying:remove-comments fixes it`. An
outside-constraint note or ADR pointer the keep list keeps fails until it carries a link or
`remove-comments-ignore`.

The lint also judges paths the comment pass excludes by default, such as a workflow file or a hook
manager's config. Fix a finding there by hand, or run the pass with its `override` argument.

Install it with `/code-tidying:setup apply install-git-hooks`; `check` reports its drift, and the
session-start probe names a missing or stale copy. It needs `python3` with pygments importable
(`python3 -m pip install pygments`); either missing follows the check-placement skip key,
`git -c checks.skipmissing=python3` or `checks.skipmissing=pygments`.

**CI.** CI re-runs the lint on each change, judged against the base branch's settings, so a commit
that skipped the hook is still checked and a branch cannot lower its own level. The plugin ships
the script; `/code-tidying:setup apply install-ci` writes the step that calls it. It finds the
repository's CI system from the files present, reads how the existing jobs get Python and their
change's commits, asks only what that leaves open, and proposes the step in that system's own
format and the repository's conventions, written only on your yes. No CI system is a default and no
vendor template ships. `/code-tidying:setup check` reports the job that runs the script, or the
drift when a call no longer matches its interface.

```text
bash git-hooks/comment-lint-ci.sh <head> <base>
```

`<head>` is the change's head commit, `<base>` the ref it merges into (such as `origin/main`) or a
commit id; run it from inside the clone, with history back to their merge base and Python 3 with
pygments on `PATH`. It adds a worktree at `<head>` without checking files out, soft-resets it to
the merge base so the change is the staged diff, takes `AGENTS.md`, `CLAUDE.md` and the home's
`code-tidying.yaml` and `code-tidying.local.yaml` as the merge base holds them, runs
`comment-lint.sh` from beside itself, and removes the worktree. It exits with the lint's status
(1 on a finding under `block`) and 2 on a usage error. A shared install
(`apply install-git-hooks scope=shared`) commits it under `.githooks/code-tidying/` beside the
hook.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `hard_exclusions` | string | `"enforce"` | How tidy, remove-comments, and batch-simplify treat the GLOBAL HARD path list. enforce (default) drops a listed path before triage; advisory reports it per path and never blocks, so a run may edit lint config, agent config, CI workflows, and hook chains. |
| `comment_posture` | string | `"auto"` | Which comments remove-comments keeps. auto (default): necessary. none: only directives, license headers, TODO(#issue), paired records and public doc comments. necessary: those plus the keep list (comment_keep_list). explanatory: whatever passes the earn-its-keep test. |
| `comment_keep_list` | string | `"default"` | What the necessary posture keeps above the floor. default: the shipped list (public-API doc comments, verified outside-constraint comments, one-line ADR pointers, a script header's exit-code list). A repository-relative path: that file's criteria replace the shipped list; the floor always stays. |
| `comment_edit_scope` | string | `"diff"` | Which comments remove-comments triages on the uncommitted and branch scope rungs. diff (default): only comments on the lines the change adds. files: every comment in each changed file. An explicit target and the repository rung are always whole files. |
| `encode_constraints_unattended` | boolean | `false` | When true, an unattended remove-comments run may encode a constraint comment as a test, assertion or lint rule without asking, behind its tier's gate. When false (default), it offers the encoding in its report. |
| `class_c_max_lines` | number<br>*min 1, max 40* | `2` | Lines a kept (class-C) comment may run before remove-comments rewrites it terser, staging any removed narrative for the commit message. A genuinely load-bearing multi-line contract may exceed it when the report says why. |
| `apply_local_renames` | boolean | `true` | When true (default), a function-local Rename Variable whose edit change-shape.py certifies as RENAME-ONLY is applied and reported with its identifier mapping even when no test net is discovered. When false, such renames are proposed. |

### How to set these

Set the options above for `code-tidying@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
