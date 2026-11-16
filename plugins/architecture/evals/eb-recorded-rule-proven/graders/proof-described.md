---
type: llm
focus: last_message
---

The repository records the rule "billing must not import reporting" and has its own import check (scripts/check-imports.sh, run by scripts/check.sh). The task was to add the rule to that check and prove it.

PASS only if the reply states, for that rule, all of: (1) the check failed while an injected billing-to-reporting import was present, and the failure named that rule (its id or its wording); (2) the check passed after the injected import was removed; (3) the rule is now enforced by the repository's existing check command (scripts/check.sh, or the import check it runs).

FAIL if the reply claims the rule is enforced without describing a failing run on an injected violation, or describes only one combined run for every rule.
