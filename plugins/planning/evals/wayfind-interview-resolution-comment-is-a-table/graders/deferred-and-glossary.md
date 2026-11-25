---
type: regex
pattern: '^(?=[\s\S]*?(?:(?<!\bnothing )(?<!\bnothing is )(?<!\bnothing was )(?<!\bnone )(?<!\bnone is )(?<!\bnot )(?<!\bnot been )(?<!\bnever )(?<!\bnever been )(?<!n''t )(?<!n''t been )\bdefer\w*\b(?:(?!\b(?:none|nothing|out of scope|out-of-scope|glossary|inherit\w*)\b)[\s\S]){0,200}?\b(?:mutual[ -]TLS|mTLS)\b(?![^\n.;]*\bout[ -]of[ -]scope\b)|\b(?:mutual[ -]TLS|mTLS)\b(?:(?!\bnot\b|n''t\b)[^\n]){0,80}\bdefer))(?=[\s\S]*?(?:\bglossary\b(?:(?!\b(?:none|nothing|no changes?|unchanged|out of scope|out-of-scope|defer\w*|inherit\w*)\b)[\s\S]){0,200}?\bpartner app\b|\bpartner app\b(?:(?!\bnot\b|n''t\b)[^\n]){0,80}\bglossary\b))'
flags: i
---
