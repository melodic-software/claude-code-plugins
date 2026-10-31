---
type: llm
arm: both
focus: last_message
---

The user asks whether to split `.claude/skills/changelog-entry/SKILL.md`, a 29-line skill
with one purpose (write one changelog entry), five steps, three rules and three one-line
examples, into a hub with reference files. Judge the final reply.

PASS only if the reply's verdict is to keep the skill as one file, and it raises no
oversize, mixed-concerns or other split finding against it. Mentioning when a split would
start to pay off (for example, if the skill grows much larger) is fine.

FAIL if the reply recommends moving any part (the steps, the rules or the examples) into a
reference, context or examples file now, or reports the file as too long or mixing concerns.
