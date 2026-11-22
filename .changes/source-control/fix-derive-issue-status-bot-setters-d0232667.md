---
bump: patch
---

### Changed

- The babysit scripts' Work status read derives the bot setters from the trusted-actor list when `models.issue-status` sets no `bot-setters`: github-actions[bot] plus every `kind: bot` actor whose login starts with `melodic-`, other than `melodic-automation-lanes[bot]`. A config that sets `bot-setters` keeps that explicit list, each entry counting while the trusted-actor list holds it as that bot. This repository's pipeline config no longer carries the key.
