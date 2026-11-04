---
description: "A plaintext http:// link. SKILL.md Gate: https? matches, and the rebuild discards the scheme and host, so the input becomes https://x.com/<handle>/status/<id>; Reporting attributes with that rebuilt URL, never the converter-echoed one. The eval sandbox blocks the network, so the xtomd response is scaffolded at notes/x-1357924680-s7.md, and its echoed source line keeps http://twitter.com. attributes-https-url passes only a reply carrying https://x.com/brinkmoss/status/1357924680, which appears in neither the prompt nor the file. no-http-in-command and no-http-in-webfetch stay as guards: they fail a run that ignores the saved file and requests the plaintext URL. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form, captures handle and id, and attributes the post with the rebuilt https://x.com/brinkmoss/status/1357924680. The plaintext scheme is discarded by the rebuild rather than carried forward, so no plaintext URL reaches a command, a fetch or the attribution.'
---

/x:read http://twitter.com/brinkmoss/status/1357924680

Fetching doesn't work from here, so I ran the xtomd step for this link on my laptop (curl exited 0, HTTP 200) and saved the converted Markdown to notes/x-1357924680-s7.md. Use that file instead of fetching again.
