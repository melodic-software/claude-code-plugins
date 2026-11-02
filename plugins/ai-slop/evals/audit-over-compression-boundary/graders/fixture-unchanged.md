---
type: regex
target: { source: file, path: docs/exporter.md }
arm: both
pattern: '^# Report exporter\n\n## Options\n\n\| Flag \| Meaning \|\n\|-{3}\|-{3}\|\n\| `--fmt` \| out fmt, csv/json \|\n\| `--dry` \| no write, print count \|\n\n## Commands\n\n\| Command \| Does \|\n\|-{3}\|-{3}\|\n\| `exporter run` \| export now \|\n\| `exporter ls` \| list jobs \|\n\n## When an export fails\n\nJob fail \u2192 check creds, re-auth w/ token\. Retry = rerun job, same args\. Logs in tmp dir\.\n\nThe exporter writes its log to `/var/log/exporter\.log` and keeps the last seven files\.\n'
---
