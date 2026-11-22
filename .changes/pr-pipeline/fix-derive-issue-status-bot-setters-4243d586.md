---
bump: patch
---

### Changed

- `models.issue-status.bot-setters` is optional. When it is absent, the Work status readers derive the bot setters from `trusted-actors.json`: github-actions[bot] plus every `kind: bot` actor whose login starts with `melodic-`, other than `melodic-automation-lanes[bot]`, in list order. When it is set, its entries are the bot setters, each counting while the trusted-actor list holds it as that bot. This repository's config no longer sets the key, so a standards sync that adds or removes a melodic- App needs no hand edit.
