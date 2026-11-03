---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*(?:\bnot|n''t)\s+(?:\w+\s+)?(?:clamp\w*|capp?ed|\btruncat\w*|limited)\b)(?=[^\n]*(?:\bWithBuffer\b|\b500,?000\b|\b500k\b|\bbuffer\s+(?:size|capacity)\b|\bqueue\s+(?:size|capacity)\b))[^\n]*(?:\b65,?53[56]\b|\buint16\b|\b64k\b|\bclamp\w*|\bcapp?ed\b|\bceiling\b|\bsilently\s+(?:reduc|shrink|\btruncat|limit)\w*|\btruncat\w*|\bcannot\s+(?:hold|exceed|reach)\b|\bmaxes?\s+out\b|\bmax(?:imum)?\s+(?:of|is)\b)'
flags: mi
target: last_message
---
