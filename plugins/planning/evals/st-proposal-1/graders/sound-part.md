---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good|right)\b))(?![^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:wrong|unsuit|inadequate|insufficient|unsafe|replac|switch|migrat|use))(?![^\n]*(?:\breschedul\w*|\bappointment_id\b|\bwindow_name\b|\bkey(?:ed|s)?\b|\b(?:start|appointment|new)\s+time\b|\bmoved\s+appointment\w*|\bappointment\w*\s+(?:is\s+|are\s+)?moved\b|\bsend_sms\b|\bgateway\w*|\b(?:three|3|several|multiple)\s+requests\b|\battempts\b|\bcrash\w*|\bkill\w*|\bpower\s+loss\b|\batomic\w*|\bbetween\W+(?:the\s+)?(?:send\w*|provider)\b|\bsend\w*\b[^\n]*\b(?:insert\w*|commit\w*)\b|\b(?:insert\w*|commit\w*)\b[^\n]*\bsend\w*))[^\n]*(?:\bSQLite\b[^\n]*\b(?:wrong|unsuit\w*|inadequate|insufficient|unsafe|risky|won''t\s+scale|does(?:n''t|\s+not)\s+scale|too\s+(?:weak|small|limited|fragile)|(?:poor|bad)\s+(?:choice|fit))\b|\breplac\w*\s+(?:the\s+)?SQLite\b|\binstead\s+of\s+SQLite\b|\b(?:switch|migrat\w*|mov\w*)\s+(?:off|away\s+from)\s+SQLite\b|\bSQLite\b[^\n]*\b(?:(?:switch|migrat\w*|mov\w*)\s+to|use)\s+(?:a\s+)?(?:Postgres\w*|MySQL|server|managed)\b)'
flags: mi
match: not_contains
target: last_message
---
