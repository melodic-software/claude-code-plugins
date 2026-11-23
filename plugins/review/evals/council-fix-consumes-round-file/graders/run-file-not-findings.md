---
type: regex
pattern: '(?<!not )(?<!n.t )(?<!never )(?<!not read )(?<!n.t read )(?<!never read )(?<!never reads )\bboth\b[^\n.]{0,40}\b(?:as findings|are read|get read|are admitted|are applied|are consumed)|(?<!not )(?<!n.t )(?<!never )\bneeds? (?:a )?(?:convert|conversion)'
flags: i
match: not_contains
---
