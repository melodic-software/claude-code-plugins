---
type: regex
flags: i
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:add\b|edit\s+(?!\S*\b(?:200|39|44|47)\b)\S+[^\n]*--body)(?:[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,1200}?(?:\[Share one invoice table across tenants\]\(|\]\(<?[^)\s]*/39\b|https?://[^\s)>]*/39\b|<[^>\n]*\b39\b[^>\n]*>)'
---
