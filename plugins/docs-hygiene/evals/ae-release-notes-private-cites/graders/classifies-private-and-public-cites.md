---
type: llm
arm: both
focus: last_message
---

The repository has these cites of the release-notes skill from outside the skill:
(a) docs/releasing.md cites `.claude/skills/release-notes/reference/changelog-format.md`;
(b) docs/releasing.md cites `.claude/skills/release-notes/SKILL.md#version-bump-rules`;
(c) docs/releasing.md invokes `/release-notes draft <version>`;
(d) docs/tooling.md names the bare path `.claude/skills/release-notes/SKILL.md` and `/release-notes`;
(e) .github/workflows/release.yml runs `.claude/skills/release-notes/scripts/collect-prs.sh`.
Judge the final reply.

PASS only if all of these hold:

1. The reply reports (a) as a violation or leak that needs fixing.
2. The reply reports (b), the heading-anchor cite, as a violation or leak that needs fixing.
3. The reply does not list (c), (d) or (e) as violations. Naming them as legal, allowed,
   public surface, filtered, or merely discouraged is fine. Saying that moving
   `scripts/collect-prs.sh` would break the CI step is also fine, as long as the CI step is not
   called a violation or leak to fix.
4. The reply does not say it has already changed, rewritten or fixed any file. Offering or
   recommending a fix is fine.

FAIL if (a) or (b) is missing from the violations, if (c), (d) or (e) is presented as a
violation, or if the reply reports having edited a file.
