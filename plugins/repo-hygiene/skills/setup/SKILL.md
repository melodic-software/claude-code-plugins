---
description: "Verify repo-hygiene's external prerequisites on this machine — `git`, which the scan, git, stash, and tree tiers and the tracked-file guarantee all rest on, and the optional `ghq` the fleet batch actions enumerate repositories from — and report the effective destructive-guard toggle and the scope it actually applies at. Use when: 'set up repo-hygiene', 'configure repo-hygiene', 'is repo-hygiene working', 'is the destructive guard on', 'why did tree-batch find no repos', or before a first clean on a new machine. Check-only: verifies, reports, and points at each remediation; installs nothing and there is nothing setup may write here. Re-runnable and safe."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Check-only setup under the Check-only carve-out (`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration surface contains no
writable artifact, so `check` inspects, reports, and points at each remediation, and no `apply` is
offered because there is nothing it could conformingly write. The warrant is the carve-out's
external-prerequisites class: `git`, which every git-touching tier of `/repo-hygiene:clean` and
the tracked-file safety guarantee depend on, and the optional `ghq` the fleet batch actions
enumerate repositories from — neither visible to a native configuration prompt, each verifiable
only. The `clean_destructive_guard_enabled` option is a native `userConfig` toggle whose only
stored home is the `pluginConfigs` this contract forbids setup to write.

Action routing: no argument or `check` runs the check. Non-interactive, never prompts.

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

## Remediation guidance (printed by `check`; the operator applies it)

Both prerequisites are system tools and the one option lives in Claude Code's native
configuration surface (Check-only carve-out, external-prerequisites and native-`userConfig`
classes), so `check` closes by pointing at each resolution rather than writing. Re-running it
after everything passes changes nothing and reports "already configured":

- **Missing `git`:** the platform's own install channel (<https://git-scm.com/downloads>). This
  plugin never downloads a tool.
- **Missing `ghq` and fleet actions wanted:** install it (<https://github.com/x-motemen/ghq>), or
  keep using `--repo` / `--repos-from` and say so. This is a convenience, not a blocker.
- **Missing Git Bash on Windows:** install Git for Windows; nothing in this plugin runs without it.
- **Toggle off (or on):** reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure repo-hygiene@<marketplace>`
  any time, or headless `claude plugin install repo-hygiene@<marketplace> -s <scope> --config clean_destructive_guard_enabled=true`
  (repeatable per key) — against an already-installed plugin it prints `already installed` and
  still writes the value. Do **not** uninstall to reconfigure: that drops this plugin's entire
  stored `pluginConfigs` entry, resetting every option in the README's Options reference to its
  manifest default. `-s` defaults to `user`; pass the scope `claude plugin list` reports, and run
  from that project's directory for a `project`/`local` scope, or the write lands at a scope that
  does not load. This skill never writes user settings or `pluginConfigs`. Afterwards rerun
  `check` in a **fresh session** — the rendered token is injected at skill load, so a same-session
  `check` still reports the OLD value; report the observed effective toggle value, never an
  unobserved change.

## What this skill does NOT do

- Scan, clean, prune, or reset anything. Those are `/repo-hygiene:clean`'s tiers, with their own
  dry-run-first and confirmation contract.
- Install `git`, `ghq`, or any tool. Guidance only.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any other Claude Code
  settings surface.
