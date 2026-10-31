---
description: "Lost sentence 85. Ported from plugins/knowledge/skills/setup/evals/evals.json id 3 (same at base). Written from MB:plugins/knowledge/skills/setup/SKILL.md:93-105 (apply install-deps runs both idempotent provisioners, then re-runs the check probes and reports their results, never trusting exit codes alone; MB:108-110, no system packages). Mechanism differs: base runs each package's own skills/<package>/extraction/setup-deps.mjs, head runs the shared vendor/node-launcher/setup-deps.mjs with --package pointing at that extraction directory (setup/SKILL.md:93-101); the graders match the shared outcome, a provisioner call naming each of video-digest/extraction and course-digest/extraction, not the script path. The sandbox has no network, so npm install and the Chromium download are expected to fail: graded are the attempts, the re-probe report, no system install, and no ingestion run. yt-dlp may be on the inherited PATH, which would contradict the prompt; the llm grader accepts either probe result."
tags: [knowledge, setup, outcome, missing-prerequisite]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "Bash runs a setup-deps.mjs provisioner for video-digest/extraction and one for course-digest/extraction, then the reply reports the node-deps and Chromium state from probes run after them. For a missing yt-dlp it gives an install command. No Bash call installs a system package or runs an extraction run.mjs."
---

/knowledge:setup apply install-deps

On this machine the vendored node deps and Chromium are absent, and yt-dlp is also missing.
