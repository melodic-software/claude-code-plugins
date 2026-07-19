---
name: setup
description: "Verify claude-config's external CLI prerequisites for this repository — jq (all audit scripts) and curl (the plugin-drift check) — so the audit skills run instead of failing. Use when: 'set up claude-config', 'configure claude-config', 'is claude-config working', or an audit skill reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply` resolves. This
plugin owns no consumer-project configuration and declares no `userConfig` — its only setup concern is
the external command-line tools its bundled scripts require. So `apply` is guidance-and-verify with no
write path: it points at platform install instructions and never installs a system package itself.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then remediation.
Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The bundled scripts are the single source of truth for what they require. **Read them first** — probe
what they actually do, don't recite this file — then run each probe via Bash and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything. The runtime scripts and their tools:

- `${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-plugin-drift.sh` — jq **and** curl
- `${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-structure.sh` and `fix-plugin-drift.sh` — jq
- `${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/inventory.sh` — jq
- `${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-grants/scripts/permission-rule-check.sh` — jq

1. **`jq`** — `command -v jq`. FAIL if absent: every audit script needs it (`inventory.sh` degrades to
   an empty inventory; the others `exit 2` with an install remediation). Missing `jq` blocks all three
   skills.
2. **`curl`** — `command -v curl`. FAIL if absent, but scoped: only the plugin-drift check
   (`check-plugin-drift.sh`) uses it and `exit 2`s without it. The rest of `audit` and the other two
   skills still run — say so in the remediation line.
3. **Bash shell** — INFO: the scripts are bash (arrays, `[[ ]]`, process substitution, `BASH_SOURCE`),
   run through Claude Code's Bash tool — the bash shell on every platform, Git Bash on native Windows.
   Report the resolved interpreter; FAIL only if no bash is resolvable.
4. **Network reachability** — INFO only: `audit`'s drift/freshness fetches read
   `raw.githubusercontent.com`, and a failed fetch degrades to SKIP rather than a setup failure. Do not
   fetch here — `check` performs no network call.

## `apply` (idempotent)

Run `check`, then for each FAIL give the platform install instructions from the README Requirements —
this skill never installs system packages:

- **missing `jq`:** the platform's jq install (for example `winget install jqlang.jq`, `brew install
  jq`, or `apt-get install jq`); rerun `check` after.
- **missing `curl`:** the platform's curl install — modern Windows and Git Bash already ship `curl`.
  Only the plugin-drift check needs it, so the rest of the plugin works meanwhile.

After any install, re-run the relevant `check` probe and report its actual result — never claim resolved
on the install command's exit code alone. Re-running `apply` once every probe passes changes nothing and
reports "already configured".

## What this skill does NOT do

- Run an audit — that is `/claude-config:audit`, `/claude-config:audit-automation-gaps`, and
  `/claude-config:audit-permission-grants`.
- Install system packages, write Claude Code settings or `pluginConfigs`, or touch the plugin cache.
- Download anything — `check` makes no network call; the audit skills' own doc/marketplace fetches are
  theirs, not setup's.
