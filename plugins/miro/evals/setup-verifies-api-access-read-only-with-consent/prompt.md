---
tags: ['setup']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Makes no Miro API request, because the invocation did not pass verify-api, and names `/miro:setup check verify-api` as the opt-in that makes one read-only miro_list_boards call with limit 1. Reports the server state without claiming the token works, discloses no board names, IDs, URLs or token material, and invokes no mutating tool.'
---

/miro:setup

Verify that my configured token works.
