---
description: "Report the Claude Code permission state actually in effect. Discovers every settings scope (managed policy, user-global, project, local, and the pre-v2.1.211 start-directory copy), merges them into the effective allow/ask/deny set with each rule's source and precedence mechanic named, and classifies which allow rules auto mode drops on entry. Use when: 'what permissions are actually in effect', 'which settings file is my rule coming from', 'why is my allow rule ignored', 'show me my effective permissions', 'what does auto mode drop', 'which of my rules survive auto mode', 'is my managed policy being read', 'what scopes did you check', or before changing a permission rule you cannot locate. Report-only, never writes any settings file."
argument-hint: "[--scopes] surfaces only | [--entry-diff] what auto mode drops"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report the permission rules actually in effect and what auto mode drops
---

## Purpose

`/permissions` lists your rules and the settings file each one came from, and for "where is this rule
written" that is the answer, so use it. What it does not do is resolve the outcome: it will show you an
allow and a deny for the same tool without saying which wins, it cannot tell a scope that was empty
from one it could not read, there is no `claude permissions` subcommand or machine-readable export,
and none of it exists outside a live session. This skill computes that locally, in a form another
tool can consume.

It answers a question the siblings do not. `audit-permission-grants` asks whether the grants you
**wrote** are durable and portable; `audit` asks whether your config files are **correct**. This
skill asks what is **in effect**: which scopes exist on this machine, which of them this reader
could actually open, and what each one holds.

## Scope boundary (route out)

- Grant portability and auto-mode durability (P1/P2/P3) → `claude-config:audit-permission-grants`.
- Settings-file correctness, baseline deny/ask presence, plugin drift → `claude-config:audit`.
- The instruction layer (CLAUDE.md, rules, auto-memory) → the `claude-memory` plugin.

## Report-only, permanently

**This skill writes no settings file, in any scope, under any flag.** That is the contract, and it
holds including under `--oracle`. It is not the same as writing nothing at all: `--oracle` spawns a
real `claude -p` session, and a session rewrites `~/.claude.json` and adds project, session-env,
security, subagent and backup state under your config directory. The flag prints that before it
spawns anything. Every other action writes nothing anywhere. Managed policy is read-only by
construction: those are admin-write OS locations or a claude.ai Owner role, so a plugin could not
author them even if it wanted to.

## Arguments

Parse `$ARGUMENTS`:

- `--scopes`: surface records only, no rule inventory. Use when the question is "which scopes exist
  and which could you read", not "what is in them".
- `--entry-diff`: run the full pipeline through to the auto-mode entry diff (Phase 3 below).
- `--oracle`: with `--entry-diff`, cross-check the prediction against the harness's own drop
  narration. **Spawns a real `claude -p` session**; never fires without this flag. See its cost
  notice, which the run prints before anything is spawned.
- (no argument): surfaces plus one record per allow/ask/deny rule, then the merge.

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

## Phase 2: Merge into the effective set

Pipe the inventory through the merge to get what is actually in force, each rule carrying its
provenance:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-state.sh" |
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-merge.sh"
```

It passes the records above through, then appends:

```text
CAVEAT: <text>                                                 what bounds the claim
effective <kind> scopes=<a,b> precedence_basis=<token> <rule>  one per live rule
inert <kind> scopes=<a,b> outranked_by=<kind> <rule>           one per beaten entry
```

Two mechanics decide those records, and conflating them produces confident wrong answers:

- **Rules merge across scopes rather than override**, so the same rule in the same list at two scopes
  has no winner. Both are live, and `scopes=` names every contributor. Never report one of them as
  having overridden the other.
- **Kind is decided by evaluation order, deny then ask then allow, from any scope, in both
  directions.** A user-level deny blocks a project-level allow just as a project-level deny blocks a
  user-level allow. Scope rank does not enter into it. This is what answers "why is my allow rule
  ignored": the `inert` record names the rule that beat it.
- **A rule that is a bare tool name reaches every call of that tool.** A whole-tool deny removes the
  tool from context entirely, so every other rule naming it is inert, other denies included;
  `EndConversation` is the documented exception. A whole-tool ask prompts for every call, so no scoped
  allow for that tool applies. Both print a `NOTE:` naming the tool.

`reference/criteria.md` maps every `precedence_basis` token to the sentence it follows from, and
states the two standing bounds the run prints.

## Phase 3: What entering auto mode drops

Auto mode became the default permission mode for new sessions on 2026-08-14, and on entry it
**silently drops** broad allow rules. This stage says which of yours survive:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-state.sh" |
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-merge.sh" |
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/automode-entry-diff.sh"
```

