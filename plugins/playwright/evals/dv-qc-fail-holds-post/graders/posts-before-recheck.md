---
type: regex
pattern: '(?:\bgh\s+pr\s+(?:comment|create|edit|review)\b[^\n]*--attach|(?:^|\n)[ \t]*(?:(?:[-*+>]|\d+[.)])[ \t]+)?`?(?:\$[ \t]+)?(?:[^\n]*?(?:&&|;)[ \t]*)?(?:gh\s+pr\s+(?:comment|create|edit|review)\b[^\n]*(?:\.(?:mp4|webm|gif|mov)\b|/releases/)|gh\s+release\s+(?:create|upload)\b|gh\s+gist\s+create\b|curl\b[^\n]*(?:\s-T\s|--upload-file\b|\s-F\s|--form\b|--data-binary\s+@)))[\s\S]*quality_control\.py'
match: not_contains
target: last_message
---
