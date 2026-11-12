---
description: "Verify the eol-normalizer hook's runtime prerequisites and configuration for this repository. Use when: 'set up eol-normalizer', 'configure eol-normalizer', 'is eol-normalizer working', line endings silently aren't normalizing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(command -v node*)"
shell: bash
---

## Pre-computed context

`check`'s `jq` and `node` probes ran at load time. Read these rows instead of re-issuing them; each
shows the tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `node`: !`command -v node 2>/dev/null || echo absent`

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
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report those probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL whatever the toggle says: the hook row
launches `node` before `exec-bash.mjs` can evaluate the gate, so every tool-call batch still tries an
unavailable command until `node` is installed or the plugin registration is disabled.

1. **Bash version.** Check against the floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`).
2. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row runs through
   `node hooks/exec-bash.mjs`, so the hook never launches and emits no notice. This probe is the
   only visibility, and it runs through the Bash tool, so it works without the launcher.
3. **`jq`.** The pre-computed `jq` row. FAIL if absent: the batch hook reads the files a batch
   wrote with jq, so without it the hook exits silently and normalizes nothing. This probe is the
   only visibility.
4. **`git`.** `command -v git`. FAIL if absent: `git check-attr` silently fails and the
   hook no-ops without any notice, so this probe is the only visibility. Distinguish the two non-failure cases
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
- toggle off: set `eol_normalizer_enabled` to `true` through Claude Code's native flow,
  interactively with `/plugin configure eol-normalizer@<marketplace>` or by a headless route, as the
  marketplace's plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Apply the scope and failure-signal caveats in its
  [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
  Read both sections and print what they give, the fallback route, its behavior on an
  already-installed plugin and the scope to pass included, rather than only naming them, and
  leave out the verified-version record.
  Never uninstall to reconfigure; that section links what an uninstall deletes. This skill never
  writes user settings or `pluginConfigs`. Afterwards rerun `check` in a **fresh session**, since a
  same-session `check` can still show the old value, and report the observed effective value,
  never an unobserved change.

  - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
    when a saved value applies, fetch
    [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
    live.
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
