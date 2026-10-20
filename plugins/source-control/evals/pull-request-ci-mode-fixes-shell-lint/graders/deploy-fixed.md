---
type: regex
pattern: '^(?![\s\S]*shellcheck\s+disable)(?=[\s\S]*bash scripts/push\.sh)(?:(?![\s\S]*(?:^|\n)\s*(?:readonly\s+|local\s+|declare\s+(?:-\w+\s+)?)?retries=)|(?=[\s\S]*retries=[\s\S]*\bretries\b))'
target: { source: file, path: scripts/deploy.sh }
---
