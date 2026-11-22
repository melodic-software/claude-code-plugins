#!/usr/bin/env bash
# Seeds the ledger-cli repository with only the old files, .claude/improvement.md (team) and
# .claude/improvement.local.md (personal), and no docs/conventions/improvement*.yaml, so the
# dual-read window reads both and the retirement records improvement-r001 and -r002 fire.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-ledger-cli.sh"

mkdir -p .claude
cat > .claude/improvement.md <<'CONFIG'
# improvement config

```yaml
churn_window: "30 days ago"
```
CONFIG
cat > .claude/improvement.local.md <<'CONFIG'
# improvement personal config

```yaml
find_size_band: small
```
CONFIG
