---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*(?:\bflush_outbox\b|\b(?:is|are)\s+(?:the\s+)?(?:fine|correct|right|sound)\b|\btwice\b|\bagain\b|\bduplicate\w*|\bmore\s+than\s+once\b))(?=[^\n]*(?:\b(?:notice_)?outbox\b|\bqueue_notice\b|\bnotices?\b))[^\n]*(?:\bnever\s+(?:\w+\s+){0,2}(?:sen[dt]\w*|deliver\w*|flush\w*|email\w*)|\b(?:not|never|cannot|(?:is|are|was|were|do|does|did|has|have|had|ca|could|wo|would|should|must)n.?t)\s+(?:\w+\s+){0,2}(?:sen[dt]\w*|deliver\w*|flush\w*|drain\w*)\b|\bnothing\s+(?:\w+\s+){0,2}(?:sends?|delivers?|flush\w*|drains?)\b|\bno\s+(?:\w+\s+){0,2}(?:sender|delivery|worker)\b|\b(?:should|must|needs?\s+to)\s+(?:\w+\s+){0,2}(?:send|call|open|use)\s+(?:\w+\s+){0,2}(?:smtp|email|directly)\b)'
flags: mi
match: not_contains
target: last_message
---
