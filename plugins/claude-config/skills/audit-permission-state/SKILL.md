---
description: "Report the Claude Code permission state actually in effect — discovers every settings scope (managed policy, user-global, project, local, and the pre-v2.1.211 start-directory copy) and inventories each one's allow/ask/deny rules with its source named. Use when: 'what permissions are actually in effect', 'which settings file is my rule coming from', 'why is my allow rule ignored', 'show me my effective permissions', 'is my managed policy being read', 'what scopes did you check', or before changing a permission rule you cannot locate. Report-only — never writes any settings file."
argument-hint: "[--scopes] — surface records only, no rule inventory"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report which permission scopes exist and what rules each one holds
---

## Purpose

Claude Code gives you no way to see the permission rules actually in effect. There is no
`claude permissions` subcommand and no documented machine-readable export, so the honest answer to
"where is this rule coming from" has been "read five files in five places and hope you know all
five". This skill computes that locally.

It answers a question the siblings do not. `audit-permission-grants` asks whether the grants you
**wrote** are durable and portable; `audit` asks whether your config files are **correct**. This
skill asks what is **in effect** — which scopes exist on this machine, which of them this reader
could actually open, and what each one holds.

## Scope boundary (route out)

- Grant portability and auto-mode durability (P1/P2/P3) → `claude-config:audit-permission-grants`.
- Settings-file correctness, baseline deny/ask presence, plugin drift → `claude-config:audit`.
- The instruction layer (CLAUDE.md, rules, auto-memory) → the `claude-memory` plugin.

## Report-only, permanently

This skill writes nothing, in any scope, under any flag. Managed policy is read-only by
construction — those are admin-write OS locations or a claude.ai Owner role, so a plugin could not
author them even if it wanted to.

## Arguments

Parse `$ARGUMENTS`:

- `--scopes` — surface records only, no rule inventory. Use when the question is "which scopes exist
  and which could you read", not "what is in them".
- (no argument) — surfaces plus one record per allow/ask/deny rule.

## Phase 1: Discover and inventory

Run the deterministic spine:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-state.sh"
```

It emits one record per line:

```text
<scope> <surface> <status> <path>          one per settings surface
rule <scope> <surface> <kind> <rule text>  one per allow/ask/deny entry
NOTE: <text>                               anything the operator must know
```

| Field | Values |
| --- | --- |
| `scope` | `managed`, `user`, `project`, `local`, `startdir-local` |
| `surface` | `file`, `dropin-dir`, `dropin-file:<name>`, `registry`, `plist` (managed); `settings` elsewhere |
| `status` | `present`, `absent`, `unreadable`, `invalid-json`, `skipped`, `not-applicable` |
| `kind` | `allow`, `ask`, `deny` |

## Reading the output honestly

<!-- fresh-eyes-exempt: external-input -- the material judged here is the consumer's own configuration as read by a deterministic script; no step in this skill judges output this skill authored -->

Interpret and report the records below; the judgment is over the consumer's configuration, never over
anything this skill produced. The status vocabulary carries the whole point of the skill, so do not
collapse it in the report:

- **`absent` means looked and found nothing.** **`skipped` means could not look.** Never present a
  `skipped` surface as "no policy" — say the surface was not read and why. The script emits a `NOTE:`
  naming the reason every time.
- **Every scope and every managed surface emits a record on every OS**, including the ones that do
  not apply here (`not-applicable`). A surface missing from the output is a defect in this reader,
  not evidence about the machine.
- **`managed` means the LOCAL managed surfaces.** Server-managed settings arrive remotely at sign-in
  and have no local path, so no local reader can see them. The script says so on every run; carry it
  into the report rather than implying completeness.
- **`invalid-json` is not `absent`.** A malformed settings file contributes no rules to the
  inventory, but its rules may still be a live problem for the operator — report it as a finding, not
  as an empty scope.

## Scopes, and why there are five

| Scope | Why it is its own member |
| --- | --- |
| `managed` | Highest precedence. Four surfaces per OS, not one file — see below |
| `user` | `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. Where Claude Code's own "Always allow" path writes, so it accumulates the most rules |
| `project` | `.claude/settings.json` at the repository root |
| `local` | `.claude/settings.local.json`, resolved **through worktrees to the main checkout** — anchoring on the worktree root looks where the file is not |
| `startdir-local` | A pre-v2.1.211 copy left in the session's start directory. Not a fallback: when both exist the repository root wins on a shared key, **but permission rules from both stay in effect**, so both are live |

## The managed scope is four surfaces

Two are the portable core, read on every OS: the per-OS `managed-settings.json` and its
`managed-settings.d/` drop-in directory (read in the documented order — base first, then `*.json`
sorted alphabetically on top, dotfiles ignored).

Two are declared optional platform integrations: the Windows policy registry keys and the macOS
managed-preferences domain. Each is read where it is native and readable; where its tool is missing
the surface reports `skipped` with a notice and **every other result is unaffected**. That is the
contract — an optional platform integration degrades visibly and preserves the portable core.

`HKCU` is not a peer of `HKLM`: it is documented as lowest policy priority, used only when no
admin-level source exists, so the first key that answers wins and the rest are not consulted.

## Prerequisites

- **`jq` — required for correctness.** Absent, the script stops at the entry point with
  `ERROR: jq required` and exit 2. Report the environment gap; do not report a clean bill.
- **`reg` (Windows) and `defaults` (macOS) — required for an optional feature.** Absent, that one
  managed surface is `skipped` with a visible notice and everything else still runs.

## Verification status

The Windows registry surface was verified end to end against a real registry key. The macOS
preferences domain and the Linux managed paths are **not** verified on real hardware — they are an
honest manual-verification gap, not a claim. Treat a macOS `plist` record as reporting the surface,
not its contents: the reader names the domain and does not yet inventory its rules.

## Gotchas

Observed failures, each of which produced a confidently wrong answer before it was found:

- **A registry read that silently reports "no policy."** On Git Bash, MSYS rewrites any argument
  containing backslashes as though it were a POSIX path, so a registry key reaches `reg.exe` mangled
  and the query dies with `ERROR: Invalid syntax`. A caller that only checks the exit status reads
  that as "no managed policy deployed" on a machine that has one. The reader disables the rewrite for
  those calls; if you invoke `reg` yourself while debugging, do the same or you will reproduce the
  wrong answer by hand.
- **A missing shared library used to look like a clean machine.** If the plugin's
  `lib/managed-scope.sh` could not be sourced, every managed surface reported `absent`. It is now a
  hard `exit 2` — a reader that cannot load its own location list must not answer the question.
- **The local file is not under the worktree you are standing in.** `settings.local.json` resolves
  through worktrees to the main checkout, so a reader anchored on `git rev-parse --show-toplevel`
  looks where the file is not and reports `absent`. Three documented exceptions keep it in the start
  directory — outside a git repository, when the repository root is the home directory, and in Agent
  SDK sessions. The reader detects the first two and states that it cannot detect the third.
- **Two live copies of `settings.local.json` are normal, not a bug.** When a pre-v2.1.211 copy sits in
  the start directory, the repository-root copy wins on a shared key but permission rules from both
  stay in effect. Reporting only one of them under-reports what is live.
