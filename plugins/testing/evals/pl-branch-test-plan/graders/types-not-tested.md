---
type: regex
pattern: '\bnot test(?:ing|ed)?\b[\s\S]{0,400}\btypes\.py\b|\btypes\.py\b[^\n]{0,160}\b(?:no behav(?:ior|iour)|no logic|nothing to test|not test(?:ing|ed)?|pure (?:contract|types?)|no tests? (?:needed|required))\b'
flags: 'i'
target: 'last_message'
---
