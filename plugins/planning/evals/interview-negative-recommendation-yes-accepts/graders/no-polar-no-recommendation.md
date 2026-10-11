---
type: regex
pattern: '\b(?:should|shall|do|does|will|would|can|could|are|is)\b[^\n?]{0,200}\b(?:rewrite|rewriting|React)\b[^\n?]*\?[\s\S]{0,400}?My recommendation:\s*(?:\*\*)?\s*(?:no|don.?t|do not)\b'
flags: i
match: not_contains
arm: both
---
