---
type: llm
focus: last_message
---

The repository records the rule "other packages import billing only by its root specifier `@shop/billing`, never a subpath", and billing's package.json already exports only its root. The task was to enforce and prove that rule.

PASS only if the reply states, for that rule, all of: (1) the existing exports map (the Node resolver, through the repository's check command) is what enforces it, and no separate scan, lint rule or test was added for it; (2) the check failed while an injected subpath import of `@shop/billing` was present, with the resolver's not-exported error; (3) the check passed after the injected import was removed.

FAIL if the reply adds or proposes adding a separately run check for this rule as the enforcement, claims the rule is enforced without describing a failing run on an injected violation, or does not describe the passing run after removal.
