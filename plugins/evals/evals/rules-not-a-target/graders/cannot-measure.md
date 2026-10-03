---
type: llm
arm: both
---

PASS if the answer says both:

1. No: `claude plugin eval` cannot measure CLAUDE.md or `.claude/rules`.
2. Why: each run starts from a clean, throwaway home where CLAUDE.md, rules, settings and memory do not load. Wording such as "your project instructions and rules never load" meets this. Adding that re-injecting them through the case measures that shim, not the rules, is welcome but not required.

FAIL if either is missing; if the answer says yes, proposes running the suite with and without CLAUDE.md through plugin eval, proposes injecting the rules through the case (append_system_prompt, a wrapper plugin) as a valid measurement, or says plugin eval loads or does not strip CLAUDE.md; or if it later contradicts or retracts this.
