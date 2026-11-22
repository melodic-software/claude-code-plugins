---
bump: patch
---

### Changed

- `get-statuses` under Work status trust derives the bot setters from the trust list when the model sets no `bot-setters`: github-actions[bot] plus every `kind: bot` entry whose login starts with `melodic-`, other than `melodic-automation-lanes[bot]`. A model that sets `bot-setters` keeps that explicit list, each entry counting while the trust list holds it as that bot.
