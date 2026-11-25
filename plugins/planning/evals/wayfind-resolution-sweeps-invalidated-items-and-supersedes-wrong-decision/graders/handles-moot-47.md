---
type: regex
flags: i
pattern: '^(?=[\s\S]*?work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?done\s+(?:<?(?:item|issue)\s+)?\S*?\b47\b[^\n]*(?:not-planned|not planned|moot))[\s\S]*?work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?(?:done|edit)\s+(?:<?(?:item|issue)\s+)?\S*?\b47\b(?:(?!work-items:track)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,1200}?(?:\[Decide invoice numbering\]|\]\(<?[^)\s]*\b44\b|https?://[^\s)>]*/44\b|<[^>\n]*\b44\b[^>\n]*>)'
---
