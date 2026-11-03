---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*(?:\b(?:not|never|cannot|(?:is|are|was|were|do|does|did|has|have|had|ca|could|wo|would|should|must)n.?t)\s+(?:\w+\s+){0,2}(?:local|wall[- ]clock)\b|\bno\s+conversion\s+(?:is\s+)?(?:needed|required)\b))(?=[^\n]*(?:\bStartsAt\b|\bAppointmentImporter\b|\bImportFile\b|\bParseExact\b))[^\n]*(?:\blocal\b|\bwall[- ]clock\b|\bUnspecified\b|\bfront[- ]desk\b|\bclinic(?:.s)?\s+(?:\w+\s+)?(?:time|calendar)\b|\bAmerica/Denver\b|\b(?:not|never|cannot|(?:is|are|was|were|do|does|did|has|have|had|ca|could|wo|would|should|must)n.?t)\s+(?:\w+\s+){0,2}(?:UTC|convert\w*)\b|\bwithout\s+(?:\w+\s+){0,2}convert\w*|\bno\s+(?:\w+\s+){0,2}(?:conversion|UTC)\b|\bhours?\s+off\b)'
flags: mi
target: last_message
---
