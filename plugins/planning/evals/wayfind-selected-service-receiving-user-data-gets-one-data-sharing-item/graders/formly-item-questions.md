---
type: regex
flags: i
pattern: '(?:^|\n)(?=(?:[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]))){0,2000}?work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b(?:[^\n]|\\\n)*?Formly)(?=(?:[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]))){0,2000}?(?:\bfields?\b|\bdate of birth\b))(?=(?:[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]))){0,2000}?\b(?:agreements?|DPA|BAA|contract|data[- ]processing)\b)'
---
