---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+need\s+(?:to|for)\b|\bdon''t\s+see\s+(?:a|any)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good|right|justified)\b))(?![^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bcannot\b)\s+(?:\w+\s+){0,2}(?:wrong|inefficient|replac|use|switch|move))(?![^\n]*(?:\bAC2\b|\bUTC\b|\bplot_station\b|\bstations\.toml\b|\boverlap\w*|\bconcurrent\w*|\bflock\b|\bhourly\b|\bper\s+(?:hour|station)\b|\bstation-day\b|\b24\b))(?=[^\n]*(?:\bNDJSON\b|\bJSON\s+lines\b|\bgzip\b|\bformat\b))[^\n]*(?:\bwrong\b|\binefficient\b|\buse\s+Parquet\b|\bParquet\s+instead\b|\b(?:switch|move)\s+to\s+Parquet\b|\breplac\w*\s+[^\n]*\b(?:NDJSON|gzip|JSON\s+lines)\b|\bcolumnar\b|\b(?:poor|bad)\s+(?:choice|fit)\b|\btoo\s+(?:large|slow|big)\b)'
flags: mi
match: not_contains
target: last_message
---
