---
max_turns: 10
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the README for stash from our product lead's notes below. Its readers are developers on other teams who have never used stash and are deciding whether to adopt it. Reply with the README in one ````markdown fenced block (four backticks).

```text
- Here's the thing: losing a day of work costs more than any tool.
- stash isn't a backup tool, it's an undo button for your whole project.
- Snapshot. Restore. Move on.
- No config files. No daemons. No surprises.
- From weekend side projects to 500-person monorepos, stash takes a snapshot in under a second.
- Every chunk is checksummed with BLAKE3 and verified on restore.
- Snapshots older than 30 days are pruned unless you tag them with --keep.
- Install: brew install stash, then run stash init in the project root.
```
