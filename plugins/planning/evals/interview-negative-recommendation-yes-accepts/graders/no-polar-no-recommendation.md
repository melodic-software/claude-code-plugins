---
type: regex
pattern: '\b(?:should|shall|do|does|will|would|can|could|are|is)\b[^\n?]{0,200}\b(?:rewrite|rewriting|rebuild\w*|(?:port|migrat|convert|mov|switch)\w*[^\n?]{0,60}\bto React)\b[^\n?]*\?(?:(?!\n\s*\**Q\d+)[\s\S]){0,400}?My recommendation:\s*(?:\*\*)?\s*(?:no|don.?t|do not)\b'
flags: i
match: not_contains
arm: both
---
