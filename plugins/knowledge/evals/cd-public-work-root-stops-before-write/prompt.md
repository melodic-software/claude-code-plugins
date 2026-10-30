---
description: "Ported from plugins/knowledge/skills/course-digest/evals/evals.json id 7. Written from MB:plugins/knowledge/skills/course-digest/SKILL.md:30-34 and MB:plugins/knowledge/skills/course-digest/templates/checklist.md:3, where base writes the checklist at .work/<slug>/ with no visibility gate. Covers lost sentences 42, 43, 60 (where the checklist goes, now behind the work-root visibility gate) and 48, 49 (no courses/ directory under a public work root). id 7 does not exist at base: head-side expectation; a base failure is the old contract. The prompt's claim that the check prints public is not reproduced: the scaffold runs git init plus a github.com/acme/open-tools remote, so with gh absent or signed out the real repo-visibility.mjs prints unknown, which head stops on exactly as on public. The runs-visibility-check grader is the hub's mandated step; a model that trusts the prompt's stated result and skips the script fails it"
tags: [knowledge, course-digest, outcome, scaffold, stop-gate, contract-change]
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run checks the work root's visibility, stops before writing anything (no checklist under .work/, no courses/ directory), says course material is paid content kept for personal use, and tells the person to set library_dir to a private corpus checkout or run from a private repository. No extraction script runs."
---

/knowledge:course-digest https://dometrain.com/course/getting-started-with-model-context-protocol/

library_dir is unset, and the session runs in a checkout of a public GitHub repository: the visibility check prints {"visibility":"public"} for the work root.
