---
bump: patch
---

### Fixed

- The issue lane's security-word stop no longer holds an issue for a word that lies wholly inside a known name: a skill id or principle name listed in `.github/scripts/work-resolve-issue/known-names.json` (starting with `attack-the-premise` and `review:security-review`), written exactly as listed as a whole identifier. A word that runs past a listed name's edge, and any security word or credential mention elsewhere in the reason, still holds. A listed name joins at least two parts with `-`, `_` or `:` and holds no secret noun.
