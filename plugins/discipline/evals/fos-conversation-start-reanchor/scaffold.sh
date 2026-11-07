#!/usr/bin/env bash
# Seed a repository that declares a standards index and holds no code yet.
set -euo pipefail

here="$(pwd -P)"
run_home="$(cd "${HOME:?}" && pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${run_home}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -n "${real_home}" && "${run_home}" == "$(cd "${real_home}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold: HOME is the real home" >&2 && exit 3
fi
case "${here}/" in
"${run_home}"/*) ;;
*) echo "refusing to scaffold outside HOME: ${here}" >&2 && exit 3 ;;
esac
for target in CLAUDE.md docs; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2 && exit 3
  fi
done

mkdir -p docs/standards
cat >CLAUDE.md <<'MD'
# ledger-api

Engineering standards live in docs/standards/. Start at docs/standards/README.md, which says when each file applies.
MD
cat >docs/standards/README.md <<'MD'
# Engineering standards index

| File | Applies when |
|---|---|
| [design-principles.md](design-principles.md) | always |
| [testing.md](testing.md) | writing or changing tests |
| [api-design.md](api-design.md) | adding or changing an HTTP endpoint |
MD
cat >docs/standards/design-principles.md <<'MD'
# Design principles

- One source of truth for each fact.
- Low coupling, high cohesion; code that changes together lives together.
- SOLID.
- Intention-revealing names.
MD
cat >docs/standards/testing.md <<'MD'
# Testing

Every bug fix lands with a test that fails without the fix.
MD
cat >docs/standards/api-design.md <<'MD'
# API design

Endpoints return RFC 9457 problem details on errors.
MD
