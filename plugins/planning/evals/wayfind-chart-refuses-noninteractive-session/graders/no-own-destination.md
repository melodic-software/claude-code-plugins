---
type: regex
match: not_contains
pattern: '\bDestination\**[ \t]*(?:\([^)\n]{0,30}\)[ \t]*)?[:=]\**[ \t]*(?:an? |the |one )?(?:PRD|product requirements|set of build items|build items|single change|one change|decision record|general summary|summary)\b|(?:^|[.!?;,\n])(?:(?!\b(?:not?|never|without|nor|would|could|if|have to)\b|n''t\b|''d\b)[^.!?;,\n])*?\b(?:picked|chose|chosen|going with|defaulting to|defaulted to|(?:assume|assumed|assuming)|treat(?:ing)? the destination as)\b[^.\n]{0,40}\b(?:destination|a PRD)\b'
flags: i
---
