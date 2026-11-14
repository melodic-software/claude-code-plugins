---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Derives the feature blueprint from the three commits, cited by hash and subject, and proposes it as a paved-path entry. On the yes it drafts the entry (the concern, the chosen way as a pointer to the commit that best shows it, the four building blocks, unordered since each feature came in one commit, and the enforcing check or none) and hands it to /discipline:reuse-or-replace through the Skill tool, writing no paved-path entry itself.'
---

/architecture:improve conventions. History shows three feature commits, a1b2c3d 'feat: add refunds', d4e5f6a 'feat: add returns' and 0789abc 'feat: add exchanges', each adding a request, a handler, a validator and a migration in one commit. /discipline:reuse-or-replace is available. When you propose the feature blueprint, I say yes.
