---
type: regex
pattern: '^\{"type":"assistant".*"type":"text","text":"(?:[^"\\]|\\.)*?(?:SEC-12|\b400\b|stopped accepting|token query auth)'
flags: mi
target: trace
---
