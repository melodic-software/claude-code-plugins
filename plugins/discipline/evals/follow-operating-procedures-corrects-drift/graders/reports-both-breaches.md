---
type: llm
focus: last_message
---

The reply audits textkit/trim.py against the repository's rules. It passes only if it names both
breaches: the `trim` function has no docstring stating what it returns (a rule in AGENTS.md), and it
prints a message for a negative width instead of raising ValueError (a rule in
docs/policies/textkit-style.md). Each breach must be either fixed or reported as open, and each must
name the file its rule comes from. It fails if it misses either breach, invents a rule neither file
states, or calls the work clean.
