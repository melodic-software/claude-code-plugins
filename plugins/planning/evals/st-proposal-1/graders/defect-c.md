---
type: regex
pattern: '^(?![^\n]*(?:\bno\s+(?:\w+\s+)?(?:issue|problem|concern|risk|finding|gap|defect)s?\b|\bnot\s+(?:a|an)\s+(?:\w+\s+)?(?:issue|problem|concern|risk|gap|defect)\b|\b(?:is|are|looks?|seems?)\s+(?:(?!not\b)\w+\s+)?(?:fine|ok|okay|correct|sound|safe|good)\b|\bno\s+need\s+to\b|\bdon''t\s+see\s+(?:a|any)\b))(?!(?![^\n]*\b(?:but|however|actually|yet|though|although)\b)[^\n]*(?:\bnot\b|n''t\b|\bnever\b|\bno\b|\bwithout\b)\s+(?:\w+\s+){0,2}(?:\bduplicat|double|twice|re-?send|resend|again))(?=[^\n]*(?:\bledger\b|\brows?\b|\binserts?\b|\bsent_reminders\b|\bcommits?\b|\brecord\b))(?=[^\n]*(?:\bcrash\w*|\bkill\w*|\bstop(?:s|ped|ping)?\b|\bdie[sd]?\b|\bdying\b|\binterrupt\w*|\bpower\b|\breboot\w*|\bbetween\b|\b(?:not|non-?)\s*atomic\b|\bbefore\s+the\s+(?:insert|row|commit)\b|\bgap\b))[^\n]*(?:\bduplicat\w*|\btwice\b|\bagain\b|\bsecond\s+(?:sms|text|message|reminder)\b|\bre-?send\w*|\bre-?sent\b|\bdouble\w*|\banother\s+(?:sms|text|message|reminder)\b)'
flags: mi
target: last_message
---
