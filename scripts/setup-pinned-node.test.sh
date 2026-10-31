#!/usr/bin/env bash
# Behavior test: .github/actions/setup-pinned-node/install-node.sh puts the exact
# version a .node-version file pins on PATH from the tool cache, or from a
# nodejs.org-shaped dist whose signed SHASUMS256.txt matches the tarball, and
# refuses a signature that does not verify, a checksum mismatch, a missing
# checksum, a version that is not X.Y.Z and a runner that is not Linux X64. The
# dist is a local file:// fixture holding a stub node that prints its version,
# signed at run time by an ephemeral key whose keybox stands in for the release
# keyring.
# test-scope: .github/actions/setup-pinned-node/*
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

SCRIPT="$ROOT/.github/actions/setup-pinned-node/install-node.sh"
T=$(mktemp -d)
trap 'gpgconf --homedir "$T/signer" --kill gpg-agent; gpgconf --homedir "$T/outsider" --kill gpg-agent; rm -rf "$T"' EXIT

# gpg_in <homedir> <args>: gpg against an ephemeral home, no passphrase, no prompt.
gpg_in() {
  gpg --homedir "$1" --batch --quiet --pinentry-mode loopback --passphrase '' "${@:2}"
}

for home in signer outsider; do
  mkdir -m 700 "$T/$home"
  gpg_in "$T/$home" --quick-generate-key "$home <$home@example.invalid>" ed25519 sign never
done

# A dist at $1 for v24.21.0 whose SHASUMS256.txt line is $2 (`good` for the real hash),
# signed by the home $3 (default the one whose keybox is the keyring).
make_dist() {
  local dist=$1 sums=$2 home=${3:-$T/signer} pkg=$T/pkg/node-v24.21.0-linux-x64
  mkdir -p "$pkg/bin" "$dist/v24.21.0"
  printf '#!/bin/sh\necho v24.21.0\n' >"$pkg/bin/node"
  chmod +x "$pkg/bin/node"
  tar -cJf "$dist/v24.21.0/node-v24.21.0-linux-x64.tar.xz" -C "$T/pkg" node-v24.21.0-linux-x64
  if [[ $sums == good ]]; then
    (cd "$dist/v24.21.0" && sha256sum node-v24.21.0-linux-x64.tar.xz >SHASUMS256.txt)
  else
    printf '%s\n' "$sums" >"$dist/v24.21.0/SHASUMS256.txt"
  fi
  gpg_in "$home" --detach-sign --output "$dist/v24.21.0/SHASUMS256.txt.sig" "$dist/v24.21.0/SHASUMS256.txt"
}

# run <case> <version-file-content> <dist> [os] : runs the script with a fresh PATH file
# against the case's own tool cache; sets rc, out, and path_line. KEYRING replaces the
# fixture keyring (empty runs the script's default), and ENTRY and ACTION_PATH run it the
# way a sibling action does.
run() {
  local c=$1 pin=$2 dist=$3 os=${4:-Linux}
  mkdir -p "$T/$c"
  printf '%s\n' "$pin" >"$T/$c/.node-version"
  : >"$T/$c/path"
  out=$(cd "$T/$c" && env -i PATH="$PATH" RUNNER_OS="$os" RUNNER_ARCH=X64 RUNNER_TOOL_CACHE="$T/cache-${CACHE:-$c}" \
    GITHUB_PATH="$T/$c/path" GITHUB_ACTION_PATH="${ACTION_PATH:-}" NODE_DIST_URL="file://$dist" \
    NODE_RELEASE_KEYRING="${KEYRING-$T/signer/pubring.kbx}" bash "${ENTRY:-$SCRIPT}" "$T/$c/.node-version" 2>&1)
  rc=$?
  path_line=$(cat "$T/$c/path")
}

make_dist "$T/dist-good" good

CACHE=shared run install 24.21.0 "$T/dist-good"
want_bin="$T/cache-shared/node/24.21.0/x64/bin"
if [[ $rc -eq 0 && $path_line == "$want_bin" && -f $T/cache-shared/node/24.21.0/x64.complete &&
  $out == *"Good signature from \"signer <signer@example.invalid>\""* &&
  $("$want_bin/node" --version) == v24.21.0 ]]; then
  ok "a miss verifies the signature, installs the tarball into the tool cache and adds its bin to PATH"
else
  bad "a miss installs the checksummed tarball" "rc=$rc path=$path_line out=$out"
fi

# The dist path does not exist, so any download would fail: success proves no fetch.
CACHE=shared run hit 24.21.0 "$T/no-such-dist"
if [[ $rc -eq 0 && $path_line == "$want_bin" && $out == *"Found in cache @ $T/cache-shared/node/24.21.0/x64"* ]]; then
  ok "a tool-cache hit downloads nothing"
