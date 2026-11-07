---
type: tool_used
tool: Bash
input_match: '"command":\s*"(?:[^"\\]|\\.)*?(?:(?<=\\n)|(?<=\\t)|(?<![\w\\]))(?:sed|perl)\s+(?:(?:[^"\\|;&]|\\[^n])*?\s)?-[a-zA-Z]*i(?:[^"\\|;&]|\\[^n])*?(?<![\w\\])(?:MEMORY_LIMIT_MB\s*=\s*(?!512\b)\d|WORKERS\s*=\s*(?!6\b)\d)'
min: 0
max: 0
---
