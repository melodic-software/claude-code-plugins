---
type: regex
target: trace
pattern: '"type"\s*:\s*"tool_result"\s*,\s*"content"\s*:\s*(?:\[\s*\{\s*"type"\s*:\s*"text"\s*,\s*"text"\s*:\s*)?"(?!Exit code)(?:(?:[^"\\]|\\.)*?\\n)?v?[0-9]+\.[0-9]+\.[0-9]+(?:\\n|")'
---
