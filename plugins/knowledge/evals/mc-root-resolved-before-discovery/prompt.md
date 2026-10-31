---
description: "Lost sentence 80. Ported from plugins/knowledge/skills/map-corpus/evals/evals.json id 1 (same at base), its pre-fetch steps only: 'Resolves the library_dir work root' and 'manifest.json is produced by extract_nodes.py, never authored by the agent'. Written from MB:plugins/knowledge/skills/map-corpus/SKILL.md:42-52 and :60-69 (default library_dir resolves against the session's git top-level, never CLAUDE_PROJECT_DIR; the slice lands at <root>/.work/<epic>/<slug>/ with slug = topic slug plus -hash8); head runs work-root.mjs for the same root (map-corpus/SKILL.md:42-52). The sandbox has no network, so discovery of llms.txt and the sitemap fails and the later expectations (link map, approval, inventory, queue) are not graded. Graded: the run resolves the root (git rev-parse at base, work-root.mjs at head) and creates slice files under .work/agent-plugins-spec/agent-plugins-spec-<hash8>/ in the workspace. Visibility: none checked by this skill; the scaffold runs git init -q with no remote so the session root is the workspace, not the eval home above it."
tags: [knowledge, map-corpus, outcome, scaffold, work-root]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A Bash call resolves the session root (git rev-parse --show-toplevel or work-root.mjs), and at least one slice file, such as map-corpus-checklist.md or seeds.txt, is created under .work/agent-plugins-spec/agent-plugins-spec-<8 hex>/ in the workspace. No Write creates manifest.json."
---

/knowledge:map-corpus "agent plugins spec" https://agent-plugins.org --max-resources 20
