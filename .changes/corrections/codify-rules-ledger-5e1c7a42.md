---
bump: minor
---

### Added

- `/corrections:codify rules <file>...` turns the rules in instruction files (`AGENTS.md` and the in-repo files it points to, `CLAUDE.md`, `.claude/rules/`, `.cursor/rules/`, review criteria docs) into checks. Each rule becomes a check on its rung with its own proof and its prose flagged for deletion, stays prose with a reason, is deleted as derivable, or is held. A rule becomes a check only when it needs no judgment and the check covers its known cases; an unproven check is held. One file's rules may go through in one pass.
- `scripts/rules-ledger.mjs` reconciles the ledger of every rule read and exits 1 naming each rule dropped or left incomplete, so the run cannot finish with a rule unaccounted for.
- `reference/adding-a-team-rule.md`: survey the legitimate uses, scope the rule, warn before error, allow only exclusions with a reason, and audit suppressions afterwards with `/code-metrics:audit-suppressions`. A rule codify proposes to write ships with its own valid and invalid rule tests in the tool's own harness where one exists, and states what it does not catch. Every checking-rung proposal now points at it.
- Eval cases `codify-rules-ledger-accounts-for-every-rule` and `codify-custom-rule-ships-rule-tests`.
