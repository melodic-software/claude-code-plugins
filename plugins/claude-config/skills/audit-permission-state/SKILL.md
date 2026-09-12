---
description: "Report the Claude Code permission state actually in effect. Discovers every settings scope (managed policy, user-global, project, local, and the pre-v2.1.211 start-directory copy), merges them into the effective allow/ask/deny set with each rule's source and precedence mechanic named, and classifies which allow rules auto mode drops on entry. Use when: 'what permissions are actually in effect' or 'show me my effective permissions' (including which settings file a rule comes from and what scopes were checked); 'which of my rules survive auto mode' (the entry diff); 'is my managed policy being read'; or before changing a permission rule whose source is unknown. An allow rule ignored because of its shape is `audit-permission-grants`. Report-only, never writes any settings file."
argument-hint: "(none) every read-only stage | [--scopes] [--entry-diff] [--lint] [--managed] [--block] narrow | [--oracle] [--critique] priced"
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
from one it could not read, there is no `claude permissions` subcommand or machine-readable export of
the merged allow/ask/deny set, and none of it exists outside a live session. This skill computes that
locally, off a live session, as line records a script can read.

> **Verification.** Claim: no CLI surface exports the merged allow/ask/deny set. Basis:
> [CLI reference](https://code.claude.com/docs/en/cli-reference) lists no `permissions` subcommand and
> no standalone `config` subcommand; the two JSON surfaces it documents, `claude auto-mode defaults`
> and `claude auto-mode config`, print classifier rules, not permission rules. As of 2026-09-12.
> Recheck when a release note mentions a permissions export or a `/permissions` export action.

It answers a question the siblings do not. `audit-permission-grants` asks whether the grants you
**wrote** are durable and portable; `audit` asks whether your config files are **correct**. This
skill asks what is **in effect**: which scopes exist on this machine, which of them this reader
could actually open, and what each one holds.

## Scope boundary (route out)

- Grant portability and auto-mode durability (P1/P2/P3) → `claude-config:audit-permission-grants`.
- Settings-file correctness **outside the permission plane** (schema and unknown keys, baseline
  deny/ask presence, deny-rule placement, MCP, hooks, plugin drift) → `claude-config:audit`. The
  permission plane's own dead config, the `disableAutoMode` type trap, and rules that cannot match
  stay here, in Phase 4: they are read across all five scopes at once, which is this skill's asset
  and not something a project-scope reader can do.
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

Parse `$ARGUMENTS`. **Flags narrow; they never widen.**

- (no argument): every read-only stage, in order, through one entry point. See "Run it" below.
- `--scopes`: surface records only, no rule inventory and no downstream stage. Use when the question
  is "which scopes exist and which could you read", not "what is in them".
- `--entry-diff`: inventory, merge, and the auto-mode entry diff (Phase 3).
- `--lint`: inventory and the permission-plane lint (Phase 4).
- `--managed`: inventory and the managed-conformance report (Phase 6).
- `--block`: the `autoMode` block lint (Phase 5). Reads the CLI, not the inventory, so it runs alone.
- `--oracle`: with `--entry-diff`, cross-check the prediction against the harness's own drop
  narration. **Spawns a real `claude -p` session**; never fires without this flag. See its cost
  notice, which the run prints before anything is spawned.
- `--critique`: with `--block`, add `claude auto-mode critique`. Slow, and it truncates or returns
  nothing while still exiting 0, so its result is reported as unavailable rather than as clean.

## Run it

One entry point runs each stage once and fans the inventory out, instead of walking every scope once
per pipeline:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/audit.sh" $ARGUMENTS
```

The phases below document what each stage decides and how to read it. Every stage script stays
independently invocable and composes on its own, which is what `draft-auto-mode-rules` and
`audit-pass` rely on; `audit.sh` is a convenience caller, never a gateway.

**Read the `status=` token on every summary line before the counts above it.** `status=read` means
the stage saw every scope; `status=incomplete` means at least one could not be opened and the counts
cover only what was read. A finding count of zero under `status=incomplete` is not a clean bill.

## Phase 1: Discover and inventory

Stage: `permission-state.sh`, the deterministic spine every other stage consumes. It emits one record
per line:

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

Stage: `permission-merge.sh`, fed the inventory. It reports what is actually in force, each rule
carrying its provenance. It passes the records above through, then appends:

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

On entering auto mode, broad allow rules that grant arbitrary code execution are **silently dropped**,
and restored when the session leaves auto mode again. This stage says which of yours survive.

**It describes a transition most run shapes never make, so state the precondition when you report
it.** Auto mode is the built-in starting mode in one of the seven documented run shapes: a Pro, Max,
or Team plan in a terminal or the VS Code extension. Every other shape, `claude -p` and the Agent SDK
among them, starts in Manual and never makes this transition. The run prints the full list as a
`DIFF-NOTE`; carry it rather than presenting the diff as unconditional.
`reference/criteria.md` §"The auto-mode entry diff" holds the dated record.

Stage: `automode-entry-diff.sh`, fed the merge.

```text
DIFF-NOTE: <text>                                     classifyAllShell state, bounds
entry-diff dropped class=<class> scopes=<a,b> <rule>  dropped on entry
entry-diff suspended reason=classifyAllShell ...      suspended while auto mode is active
entry-diff kept scopes=<a,b> <rule>                   carries over
entry-diff summary allow_before=<n> dropped=<n> suspended=<n> kept=<n>
```

- **Only allow rules change on entry.** Deny and ask are evaluated before the classifier in every
  mode, so they are not part of this diff. Do not report them as "surviving".
- **Neither label is permanent.** `dropped` and `suspended` both describe what is in force while auto
  mode is active; the rules are restored when the session leaves it, and nothing edits a settings
  file. The two labels are kept apart because the remedies differ: a `dropped` rule is fixable by
  narrowing that rule, while `suspended` is a global switch no rule edit reaches.
- **`class` names the documented reason**: `blanket`, `interpreter-wildcard`, `package-manager-run`,
  `agent`, or `monitor`. The three shell shapes come from `lib/permission-patterns.sh`, the
  vocabulary `audit-permission-grants` check P1 also scans with; `agent` and `monitor` are
  whole-tool classes this script tests on the tool token. `Monitor` allow rules joined the dropped
  set upstream in v2.1.236, because Claude Code runs Monitor commands through the shell.
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

Stage: `permission-plane-lint.sh`, fed the inventory.

```text
finding <severity> [<check>] <scope> <detail>
lint summary findings=<n> checks_run=<n> status=<read|incomplete>
```

Nine checks: three `C2-*` dead-config gates, `C5-disableType`, and five `C6-*` rules-that-cannot-match.
`reference/criteria.md` maps each to the sentence it follows from and lists the legitimate rule shapes
the checks are written NOT to flag.

- **`C5-disableType` is the one to read first.** `disableAutoMode` must be the **string** `"disable"`;
  a boolean is valid JSON, is accepted, and does nothing, so the operator believes auto mode is
  locked out when it is not.
- **The three `C2` gates stay separate findings.** Different scope sets, different version histories:
  an operator who fixed one and saw the count drop would reasonably believe they had fixed all three.
- **`findings=0` is a clean bill only under `status=read`.** Under `status=incomplete` a scope could
  not be opened and was never linted; the accompanying `LINT-NOTE` names which.
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
nothing surfaces which. Stage: `managed-conformance.sh`, fed the inventory.

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
`managed` is four surfaces per OS, not one file. `reference/criteria.md` §Scopes has the full table
and the dated record for the `pre-v2.1.211` boundary.

**Four documented conditions keep the local file beside `.claude/settings.json` instead**, and the
reader resolves all four: outside a git repository, repository root is the home directory, on Windows,
and repository root or its `.git`/`.claude` not owned by the current user. The basis line names which
applied. A fifth case is stated rather than detected, because it is a helper's behavior and not a
session property: the Agent SDK's `resolveSettings()` always reads from the starting directory.

**A cloud session reads a different scope set, and the run says so.** The operator's own user and
local settings are not read there, and only server-managed settings arrive, so a user-scope record in
a cloud session describes the container. `CLAUDE_CODE_REMOTE` is the documented detection and the only
entrypoint variable this reader branches on. `reference/criteria.md` §Scopes holds both dated records.

## Prerequisites

- **`jq`, required for correctness.** Absent, the script stops at the entry point with
  `ERROR: jq required` and exit 2. Report the environment gap; do not report a clean bill.
- **`reg` (Windows) and `defaults` (macOS), required for an optional feature.** Absent, that one
  managed surface is `skipped` with a visible notice and everything else still runs.

## Gotchas

Failure modes that produce a confidently wrong answer, and the honest limits of what has been
verified on real hardware, are in [reference/gotchas.md](reference/gotchas.md). Read it when a result
looks wrong, when debugging a stage by hand, or before trusting a managed surface on macOS or Linux.
