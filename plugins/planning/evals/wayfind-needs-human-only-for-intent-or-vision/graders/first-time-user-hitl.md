---
type: regex
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b(?=(?:[^\n]|\\\n)*?\bfirst[- ]time\b)(?=(?:[^\n]|\\\n)*?(?<!\bno )(?<!\bwithout )(?<!\bnot )(?<!\bno `)(?<!\bno '')(?<!\bwithout the )needs-human\b(?![ \t]*(?::[ \t]*(?:no|false|none)\b|(?:is )?not (?:set|needed|applied)\b|(?:omitted|dropped|removed)\b)))'
flags: i
---
