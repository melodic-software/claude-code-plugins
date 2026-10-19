---
type: regex
pattern: '^(?![^\n]*\b(?:no|not|nothing|none|never)(?:\s+\w+){0,3}\s+(?:missing|absent|lacks?)\b)(?![^\n]*n''t(?:\s+\w+){0,2}\s+(?:missing|absent)\b)(?=[^\n]*\b(?:reversib\w*|lifecycle|doors?)\b)[^\n]*?(?:\b(?:reversib\w*|lifecycle|doors?)\b[^\n.;]{0,80}\b(?:missing|absent|not (?:recorded|present|found))\b|\b(?:missing|absent|lacks?|lacking|without)\b[^\n.;]{0,60}\b(?:reversib\w*|lifecycle|doors?)\b|\bno\s+(?:[\w\x60*-]+\s+){0,2}(?:threads?\b|doors?\b|calls?\b|\x60?Door:))'
flags: mi
---
