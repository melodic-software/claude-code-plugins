---
type: regex
flags: i
pattern: 'work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b(?:[^\n]|\\\n)*?Formly(?=(?:(?!work-items:track|Statusly)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,2000}?(?:\bfields?\b|\bdate of birth\b))(?=(?:(?!work-items:track|Statusly)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,2000}?\b(?:agreements?|DPA|BAA|contract|data[- ]processing)\b)|(?:^|\n)(?=(?:(?!work-items:track|Statusly)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,2000}?(?:\bfields?\b|\bdate of birth\b))(?=(?:(?!work-items:track|Statusly)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,2000}?\b(?:agreements?|DPA|BAA|contract|data[- ]processing)\b)(?:(?!work-items:track|Statusly)[^\n]|\n(?![ \t]*(?:\d+[.)][ \t]|#{1,6}[ \t]|\n))){0,2000}?work-items:track[\s`*"]*(?:[Aa]rg(?:ument)?s[\s:=*`"]*)?add\b(?:[^\n]|\\\n)*?Formly'
---
