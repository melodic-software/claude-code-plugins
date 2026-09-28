# Baseline permission patterns

Concrete permission patterns the Phase 2 Category B audit checks for presence in the project's
`.claude/settings.json`. Organized into three sub-categories matching `audit-checklist.md`
B.1 / B.2 / B.3:

- `sensitive-file-deny` → must appear in `permissions.deny` (Read patterns)
- `destructive-bash-deny` → must appear in `permissions.deny` (Bash patterns)
- `ask-rules` → must appear in `permissions.ask` (Bash patterns)

This is the cross-repo security floor. Projects with a stricter posture (extra secret-file paths,
destructive API-endpoint families, hook-bypass blockers, additional ask-gates) declare those in their
own rules files; Category B checks them alongside this baseline. Both arg-bearing and bare forms are
listed separately where relevant, because CC permission globs are greedy across slashes but require an
explicit pattern for each invocation shape.

## sensitive-file-deny (Read deny)

Read deny patterns for secret-bearing files. `.env` / `.env.*` are the de-facto secrets convention;
`secrets/**` is the conventional secrets directory; the `settings.local.json` deny prevents tokens
stored there from being read by tools; key/PEM/SSH patterns cover private-key material anywhere in the
tree.

| Pattern | Purpose |
| --- | --- |
| `Read(./.env)` | Block reading .env file |
| `Read(./.env.*)` | Block reading .env.local, .env.production, etc. |
| `Read(./secrets/**)` | Block reading secrets directory |
| `Read(./.claude/settings.local.json)` | Block reading file containing tokens/secrets |
| `Read(**/*.key)` | Block reading private-key files anywhere in tree |
| `Read(**/*.pem)` | Block reading PEM certificate/key files anywhere in tree |
| `Read(**/id_rsa)` | Block reading SSH private keys |

### Scope of a Read deny: what it covers, and what it does not

