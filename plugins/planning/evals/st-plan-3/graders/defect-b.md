---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*\b(?:does\s+not|doesn.?t|never)\s+(?:return|resolve)\b(?![^\n]*\b(?:but|however|yet|although|though)\b[^\n]*(?:\bcharge\b|\bPaymentClient\b|\bclient\.ts\b|\bPaymentDeclined\b|\bdeclin\w*)))(?=[^\n]*(?:\bcharge\b|\bPaymentClient\b|\bclient\.ts\b|\bPaymentDeclined\b|\bdeclin\w*))[^\n]*(?:\b(?:returns|resolves|returned|resolved)\b[^\n]*\bdeclin\w*|\bdeclin\w*[^\n]*\b(?:returns|resolves|returned|resolved)\b|\b(?:does\s+not|doesn.?t|never|not|won.?t|will\s+not)\s+(?:\w+\s+)?throw\w*\b|\bwithout\s+throwing\b|\bno\s+(?:\w+\s+)?PaymentDeclined\b|\bPaymentDeclined\b[^\n]*\b(?:does\s+not\s+exist|doesn.?t\s+exist|not\s+(?:\w+\s+)?(?:exist|defined|declared)|nonexistent|non-existent|undefined|missing|nowhere)\b)'
flags: mi
target: last_message
---
