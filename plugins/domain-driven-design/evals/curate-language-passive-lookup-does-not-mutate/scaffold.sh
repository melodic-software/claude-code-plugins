#!/usr/bin/env bash
# A claims table glossary at docs/language/custom-terms.md, the file the prompt names.
set -euo pipefail
mkdir -p docs/language
cat >docs/language/custom-terms.md <<'MD'
# Claims language

| Preferred term | Meaning | Rejected names |
|---|---|---|
| Policyholder | The party that owns the insurance contract. | account owner |
MD
