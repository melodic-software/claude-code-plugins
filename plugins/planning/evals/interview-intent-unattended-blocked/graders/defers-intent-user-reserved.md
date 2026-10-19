---
type: regex
pattern: '### Deferred questions(?:[^#]|#(?!#))*?\n- \**Q\d+\b[^\n]*\b(?:second|another|other|more|variants?|providers?|generali[sz]e|generic|repeat|vary)\b[^\n]*USER-RESERVED'
flags: i
target: { source: file, path: .work/address-validation/PLAN.md }
---
