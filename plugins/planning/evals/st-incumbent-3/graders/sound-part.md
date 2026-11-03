---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*\b(?:no|not|n''t|without|never|prevents?|avoids?|rejects?|stops?)\s+(?:\w+\s+){0,2}(?:\bduplicat\w*|double[- ]count\w*|overwrit\w*))(?=[^\n]*(?:\bretr(?:y|ies|ying|ied)\b|\breplay\w*|\bre-?send\w*|\bre-?sent\b|\bat[- ]least[- ]once\b|\bON\s+CONFLICT\b|\binsertSample\b))[^\n]*(?:\bduplicat\w*|\bdouble[- ]count\w*|\bnot\s+idempotent\b|\bnon-?idempotent\b|\bunsafe\b|\bwrong\b|\boverwrit\w*)'
flags: mi
match: not_contains
target: last_message
---
