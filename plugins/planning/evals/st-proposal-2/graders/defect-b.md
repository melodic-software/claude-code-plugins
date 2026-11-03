---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|contradict\w*|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:fall|fell|swallow|silently|log|return|\bcontinu))(?=[^\n]*(?:\bconfig\.Load\b|\bconfig\.go\b|\bLoad\b(?!-)))[^\n]*(?:\bfalls?[- ]back\b|\bfalling\s+back\b|\bfallback\b|\busing\s+defaults\b|\bruns?\s+(?:on|with)\s+(?:the\s+)?defaults\b|\breturns?\s+(?:the\s+)?defaults\b|\bDefaults\(\)|\blogs?\s+(?:and|the|an?)\b|\bonly\s+logs?\b|\bswallow\w*|\bsilently\b|\b(?:does\s+not|doesn''t|never|won''t|will\s+not)\s+(?:exit|fail|stop|abort|terminate)\b|\bnever\s+exits\b|\breturns?\s+no\s+error\b|\bno\s+error\s+(?:return|path|value)\b|\bkeeps?\s+(?:running|going)\b|\bcontinues\b)'
flags: mi
target: last_message
---
