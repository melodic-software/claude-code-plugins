---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*(?:\bis\s+idempotent\b|\b(?:will\s+not|won.?t|cannot|can.?t|never)\s+(?:\w+\s+){0,2}(?:doubl\w*|\bduplicat\w*)\b|\bno\s+(?:risk\s+of\s+)?(?:double|duplicate)\s+(?:charge|charges|entr\w+|rows?|fines?)\b))(?=[^\n]*(?:\baccrue_fines\b|\baccrual\b|\bmember_ledger\b|\bledger\b|\brun-job\b|\bnightly\s+job\b|\bPhase\s*1\b))[^\n]*(?:\bdoubl\w*|\btwice\b|\bduplicat\w*|\bidempoten\w*|\bover-?charg\w*|\bcharg\w*\s+(?:\w+\s+){0,3}again\b|\bsecond\s+(?:\w+\s+)?(?:row|entry|fine|charge)\b|\b(?:extra|repeat\w*)\s+(?:\w+\s+)?(?:rows?|entry|entries|fines?|charges?)\b|\bno\s+(?:\w+\s+)?(?:unique|uniqueness|dedup\w*)\b)'
flags: mi
target: last_message
---
