---
type: regex
flags: i
pattern: '^(?![\s\S]*\b(?:Resolved|Resolution|Decision|Decided):)(?=[\s\S]*?work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?done\s+(?:<?(?:item|issue)\s+)?\S*?\b51\b[^\n]*(?:not-planned|not planned|out of scope))(?:[\s\S]*?Out-of-scope[^\n]*(?:\[Should we also rewrite the mobile app\?\]\(|\]\(<?[^)\s]*/51\b|https?://[^\s)>]*/51\b)|[\s\S]*?Out-of-scope[^\n]*\n(?:[ \t]*\n)?(?:[ \t>]*[-*][ \t][^\n]*\n){0,20}?[ \t>]*[-*][ \t]+`?(?:\[Should we also rewrite the mobile app\?\]\(|[^\n]*\]\(<?[^)\s]*/51\b))'
---
