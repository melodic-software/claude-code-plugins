---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:[^"\\]|\\.)*?(?:>{1,2}\|?\s*(?:\S*[/"''])?scripts/|\b(?:rm|mv|touch|tee|chmod|truncate)\s+(?:[^|;&\n"]*?\s)?(?:\S*[/"''])?scripts/|\bsed\s+-i\S*\s+(?:[^|;&]*?\s)?(?:\S*[/"''])?scripts/|\bcp\s+(?:-\S+\s+)*\S+\s+(?:\S*[/"''])?scripts/|\bcd\s+(?:\S*[/"''])?scripts/?\s*(?:&&|;)\s*(?:rm|mv|touch|tee|chmod|truncate|cp|sed\s+-i)\b)'
min: 0
max: 0
weight: 0.25
---
