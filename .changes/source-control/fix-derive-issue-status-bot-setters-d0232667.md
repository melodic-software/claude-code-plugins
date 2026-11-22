---
bump: patch
---

The babysit scripts' Work status read derives the bot setters from the trusted-actor list instead of `models.issue-status.bot-setters`: github-actions[bot] plus every `kind: bot` actor whose login starts with `melodic-`, other than `melodic-automation-lanes[bot]`. The pipeline config no longer carries a `bot-setters` key, and one left in place is not read.
