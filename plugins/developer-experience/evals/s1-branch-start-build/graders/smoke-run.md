---
type: tool_used
tool: Bash
input_match: '(?:"command":"|&&|\|\||[;|(]|\\n)\s*(?:[^\s"\\;&|]*/)?tq\s+branch\s+start\b|\bdotnet\s+(?:exec\s+)?[^\s"\\;&|]*\btq\.dll\s+branch\s+start\b|\bdotnet\s+run\b(?:[^"\\;&|]|\\.)*?\s(?:--\s+)?branch\s+start\b|\bmake\s+tq\s+ARGS=(?:\\"|'')?branch\s+start\b'
---
