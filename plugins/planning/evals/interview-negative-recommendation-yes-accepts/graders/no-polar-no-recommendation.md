---
type: regex
pattern: '\b(?:should|shall|do|does|will|would|can|could|are|is)\b(?:(?!\b(?:defer|stay|keep|out of|skip|separate|follow|wait|later|postpone|hold|own)\w*)[^\n?]){0,200}\b(?:rewrite|rewriting|rebuild\w*|(?:port|migrat|convert|mov|switch)\w*(?:(?!\b(?:defer|stay|keep|out of|skip|separate|follow|wait|later|postpone|hold|own)\w*)[^\n?]){0,60}\bto React)\b(?:(?!\b(?:defer|stay|keep|out of|skip|separate|follow|wait|later|postpone|hold|own)\w*)[^\n?])*\?(?:(?!\n\s*\**Q\d+)[\s\S]){0,400}?(?:My )?recommend(?:ation|ed):\s*(?:\*\*)?\s*(?:no|don.?t|do not|not (?:now|yet|in this|as part)|skip|defer|keep (?:it|the rewrite|this|that) out|out of scope|leave it)\b'
flags: i
match: not_contains
arm: both
---
