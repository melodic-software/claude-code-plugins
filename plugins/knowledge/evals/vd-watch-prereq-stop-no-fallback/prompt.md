---
description: "A watch in a sandbox whose plugin data has no node_modules (and no network for setup-deps.mjs, with or without yt-dlp on PATH) stops at the Watch action's prerequisites gate (or at No video, no watch) and names the fix path; it never switches to the transcript action on the user's behalf and never improvises a direct yt-dlp/curl/wget download"
tags: [knowledge, video-digest, outcome, missing-prerequisite]
max_turns: 15
timeout_seconds: 450
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply says the watch stopped (cannot proceed) and names the fix path: re-run setup-deps.mjs, or install the missing yt-dlp/ffmpeg/ImageMagick. No Bash call runs run-transcript.js, and none runs yt-dlp, youtube-dl, curl or wget against the YouTube URL directly."
---

/knowledge:video-digest watch https://www.youtube.com/watch?v=7zZy1QTvokM
