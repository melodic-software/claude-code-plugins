---
type: regex
flags: i
pattern: '(?<!\bnot )(?<!n''t )(?<!\bnever )\b(?:creat\w*|git (?:switch|checkout) -[cb]|git branch|git push (?:-u|--set-upstream))\b[^\n]{0,200}?dossier/[\w./-]*?\b300\b|dossier/[\w./-]*?\b300\b(?:(?!\b(?:not|never|no|none|without)\b|n''t\b)[^\n]){0,200}?\b(?:created|creating|new)\b'
---
