---
type: regex
pattern: '^(?![^\n]*\bNo plan gaps found)(?![^\n]*\b(?:is|are|was|were|looks?|seems?|remains?)\s+(?!not\b|never\b)(?:(?:perfectly|entirely|totally|already|also|still|actually)\s+)?(?:fine|ok|okay|good|correct|accurate|sound|acceptable|safe|justified|reasonable)\b(?![^\n]*\b(?:but|however|yet)\b))(?![^\n]*\b(?:no|not\s+an?|n''t\s+an?)\s+(?:\w+\s+){0,2}(?:issue|problem|concern|risk|defect|gap|finding|blocker)s?\b)(?![^\n]*\b(?:nothing\s+wrong|no\s+need\s+to|need\s+not|can\s+be\s+ignored|no\s+action\s+needed|no\s+changes?\s+needed)\b)(?![^\n]*\b(?<!n''t )(?<!not )(?<!never )(?<!cannot )(?<!can''t )(?:handles?|follows?|tracks?|covers?|accounts?\s+for|adjusts?\s+for|survives?)\s+(?:\w+\s+){0,2}(?:daylight|DST|clock\s+changes?))(?=[^\n]*(?:\btickwheel\b|\butc_offset\b|\boffsets?\b|\bclinics\.ya?ml\b|\bAC1\b))[^\n]*(?:\bdaylight\b|\bDST\b|\bclock\s+changes?\b|\bsummer\s+time\b|\bstandard\s+time\b|\b(?:an?|one|1)[- ]hour\s+(?:early|late|off)\b|\bseasonal\w*)'
flags: mi
target: last_message
---
