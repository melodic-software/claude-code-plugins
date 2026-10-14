---
type: regex
pattern: '\b(?:prototype|proof[- ]of[- ]concept|throwaway|spike|quick hack|MVP|hobby|one-off|experiment\w*|internal[- ](?:tool|use|only))\b(?:(?!\bQ\d)[^?\n.;]){0,300}?\b(?:production|internal[- ](?:tool|use|only)|customer[- ]facing|long[- ]lived|ship(?:ped|ping)? to (?:users|customers))\b(?:(?!\bQ\d)[^?\n.;])*\?|\b(?:production|internal[- ](?:tool|use|only)|customer[- ]facing|long[- ]lived|ship(?:ped|ping)? to (?:users|customers))\b(?:(?!\bQ\d)[^?\n.;]){0,300}?\b(?:prototype|proof[- ]of[- ]concept|throwaway|spike|quick hack|MVP|hobby|one-off|experiment\w*|internal[- ](?:tool|use|only))\b(?:(?!\bQ\d)[^?\n.;])*\?|\bquality (?:bar|level|target)\b(?:(?!\bQ\d)[^?\n.;])*\?|\bhow (?:polished|robust|production[- ]ready)\b(?:(?!\bQ\d)[^?\n.;])*\?'
flags: i
arm: both
---
