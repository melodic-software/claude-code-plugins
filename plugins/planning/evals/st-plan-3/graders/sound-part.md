---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*(?:\balready\b|\b(?:no|(?:not|never|cannot|(?:is|are|was|were|do|does|did|has|have|had|ca|could|wo|would|should|must)n.?t)|without)\s+(?:\w+\s+){0,2}(?:needed|required|need\w*|requires?)\b))(?=[^\n]*(?:\bnext_renewal_at\b|\bsubscriptions_active_next_renewal_idx\b|\bfindDue\b))[^\n]*(?:\b(?:no|missing)\s+(?:\w+\s+){0,2}(?:index|column)\b|\b(?:index|column)\s+(?:\w+\s+){0,2}(?:is|are)\s+missing\b|\b(?:index|column)\s+(?:does\s+not|doesn.?t)\s+exist\b|\bscans?\s+(?:the\s+)?(?:whole\s+|full\s+|entire\s+)?table\b|\bfull\s+(?:table\s+)?scan\b|\bmigration\b[^\n]*\bnext_renewal_at\b|\b(?:findDue|next_renewal_at)\b[^\n]*\b(?:needs?|requires?|should\s+add|must\s+add)\s+(?:an?\s+)?(?:index|migration)\b)'
flags: mi
match: not_contains
target: last_message
---
