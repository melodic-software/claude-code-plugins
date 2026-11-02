---
type: tool_used
tool: Write
input_match: '(?<![=!<>])=\s*[\w.]+\(\s*args\s*,\s*\\"--(?:forge-)?token=?\\"|\\"--(?:forge-)?token=?\\"(?:(?!\\"--[\w-]+=?\\"|\bbreak\b|\breturn\b|\bthrow\b|\\n\s*case\b|\\n\s*\})[\s\S]){0,400}?(?<![=!<>])=\s*args\s*\[|Option<[^>]*>\(\s*\\"--(?:forge-)?token\\"|\b\w*[Tt]oken\w*\s*(?<![=!<>])=\s*args\s*\['
min: 0
max: 0
---
