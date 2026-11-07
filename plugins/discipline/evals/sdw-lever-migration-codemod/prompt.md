---
description: "Legacy script-the-deterministic-work 12 (narration: no user option, no repo file). scope-default, answers-build, names-codemod and pilot-one-site are regex; no-write and no-edit (max 0, both arms) check no file is edited; tool-order (llm) quotes legacy expectations 2-4. Needs --allow-tools Write Edit so the no-edit graders can fail."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "lever_scope: deterministic (default); answer: build-a-lever with an established codemod or structural-rewrite tool first, a written script only if none covers it, hand edits last, and a pilot on one call site. No file edited."
---

/discipline:script-the-deterministic-work lever-check migrate 40 call sites from the deprecated fetchUser(id) to its renamed replacement getUser(id), same arguments and same return value, across a TypeScript monorepo

[No lever_scope option is set and the repository, a git checkout that is not the home directory, has no docs/conventions/discipline.yaml.]
