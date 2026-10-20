---
type: regex
pattern: '(?:^|\n)- Q\d+ \| open \| round \d+ \|[^|\n]*\b(?:second|another|other|variants?|providers?|generali[sz]e|specific)\b'
flags: i
target: { source: file, path: .work/address-validation/interview-checklist.md }
---
