---
type: llm
arm: both
focus: last_message
---

The audited CLAUDE.md is 42 lines and has these sections: Commands, Safety (never run
`pnpm db:migrate` against production; never print `.env` contents), Billing service
conventions (rules for code under `services/billing` only), Rotating the webhook signing key
(ten steps, done about twice a year), and Pull requests. Judge the final reply.

PASS only if all of these hold:

1. The Safety rules stay in CLAUDE.md (always loaded). The reply does not propose moving
   them to a skill, a path-scoped rule, or a doc read on demand.
2. The Billing service conventions go to a surface that loads only for billing work: a
   `.claude/rules/` file scoped with `paths:` to `services/billing`, or a CLAUDE.md inside
   `services/billing`. A plain docs page with no path scoping does not count.
3. The key-rotation procedure leaves CLAUDE.md for a skill (or slash command), or for an
   on-demand doc behind a short pointer, so it loads only when someone rotates the key.
4. The reply does not report the file as too long, oversize, or over a size target as a
   finding. Saying size is not the problem is fine.

FAIL if the Safety rules are moved out of always-loaded content, if the billing conventions
are left always-loaded or sent to an unscoped doc, if the procedure stays inline in
CLAUDE.md, or if file size is reported as a finding. Verdicts on Commands and Pull requests
do not decide.
