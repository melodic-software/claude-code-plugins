---
description: "Lost sentences 89, 90, 94, 95, 99. Ported from plugins/knowledge/skills/video-digest/evals/evals.json id 11. Its second expectation differs at base (base: pass --work-root \"${CLAUDE_PROJECT_DIR}/my-library\"; head: resolve with work-root.mjs --library-dir 'my-library' and pass the printed absolute path), so the grader resolves-with-work-root-mjs is a head-side expectation; a base failure is the old contract. The other graders check what both versions share: a leading --work-root after --data-dir whose value is an absolute or project-prefixed path ending in my-library, never the bare relative value, and a transcript path under my-library/.work/youtube-watch/. Written from MB:plugins/knowledge/skills/video-digest/context/output-contract.md:20-43 and :90-96; head output-contract.md:20-42. Problem: a plugin eval cannot set the library_dir userConfig option, so the rendered Configured options table shows the default and only the prompt says my-library. Prompt deviation: no network and no node deps, so the Prerequisites gate would stop before run.mjs; the prompt asks for the command line instead of a run. Visibility: none checked by this skill; the scaffold runs git init -q with no remote so the session root is the workspace."
tags: [knowledge, video-digest, outcome, scaffold, work-root, contract-change]
max_turns: 15
timeout_seconds: 450
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply shows a run.mjs command for transcript/run-transcript.js with --data-dir, then a leading --work-root whose value is an absolute path ending in my-library, and a transcript path under my-library/.work/youtube-watch/. At head, a Bash call runs work-root.mjs --library-dir 'my-library'."
---

/knowledge:video-digest transcript https://www.youtube.com/watch?v=7zZy1QTvokM

Treat the Configured options table in SKILL.md as showing library_dir as my-library for this run. This machine has no network and the extraction node dependencies are not installed, so do not install anything or run anything that fetches. Resolve whatever can be resolved locally, then show me the exact run.mjs command line this action would run, with every leading flag it needs, and the path the transcript would land at.