These entries are a guardrail against routine access, not a containment boundary. Category B checks
that the rules are present; presence is not evidence the file is unreachable. Say so whenever the
category is reported, in either direction. Verified 2026-09-28 against
[permissions](https://code.claude.com/docs/en/permissions),
[sandboxing](https://code.claude.com/docs/en/sandboxing), and
[settings reference](https://code.claude.com/docs/en/settings-reference#permissionsblockreadsoutsideworkingdirectories).
Recheck when a release note changes Read/Edit deny coverage, Bash redirect checks, sandbox
shell-mode, or `permissions.blockReadsOutsideWorkingDirectories`.

**Covered.** A `Read(...)` deny applies to the built-in file tools (Read, Grep, Glob, LSP), to
`@file` mentions in a prompt, to the selection and open-file context a connected IDE shares, to the
Edit tool on the same path (CC v2.1.208+), and to file commands Claude Code recognizes inside a Bash
command, such as `cat`, `head`, `tail`, `sed`, and `tee`. It also applies to Bash redirect targets.
An input redirect (`< file`) is checked against Read allow and deny rules; Claude Code checks input
targets in v2.1.257 and later. An output redirect (`> file`, `>> file`, `2> file`) is checked
against Edit allow and deny rules. The 2.1.259 widening that applied `Read()` deny rules to Bash
arguments generally was reverted in 2.1.260 and is not the rule: a command that reads files without
naming them, such as `grep -r pattern .` from the directory that holds the file, is not covered.

**Not covered.** The same page: the rules "don't apply to arbitrary subprocesses that read or write
files indirectly, like a Python or Node script that opens files itself." A `python -c`, a `node -e`,
or any script that opens the path reads a `Read`-denied file with no deny firing. That is the real
gap, and it is reached *routinely*: an agent blocked on `Read` reaches for an interpreter one-liner
as an ordinary next step, not as an attack. This plugin's own `scripts/check-structure.sh` is an
instance: it opens `settings.local.json` from inside a subprocess, and its safety comes from emitting
only counts, never from the deny rule.

**Do not try to close the gap with `Bash(...)` deny globs.** The permissions page warns that "Bash
permission patterns that try to constrain command arguments are fragile", and the set of programs
that can open a file is unbounded. Enumerating readers relocates the false confidence instead of
removing it. Never propose a `Bash(cat *)`-style enumeration as the remedy here.

**The documented enforcement path is the sandbox**, which the OS enforces on every Bash command and
its child processes: `sandbox.filesystem.denyRead`, or `sandbox.credentials.files` entries with
`"mode": "deny"`. Read/Edit deny rules and `sandbox.filesystem` paths merge into the final sandbox
boundary. The sandbox's default read policy still allows credential files such as `~/.aws/credentials`
and `~/.ssh/` unless they are listed.

**`sandbox.enabled: true` alone is not a boundary. Check the escape surfaces before calling it one.**
Upstream documents four, all open at their defaults, and each puts a subprocess back outside the OS
boundary where it can read the denied path. A fifth path is not a setting: commands typed at the
`!` shell-mode prompt run outside the sandbox even when strict mode
(`allowUnsandboxedCommands: false`) is on, in an interactive session, from Claude Code 2.1.260.
Two sessions are the exception: a background session, where strict mode covers shell-mode commands
too, and a Linux session with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set, where every command runs
sandboxed. Before v2.1.260, strict mode sandboxed shell-mode commands in every session.
**Claim, basis, as of, recheck:** that sentence,
[sandboxing: the unsandboxed retry escape hatch](https://code.claude.com/docs/en/sandboxing#the-unsandboxed-retry-escape-hatch),
2026-09-28, and a re-fetch of that section that no longer says shell-mode commands run outside the
sandbox.

| Setting | Why it matters | What a boundary requires |
| --- | --- | --- |
| `allowUnsandboxedCommands` | A command that fails under the sandbox may be retried with `dangerouslyDisableSandbox`, which runs it outside | set to `false` |
| `failIfUnavailable` | A missing dependency or an unsupported platform warns and then runs commands unsandboxed | set to `true` |
| `excludedCommands` | Anything listed runs outside the sandbox, and upstream notes a developer can always append entries | kept narrow, and reviewed |
| `filesystem.disabled` | Turning the filesystem layer off lifts the `denyRead` and `credentials.files` read protections entirely | not set |
| `!` shell mode | Commands typed at the `!` prompt run outside the sandbox by design, even when `allowUnsandboxedCommands` is `false`. Interactive sessions only: a background session, and a Linux session with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` set, still sandbox shell-mode commands. Before v2.1.260, strict mode sandboxed shell-mode commands in every session | not treated as closed by strict mode in an interactive session |

Report an enabled-but-default sandbox as partial, not as protection. Recommending it without these is
the same defect as recommending the deny globs without their scope. Strict mode
(`allowUnsandboxedCommands: false`) closes the unsandboxed retry for commands Claude runs. It does
not close `!` shell mode in an interactive session.

**Platform limit. Check before recommending it.** The sandbox runs on macOS, Linux, and WSL2; native
Windows is not supported, and the PowerShell tool lists "On Windows, sandboxing is not supported"
among its preview limitations. On a native-Windows workstation the OS-level remedy is unavailable, so
do not offer it there as the fix.

**A `PreToolUse` hook on `Bash|PowerShell` is a speed bump, not a boundary, *against this threat
model*.** It can inspect the command string and deny the call, and a hook exiting 2 blocks a call an
*allow* rule would otherwise have permitted. A decision it returns cannot loosen a deny. See
"Interaction with hook-based gates" below for the precise ordering. But it inspects that same command
string, so it inherits the evasion surface of a Bash deny glob. Rank it below the sandbox and never
describe it as protection.

**The ranking is scoped to secret exfiltration; it does not carry to destructive-bash-deny.** It holds
here because an OS-level boundary for *reading a file* exists, so something strictly better than the
hook is on the table. Nothing equivalent exists for a destructive git argument: the sandbox's
vocabulary is `filesystem.*` paths and `network.*` hosts, with no expression for a command's
*arguments*, so it cannot separate `git push` from `git push --force` to the same remote. Do not
carry "rank it below the sandbox" into a destructive-git finding. See that section's own note.

**Residual risk, stated plainly.** Where no OS-level boundary is available, a deny glob cannot keep a
secret from a session that has shell execution. **Directory location is a fence for the file tools,
not for an arbitrary subprocess.** From Claude Code 2.1.257,
`permissions.blockReadsOutsideWorkingDirectories` stops Read, Grep, Glob, and LSP from reading
paths outside the working directories, in every permission mode including `bypassPermissions`. Auto
mode offers to turn that block on before the first such read. A Bash command that reads a matching
path through a recognized file command, such as `cat`, prompts even in auto mode and
`bypassPermissions`. A command the shell parser cannot trace prompts even when it names no outside
path. A Python or Node script that opens the path itself is still not fenced by the setting.
**Claim, basis, as of, recheck:** that paragraph,
[settings-reference](https://code.claude.com/docs/en/settings-reference#permissions-blockreadsoutsideworkingdirectories),
2026-09-28, and a re-fetch of that section that changes which tools the block covers. Moving a
secret outside the working directory is still not protection against a subprocess the fence does
not cover. The boundary that holds for that case is the OS principal. A file readable by the
account the session runs as is reachable by that subprocess, wherever it sits. So the durable
control is that the secret is not sitting in a file that account can read at all: keep it in an OS
credential store or a secrets manager and inject it at use time, scope it to a short-lived
credential whose theft expires, or run the session as a different principal or inside a container
that never receives it. Keep the deny rules above; do not report them as proof the file is
protected.

**Redirect targets are covered. The 2.1.259 argument widening is not.** Read and Edit deny rules
apply to recognized Bash file commands, such as `cat`, `head`, `tail`, `sed`, and `tee`, and to
the targets of Bash redirections such as `> file` and `< file`. Input redirect targets are checked
in v2.1.257 and later. They do not apply to a command that reads files without naming them, such
as `grep -r pattern .` from the directory that holds the file, or to an arbitrary subprocess.
Claude Code 2.1.259 briefly applied `Read()` deny rules to Bash arguments (option values, `git`
file operands, `cd && cat`). 2.1.260 reverted that widening. Do not write the widening back in.
**Claim, basis, as of, recheck:** the page sentence plus the revert,
[permissions: Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) and
[changelog](https://code.claude.com/docs/en/changelog) 2.1.260 ("Reverted the 2.1.259 change
applying `Read()` deny rules to Bash arguments"), 2026-09-28, and either page stating the widening
again.

**Unverified. Flag it rather than asserting either way.** No fetched page states whether reads
through the **PowerShell tool** (`Get-Content`, `type`) are covered: the permissions page scopes the
recognized-command coverage to commands in Bash, and the tools reference lists `Read(...)` as
applying to "Read, Grep, Glob, LSP". Treat PowerShell reads as uncovered until upstream says
otherwise. The recognized-command list is also introduced with "such as" and is not exhaustive, so
`grep`, `jq`, and `strings` remain unconfirmed as recognized file commands.

## destructive-bash-deny (Bash deny)

Bash deny patterns for destructive git operations, the universal baseline.

| Pattern | Blocks |
| --- | --- |
| `Bash(git push --force *)` | Force push with args |
| `Bash(git push --force)` | Force push without args |
| `Bash(git push -f *)` | Short flag force push with args |
| `Bash(git push -f)` | Short flag force push without args |
| `Bash(git reset --hard *)` | Hard reset with args |
| `Bash(git reset --hard)` | Hard reset without args |
| `Bash(git clean -f *)` | Force clean |
| `Bash(git clean -fd *)` | Force clean with directories |

**Report this baseline with its fragility, the same way the Read deny table is reported with its
scope.** Every pattern above constrains a command's *arguments*, and the permissions page's own
warning is that *"Bash permission patterns that try to constrain command arguments are fragile"*
([permissions](https://code.claude.com/docs/en/permissions)). A finding that recommends these without
saying so ships the false confidence the `sensitive-file-deny` section refuses to ship.

**The concrete hole is prefix anchoring, and it is worth stating in the finding.** Matching is
prefix-based: *"`Bash(npm run test *)` matches Bash commands starting with `npm run test`"*, and a
*"The space before a trailing `*` is part of the rule"* (same page), so `Bash(ls *)` does not
match `lsof`. So
`Bash(git push --force *)` matches `git push --force origin main` and does **not** match
`git push origin main --force`, which is the ordinary spelling. Flag-position variants, `--force-with-lease`,
`-f` bundled into another short-flag cluster, and `git push` aliases all pass the same way. These
patterns raise the cost of an accidental force push; they do not bound a determined one.

**What the ranking is here, and what it is not.** Do not import the Read-deny section's "rank the hook
below the sandbox": the sandbox constrains filesystem paths and network hosts and has no expression
for a command's arguments, so it does not bound `git push --force` at all. Against destructive git
the available controls are the deny globs above and a `PreToolUse` hook, and the honest ordering is
that a hook can parse the command rather than prefix-match it, while inheriting the same
command-string evasion surface. Upstream supports the fragility claim generally; its *"use PreToolUse
hooks"* recommendation on that page is scoped to URL filtering, so do not cite upstream as ranking
the hook above the glob for destructive commands. That reach is ours to argue, not theirs to have
said.

## ask-rules (Bash ask)

Bash patterns that should require confirmation before execution. `git push` is the canonical ask-gate,
because pushes carry intent the agent should not infer.

| Pattern | Purpose |
| --- | --- |
| `Bash(git push *)` | Require confirmation before pushing with args |
| `Bash(git push)` | Require confirmation before pushing without args |

## Narrowing the baseline

The baseline is a floor for the common case, not an unconditional mandate. Three narrowings apply, and
Category B checks all three before flagging an absent pattern.

**1. A documented exemption in the consuming repo.** A repo where a pattern is
genuinely inapplicable, e.g. a read-only analysis or documentation repo with no push access, where
the `git push` ask-gates protect nothing, documents the exemption in its own rules files; Category B
checks for such a documented exemption before flagging an absent pattern. Undocumented absence is
still a finding.

A declared unattended-push lane is a documented exemption for the `ask-rules` family **only**, never
for `destructive-bash-deny` or `sensitive-file-deny`. An ask rule prompts even in auto mode, and
`dontAsk` auto-denies every call that would otherwise prompt
([permissions](https://code.claude.com/docs/en/permissions)), so the `git push` ask-gates stall or
break a lane that pushes on its own. The signal the engine recognizes is `babysit_loop_merge`
resolving above `human-only` in the team-tracked `.claude/source-control.md`: an explicit
`c2-mechanical`, `c3-autonomous`, or `full-autonomy`, or loop-lane (`babysit_loop_*`) keys with no
merge key, which resolves to the `c2-mechanical` baseline. Only the team-tracked layer counts,
because merge-rung raises bind from that layer alone (source-control's `config-resolution.md`).
With the signal present, the push ask rows are `info` and name the signal. Every push ask row, with
or without it, states that the rule blocks unattended lanes.

**2. A documented project hook convention.** See "Interaction with hook-based gates" below: where the
project's own documented conventions say a safety hook escalates the operation, audit the pattern
against those conventions rather than flagging its absence.

**3. A live `PreToolUse` hook that already blocks the family.** An absent baseline pattern whose
command family is blocked by a `PreToolUse` hook that is *installed, enabled, and able to run* on the
tool surface the pattern defends is reported `info`, not `error`, because the deny rule is redundant with an
enforcement path that already holds. This narrowing is available whether the hook comes from the repo
or from an installed plugin; a plugin-provided hook is no weaker a block than a repo-provided one.

**Three preconditions, all of which must hold before you take it.**

- **The hook is live, not merely present.** Installed and enabled is not sufficient: `disableAllHooks`
  turns every hook off, and a managed `allowManagedHooksOnly` or a
  `strictPluginOnlyCustomization` value of `true` or an array that includes `"hooks"` suppresses
  non-exempt hooks outright. The key is per-surface: `true` locks skills, agents, hooks, and mcp;
  an array locks only the named surfaces. `"mcp"` blocks MCP servers from `~/.claude.json` and
  `.mcp.json` and does not switch hooks off. v2.1.257 closed the `/mcp` reconnect bypass for a lock
  loaded after startup. A hook a setting has already switched off blocks nothing, so
  under any of those the narrowing does not apply at all and the finding stands at its unnarrowed
  severity. **Phase 1.0's `check-hook-coverage.sh` reports all three**, in every scope it could read,
  so the reading is available before Category B runs and on a scope-filtered `/audit permissions` run
  as well. Where the reading was not taken at
  all, the narrowing is **unavailable** rather than assumed clear: an unread lever is not an unset one.
  Note the script reads the scopes it can open; a managed-settings layer it cannot read leaves
  `allowManagedHooksOnly` unknown, which is a partial reading, not a clear one.
- **The hook the coverage manifest names is one the inventory found.** A `hooks/coverage.json`
  is a claim by the plugin about its own enforcement, not evidence of it, so the named hook must
  appear in the enumerated inventory on the event and matcher the entry declares. An entry naming
  a hook the plugin does not register takes no narrowing and is reported, because the alternative
  is a manifest talking a missing deny rule down to `info` on the strength of code that does not
  run.
- **The hook is on the tool surface the pattern defends.** `destructive-bash-deny` and `ask-rules` are
  Bash-command families, so a `PreToolUse` hook on `Bash`/`PowerShell` can cover them.
  `sensitive-file-deny` is a `Read`-pattern family, and a Read deny covers the built-in file tools as
  well as the recognized Bash file commands, so a hook matching only `Bash` leaves the
  `Read`/`Grep`/`Glob` path open and **does not** retire a `sensitive-file-deny` finding. Match the
  matcher to the family, and where the hook covers only part of the family, narrow only that part.
- **The hook blocks that specific family**, not a neighboring one. Coverage of `git push --force`
  says nothing about `git clean -fd`, and coverage of a long flag says nothing about its short
  spelling unless the hook matches both. Narrow per family, pattern by pattern.

**Name the residual whenever you take narrowing 3.** Hook coverage is contingent in ways a deny rule
is not, and an `info` that hides this is worse than the `error` it replaced. State that the coverage
ends if the providing plugin is disabled or uninstalled, that it is narrowable by any per-guard opt-out
the hook exposes, and that it is suppressible later by `disableAllHooks`, `allowManagedHooksOnly`, or
`strictPluginOnlyCustomization` set to `true` or to an array that includes `"hooks"`, even where
none of them is set today. An array that names only `"mcp"` does not suppress hooks.

**Take the inventory; fail open only where it is incomplete.** Phase 1.0 runs
`scripts/check-hook-coverage.sh`, which enumerates settings-declared hooks **and** every enabled
plugin's hook config, resolved through the installed-plugin registry. Read its **exit code**, because
that is what tells you which posture you are in:

- **`0`, complete.** Every enabled plugin resolved. Narrowing 3 is decidable: an absent pattern whose
  family no enumerated hook blocks is a genuine finding at full severity, and one a live hook does
  block drops to `info` with the residual named. State that the inventory was taken.
- **`1`, partial.** The script's "Not enumerated" block names what it could not read. For families
  those sources could plausibly cover, do **not** assume absence: state the finding as conditional,
  as in "if a `PreToolUse` hook on `Bash` already blocks this family, this finding is void", and name the
  specific unresolved plugin or unparsed file that would settle it. Everything the run *did* enumerate
  is still decidable; partial is not a blanket license to hedge.
- **`2` or not run, no inventory.** Treat as partial for every family, and say so. "Could not look" is
  never reportable as "looked and found nothing".

## Interaction with hook-based gates

The ordering runs both ways, so state it precisely, and keep the two cases apart: a hook that
*returns a decision* is not a hook that *exits 2*.

- **A returned decision cannot loosen a rule.** Deny and ask rules are evaluated regardless of which
  decision a `PreToolUse` hook returns, so a matching deny blocks the call even when the hook returned
  `allow`, and a matching ask still prompts.
- **Exit 2 short-circuits instead of feeding in a decision.** A hook that exits 2 stops the tool call
  before permission rules are evaluated at all, so it blocks where an allow rule would have let the
  call through. Nothing downstream runs, including an otherwise-matching ask rule, which never
  gets to prompt. The bullet above describes returned decisions only; it does not apply here.

The consequence for this baseline is the first direction. When a project escalates an operation to a
permission prompt via its own safety hook (e.g. a git-safety hook that turns `git branch -D` into an
ask), adding a deny entry for the same pattern suppresses that prompt. Audit such patterns against
the project's own documented hook conventions rather than flagging their absence here.
