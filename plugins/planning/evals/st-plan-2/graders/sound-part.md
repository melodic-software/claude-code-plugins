---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*(?:\b(?:no|(?:not|never|cannot|(?:is|are|was|were|do|does|did|has|have|had|ca|could|wo|would|should|must)n.?t)|without|free\s+of|prevents?|avoids?|rules?\s+out)\s+(?:\w+\s+){0,3}(?:rac\w*|lost\s+updates?|corrupt\w*|lock|locking)\b|\bserializ\w*|\bholds?\s+`?s\.mu))(?=[^\n]*(?:\bs\.mu\b|\bmutex\b|\block\w*\b|\brac(?:e|es|y|ing)\b|\bconcurren\w*))[^\n]*(?:\brac(?:e|es|y|ing)\b|\blost\s+updates?\b|\block\s+is\s+(?:\w+\s+)?(?:needed|required|missing)\b|\b(?:need|needs|requires?|must\s+(?:add|take|hold)|should\s+(?:add|take|hold)|add)\s+(?:\w+\s+){0,2}lock\b|\bconcurren\w*[^\n]*\b(?:corrupt\w*|unsafe|clobber\w*|interleav\w*|overwrite\w*))'
flags: mi
match: not_contains
target: last_message
---
