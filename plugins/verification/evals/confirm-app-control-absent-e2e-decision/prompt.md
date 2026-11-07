---
description: 'Legacy evidence-loop-04, expectation 3. Without app-control no touched feature is matched, so whether /testing:run-e2e runs is decided from the e2e-* path categories and the other Stage 2 triggers alone (SKILL.md Stage 2 step 1, ''In every case the e2e-* path categories still apply''). The prompt is the legacy one, with the testing plugin installed. Expectations 1, 2 and 4 are graded by confirm-app-control-absent-fallback-line, whose scenario has no testing plugin and so cannot grade 3. fallback-line and names-path-category grade the reply; e2e-from-paths (llm) legacy expectations 2 and 3 verbatim.'
tags: [verification, confirm, narration, no-network, app-control, fallback, e2e, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Carries touched features not matched (app-control not installed), reads no sources glob itself, and decides /testing:run-e2e from the e2e-* path categories (src/cart/total.ts is app source) with no touched feature.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed. The app-control plugin is not installed: no app-control skill resolves in this session. The repository has a control skill .claude/skills/control-shop/ whose index lists a cart/total feature with `sources: src/cart/**`. This branch changes only src/cart/total.ts. The testing plugin is installed. Say how you decide the touched features and whether /testing:run-e2e runs, then stop.
