---
type: regex
pattern: '^\{"type":"assistant".*"type":"text","text":"(?:[^"\\]|\\.)*?(?:RET-41|off[- ]by[- ]one|(?:includes?|including) the first|one more call)'
flags: mi
target: trace
---
