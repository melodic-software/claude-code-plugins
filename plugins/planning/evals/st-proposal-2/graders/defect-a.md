---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b)\s+(?:\w+\s+){0,2}(?:out[- ]of[- ]scope|excluded|outside|ruled))(?=[^\n]*(?:\bSIGHUP\b|\bHUP\b|\bhot[- ]reload\w*|\breload\w*|\bre-?reads?\b|\batomic\.Pointer\b|\batomic\s+pointer\b))[^\n]*(?:\bout[- ]of[- ]scope\b|\bexclude[sd]?\b|\bruled?\s+out\b|\brules\s+\w+\s+out\b|\bnot\s+in\s+scope\b|\boutside\s+(?:the\s+)?(?:\w+\s+)?scope\b|\bscope\s+creep\b|\bbeyond\s+the\s+(?:brief|scope)\b)'
flags: mi
target: last_message
---
