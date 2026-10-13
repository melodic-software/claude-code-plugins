---
bump: patch
---

### Security

- `/review:explain-change`: the artifact medium's publish gate takes no visibility argument. `digest-policy.mjs --publish-gate` now accepts only `--facts <facts.json>`, the repository visibility `/source-control:pull-request view` looked up and wrote, so a visibility the model typed can no longer send a private repository's page to claude.ai. The hosted medium already looked visibility up itself.
