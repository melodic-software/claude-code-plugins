---
type: regex
pattern: '\b(?:is|will|would|should|does|must) (?:this|it) (?:(?:just|ever|eventually|go|going|be|used|run|deployed|to|into|in|become|need|needs) ){0,3}(?:production|customer[- ]facing|an internal tool|long[- ]lived|a (?:prototype|throwaway|spike|proof[- ]of[- ]concept|MVP))\b[^\n?]{0,160}\?|\b(?:prototype|throwaway|spike|proof[- ]of[- ]concept|MVP|internal tool|production)\b[^\n?]{0,80}\b(?:or|vs\.?|versus)\b[^\n?]{0,80}\b(?:prototype|throwaway|spike|proof[- ]of[- ]concept|MVP|internal tool|production)\b[^\n?]{0,80}\?|\bquality (?:bar|level|target)\b[^\n?]{0,160}\?|\bhow (?:polished|robust|production[- ]ready)\b[^\n?]{0,160}\?|\bconfirm\w*\b[^\n?]{0,60}\b(?:prototype|throwaway|production|quality bar)\b[^\n?]{0,40}\?|\b(?:this|it) (?:is|stays|remains) (?:still |just |only )?(?:a |an )?(?:(?:quick|throwaway|weekend) )*(?:prototype|throwaway|demo|spike)\b[,.]? ?(?:right|correct)\?'
flags: i
match: not_contains
arm: both
---
