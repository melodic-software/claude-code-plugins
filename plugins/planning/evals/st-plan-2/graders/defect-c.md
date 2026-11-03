---
type: regex
pattern: '^(?:(?=[^\n]*\b(?:but|however|only\s+if|unless|although|though)\b)|(?![^\n]*(?:\bNo plan gaps found\b|\b(?:is|are|looks?|seems?)\s+(?:perfectly\s+|entirely\s+|fully\s+|also\s+)?(?:fine|ok|okay|good|sound|correct|right|accurate|safe)\b|\bno\s+(?:\w+\s+)?(?:issue|problem|concern|finding|gap|defect|risk)s?\b|\bnot\s+a\s+(?:\w+\s+)?(?:issue|problem|concern|defect|gap|risk)\b|\bnothing\s+to\s+(?:flag|fix|report)\b)))(?![^\n]*\bcapacity(?:_kg)?\s+(?:is|are|counts?)\s+(?:in\s+)?units,?\s+not\b(?![^\n]*\b(?:but|however|yet|although|though)\b[^\n]*(?:\bcapacity(?:_kg)?\b|\bCapacityKg\b|\bwarehouse\.yaml\b)))(?=[^\n]*(?:\bcapacity(?:_kg)?\b|\bCapacityKg\b|\bwarehouse\.yaml\b))[^\n]*(?:\b(?:in|is|are|measured\s+in|counts?|expressed\s+in|as)\s+(?:\w+\s+){0,2}(?:kg|kilo\w*|weights?|mass)\b|\bkilo\w*|\bweigh\w*|\bmass\b|\bunits?\b[^\n]*(?:capacity_kg|CapacityKg|\bkg\b|\bunit_kg\b)|(?:capacity_kg|CapacityKg|\bkg\b)[^\n]*\b(?:units?|on-?hand|OnHand|count\w*|convert\w*|conversion)\b|\bdifferent\s+units?\b|\bunit\s+mismatch\b)'
flags: mi
target: last_message
---