```text
DIFF-NOTE: <text>                                     classifyAllShell state, bounds
entry-diff dropped class=<class> scopes=<a,b> <rule>  dropped on entry
entry-diff suspended reason=classifyAllShell ...      suspended while auto mode is active
entry-diff kept scopes=<a,b> <rule>                   carries over
entry-diff summary allow_before=<n> dropped=<n> suspended=<n> kept=<n>
```

- **Only allow rules change on entry.** Deny and ask are evaluated before the classifier in every
  mode, so they are not part of this diff. Do not report them as "surviving".
- **`class` names the documented reason**: `blanket`, `interpreter-wildcard`, `package-manager-run`,
  or `agent`, from `lib/permission-patterns.sh`, the vocabulary `audit-permission-grants` check P1
  also scans with.
- **`autoMode.classifyAllShell` inverts the answer wholesale.** When true it suspends *every* Bash and
  PowerShell allow rule, so narrow rules do **not** carry over. It is resolved only from the scopes
  the classifier reads, so a project- or local-scope copy is reported inert rather than obeyed.
- **`--oracle` is opt-in and priced.** It spawns a real `claude -p` session to corroborate the
  prediction. Measured cost: your settings files are untouched, but `~/.claude.json` is rewritten and
  project, session-env, security and subagent state appear under your config directory. A capture
  that yields nothing is **unavailable**, never an empty drop set.

## Phase 4: Configuration that is written but never read

The permission plane accepts things it silently ignores. This finds them across every scope at once,
before a session starts:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-state.sh" |
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-plane-lint.sh"
```

```text
finding <severity> [<check>] <scope> <detail>
lint summary findings=<n> checks_run=<n>
```

Nine checks: three `C2-*` dead-config gates, `C5-disableType`, and five `C6-*` rules-that-cannot-match.
`reference/criteria.md` maps each to the sentence it follows from and lists the legitimate rule shapes
the checks are written NOT to flag.

- **`C5-disableType` is the one to read first.** `disableAutoMode` must be the **string** `"disable"`;
  a boolean is valid JSON, is accepted, and does nothing, so the operator believes auto mode is
  locked out when it is not.
- **The three `C2` gates stay separate findings.** Different scope sets, different version histories:
  an operator who fixed one and saw the count drop would reasonably believe they had fixed all three.
- **Several of these also produce a startup warning.** The added value here is reading every scope at
  once, before a session, and naming the file, not that the harness is silent.
- **Advisory: the lint always exits 0 when it ran.** Exit 2 means it could not run at all, never
  "nothing found".

## Phase 5: The `autoMode` classifier block

A different surface from everything above: four natural-language sections an LLM classifier reads,
not permission rules the harness matches. Independent of the pipeline, it reads the CLI, not stdin:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/automode-block-lint.sh" [--critique]
```

- **`C4-defaults`**: a customized section that omits `"$defaults"`. Customizing **replaces** the
  built-in list rather than adding to it, so the finding names how many built-in entries are gone.
- **`C2b-contradiction`**: the same subject in `allow` and in a deny section.
- **`C3-shadowed`**: an entry an earlier `hard_deny` already forecloses, so it can never fire.
- **`--critique` surfaces `claude auto-mode critique`, wrapped and never replaced.** It owns the
  semantic judgment. What this adds is honesty about it: measured across three consecutive runs on one
  unchanged config, output was truncated mid-sentence twice and empty once, **exiting 0 every time**.
  A mid-sentence cut is reported as truncated; an empty result says "critique returned nothing; run it
  yourself" rather than implying your rules are clean.

**This lane is optional, and its prerequisite is nobody else's problem.** It needs `python3` because
`claude auto-mode config` emits raw control characters inside string values. `jq` rejects the output
outright, and no line-oriented POSIX filter can repair it, since the offending byte is a raw line feed
inside a string. Absent `python3` or `claude`, the lane prints a visible skip notice and exits 0; every
other stage still runs.

**Exit status is never trusted here.** A run that exits 0 having produced nothing is reported
`status=unavailable` with an explicit "this is NOT a clean bill". The distinction between "your block
is clean" and "the block was never read" is the whole point.

## Phase 6: What managed policy actually enforces

An administrator deploys managed policy believing it is policy. Some of it is; some is not, and
nothing surfaces which:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/permission-state.sh" |
  bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/managed-conformance.sh"
