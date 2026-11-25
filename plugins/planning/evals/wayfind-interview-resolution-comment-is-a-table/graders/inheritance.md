---
type: regex
pattern: '^(?=[\s\S]*\brate[- ]?limit)[\s\S]*?(?:\binherit\w*\b(?:(?!\b(?:none|nothing|defer\w*|glossary|out of scope|out-of-scope)\b)[\s\S]){0,250}?\bper[- ]client\b|\bper[- ]client\b[^\n]{0,120}\binherit)'
flags: i
---
