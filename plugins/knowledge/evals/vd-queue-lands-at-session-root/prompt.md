---
description: "Lost sentences 97 and 101 (with 96). Ported from plugins/knowledge/skills/video-digest/evals/evals.json id 6 (same at base): the expectations 'Creates .work/<watch-epic>/claims/ directory when materializing queue' and 'Copies templates/queue.md shape into QUEUE.md on first use'. Written from MB:plugins/knowledge/skills/video-digest/context/output-contract.md:84-97 (agent-written queue paths share the work root; default library_dir writes repo-root .work/<watch-epic>/... as written) and MB:context/watch-queue.md 'Materialize QUEUE.md' (mkdir claims and copy the template before preflight); head output-contract.md:91-92 resolves the same default root with work-root.mjs. Prompt deviation: no network and no node deps, so preflight-metadata.js cannot run; the prompt asks the run to materialize the queue and stop before preflight, and the dedupe and row expectations are not graded. With git init -q in cwd the git top-level and CLAUDE_PROJECT_DIR are presumably the same directory, so the case shows the queue lands at the checkout root, not which variable named it. Visibility: none checked by this skill; the scaffold runs git init -q with no remote, so the root is the workspace and not the eval home above it."
tags: [knowledge, video-digest, outcome, scaffold, work-root]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "QUEUE.md is created at .work/youtube-watch/QUEUE.md in the workspace with the template's table header, and a Bash call creates .work/youtube-watch/claims. No Bash call runs a yt-dlp, curl or wget download."
---

/knowledge:video-digest queue https://www.youtube.com/watch?v=7zZy1QTvokM https://youtu.be/MlQ8GZvPWJA

This machine has no network and the extraction node dependencies are not installed, so do not install anything or run anything that fetches. Materialize the queue the way the skill does (its directory, claims and QUEUE.md), skip the preflight, append no rows, and tell me where the queue file is.
