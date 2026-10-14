---
description: "A single public YouTube URL given to course-digest is routed to /knowledge:video-digest (Platform detection table row and frontmatter description) and starts no course extraction script and writes no checklist"
tags: [knowledge, course-digest, outcome, routing]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write]
expected_outcome: "The reply points the user to /knowledge:video-digest for the single YouTube video. No Bash call runs extract-course.js, discover-resources.js, build-course-json.js or download-resources.js, and no Write call (no .work checklist for a run that is not a course digest)."
---

/knowledge:course-digest https://www.youtube.com/watch?v=Ab3dE5fGh7I
