---
type: regex
pattern: "(?:re-?run|each run|per run|rerunning)[^\\n]{0,120}(?:cost|free|metered|billed|paid|\\$)|(?:cost|free|metered|billed)[^\\n]{0,120}(?:re-?run|per run|each run)"
flags: i
target: last_message
---
