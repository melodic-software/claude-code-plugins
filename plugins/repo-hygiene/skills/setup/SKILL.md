---
description: "Verify repo-hygiene's external prerequisites on this machine and report the effective destructive-guard toggle and the scope it actually applies at. The prerequisites are `git`, which the scan, git, stash, and tree tiers and the tracked-file guarantee all rest on, `node`, which launches the destructive guard, and the optional `ghq` the fleet batch actions enumerate repositories from. Use when: 'set up repo-hygiene', 'configure repo-hygiene', 'is repo-hygiene working', 'is the destructive guard on', 'why did tree-batch find no repos', or before a first clean on a new machine. Check-only: verifies, reports, and points at each remediation; installs nothing and there is nothing setup may write here. Re-runnable and safe."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v ghq*)"
shell: bash
---

## Pre-computed context

`check`'s `ghq` probe ran at load time. Read this row instead of re-issuing it; it shows
the tool's path when present, or `absent` when missing:

- `ghq`: !`command -v ghq 2>/dev/null || echo absent`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

`git` is probed in the body, not here ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation").

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration contains no
writable artifact, so `check` inspects, reports, and points at each remediation, and no `apply` is
offered because there is nothing it could conformingly write. The warrant is the carve-out's
external-prerequisites class: `git`, which every git-touching tier of `/repo-hygiene:clean` and
the tracked-file safety guarantee depend on, `node`, which launches the destructive guard, and the
optional `ghq` the fleet batch actions
enumerate repositories from. None is visible to a native configuration prompt; each is
verifiable only. The `clean_destructive_guard_enabled` option is a native `userConfig` toggle whose only
stored home is the `pluginConfigs` this contract forbids setup to write.

Action routing: no argument or `check` runs the check. Non-interactive, never prompts.

## `check` (read-only)

The clean skill and its bundled scripts are the single source of truth for what each tier requires.
**Read it first**, with the Read tool, by the paths the steps below name: `${CLAUDE_PLUGIN_ROOT}/skills/clean/SKILL.md` first, then each script a step names. Probe what it actually does, don't recite this file.

Never search the plugin directory: no Glob, Grep, `find`, `ls` or `cd` in `${CLAUDE_PLUGIN_ROOT}`, and no shell `head` or `cat` of its files. The files below are all it needs. Then read the
pre-computed `ghq` row, run each remaining probe as its own Bash call with nothing chained to it, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

Install nothing, and run no mutating tier.

1. **`git` on `PATH`**. `command -v git`, and report the resolved path and version. FAIL when
   absent, and state what is lost rather than a blanket "the plugin is broken":
   - `scan` resolves the repository through git and reports `not a git repository` when it cannot;
     the `git`, `stash`, `tree`, and `tree-batch` tiers are git operations outright.
   - The **any git-tracked file is off-limits** guarantee is enforced against the index by the
     shared `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/lib/clean-common.sh` (Read that file to confirm it)
     (`git ls-files --error-unmatch`), so even the `caches` and
     `build` tiers reach git through it, as does restoring a tracked file deleted by reparse-point
     traversal during a `tree` clean. No tier is safe to run without git.
2. **`ghq`** (optional). The pre-computed `ghq` row. Present: INFO, `ghq list -p` can feed
   `tree-batch` and the other `*-batch` actions. Absent: INFO, not a defect, the batch actions still
   take `--repo` (repeatable, glob-expanded) and `--repos-from FILE|-`; only the `ghq`-derived
   enumeration is unavailable. Report this rather than letting an empty repo list look like a bug.
3. **A POSIX shell for the bundled scripts**. Every tier script and the destructive guard are
   `bash`. On Windows that means Git Bash must be present. The guard is exec form: `command` is
   `node`, and `${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs` (Read it to confirm) finds bash (on Windows `CLAUDE_CODE_GIT_BASH_PATH`, then
   `Git\bin\bash.exe`, then `PATH`, never `System32\bash.exe`; <!-- portability-ok: Windows path, not a shell regex -->
   elsewhere `PATH`, then `/bin/bash` and `/usr/bin/bash`).
   - **Pointer**: for how an exec-form hook launches its command, fetch
     <https://code.claude.com/docs/en/hooks#exec-form-and-shell-form> live.

   Report the shell as INFO on Unix; FAIL on Windows when no Git Bash resolves, since the
   scripts and the guard alike cannot launch.
