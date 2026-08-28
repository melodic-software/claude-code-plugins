---
description: "Verify repo-hygiene's external prerequisites on this machine — `git`, which the scan, git, stash, and tree tiers and the tracked-file guarantee all rest on, and the optional `ghq` the fleet batch actions enumerate repositories from — and report the effective destructive-guard toggle and the scope it actually applies at. Use when: 'set up repo-hygiene', 'configure repo-hygiene', 'is repo-hygiene working', 'is the destructive guard on', 'why did tree-batch find no repos', or before a first clean on a new machine. Actions: check (read-only verification, default) | apply (point at each remediation; installs nothing). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and reports,
`apply` points at what it found. The warrant is criterion (b), external prerequisites. `git`,
which every
git-touching tier of `/repo-hygiene:clean` and the tracked-file safety guarantee depend on, and the
optional `ghq` the fleet batch actions enumerate repositories from. Neither of which a native
configuration prompt can see, and each of which setup can only verify. The
`clean_destructive_guard_enabled` option is a native `userConfig` toggle whose only stored home is
the `pluginConfigs` this contract forbids setup to write, so this setup is check-only: `apply`
installs nothing, writes nothing, and is idempotent by construction.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then points at
each remediation. Both are non-interactive, never prompt when the action is given.

## `check` (read-only)

The clean skill and its bundled scripts (`${CLAUDE_PLUGIN_ROOT}/skills/clean/`) are the single
source of truth for what each tier requires.

**Read it first.** Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

Install nothing, and run no mutating tier.

1. **`git` on `PATH`**. `command -v git`, and report the resolved path and version. FAIL when
   absent, and state what is lost rather than a blanket "the plugin is broken":
   - `scan` resolves the repository through git and reports `not a git repository` when it cannot;
     the `git`, `stash`, `tree`, and `tree-batch` tiers are git operations outright.
   - The **any git-tracked file is off-limits** guarantee is enforced against the index by the
     shared `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/lib/clean-common.sh`
     (`git ls-files --error-unmatch`), so even the `caches` and
     `build` tiers reach git through it, as does restoring a tracked file deleted by reparse-point
     traversal during a `tree` clean. No tier is safe to run without git.
2. **`ghq`** (optional). `command -v ghq`. Present: INFO, `ghq list -p` can feed `tree-batch` and
   the other `*-batch` actions. Absent: INFO, not a defect, the batch actions still take `--repo`
   (repeatable, glob-expanded) and `--repos-from FILE|-`; only the `ghq`-derived enumeration is
   unavailable. Report this rather than letting an empty repo list look like a bug.
3. **A POSIX shell for the bundled scripts**. Every tier script and the destructive guard are
   `bash`. On Windows that means Git Bash must be present; the guard is registered in **shell form**
   with `shell: bash` precisely so Claude Code resolves it rather than a `PATH` lookup finding the
   WSL relay. Report the shell as INFO on Unix; FAIL on Windows when no Git Bash resolves, since the
   scripts and the guard alike cannot launch.
4. **Destructive-guard registration and toggle**. INFO, and be precise about *where* the guard
   lives, because the answer is the reason it is session-scoped:
   - It registers from the `hooks:` block in `${CLAUDE_PLUGIN_ROOT}/skills/clean/SKILL.md`
     frontmatter, not from a plugin-level `hooks/hooks.json`. This plugin ships none. Claude Code
     arms it once `/repo-hygiene:clean` is invoked and keeps it armed for the rest of that session,
     so a session that never invoked the skill has no guard and nothing is wrong with that.
   - Report the effective `${user_config.clean_destructive_guard_enabled}` (an unexpanded token or
     an empty value means the manifest default `true`). The rendered value is injected when this
     skill loads, so a change made now is observed only in a **fresh session**.
   - The option is **user-scoped**: plugin option values are read from user, `--settings`, and
     managed settings only, never from a project's `.claude/settings.json`. So there is no
     per-repository value of this toggle. To vary the behavior for one repository, enable or disable
     the plugin in that project's `enabledPlugins` instead.

## `apply` (idempotent)

Run `check`, then point at each resolution. Both prerequisites are system tools and the one option
lives in Claude Code's native configuration surface, so `apply` writes nothing and installs
nothing. Re-running it after everything passes changes nothing and reports "already configured":

- **Missing `git`:** the platform's own install channel (<https://git-scm.com/downloads>). This
  plugin never downloads a tool.
- **Missing `ghq` and fleet actions wanted:** install it (<https://github.com/x-motemen/ghq>), or
  keep using `--repo` / `--repos-from` and say so. This is a convenience, not a blocker.
- **Missing Git Bash on Windows:** install Git for Windows; nothing in this plugin runs without it.
- **Toggle off (or on):** direct to `/plugin configure repo-hygiene@<marketplace>` (interactive, any
  time). Headless: rerun the install with the new value: `claude plugin install repo-hygiene@<marketplace> -s <scope> --config clean_destructive_guard_enabled=true`
  (repeatable per key). Against an already-installed plugin it
  prints `already installed` **and still writes the value**. Verified on Claude Code 2.1.240 (a
  non-sensitive option at `user` scope: a non-default value written to an installed plugin, then
  restored). The short-circuit is about the install, not the config write. Re-verify before relying
  on it outside those conditions. A `sensitive` option, or `project`/`local` scope, were not
  covered. Do **not** uninstall to reconfigure: uninstalling drops this plugin's entire stored
  `pluginConfigs` entry, resetting every option in the README's Options reference table to its
  manifest default. `-s` defaults to `user`, so pass the scope `claude plugin list` reports for this
  plugin, and run from that project's directory for a `project`/`local` scope, or the write lands at
  a scope that does not load. This skill never writes user settings or `pluginConfigs`. Afterwards
  rerun `check` **in a fresh session**, the rendered token is injected at skill load, and report
  the observed effective toggle value; never claim an unobserved change.

## What this skill does NOT do

- Scan, clean, prune, or reset anything. Those are `/repo-hygiene:clean`'s tiers, with their own
  dry-run-first and confirmation contract.
- Install `git`, `ghq`, or any tool, during either `check` or `apply`. Guidance only.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any other Claude Code
  settings surface.
