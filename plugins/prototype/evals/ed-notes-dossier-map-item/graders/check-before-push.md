---
type: regex
target: trace
match: not_contains
arm: both
pattern: '^(?:(?!"name":"Bash","input":\{"command":"(?:[^"\\\n]|\\.)*?check-secrets\.sh\s(?:[^|&;>"\\]|\\[^n]|\\\\\\n)*(?:\.html|prototype-notes\.md|prototype/|42-parcel-card-layout|notes-run|shots))[\s\S])*?"name":"Bash","input":\{"command":"(?:(?!check-secrets\.sh\s(?:[^|&;>"\\]|\\[^n]|\\\\\\n)*(?:\.html|prototype-notes\.md|prototype/|42-parcel-card-layout|notes-run|shots))(?:[^"\\\n]|\\.))*?(?:\b|\\[nt])git(?:\s|\\\\\\n)+(?:-[cC](?:\s|\\\\\\n)+\S+(?:\s|\\\\\\n)+)*push\b'
---
