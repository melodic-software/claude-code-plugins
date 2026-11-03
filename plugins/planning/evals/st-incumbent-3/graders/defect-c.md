---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*\b(?:won''t|will\s+not|cannot|can''t|not|never|no)\s+(?:\w+\s+)?(?:los[et]\w*|wip\w*|discard\w*|clear\w*|destroy\w*))(?=[^\n]*(?:\bhealth\w*|\bwatchDatabase\b|\blog\.Fatalf?\b|\bmain\.go\b|\bingest\.service\b|\bRestart=always\b|\bsystemd\b|\bmaxBadCheck\b))(?=[^\n]*(?:\bbuffer\w*|\bqueue\w*|\bin[- ]memory\b|\bring\b|\bprocess\s+memory\b))[^\n]*(?:\blos[et]\w*|\bwip\w*|\bdiscard\w*|\bempt(?:y|ies|ied)\b|\bclear\w*|\bgone\b|\bdestroy\w*|\bkill\w*|\bvanish\w*|\berase\w*|\b(?:not|doesn''t|does\s+not|won''t|will\s+not|cannot|can''t)\s+survive\b)'
flags: mi
target: last_message
---
