#!/usr/bin/env bash
# shellcheck disable=SC2154 # the runner sets RUNNER_TEMP and GITHUB_PATH
set -e
GO_VERSION=1.27.4
GO_SHA256=7226736c2339719cda28fbf3a54d71aa63bcefe376e98cef00034268dab24840
GOIMPORTS_VERSION=v0.52.0
bin=${1:?usage: install-pinned-goimports.sh <bin-dir> [cache-dir]}
cache=${2:-$RUNNER_TEMP}
asset="go$GO_VERSION.linux-amd64.tar.gz"
archive="$cache/$asset"
mkdir -p "$bin" "$cache"
[[ -f "$archive" ]] || curl -fSL --no-progress-meter --retry 7 --retry-all-errors -o "$archive" "https://go.dev/dl/$asset"
echo "$GO_SHA256  $archive" | sha256sum -c - ||
  {
    echo "::error::$asset does not match GO_SHA256"
    exit 1
  }
tar -xzf "$archive" -C "$RUNNER_TEMP"
go="$RUNNER_TEMP/go/bin/go"
[[ "$("$go" env GOVERSION)" == "go$GO_VERSION" ]] || {
  echo "::error::$asset does not hold go$GO_VERSION"
  exit 1
}
GOBIN="$bin" GOTOOLCHAIN=local "$go" install "golang.org/x/tools/cmd/goimports@$GOIMPORTS_VERSION"
echo "$bin" >>"$GITHUB_PATH"
echo "$RUNNER_TEMP/go/bin" >>"$GITHUB_PATH"
