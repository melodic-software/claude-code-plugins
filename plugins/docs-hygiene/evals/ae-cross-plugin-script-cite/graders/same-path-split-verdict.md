---
type: llm
arm: both
focus: last_message
---

Two files cite `plugins/lint-kit/skills/check/scripts/run-checks.sh`:
(a) `plugins/release-kit/skills/ship/SKILL.md`, a skill in another plugin;
(b) the repository's own CI workflow file, `ci.yml`.
The READMEs also hold `claude plugin install lint-kit@acme-tools` and
`claude plugin install release-kit@acme-tools` lines (c).
Judge the final reply.

PASS only if all of these hold:

1. The reply reports (a) as a violation, leak or cross-plugin dependency that needs fixing.
2. The reply does not list (b) as a violation; naming it as legal, allowed, or the script's
   public entry surface is fine.
3. The reply does not list the install lines (c) as violations.

FAIL if (a) is missing from the violations, or if (b) or (c) is presented as a violation.
Whether the reply proposes `/lint-kit:check` or another route for (a) does not decide the verdict.
