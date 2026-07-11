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

A deny rule fires before any PreToolUse hook. When a project escalates an operation to a permission
prompt via its own safety hook (e.g. a git-safety hook that turns `git branch -D` into an ask), adding
a deny entry for the same pattern would suppress that prompt — audit such patterns against the
project's own documented hook conventions rather than flagging their absence here.
