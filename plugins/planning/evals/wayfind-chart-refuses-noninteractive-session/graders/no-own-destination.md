---
type: regex
match: not_contains
pattern: '\bDestination\**[ \t]*[:=]\**[ \t]*(?:an? |the |one )?(?:PRD|product requirements|set of build items|build items|single change|one change|decision record|general summary|summary)\b|\b(?:picked|chose|chosen|going with|defaulting to|defaulted to)\b[^.\n]{0,40}\b(?:destination|a PRD)\b'
flags: i
---
