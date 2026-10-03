---
type: llm
arm: both
---

PASS if the answer says to move the content the cases depend on into the hub `SKILL.md` (within its size limit), so the with-arm can measure it. Saying the eval measures only what SKILL.md carries, so what matters must go there, also meets this.

FAIL if the answer says to keep the reference out of SKILL.md; offers only permission grants, `allowed_tools`, or `context.add_dirs` changes; proposes copying the reference into the case directory; says to ignore the denial and accept the score; or later contradicts or retracts this.
