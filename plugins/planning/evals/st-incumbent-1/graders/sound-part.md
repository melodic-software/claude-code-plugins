---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*(?:\bnot|n''t)\s+(?:\w+\s+)?(?:too|arbitrar\w*|wrong|incorrect|unjustified|exceed\w*|a\s+bottleneck)\b)(?=[^\n]*(?:\bBATCH_SIZE\b|\bbatch\s+size\b|\bbatch(?:es)?\s+of\s+200\b|\b200[- ](?:recipient|per|message)\w*))[^\n]*(?:\btoo\s+(?:small|low|large|high|big)\b|\barbitrar\w*|\bunjustified\b|\bwrong\b|\bincorrect\b|\bexceed\w*|\bshould\s+(?:be\s+)?(?:raised?|increased?|lowered?|reduced?|larger|smaller)\b|\b(?:raise|increase|lower|reduce)\s+(?:it|the|BATCH)\b|\bbottleneck\b|\bunsupported\b|\bno\s+basis\b|\bunverified\b)'
flags: mi
match: not_contains
target: last_message
---
