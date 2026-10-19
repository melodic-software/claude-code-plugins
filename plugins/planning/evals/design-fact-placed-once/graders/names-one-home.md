---
type: regex
pattern: '^(?![^\n]*\b(?:not worth|no need|overkill|unnecessary|needless|unneeded|don''t|do not|avoid|skip)\b)(?![^\n]*\b(?:isn[''’]t|aren[''’]t|not)\s+(?:\w+\s+)?(?:needed|necessary|required|warranted)\b)(?![^\n]*\b(?:instead of|rather than|not|no|without)\s+(?:\w+\s+){0,2}(?:single|shared|central|common|one)\b)(?=[^\n]*(?:\b25\b|\bcap\b|\blimits?\b|MAX_UPLOAD|\bsize\b))[^\n]*(?:\b(?:one|single|shared|central|common|authoritative)\b[^\n]{0,40}?\b(?:constant|settings?|config|module|source|home|place|definition)\b|\bnew\b[^\n]*\b(?:all|every)\b[^\n]{0,20}?\b(?:read|import|use)\w*)'
flags: mi
---
