---
type: regex
target: { source: file, path: docs/conventions/developer-experience.md }
pattern: '`(?:[\w./-]*/)?(?!(?:AGENTS\.md|README\.md|CLAUDE\.md|developer-experience\.md|Tarnquill\.sln|build\.sh|build\.ps1|clean-outbox\.sh|Program\.cs|Tarnquill\.Cli\.csproj|CommitCommand\.cs|EnvCheckCommand\.cs|ItemCommentCommand\.cs|ProcessRunner\.cs|Paging\.cs|Tarnquill\.Core\.csproj|Tarnquill\.Core\.Checks\.csproj)`)[\w.-]+\.(?:sh|ps1|py|cs|csproj|sln|toml|md|jsonl)`'
match: not_contains
arm: with-only
---
