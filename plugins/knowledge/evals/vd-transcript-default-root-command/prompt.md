---
description: "Lost sentence 96 (with 101 for the landing path). Ported from plugins/knowledge/skills/video-digest/evals/evals.json id 1 (same at base): the expectations 'Invokes run.mjs transcript/run-transcript.js with the URL', 'Does NOT download video', and 'Reports video slug and transcript path under .work/'. Written from MB:plugins/knowledge/skills/video-digest/context/output-contract.md:45-46 (default library_dir: run.mjs without --work-root, artifacts at the consuming repo root) and :97; head output-contract.md:44-47 keeps the no-flag rule with the git top-level as the fallback. Prompt deviation: the sandbox has no network and no node deps in the plugin data dir, and the Prerequisites gate stops any action before run.mjs (as vd-watch-prereq-stop-no-fallback shows), so the prompt asks for the command and landing path instead of a run. With git init -q in cwd the git top-level and CLAUDE_PROJECT_DIR are presumably the same directory, so the case shows the default lands at the checkout root, not which variable named it. Visibility: none checked by this skill; the scaffold runs git init -q with no remote."
tags: [knowledge, video-digest, outcome, scaffold, work-root]
max_turns: 15
timeout_seconds: 450
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply shows the run.mjs command line for transcript/run-transcript.js with the URL and no --work-root flag, and names a transcript path under .work/youtube-watch/<video-slug>/transcript.txt. No Bash call runs run-watch.js or a yt-dlp, curl or wget download."
---

/knowledge:video-digest transcript https://www.youtube.com/watch?v=7zZy1QTvokM

This machine has no network and the extraction node dependencies are not installed, so do not install anything or run anything that fetches. Show me the exact run.mjs command line this action would run, with every leading flag it needs here, and the path the transcript would land at.