4. **`node` on `PATH`**. `command -v node`, and report the resolved path and version. Probe it
   through Bash, so it works without the launcher. FAIL when absent: every hook row runs
   `node hooks/exec-bash.mjs`, so without it the guard does not launch and is not enforced.

   - **Pointer**: for whether Claude Code's install uses Node at runtime, fetch
     <https://code.claude.com/docs/en/setup#install-with-npm> live.

5. **Destructive-guard registration and toggle**. INFO, and be precise about *where* the guard
   lives, because the answer is the reason it is session-scoped:
   - It registers from the frontmatter `hooks:` block in `${CLAUDE_PLUGIN_ROOT}/skills/clean/SKILL.md`,
     not from a plugin-level `hooks/hooks.json`, which this plugin does not ship. Claude Code
     arms it once `/repo-hygiene:clean` is invoked and keeps it armed for the rest of that session,
     so a session that never invoked the skill has no guard and nothing is wrong with that. Read that SKILL.md for the block (it runs `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive-guard.sh`); never look for a `hooks.json` or list `hooks/`.
   - Report the effective `${user_config.clean_destructive_guard_enabled}` (an unexpanded token or
     an empty value means the manifest default `true`). Read it from this text as rendered; never
     echo it through Bash, where an unexpanded token is invalid shell syntax and the call is
     refused. A change made now is observed only in a **fresh session**.

     - **Pointer**: for when a saved value reaches skill content, fetch
       [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
       live.
   - The option is **user-scoped**: plugin option values are read from user, `--settings`, and
     managed settings only, never from a project's `.claude/settings.json`. So there is no
     per-repository value of this toggle. To vary the behavior for one repository, enable or disable
     the plugin in that project's `enabledPlugins` instead.

## Remediation guidance (printed by `check`; the operator applies it)

The prerequisites are system tools and the one option lives in Claude Code's native
plugin configuration (Check-only carve-out, external-prerequisites and native-`userConfig`
classes), so `check` closes by pointing at each resolution rather than writing. Re-running it
after everything passes changes nothing and reports "already configured":

- **Missing `git`:** the platform's own install channel (<https://git-scm.com/downloads>). This
  plugin never downloads a tool.
- **Missing `ghq` and fleet actions wanted:** install it (<https://github.com/x-motemen/ghq>), or
  keep using `--repo` / `--repos-from` and say so. This is a convenience, not a blocker.
- **Missing `node`:** install Node.js (<https://nodejs.org/en/download>) and put it on `PATH`. Until
  then the destructive guard is not enforced.
- **Missing Git Bash on Windows:** install Git for Windows; nothing in this plugin runs without it.
- **Toggle off (or on):** set `clean_destructive_guard_enabled` to `true` or `false` through
  Claude Code's native flow, interactively with `/plugin configure repo-hygiene@<marketplace>` or
  by a headless route, as the marketplace's plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Apply the scope and failure-signal caveats in its
  [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
  Read both sections and print what they give, the fallback route, its behavior on an
  already-installed plugin and the scope to pass included, rather than only naming them, and
  leave out the verified-version record.
  Never uninstall to reconfigure; that section links what an uninstall deletes. This skill never
  writes user settings or `pluginConfigs`. Afterwards rerun `check` in a **fresh session**, since a
  same-session `check` can still show the old value, and report the observed effective toggle
  value, never an unobserved change.

  - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
    when a saved value applies, fetch
    [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
    live.

## What this skill does NOT do

- Scan, clean, prune, or reset anything. Those are `/repo-hygiene:clean`'s tiers, with their own
  dry-run-first and confirmation contract.
- Install `git`, `ghq`, or any tool. Guidance only.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor any other Claude Code
  settings file.