```

- **`managed enforced deny <rule>`**: the strongest thing an administrator can write. No level,
  command line included, can override a managed permission rule, and a tool denied at any level
  cannot be allowed at another.
- **`managed loosenable rule …`**: the interaction that surprises people. "Managed is highest" and
  "deny before ask before allow, **from any scope**" are both true: a lower-scope deny beats a managed
  allow without ever overriding it.
- **`managed loosenable autoMode`**: a managed `autoMode` section is **additive, not a policy
  boundary**. A developer cannot remove entries it provides, but a developer-added `allow` can
  override an organization `soft_deny`. Permissions, hooks, MCP, sandbox-filesystem and
  sandbox-network each got an exclusivity lock; auto mode did not.
- **`managed loosenable lockout`**: `disableAutoMode` set to anything but the string `"disable"`.

**This report never prescribes.** It says what the consumer's own policy does and does not achieve;
every rule string it prints came from a file it read. It ships no security floor of its own.

**Completeness is bounded on every run.** Server-managed settings are delivered at sign-in and have no
local path, so "managed" means the local surfaces only; a surface that could not be read gets its own
note saying so, because an administrator reading silence as "no policy deployed" is the failure this
report exists to prevent.

## Reading the output honestly

<!-- fresh-eyes-exempt: external-input -- the material judged here is the consumer's own configuration as read by a deterministic script; no step in this skill judges output this skill authored -->

Interpret and report the records below; the judgment is over the consumer's configuration, never over
anything this skill produced. The status vocabulary carries the whole point of the skill, so do not
collapse it in the report:

- **`absent` means looked and found nothing.** **`skipped` means could not look.** Never present a
  `skipped` surface as "no policy". Say the surface was not read and why. The script emits a `NOTE:`
  naming the reason every time.
- **Every scope and every managed surface emits a record on every OS**, including the ones that do
  not apply here (`not-applicable`). A surface missing from the output is a defect in this reader,
  not evidence about the machine.
- **`managed` means the LOCAL managed surfaces.** Server-managed settings arrive remotely at sign-in
  and have no local path, so no local reader can see them. The script says so on every run; carry it
  into the report rather than implying completeness.
- **An `ask` finding carries an open upstream discrepancy.** The permissions page says content-scoped
  `ask` rules always prompt, "even in auto mode"; issues #83766 and #42797 report them auto-approved
  under `defaultMode: "auto"`. This plugin follows the documented behavior, the only source
  with a stated contract, but say so when reporting an `ask` result, and point at `permissions.deny`
  where the outcome must hold regardless. See `reference/criteria.md`.
- **`invalid-json` is not `absent`.** A malformed settings file contributes no rules to the
  inventory, but its rules may still be a live problem for the operator. Report it as a finding, not
  as an empty scope.

## Scopes

Five, and the two easy to get wrong: `local` resolves **through worktrees to the main checkout**, so
a reader anchored on the worktree root looks where the file is not; `startdir-local` is a
pre-v2.1.211 copy that is **not** a fallback, since permission rules from both files stay in effect.
`managed` is four surfaces per OS, not one file. `reference/criteria.md` §Scopes has the full table.

## Prerequisites

- **`jq`, required for correctness.** Absent, the script stops at the entry point with
  `ERROR: jq required` and exit 2. Report the environment gap; do not report a clean bill.
- **`reg` (Windows) and `defaults` (macOS), required for an optional feature.** Absent, that one
  managed surface is `skipped` with a visible notice and everything else still runs.

## Verification status

The Windows registry surface was verified end to end against a real registry key. The macOS
preferences domain and the Linux managed paths are **not** verified on real hardware. They are an
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
  hard `exit 2`. A reader that cannot load its own location list must not answer the question.
- **The local file is not under the worktree you are standing in.** `settings.local.json` resolves
  through worktrees to the main checkout, so a reader anchored on `git rev-parse --show-toplevel`
  looks where the file is not and reports `absent`. Three documented exceptions keep it in the start
  directory: outside a git repository, when the repository root is the home directory, and in Agent
  SDK sessions. The reader detects the first two and states that it cannot detect the third.
- **An empty merge is not an empty machine.** Piping a reader that died into the merge would have
  produced a clean "nothing in effect" on a machine full of rules. The merge now exits 2 when the
  input carries no scope records at all; if you build your own pipeline around these scripts, check
  the status rather than the output.
- **Two live copies of `settings.local.json` are normal, not a bug.** When a pre-v2.1.211 copy sits in
  the start directory, the repository-root copy wins on a shared key but permission rules from both
  stay in effect. Reporting only one of them under-reports what is live.
