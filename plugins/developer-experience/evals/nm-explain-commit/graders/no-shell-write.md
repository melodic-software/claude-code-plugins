---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:[^"\\]|\\.)*?(?:(?<=[\s;(&0-9])>{1,2}\|?(?!\s*(?:/dev/null|&))\s*[^\s&|;)]|\b(?:cp|mv|rm|touch|mkdir|tee)\s|\bsed\s+-i|\bdotnet\s+(?:new\s+(?!list\b|search\b|--help\b|-h\b)|add\s|sln\s+(?:add|remove)\b)|\bgit\s+(?:apply|mv|rm|checkout\s+-b|switch\s+-c)\b|\bgit\s+(?:clean|checkout|restore|reset|stash(?!\s+(?:list|show)))\b|\bdotnet\s+format\b|\bperl\s+-\S*i|\.write(?:_text|_bytes|lines)?\(|\bshutil\.(?:copy\w*|move)\()'
min: 0
max: 0
weight: 0.25
---
