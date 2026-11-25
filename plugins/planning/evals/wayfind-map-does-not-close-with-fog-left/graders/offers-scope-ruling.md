---
type: regex
pattern: '\b(?:you|your)\b[^\n]{0,40}\b(?:rule|ruling|declare|decide|call)\w*\b[^\n]{0,60}\bout[- ]of[- ]scope\b|(?<!\bnot )(?<!\bnever )(?<!\bcannot )(?<!n''t )\brul(?:e|ing) (?:it|this|that|the bullet|\**Tax display\**|''Tax display'')\s+out\b|\bout[- ]of[- ]scope\b[^\n]{0,60}\byour\b[^\n]{0,20}\b(?:ruling|reason|call|decision|say-so)\b|\bscope ruling\b'
flags: i
---
