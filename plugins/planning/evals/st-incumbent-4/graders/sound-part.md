---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*(?:\bnot|\bnever|n''t|\bnone|\bnothing|\bno)\s+(?:\w+\s+){0,4}(?:exceed\w*|overflow\w*|\btruncat\w*|too\s+\w+))(?=[^\n]*(?:\b4\s*KB\b|\bsize\s+limit\b|\bvalue\s+(?:limit|size)\b))(?:[^\n]*(?:\btoo\s+(?:small|low|large|long|big)\b|\bexceed\w*|\boverflow\w*|\btruncat\w*|\b(?:won''t|doesn''t|does\s+not|cannot|can''t)\s+fit\b|\bnot\s+enough\b)|[^\n]*(?:\b4\s*KB\b|\bsize\s+limit\b|\bvalue\s+(?:limit|size)\b)(?:(?!\b(?:but|however|yet)\b)[^\n.;:!?|,])*\b(?:unverified|wrong)\b|[^\n]*\b(?:unverified|wrong)\b(?:(?!\b(?:but|however|yet)\b)[^\n.;:!?|,])*(?:\b4\s*KB\b|\bsize\s+limit\b|\bvalue\s+(?:limit|size)\b))'
flags: mi
match: not_contains
target: last_message
---
