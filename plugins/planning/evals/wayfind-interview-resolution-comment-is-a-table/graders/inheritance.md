---
type: regex
pattern: '^(?=[\s\S]*\brate[- ]?limit)[\s\S]*?(?:(?<!\bnot )(?<!n''t )(?<!\bnever )\binherit\w*\b(?:(?!\b(?:none|nothing|defer\w*|glossary|out of scope|out-of-scope)\b)[\s\S]){0,250}?\bper[- ]client\b|\bper[- ]client\b(?:(?!\b(?:not|never)\b|n''t\b)[^\n]){0,120}\binherit)'
flags: i
---
