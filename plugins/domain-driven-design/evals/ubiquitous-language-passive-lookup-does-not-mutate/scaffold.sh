#!/usr/bin/env bash
set -euo pipefail
mkdir -p docs/language
cat >docs/language/custom-terms.md <<'MD'
# Claims language

| Preferred term | Meaning | Rejected names |
|---|---|---|
| Policyholder | The party that owns the insurance contract. | account owner |
MD
