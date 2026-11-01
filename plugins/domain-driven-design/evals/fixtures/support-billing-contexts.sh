#!/usr/bin/env bash
# Writes a Fabrikam repository with two established bounded contexts, Support and Billing: a context
# map at docs/language/context-map.md and one table glossary per context. Billing already defines
# Ticket as a metered charge record; Support has no Ticket entry.
set -euo pipefail
mkdir -p docs/language src/support src/billing
cat >docs/language/context-map.md <<'MD'
# Domain language map

| Context | Glossary | Relationship |
|---|---|---|
| Support | `support-terms.md` | Support requests billing evidence through the published case reference. |
| Billing | `billing-terms.md` | Billing publishes charge references to Support. |
MD
cat >docs/language/support-terms.md <<'MD'
# Support language

| Term | Definition | Avoid |
|---|---|---|
| Case | The internal investigation opened in response to one or more customer requests. | incident |
MD
cat >docs/language/billing-terms.md <<'MD'
# Billing language

| Term | Definition | Avoid |
|---|---|---|
| Ticket | A metered charge record received from a usage source. | support request |
MD
