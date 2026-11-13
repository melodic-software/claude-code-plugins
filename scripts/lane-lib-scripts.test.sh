#!/usr/bin/env bash
# Behavior test for the two lane lib scripts the workflows run from .base:
# revoke-lane-token.sh prints "the lane token is revoked" on a 204, else the
# not-revoked warning, and exits 0 either way; install-pinned-pyyaml.sh installs
# exactly the `pyyaml==` block of the requirements-ci.txt two directories above
# it, and on a failed install prints its argument as a warning and exits 1.
# Stub curl and python3 stand in for the network.
# test-scope: .github/scripts/lib/revoke-lane-token.sh .github/scripts/lib/install-pinned-pyyaml.sh .github/requirements-ci.txt
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub204" "$T/stub401" "$T/pyok" "$T/pyfail" "$T/tree/.github/scripts/lib" "$T/rt"
printf '#!/bin/sh\ncat >/dev/null\nprintf 204\n' >"$T/stub204/curl"
printf '#!/bin/sh\ncat >/dev/null\nprintf 401\n' >"$T/stub401/curl"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >"%s/pip-args"\n' "$T" >"$T/pyok/python3"
printf '#!/bin/sh\nexit 1\n' >"$T/pyfail/python3"
chmod +x "$T/stub204/curl" "$T/stub401/curl" "$T/pyok/python3" "$T/pyfail/python3"

# The install script resolves requirements-ci.txt from its own directory, so it
# runs from a copied tree laid out as .base is.
cp "$ROOT/.github/scripts/lib/install-pinned-pyyaml.sh" "$T/tree/.github/scripts/lib/"
cp "$ROOT/.github/requirements-ci.txt" "$T/tree/.github/"
revoke="$ROOT/.github/scripts/lib/revoke-lane-token.sh"
install="$T/tree/.github/scripts/lib/install-pinned-pyyaml.sh"

out=$(env -i PATH="$T/stub204:/usr/bin:/bin" GH_TOKEN=t GITHUB_API_URL=https://api.example bash "$revoke" 2>&1)
rc=$?
if [[ $rc -eq 0 && $out == "the lane token is revoked" ]]; then
  ok "a 204 prints the revoke and exits 0"
else
  fail "a 204 printed [$out], exit $rc"
fi

out=$(env -i PATH="$T/stub401:/usr/bin:/bin" GH_TOKEN=t GITHUB_API_URL=https://api.example bash "$revoke" 2>&1)
rc=$?
if [[ $rc -eq 0 && $out == "::warning::the lane token was not revoked (DELETE 401); it expires within the hour" ]]; then
  ok "any other status warns and still exits 0"
else
  fail "a 401 printed [$out], exit $rc"
fi

out=$(env -i PATH="$T/pyok:/usr/bin:/bin" RUNNER_TEMP="$T/rt" bash "$install" 'the warning' 2>&1)
rc=$?
want=$(awk '/^pyyaml==/ { keep = 1 } keep { print } keep && !/\\$/ { exit }' "$ROOT/.github/requirements-ci.txt")
if [[ $rc -eq 0 && -z $out && $(head -1 <<<"$want") == pyyaml==* && "$(cat "$T/rt/pyyaml-requirements.txt")" == "$want" ]]; then
  ok "the install reads exactly the pyyaml== block of the requirements file two directories up"
else
  fail "install exit $rc, output [$out], requirements [$(head -1 "$T/rt/pyyaml-requirements.txt" 2>/dev/null)]"
fi
if [[ "$(cat "$T/pip-args" 2>/dev/null)" == "-m pip install --disable-pip-version-check --only-binary=:all: --require-hashes --requirement $T/rt/pyyaml-requirements.txt" ]]; then
  ok "the install runs pip with binary-only, hash-checked flags"
else
  fail "pip ran with [$(cat "$T/pip-args" 2>/dev/null)]"
fi

out=$(env -i PATH="$T/pyfail:/usr/bin:/bin" RUNNER_TEMP="$T/rt" bash "$install" 'PyYAML did not install; the read fails' 2>&1)
rc=$?
if [[ $rc -eq 1 && $out == "::warning::PyYAML did not install; the read fails" ]]; then
  ok "a failed install prints its argument as a warning and exits 1"
else
  fail "a failed install printed [$out], exit $rc"
fi

test_harness::report
