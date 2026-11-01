---
description: "A rule whose word is too weak to beat the default is fixed with a stronger word and kept, not deleted, and the hard-limit rule beside it survives. Written from MB:plugins/docs-hygiene/skills/write-for-agents/SKILL.md:158-163 (the base no-op test: a sentence the model already follows is deleted whole; a word too weak to beat the default is fixed with a stronger word). Head defines the stronger word as a more precise one and keeps firm words for hard limits; either form passes here, so the graders check only what both versions require."
tags: [no-op-test, stronger-word]
runs: 3
max_turns: 8
allowed_tools: [Skill]
expected_outcome: "The revised file keeps a subject-line rule with 'reasonably' and 'where appropriate' replaced by a word or limit strong enough to change behavior, and keeps the rule that never commits a file under secrets/"
---

Agents keep writing long commit subjects even though our `.claude/rules/commits.md` (below) covers it, so the rule is not changing what they do. Fix the file so it does. Reply with the revised file in full inside one ```markdown fenced block, then one line per change saying why.

```markdown
# Commit messages

- Keep the subject line reasonably short where appropriate.
- Never commit a file under `secrets/`: no hook checks that folder, and the files in it hold live
  API keys.
```
