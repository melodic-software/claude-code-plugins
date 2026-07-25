---
name: setup
description: "Verify claude-config's readiness for this repository — the external CLI prerequisites its audit scripts need, jq (the JSON-parsing audit scripts) and curl (the plugin-drift check), and the tracked suppression record audit-pass reads at .claude/audit-pass.md — so the audit skills run instead of failing. Use when: 'set up claude-config', 'configure claude-config', 'is claude-config working', 'set up audit-pass suppressions', or an audit skill reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Setup per the uniform contract: `check` inspects and reports, `apply` resolves. This plugin declares no
`userConfig`, and has two setup concerns:

- the external command-line tools its bundled scripts require — here `apply` is guidance-and-verify
  with no write path: it points at platform install instructions and never installs a system package;
- the **tracked consumer-project configuration** `audit-pass` reads, the suppression record at
  `.claude/audit-pass.md` — the one surface `apply` may write.

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
- `${CLAUDE_PLUGIN_ROOT}/skills/audit-instructions/scripts/instruction-scan.sh` — grep only (POSIX; no jq)

1. **`jq`** — `command -v jq`. FAIL if absent: the JSON-parsing scripts need it (`inventory.sh` degrades
   to an empty inventory; the others `exit 2` with an install remediation). Missing `jq` blocks the three
   JSON-parsing audit skills (`audit`, `audit-automation-gaps`, `audit-permission-grants`);
   `audit-instructions` scans markdown with grep only and is unaffected.
2. **`curl`** — `command -v curl`. FAIL if absent, but scoped: only the plugin-drift check
   (`check-plugin-drift.sh`) uses it and `exit 2`s without it. The rest of `audit` and the other three
   skills still run — say so in the remediation line.
3. **Bash shell** — INFO: the scripts are bash (arrays, `[[ ]]`, process substitution, `BASH_SOURCE`),
   run through Claude Code's Bash tool — the bash shell on every platform, Git Bash on native Windows.
   Report the resolved interpreter; FAIL only if no bash is resolvable.
4. **Network reachability** — INFO only: `audit`'s drift/freshness fetches read
   `raw.githubusercontent.com`, and a failed fetch degrades to SKIP rather than a setup failure. Do not
   fetch here — `check` performs no network call.

### The `audit-pass` suppression record

`audit-pass` reads a tracked suppression record layered per the marketplace's config-cascade
convention. Its keys, required fields, merge form, and precedence inversion are owned by
[docs/conventions/finding-suppression](../../../../docs/conventions/finding-suppression/README.md) —
read it rather than inferring the shape. All layers absent is a valid state (no suppressions), so
report INFO, never FAIL, when none exists.

Anchor at the repo root (`${CLAUDE_PROJECT_DIR}`, else `git rev-parse --show-toplevel`) — never a
CWD-relative read — then report one row per layer. The same tracked/ignored question has opposite
correct answers per layer, so verify each on its own terms:

- **user-global** `~/.claude/audit-pass.md` — outside the worktree; no git command applies. INFO only.
- **team** `.claude/audit-pass.md` — must be tracked. Untracked while present is a hard STOP:
  teammates never receive the shared suppressions.
- **local overlay** `.claude/audit-pass.local.md` — must be gitignored and never staged. Staged or
  tracked is a FAIL: a personal deviation can reach team history.

Parse each present layer and report any entry missing its required `reason` or `date` as malformed —
those do not suppress, and a silent partial parse would turn a formatting slip into a lost check.

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

Then converge the one surface this plugin owns, conservatively:

- **No suppression record anywhere** — leave it that way and say so. Absent is valid; an empty
  scaffold is noise. Scaffold the team layer with the documented shape only on an explicit request.
- **Team layer present but untracked** — report the STOP and the exact `git add` the operator should
  run. Never stage on their behalf.
- **Overlay present but not ignored** — recommend the recursive `.claude/**/*.local.*` line and leave
  the `.gitignore` edit to the consumer.
- **Malformed or unrecognized entries** — report them and stop. Never rewrite, reorder, or drop an
  operator's suppression: an entry this skill cannot reconcile is a question for the operator, and a
  silent rewrite would hide the very finding the entry was suppressing.

Every write names the file and the exact change before making it, and preserves unrelated content.

## Gotchas

- **Never run a git command against the user-global layer.** `~/.claude/audit-pass.md` is outside the
  worktree, so `git check-ignore` and `git status` return a meaningless verdict there — or a
  confidently wrong one when the home directory is itself a git repository.
- **Missing config is not a failure.** All three suppression layers absent means no suppressions,
  which is the normal state for a repo that has never suppressed a finding. INFO, never FAIL.
- **Recommend the recursive gitignore line, and leave the edit to the consumer.** `.claude/**/*.local.*`
  covers flat, folder-form, and profiled overlays alike; the narrower `.claude/*.local.*` silently
  misses any nested overlay. The consumer's ignore file is their artifact — this skill never writes it.
- **An install command's exit code is not verification.** After any install, re-run the probe and
  report its actual result.

## What this skill does NOT do

- Run an audit — that is `/claude-config:audit`, `/claude-config:audit-automation-gaps`,
  `/claude-config:audit-permission-grants`, `/claude-config:audit-instructions`, and
  `/claude-config:audit-pass`.
- Install system packages, write Claude Code settings or `pluginConfigs`, or touch the plugin cache.
- Write the consumer's `.gitignore`, stage anything, or edit an operator's suppression entries.
- Download anything — `check` makes no network call; the audit skills' own doc/marketplace fetches are
  theirs, not setup's.
