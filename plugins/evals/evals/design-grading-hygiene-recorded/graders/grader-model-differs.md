---
type: regex
pattern: "(?:(?:grader|judge)[^\\n]{0,120}(?:different|other than|not the same|not sonnet|distinct|separate)[^\\n]{0,60}(?:model|generator|sonnet|drafter)|(?:different|other|distinct|separate)[^\\n]{0,40}(?:model|family)[^\\n]{0,80}(?:grader|judge|grad))"
flags: i
target: last_message
---
