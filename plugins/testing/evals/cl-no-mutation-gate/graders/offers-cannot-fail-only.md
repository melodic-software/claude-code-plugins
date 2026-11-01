---
type: regex
pattern: '^(?=[\s\S]*\bmutation[- ]testing\b)(?=[\s\S]*(?:\bcannot[- ]fail[- ]only\b|\b(?:(?:deletes?|deleted|deleting|removes?|removed|removing)\s+only|only\s+(?:deletes?|deleted|deleting|removes?|removed|removing))\s+(?:[\w-]+\s+){0,3}?tests?\s+(?:that|which)\s+(?:cannot|can not|can''t|can’t)\s+(?:ever\s+)?fail\b))'
flags: 'i'
target: 'last_message'
---
