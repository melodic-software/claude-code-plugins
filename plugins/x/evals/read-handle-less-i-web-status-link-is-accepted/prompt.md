---
description: "The handle-less post form. SKILL.md Gate: /i/web/status/<id> matches its own pattern and rebuilds to https://x.com/i/web/status/<id>; no handle was captured, so inventing one breaches rebuild-from-captures, and Reporting attributes with the handle from the converted body and the gate's rebuilt URL, never the converter-echoed one. The eval sandbox blocks the network, so the xtomd response is scaffolded at notes/x-1234567890123456789-h2.md; its body names @quillfinch and echoes a twitter.com/quillfinch/... source line. attributes-rebuilt-url passes only a reply carrying the rebuilt /i/web/ URL, which appears in neither the prompt nor the file; no-invented-handle-url fails a reply that folds the body's handle into an x.com/<handle>/status/<id> URL. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the handle-less post form, captures the numeric id, and attributes the post with the rebuilt https://x.com/i/web/status/1234567890123456789 and the @quillfinch handle from the converted body. No handle is invented for the rebuilt URL.'
---

/x:read https://x.com/i/web/status/1234567890123456789

Fetching doesn't work from here, so I ran the xtomd step for this link on my laptop (curl exited 0, HTTP 200) and saved the converted Markdown to notes/x-1234567890123456789-h2.md. Use that file instead of fetching again.
