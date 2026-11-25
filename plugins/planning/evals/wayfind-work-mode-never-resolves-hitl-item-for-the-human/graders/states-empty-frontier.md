---
type: regex
flags: i
pattern: '^(?![\s\S]*(?:work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:start|done)\b|\bResolved:))[\s\S]*?(?:\b(?:all|every)\b[^\n.]{0,40}\b(?:decisions?|items?)\b[^\n.]{0,40}\bneeds?\s+(?:a\s+)?human|\bfrontier\b[^\n.]{0,40}\bempty\b|\bempty\b[^\n.]{0,15}\bfrontier\b|\bno (?:workable|agent-capable|claimable) items?\b|\bnothing (?:is )?(?:workable|claimable)\b)'
---
