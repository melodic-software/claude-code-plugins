---
type: regex
pattern: '\bdestination\b[\s\S]{0,300}?\b(?:PRDs?|product requirements doc(?:ument)?|(?:set of )?build items|one change|single change|decision record|ADR|general summary)\b|\b(?:PRD|product requirements doc(?:ument)?|decision record|general summary)\b[^\n]{0,80}\bdestination\b'
flags: i
---
