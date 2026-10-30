#!/usr/bin/env bash
# A music service whose root AGENTS.md binds the convention home to docs/conventions, where
# authoring-formats/README.md selects the EARS acceptance-criteria format. The graded outcome is
# that the acceptance criteria the PRD records carry the EARS pattern tags.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions/authoring-formats src

cat >AGENTS.md <<'MD'
# tuneshelf

<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/conventions`; read the topic doc there before changing a governed surface.
<!-- END GENERATED: convention-home -->
MD

cat >docs/conventions/authoring-formats/README.md <<'MD'
# Authoring formats

```yaml
acceptance_criteria_format: ears
```
MD

cat >src/history_export.py <<'PY'
import csv
from pathlib import Path


def build_export(member_id: str, plays, out_dir: Path) -> Path:
    path = out_dir / f"{member_id}-history.csv"
    with path.open("w", newline="") as fh:
        csv.writer(fh).writerows(plays)
    return path
PY

git add .
git commit -q -m "feat: listening-history CSV builder"
