---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*\b(?:no|without(?:\s+an?)?|needs\s+no)\s+(?:Node\s+)?(?:upgrade|bump)\b)(?![^\n]*(?:\bnot|n''t)\s+(?:\w+\s+)?(?:incompatib\w*|unsupported|too\s+old|a\s+conflict|a\s+mismatch))(?=[^\n]*(?:\bNode(?:\.js)?\b))[^\n]*(?:\bupgrades?\b|\btoo\s+old\b|\bolder\s+than\b|\bincompatib\w*|\bunsupported\b|\bnot\s+(?:met|satisfied)\b|\bbump\b|\bconflicts?\b|\bmismatch\w*|\bwrong\b)'
flags: mi
match: not_contains
target: last_message
---
