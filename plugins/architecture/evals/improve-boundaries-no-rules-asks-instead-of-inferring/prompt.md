---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Says that no boundary rule is recorded and names the sources it checked. Collects the edges through the plugin''s dependency map, presents the three internal edges, and asks the user which reference directions must never occur. It proposes no rule from the folder names or the existing references, and writes no findings file because no rule has been confirmed.'
---

/architecture:improve boundaries. This repository has no REVIEW.md, no ARCHITECTURE.md, no ADRs, no docs/architecture folder, no unscoped rules files and no architecture-test configuration. It has three projects: src/Web, src/Orders and src/Shared, and Web references Orders, which references Shared.
