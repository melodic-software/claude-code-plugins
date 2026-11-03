---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:overrid|win|beat|take\s+precedence|shadow|mask|clobber|overwrit|conflict))(?=[^\n]*(?:\bSCANHUB_\w*|\bApplyEnv\b|\benv(?:ironment)?\s+(?:var\w*|layer|overrides?|settings?|values?)\b|\bdocker-compose\b|\bcompose\s+file\b))(?=[^\n]*(?:\boverlays?\b|\bsite\.yaml\b|\bsite\s+(?:file|lead|value|setting)s?\b|\bAC1\b|\bYAML\b))[^\n]*(?:\boverrid\w*|\bwins?\b|\bbeats?\b|\btakes?\s+(?:precedence|priority)\b|\bshadow\w*|\bmask\w*|\bclobber\w*|\boverwrit\w*|\bignored\b|\bno\s+effect\b|\bnever\s+(?:take|takes|reach|reaches|apply|applies)\b|\bapplied\s+after\b|\b(?:runs?|applies)\s+after\b|\bconflicts?\b|\bcontradict\w*|\bdefeats?\b)'
flags: mi
target: last_message
---
