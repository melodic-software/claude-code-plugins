---
type: regex
pattern: '^(?:(?!"name":"(?:Edit|Write|MultiEdit|NotebookEdit)"|"command":"(?:[^"\\]|\\.)*?(?:(?:\bsed\s+-i|\bperl\s+-\w*i|(?<![\d&])>(?!&)|\b(?:cp|mv|tee)\s)(?:[^"\\]|\\.)*?(?<!\w)(?:retry\.py|README\.md)\b|\b(?:checkout|restore)\s+(?:\S+\s+)*?--(?:ours|theirs)\b))[\s\S])*?"command":"(?:[^"\\]|\\.)*?\bgit\s+(?:-C\s+\S+\s+)?(?:--no-pager\s+)?(?:log|show)\b'
target: trace
---