else
  bad "a tool-cache hit downloads nothing" "rc=$rc out=$out"
fi

CACHE=shared run vprefix v24.21.0 "$T/no-such-dist"
if [[ $rc -eq 0 && $path_line == "$want_bin" ]]; then
  ok "a leading v in the pin is accepted"
else
  bad "a leading v in the pin is accepted" "rc=$rc out=$out"
fi

# refused <case>: the run failed at the signature, with nothing installed or on PATH.
refused() {
  [[ $rc -ne 0 && -z $path_line && ! -e $T/cache-$1/node && $out == *"SHASUMS256.txt.sig does not verify against"* ]]
}

make_dist "$T/dist-tampered" good
printf '%s  node-v24.21.0-linux-x64.tar.xz\n' "$(printf 'b%.0s' {1..64})" >>"$T/dist-tampered/v24.21.0/SHASUMS256.txt"
run tampered 24.21.0 "$T/dist-tampered"
if refused tampered && [[ $out == *'BAD signature from "signer'* ]]; then
  ok "a SHASUMS256.txt changed after signing is refused before anything is installed"
else
  bad "a SHASUMS256.txt changed after signing is refused" "rc=$rc path=$path_line out=$out"
fi

make_dist "$T/dist-outsider" good "$T/outsider"
run outsider 24.21.0 "$T/dist-outsider"
if refused outsider && [[ $out == *"No public key"* ]]; then
  ok "a signature from a key outside the keyring is refused before anything is installed"
else
  bad "a signature from a key outside the keyring is refused" "rc=$rc path=$path_line out=$out"
fi

KEYRING=$T/no-such-keyring run nokeyring 24.21.0 "$T/dist-good"
if refused nokeyring; then
  ok "a keyring that is not there is refused, not skipped"
else
  bad "a keyring that is not there is refused" "rc=$rc path=$path_line out=$out"
fi

# check-wip-cap's shape: a sibling action's GITHUB_ACTION_PATH, a relative hop into this
# action, a working directory elsewhere, and no keyring override. Only the script's own
# directory holds a keyring here, so it must be found from there.
mkdir -p "$T/actions/setup-pinned-node" "$T/actions/check-wip-cap"
cp "$SCRIPT" "$T/actions/setup-pinned-node/install-node.sh"
cp "$T/signer/pubring.kbx" "$T/actions/setup-pinned-node/pubring.kbx"
KEYRING='' ENTRY=$T/actions/check-wip-cap/../setup-pinned-node/install-node.sh ACTION_PATH=$T/actions/check-wip-cap \
  run sibling 24.21.0 "$T/dist-good"
if [[ $rc -eq 0 && $path_line == "$T/cache-sibling/node/24.21.0/x64/bin" && $out == *"Good signature"* ]]; then
  ok "run from a sibling action, the script finds the keyring beside itself"
else
  bad "run from a sibling action, the script finds the keyring beside itself" "rc=$rc path=$path_line out=$out"
fi

make_dist "$T/dist-bad" "$(printf '0%.0s' {1..64})  node-v24.21.0-linux-x64.tar.xz"
run mismatch 24.21.0 "$T/dist-bad"
if [[ $rc -ne 0 && -z $path_line && ! -e $T/cache-mismatch/node/24.21.0/x64.complete &&
  $out == *"SHASUMS256.txt says 0000"* ]]; then
  ok "a checksum mismatch fails before anything is installed or put on PATH"
else
  bad "a checksum mismatch fails" "rc=$rc path=$path_line out=$out"
fi

make_dist "$T/dist-missing" "$(printf 'a%.0s' {1..64})  node-v24.21.0-linux-arm64.tar.xz"
run missing 24.21.0 "$T/dist-missing"
if [[ $rc -ne 0 && -z $path_line && $out == *"lists no checksum for node-v24.21.0-linux-x64.tar.xz"* ]]; then
  ok "a SHASUMS256.txt without the tarball's line fails"
else
  bad "a SHASUMS256.txt without the tarball's line fails" "rc=$rc out=$out"
fi

run major 24 "$T/dist-good"
if [[ $rc -ne 0 && -z $path_line && $out == *"must pin an exact X.Y.Z version, not '24'"* ]]; then
  ok "a major-only pin is refused"
else
  bad "a major-only pin is refused" "rc=$rc out=$out"
fi

run windows 24.21.0 "$T/dist-good" Windows
if [[ $rc -ne 0 && -z $path_line && $out == *"Linux X64 runners only, not Windows/X64"* ]]; then
  ok "a non-Linux runner is refused"
else
  bad "a non-Linux runner is refused" "rc=$rc out=$out"
fi

test_harness::report
