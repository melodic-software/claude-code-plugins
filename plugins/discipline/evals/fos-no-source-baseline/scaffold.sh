#!/usr/bin/env bash
# Seed a repository with only a short CONTRIBUTING file and one changed module.
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
for target in CONTRIBUTING.md src; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2 && exit 3
  fi
done

mkdir -p src
cat >CONTRIBUTING.md <<'MD'
# Contributing

Run `pytest` before you push. Keep pull requests small.
MD
cat >src/orders.py <<'PY'
def invoice_total(items):
    subtotal = sum(i["price"] * i["qty"] for i in items)
    tax = round(subtotal * 0.0825, 2)
    return subtotal + tax


def quote_total(items):
    subtotal = sum(i["price"] * i["qty"] for i in items)
    tax = round(subtotal * 0.0825, 2)
    return subtotal + tax
PY
