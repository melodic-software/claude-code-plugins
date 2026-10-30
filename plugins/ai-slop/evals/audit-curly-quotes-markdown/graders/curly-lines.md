---
type: llm
arm: both
---

PASS only if the audit reports rule-curly-artifacts findings for both line 3 (the
apostrophe in `It’s`) and line 5 (the double quotes around `fast mode`) of docs/upgrade.md,
and does not say it changed the file. FAIL if either line is missing, if the curly characters are
declined or dismissed as correct typography, or if the reply says the file was rewritten.
