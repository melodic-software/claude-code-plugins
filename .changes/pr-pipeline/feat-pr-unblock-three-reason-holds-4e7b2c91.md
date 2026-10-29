---
bump: minor
---

### Changed

- pr-unblock holds a pull request for a person only for the owner's three reasons, and queues the rest for a session builder

  `escalation-routes.json` now routes `hold` (`needs-human`) only for an intent or design question, a person's own thread or hold, and a HIGH or CRITICAL security risk: `feedback-question-*`, `feedback-uncertain`, `feedback-disputed`, `feedback-round-cap`, `dependency-security-close`, `dependency-escalate` and `dependency-fix-refused`. The protected-path stops (`protected-path-conflict`, `conflict-patch-protected-path`, `feedback-protected-path`, `ci-fix-protected-path`), `ci-fix-weaken-required` after its fresh fixer round, and the other review-dependency stops route `fail` with `"label": "needs-session"`: `report-escalation.sh` adds that label before its lane-stopped comment and posts the failing status, and no merge gate reads the label. A well-formed reason the table does not list now holds for a person instead of failing the job.

- pr-unblock's adjudicator settles an intent or design question from the work item contract

  The adjudicate-feedback job stages the linked issues' spec text that pr-verify reads (`resolve-pr.mjs` `linkedIssues`, now exported) as `contract.json`. A lane or reviewer verdict on an intent or design question must carry a `quote`; the script keeps it only when it is an exact substring of that text, at least 20 characters, and the reply quotes it with the issue's URL. Any other quote, or no spec text, leaves `feedback-question-intent` or `feedback-question-design` a person's. A security question, a CRITICAL finding and a security-review finding rated `IMPORTANT` or above never settle by quote. The job gains `issues: read` and `pull-requests: read`.
