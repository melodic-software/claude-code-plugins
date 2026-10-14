---
description: "A Dometrain course URL given to video-digest fails closed: the reply names the supported sources (YouTube and X) and routes to /knowledge:course-digest (intro unsupported-host rule and frontmatter description), with no acquisition, watch or transcript script run and no file written"
tags: [knowledge, video-digest, outcome, routing]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write]
expected_outcome: "The reply refuses the unsupported host, lists YouTube and X/Twitter as the supported sources, and points to /knowledge:course-digest. No Bash call runs run-watch.js, run-transcript.js, preflight-metadata.js or a direct yt-dlp/curl/wget download; no Write call."
---

/knowledge:video-digest https://dometrain.com/course/getting-started-domain-driven-design/
