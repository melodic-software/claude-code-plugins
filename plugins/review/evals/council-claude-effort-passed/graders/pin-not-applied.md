---
type: regex
pattern: '(?<!not )(?<!never )(?<!n.t )(?<!would )(?<!otherwise )(?<!else )\b(?:runs?|executes?|uses?|falls? back to)\s+(?:on\s+|with\s+)?(?:opus|effort\s+high|high\s+effort)\b|\beffort\b[^\n.]{0,30}\b(?:is|gets?)\s+(?:ignored|dropped)'
flags: i
match: not_contains
---
