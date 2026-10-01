---
description: "Verify the eol-normalizer hook's runtime prerequisites and configuration for this repository. Use when: 'set up eol-normalizer', 'configure eol-normalizer', 'is eol-normalizer working', line endings silently aren't normalizing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Pre-computed context

`check`'s `jq` and `node` probes ran at load time. Read these rows instead of re-issuing them; each
shows the tool's path when present, or `absent` when missing:

- `jq`: !`{ command -v jq 2>/dev/null || echo "absent"; }`
- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

`git` is probed in the body, not here: the harness runs a skill's whole pre-compute block as one
shell invocation, and a worktree-isolated session refuses a compound command that names git.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. The
normalization policy is the repository's own `.gitattributes`, and the only tunable is the
native `userConfig` toggle. Every prerequisite is a system tool (Node.js, Bash, jq, git), so `apply`
is pure guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive. Never prompt when the action is given.

## `check` (read-only)

The hook is the single source of truth for what it requires and how it resolves things, and it
spans the entry script and the libraries it sources: `${CLAUDE_PLUGIN_ROOT}/hooks/eol-normalizer.sh`
sources `${CLAUDE_PLUGIN_ROOT}/hooks/normalize-eol.sh` (alongside the shared hook utilities), and
that sourced library is where the real resolution lives (the `git check-attr` calls, the repo-root
anchoring, and the NUL-byte binary guard), so the sourced files are in scope and the entry script
alone will not tell you what runs.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed `jq` and `node` rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report those probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL whatever the toggle says: the hook row
launches `node` before `exec-bash.mjs` can evaluate the gate, so every Write/Edit still tries an
unavailable command until `node` is installed or the plugin registration is disabled.

1. **Bash version.** Check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   Bash 5.0+).
2. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row runs through
   `node hooks/exec-bash.mjs`, so the hook never launches and emits no notice. This probe is the
   only visibility, and it runs through the Bash tool, so it works without the launcher.
3. **`jq`.** The pre-computed `jq` row. FAIL if absent: the hook then skips with a visible
   once per session and agent notice instead of normalizing.
4. **`git`.** `command -v git`. FAIL if absent: unlike jq, the hook emits NO visible notice
   when git is missing. `git check-attr` and repo-root resolution silently fail and the
   hook no-ops, so this probe is the only visibility. Distinguish the two non-failure cases
   the hook treats differently. Git present but the path is not inside a git repository →
   INFO, not applicable: nothing to normalize against, per the README. Git present
   inside a repo but no `eol=` rule governs any path → INFO, inert by design, the opt-in
   analog: resolution is entirely `.gitattributes`-driven.
5. **Consumer `.gitattributes` `eol=` policy.** Using the hook's own resolver
   (`git check-attr eol` anchored at the repo root), confirm whether any `eol=lf`/`eol=crlf`
   rule governs paths the hook would touch. `check-attr` answers for ANY candidate path,
   tracked or not. The hook normalizes a first write to a brand-new file the same as an
   edit to a tracked one, so probe representative candidate paths (or report the declared
   patterns), never a tracked-files listing that would miss untracked matches. Report what
   governs, or INFO that none does. Absence is the opt-out by design, so the plugin is
   inert (INFO, not FAIL), matching the README's "ships no policy of its own" stance.
6. **Hook toggle.** Report the effective `eol_normalizer_enabled` value:
   `${user_config.eol_normalizer_enabled}` (unexpanded or empty means default `true`).
7. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite here is a system
tool, so `apply` installs nothing and writes nothing. It only points:

- missing `node` / `jq` / Bash / git: platform install instructions from the README Requirements
  section; this skill never installs system packages.
- toggle off: reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention, which owns the verified-version record
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>):
  interactive `/plugin configure eol-normalizer@<marketplace>` any time, or headless
  `claude plugin install eol-normalizer@<marketplace> -s <scope> --config eol_normalizer_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed` **and
  still writes the value**. Do **not** uninstall to reconfigure: uninstalling drops this plugin's
  entire stored `pluginConfigs` entry, resetting every option in the README's Options reference
  to its manifest default. Pass the scope `claude plugin list` reports for this plugin, and for a
  `project` or `local` scope run from that project's directory, so the rerun matches the existing
  install record; from the home directory pass `user`. `-s` places the install record and
  `enabledPlugins`; the option value lands in user settings either way, and a rerun at another
  scope adds an install record at that scope and enables the plugin there. A rejected value prints
  a warning yet exits 0, so read the output. This skill never writes user settings or
  `pluginConfigs`. Afterwards rerun `check` in a **fresh session**. The rendered
  `${user_config.*}` is injected at skill load and each hook receives its
  `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so a same-session `check`
  still reports the OLD value; report the observed effective value, never an unobserved change.
- no `eol=` policy: this is the opt-out, not a defect. Point at the repository's own
  `.gitattributes` as the place to declare policy; this skill never writes `.gitattributes`,
  because that would impose a repo-wide line-ending policy the plugin has no mandate to
  choose.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Normalize any file. Editing a file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor `.gitattributes`.
- Install any tool, during either `check` or `apply`. All prerequisites are system tools
  resolved with guidance only.
