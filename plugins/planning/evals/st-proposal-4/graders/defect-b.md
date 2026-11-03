---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|contradict\w*|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bno\b)\s+(?:\w+\s+){0,2}(?:local|wrong|\bmis-?))(?=[^\n]*(?:\bUTC\b|\bstations\.toml\b|\butc_offset\w*|\bclock\b|\bvalley-03\b|\blakeside-05\b|\bsummit-06\b))[^\n]*(?:\bnot\s+(?:all\s+)?(?:in\s+|on\s+)?UTC\b|\b(?:aren''t|isn''t)\s+(?:all\s+)?(?:in\s+|on\s+)?UTC\b|\bnon-UTC\b|\blocal[- ](?:time|clocks?)\b|\b(?:clock\s*=\s*)?[''"`]local[''"`]\s+(?:clocks?|stations?|time)\b|\bfalse\b|\bcontradict\w*|\bincorrect\b|\bwrong\s+(?:hour|segment|day|bucket|partition)\b|\bmis-?(?:partition|bucket|fil|assign|plac)\w*|\bstations?\s+(?:report|use|run|are|is)\s+(?:on\s+|in\s+)?local\b)'
flags: mi
target: last_message
---
