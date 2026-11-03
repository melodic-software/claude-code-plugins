---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good|right)\b))(?![^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:wrong|unsuit|inadequate|insufficient|unsafe|replac|switch|migrat|use))(?![^\n]*(?:\breschedul\w*|\bappointment_id\b|\bsend_sms\b|\bcrash\w*|\bbetween\b|\binsert\w*|\bAC1\b|\bAC2\b|\bretr\w*|\bkey(?:ed)?\b|\bstart\b|\bwindow\w*))[^\n]*(?:\bSQLite\b[^\n]*\b(?:wrong|unsuit\w*|inadequate|insufficient|unsafe|risky|won''t\s+scale|does(?:n''t|\s+not)\s+scale|too\s+(?:weak|small|limited|fragile)|(?:poor|bad)\s+(?:choice|fit))\b|\breplac\w*\s+(?:the\s+)?SQLite\b|\binstead\s+of\s+SQLite\b|\b(?:switch|migrat\w*|mov\w*)\s+(?:off|away\s+from)\s+SQLite\b|\bSQLite\b[^\n]*\b(?:(?:switch|migrat\w*|mov\w*)\s+to|use)\s+(?:a\s+)?(?:Postgres\w*|MySQL|server|managed)\b)'
flags: mi
match: not_contains
target: last_message
---
