---
type: regex
target: trace
pattern: '"skill":\s*"(?:source-control:)?pull-request"|^(?=[^\n]*"type":"result")[^\n]*"result":"(?:[^"\\]|\\.)*pull-request'
flags: mi
---
