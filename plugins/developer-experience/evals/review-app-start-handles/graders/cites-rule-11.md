---
type: llm
focus: last_message
---

Rubric item: the reply names the CLI contract rule the command breaks.

User prompt: "Use the build-cli skill to review our new `bfk app start` command before I merge it. ... Tell me why it hangs, what to change, and which rule of the CLI contract it breaks." The build-cli CLI contract's rule 11, "No inherited handles", says a command that starts a long-running child must not let it inherit the caller's stdin, stdout or stderr: redirect the three to null or a file, and detach it.

PASS when the reply names that rule as the one broken: by its name ("No inherited handles"), as rule 11 of the CLI contract, or by stating the contract's requirement that a started child must not inherit the caller's standard streams and attributing it to the contract.

FAIL when the reply names no contract rule for this problem, cites a different rule (non-interactive use, exit codes, `--help`, `--json`, `--dry-run`, the shared process helper), presents the fix only as a best practice, a preference or general advice, or cites only Python or operating-system documentation.
