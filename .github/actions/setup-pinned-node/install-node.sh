#!/usr/bin/env bash
# install-node.sh VERSION_FILE: put the exact Node version VERSION_FILE pins on PATH.
# A hit in the runner tool cache is used as is. A miss downloads the release from
# nodejs.org/dist and checks its SHA-256 against that release's SHASUMS256.txt
# before extracting it into the tool cache. No GitHub API call either way.
# NODE_DIST_URL replaces https://nodejs.org/dist (the test points it at a local
# fixture).
set -euo pipefail

file=${1:?usage: install-node.sh VERSION_FILE}
[[ -r $file ]] || {
  echo "::error::setup-pinned-node: cannot read $file"
  exit 1
}
version=$(tr -d '[:space:]' <"$file")
version=${version#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "::error::setup-pinned-node: $file must pin an exact X.Y.Z version, not '$version'"
  exit 1
}
[[ ${RUNNER_OS:-}/${RUNNER_ARCH:-} == Linux/X64 ]] || {
  echo "::error::setup-pinned-node: supports Linux X64 runners only, not ${RUNNER_OS:-?}/${RUNNER_ARCH:-?}"
  exit 1
}

dir=${RUNNER_TOOL_CACHE:?}/node/$version/x64
if [[ -f $dir.complete && -x $dir/bin/node ]]; then
  echo "Found in cache @ $dir"
else
  name=node-v$version-linux-x64.tar.xz
  base=${NODE_DIST_URL:-https://nodejs.org/dist}/v$version
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading $base/$name"
  curl -fsSL --proto-redir '=https' --retry 5 --retry-all-errors -o "$tmp/SHASUMS256.txt" "$base/SHASUMS256.txt"
  curl -fsSL --proto-redir '=https' --retry 5 --retry-all-errors -o "$tmp/$name" "$base/$name"
  want=$(awk -v n="$name" '$2 == n { print $1 }' "$tmp/SHASUMS256.txt")
  [[ $want =~ ^[0-9a-f]{64}$ ]] || {
    echo "::error::setup-pinned-node: SHASUMS256.txt lists no checksum for $name"
    exit 1
  }
  got=$(sha256sum "$tmp/$name" | cut -d' ' -f1)
  [[ $got == "$want" ]] || {
    echo "::error::setup-pinned-node: $name has SHA-256 $got, SHASUMS256.txt says $want"
    exit 1
  }
  rm -rf "$dir" "$dir.complete"
  mkdir -p "$dir"
  tar -xJf "$tmp/$name" -C "$dir" --strip-components=1
  touch "$dir.complete"
  echo "Installed $name (sha256 $got) @ $dir"
fi

[[ $("$dir/bin/node" --version) == "v$version" ]] || {
  echo "::error::setup-pinned-node: $dir/bin/node does not report v$version"
  exit 1
}
echo "$dir/bin" >>"${GITHUB_PATH:?}"
