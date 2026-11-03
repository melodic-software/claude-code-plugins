---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:violat|break|fail|open|read|need|require|multiple|more\s+than))(?=[^\n]*(?:\bAC2\b|\bplot_station\b|\bone\s+station\b|\bsingle\s+station\b|\bstation[- ]day\b|\ba\s+station''s\b))(?=[^\n]*(?:\bhourly\b|\bsegments?\b|\bper\s+hour\b|\bHH\.ndjson\b))[^\n]*(?:\b24\b|\btwenty-four\b|\bmultiple\s+(?:files|segments)\b|\bseveral\s+(?:files|segments)\b|\bmany\s+(?:files|segments)\b|\bmore\s+than\s+one\s+(?:file|segment)\b|\bevery\s+segment\b|\beach\s+hour''s\b|\bAC2\b[^\n]*\b(?:fails?|violat\w*|breaks?|unmet)\b|\b(?:fails?|violat\w*|breaks?|(?:cannot|can''t|does\s+not|doesn''t|won''t)\s+(?:meet|satisfy))\s+AC2\b)'
flags: mi
target: last_message
---
