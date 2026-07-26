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
listed separately where relevant — CC permission globs are greedy across slashes but require an
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

### Scope of a Read deny — what it covers, and what it does not

These entries are a guardrail against routine access, not a containment boundary. Category B checks
that the rules are present; presence is not evidence the file is unreachable. Say so whenever the
category is reported, in either direction. Verified 2026-07-26 against
[permissions](https://code.claude.com/docs/en/permissions#read-and-edit),
[sandboxing](https://code.claude.com/docs/en/sandboxing), and
[tools reference](https://code.claude.com/docs/en/tools-reference#powershell-tool).

**Covered.** A `Read(...)` deny applies to the built-in file tools (Read, Grep, Glob, LSP), to
`@file` mentions in a prompt, to the selection and open-file context a connected IDE shares, to the
Edit tool on the same path (CC v2.1.208+), and — per the permissions page — to *file commands Claude
Code recognizes inside a Bash command, such as `cat`, `head`, `tail`, and `sed`*. The obvious
"`cat` it instead" fallback is therefore blocked.

**Not covered.** The same page: the rules "don't apply to arbitrary subprocesses that read or write
files indirectly, like a Python or Node script that opens files itself." A `python -c`, a `node -e`,
or any script that opens the path reads a `Read`-denied file with no deny firing. That is the real
gap, and it is reached *routinely* — an agent blocked on `Read` reaches for an interpreter one-liner
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

**`sandbox.enabled: true` alone is not a boundary — check the escape surfaces before calling it one.**
Upstream documents four, all open at their defaults, and each puts a subprocess back outside the OS
boundary where it can read the denied path:

| Setting | Why it matters | What a boundary requires |
| --- | --- | --- |
| `allowUnsandboxedCommands` | A command that fails under the sandbox may be retried with `dangerouslyDisableSandbox`, which runs it outside | set to `false` |
| `failIfUnavailable` | A missing dependency or an unsupported platform warns and then runs commands unsandboxed | set to `true` |
| `excludedCommands` | Anything listed runs outside the sandbox, and upstream notes a developer can always append entries | kept narrow, and reviewed |
| `filesystem.disabled` | Turning the filesystem layer off lifts the `denyRead` and `credentials.files` read protections entirely | not set |

Report an enabled-but-default sandbox as partial, not as protection. Recommending it without these is
the same defect as recommending the deny globs without their scope.

**Platform limit — check before recommending it.** The sandbox runs on macOS, Linux, and WSL2; native
Windows is not supported, and the PowerShell tool lists "On Windows, sandboxing is not supported"
among its preview limitations. On a native-Windows workstation the OS-level remedy is unavailable, so
do not offer it there as the fix.

**A `PreToolUse` hook on `Bash|PowerShell` is a speed bump, not a boundary.** It can inspect the
command string and deny the call, and a hook exiting 2 blocks a call an *allow* rule would otherwise
have permitted. A decision it returns cannot loosen a deny — see "Interaction with hook-based gates"
below for the precise ordering. But it inspects that same command string, so it inherits the evasion surface of a
Bash deny glob. Rank it below the sandbox and never describe it as protection.

**Residual risk, stated plainly.** Where no OS-level boundary is available, a deny glob cannot keep a
secret from a session that has shell execution. **Directory location is not a boundary**: a
subprocess opens absolute paths, so moving the file outside the working directory and
`additionalDirectories` changes nothing about who can read it — never present relocation as
protection. The boundary that holds is the OS principal. A file readable by the account the session
runs as is reachable, wherever it sits. So the durable control is that the secret is not sitting in a
file that account can read at all: keep it in an OS credential store or a secrets manager and inject
it at use time, scope it to a short-lived credential whose theft expires, or run the session as a
different principal or inside a container that never receives it. Keep the deny rules above; do not
report them as proof the file is protected.

**Unverified — flag it rather than asserting either way.** No fetched page states whether reads
through the **PowerShell tool** (`Get-Content`, `type`) are covered: the permissions page scopes the
recognized-command coverage to commands "in Bash", and the tools reference lists `Read(...)` as
applying to "Read, Grep, Glob, LSP". Treat PowerShell reads as uncovered until upstream says
otherwise. The recognized-command list is also introduced with "such as" and is not exhaustive, so
`grep`, `jq`, `strings`, and shell redirects are unconfirmed in both directions.

## destructive-bash-deny (Bash deny)

Bash deny patterns for destructive git operations — the universal baseline.

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

## ask-rules (Bash ask)

Bash patterns that should require confirmation before execution. `git push` is the canonical ask-gate
— pushes carry intent the agent should not infer.

| Pattern | Purpose |
| --- | --- |
| `Bash(git push *)` | Require confirmation before pushing with args |
| `Bash(git push)` | Require confirmation before pushing without args |

## Narrowing the baseline

The baseline is a floor for the common case, not an unconditional mandate. A repo where a pattern is
genuinely inapplicable — e.g. a read-only analysis or documentation repo with no push access, where
the `git push` ask-gates protect nothing — documents the exemption in its own rules files; Category B
checks for such a documented exemption before flagging an absent pattern. Undocumented absence is
still a finding.

## Interaction with hook-based gates

The ordering runs both ways, so state it precisely, and keep the two cases apart — a hook that
*returns a decision* is not a hook that *exits 2*.

- **A returned decision cannot loosen a rule.** Deny and ask rules are evaluated regardless of which
  decision a `PreToolUse` hook returns, so a matching deny blocks the call even when the hook returned
  `allow`, and a matching ask still prompts.
- **Exit 2 short-circuits instead of feeding in a decision.** A hook that exits 2 stops the tool call
  before permission rules are evaluated at all, so it blocks where an allow rule would have let the
  call through — and nothing downstream runs, including an otherwise-matching ask rule, which never
  gets to prompt. The bullet above describes returned decisions only; it does not apply here.

The consequence for this baseline is the first direction. When a project escalates an operation to a
permission prompt via its own safety hook (e.g. a git-safety hook that turns `git branch -D` into an
ask), adding a deny entry for the same pattern suppresses that prompt — audit such patterns against
the project's own documented hook conventions rather than flagging their absence here.
