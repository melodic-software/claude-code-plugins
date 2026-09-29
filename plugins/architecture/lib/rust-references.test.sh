#!/usr/bin/env bash
# Self-contained tests for rust-references.sh, the Cargo.toml reader
# map-dependencies uses (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/rust-references.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

# shellcheck source=rust-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

T=$'\t'
toml="$TEST_TMPDIR/Cargo.toml"
cat >"$toml" <<'EOF'
[package]
name = "My_App"
description = """
[dependencies]
ghost = { path = "../ghost" }
"""

[dependencies]
serde = "1"   # comment
tokio = { version = "1", features = ["full"] }
local = { path = "../local", optional = true }
ren = { package = "Real_Name", version = "1" }
inh = { workspace = true, features = ["x"] }
dot.path = "../dot"
dot.version = "1"
flat.workspace = true
gitdep = { git = "https://example.com/g.git" }
multi = { version = "1",
  features = ["a"] }
weird = 3

[dependencies.sub]
path = "../sub"

[dependencies.subver]
version = "2"

[target.'cfg(unix)'.dependencies]
libc = "0.2"

[dev-dependencies]
serde = "1"

[build-dependencies]
cc = { path = "../cc" }

[patch.crates-io]
a = { path = "../a" }
b = { git = "https://example.com/b.git" }

[[bin]]
name = "x"
EOF
records="$(rust_manifest_records "$toml")"
assert_contains "the package name is read" "$records" "name${T}My_App"
assert_not_contains "text inside a multi-line string is skipped" "$records" "ghost"
assert_contains "a version string is a crate, comment removed" "$records" "pkg${T}serde${T}serde = \"1\""
assert_contains "an inline table without path is a crate" "$records" "pkg${T}tokio${T}"
assert_contains "an inline table path is a path line" "$records" "path${T}../local${T}local = { path = \"../local\", optional = true }${T}local"
assert_contains "package = renames to the real name, folded" "$records" "pkg${T}real-name${T}"
assert_contains "workspace = true is inherit" "$records" "inherit${T}inh${T}inh = { workspace = true, features = [\"x\"] }"
assert_contains "a dotted path key is a path line" "$records" "path${T}../dot${T}dot.path = \"../dot\"${T}dot"
assert_not_contains "a dotted version key beside a path adds no crate" "$records" "pkg${T}dot"
assert_contains "a dotted workspace key is inherit" "$records" "inherit${T}flat${T}flat.workspace = true"
assert_contains "a git dependency is a crate" "$records" "pkg${T}gitdep${T}"
assert_contains "an inline table split across lines is one unread declaration" "$records" "unread${T}multi = { version = \"1\", features = [\"a\"] }"
assert_contains "a non-string non-table value is unread" "$records" "unread${T}weird = 3"
assert_contains "a [dependencies.name] table path is a path line citing the header" "$records" "path${T}../sub${T}[dependencies.sub] path = \"../sub\"${T}sub"
assert_contains "a [dependencies.name] table without path is a crate" "$records" "pkg${T}subver${T}[dependencies.subver] version = \"2\""
assert_contains "a target-specific table is unread" "$records" "unread${T}[target.'cfg(unix)'.dependencies]"
assert_not_contains "a target-specific dependency draws no line" "$records" "libc"
assert_contains "a dev-dependency is read" "$records" "pkg${T}serde${T}serde = \"1\""
assert_contains "a build-dependency path is a path line" "$records" "path${T}../cc${T}cc = { path = \"../cc\" }${T}cc"
assert_contains "a path under [patch] is unread" "$records" "unread${T}a = { path = \"../a\" }"
assert_not_contains "a git patch is not unread" "$records" "example.com/b.git"
assert_not_contains "a manifest with no [workspace] table gives no workspace line" "$records" "workspace${T}"

ws="$TEST_TMPDIR/ws.toml"
cat >"$ws" <<'EOF'
[workspace]
members = ["crates/*", 'tools/cli',
  "libs/{a,b}"]
exclude = [
  "crates/old",
]

[workspace.dependencies]
core = { path = "crates/core", version = "0.1" }
anyhow = "1"
alias = { package = "some_thing", version = "2" }
[workspace.dependencies.sub]
path = "crates/sub"
[workspace.dependencies.tbl]
version = "3"
EOF
wrecords="$(rust_manifest_records "$ws")"
assert_equals "a [workspace] table gives one workspace line" "$(printf '%s\n' "$wrecords" | grep -c '^workspace$')" "1"
assert_contains "a members glob is a member line" "$wrecords" "member${T}crates/*${T}members \"crates/*\""
assert_contains "a single-quoted member on a continued array is read" "$wrecords" "member${T}tools/cli${T}members 'tools/cli'"
assert_contains "a member glob with braces is still a member line for the collector to refuse" "$wrecords" "member${T}libs/{a,b}${T}"
assert_contains "a multi-line exclude is read" "$wrecords" "exclude${T}crates/old${T}exclude \"crates/old\""
assert_contains "a workspace path entry is a wpath line" "$wrecords" "wpath${T}crates/core${T}core = { path = \"crates/core\", version = \"0.1\" }${T}core"
assert_contains "a workspace version entry is a wpkg line" "$wrecords" "wpkg${T}anyhow${T}anyhow${T}anyhow = \"1\""
assert_contains "a workspace entry renamed by package = keeps the key and the real name" "$wrecords" "wpkg${T}alias${T}some-thing${T}"
assert_contains "a [workspace.dependencies.name] table path is a wpath line" "$wrecords" "wpath${T}crates/sub${T}[workspace.dependencies.sub] path = \"crates/sub\"${T}sub"
assert_contains "a [workspace.dependencies.name] table version is a wpkg line" "$wrecords" "wpkg${T}tbl${T}tbl${T}"
assert_not_contains "a workspace entry is not a plain crate line" "$wrecords" "pkg${T}core"

printf '[workspace]\nmembers = "crates/*"\n' >"$TEST_TMPDIR/ws2.toml"
assert_contains "a members value that is not an array is unread" "$(rust_manifest_records "$TEST_TMPDIR/ws2.toml")" "unread${T}members = \"crates/*\""

printf '[workspace]\nmembers = [\n  "a",\n' >"$TEST_TMPDIR/open.toml"
assert_contains "an unterminated array is unread" "$(rust_manifest_records "$TEST_TMPDIR/open.toml")" "unread${T}<unterminated array>"

assert_equals "a missing file gives nothing" "$(rust_manifest_records "$TEST_TMPDIR/absent")" ""

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
