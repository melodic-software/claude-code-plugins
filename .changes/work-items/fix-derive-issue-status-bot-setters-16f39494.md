---
bump: patch
---

`get-statuses` under Work status trust now derives the bot setters from the trust list instead of the model's `bot-setters`: github-actions[bot] plus every `kind: bot` entry whose login starts with `melodic-`, other than `melodic-automation-lanes[bot]`. The model no longer needs a `bot-setters` key, and one left in place is not read.
