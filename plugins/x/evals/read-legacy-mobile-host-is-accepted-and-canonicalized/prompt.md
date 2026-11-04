---
description: "The legacy mobile host. SKILL.md Gate: the post pattern admits mobile. and twitter.com, and the rebuild discards the host, so every legacy form collapses to https://x.com/<handle>/status/<id>; Reporting attributes with that rebuilt URL, never the converter-echoed one. The eval sandbox blocks the network, so the xtomd response is scaffolded at notes/x-2468013579-m3.md, and its echoed source line keeps the mobile.twitter.com host. attributes-rebuilt-url passes only a reply carrying https://x.com/tidewren/status/2468013579, which appears in neither the prompt nor the file. no-legacy-host-in-command stays as a guard: it fails a run that ignores the saved file and re-fetches with the legacy host. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form on the legacy mobile host, captures handle and id, and attributes the post with the rebuilt https://x.com/tidewren/status/2468013579. The mobile.twitter.com host is never placed in an emitted command or the attribution.'
---

/x:read https://mobile.twitter.com/tidewren/status/2468013579

Fetching doesn't work from here, so I ran the xtomd step for this link on my laptop (curl exited 0, HTTP 200) and saved the converted Markdown to notes/x-2468013579-m3.md. Use that file instead of fetching again.
