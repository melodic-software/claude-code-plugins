#!/usr/bin/env bash
# Self-contained tests for python-references.sh, the Python manifest reader
# map-dependencies uses (assertion primitives are duplicated on purpose, per
# docs/conventions/shell-test-helpers/README.md).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/python-references.sh"
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

# shellcheck source=python-references.sh
source "$LIB"

ran="$(bash "$LIB" 2>&1)"
assert_equals "the shared reader is not a command" "$?" "2"
assert_contains "the shared reader says it is sourced" "$ran" "sourced"

T=$'\t'
toml="$TEST_TMPDIR/pyproject.toml"
cat >"$toml" <<'EOF'
[project]
name = "My_App"
description = """
[tool.uv.sources]
ghost = { path = "../ghost" }
"""
dynamic = ["version"]
dependencies = [
  "requests>=2",   # http client
  "Lib_A @ file:../liba",
  "numpy ; python_version > '3'",
  'flask[async]>=2',
  "abs @ file:///opt/abs",
  "git-dep @ git+https://example.com/x.git",
  {include-group = "x"},
]

[project.optional-dependencies]
dev = ["pytest"]

[tool.poetry.dependencies]
python = "^3.11"
lib-b = { path = "../libb", develop = true }
httpx = "^0.27"
split = { version = "1",
  extras = ["a"] }
several = [ {version = "1"}, {version = "2"} ]
[tool.poetry.group.dev.dependencies]
black = { version = "*" }
[tool.poetry.dependencies.sub]
version = "1"

[tool.uv.sources]
lib-c = { path = "../libc" }
lib-w = { workspace = true }
from-git = { git = "https://example.com/y.git" }
EOF
records="$(py_project_records "$toml")"
assert_contains "the project name is read" "$records" "name${T}My_App"
assert_contains "a PEP 508 string is a named requirement, comment removed" "$records" "pkg${T}requests${T}\"requests>=2\""
assert_contains "an environment marker is cut from the name" "$records" "pkg${T}numpy${T}"
assert_contains "extras are cut and the name is normalized" "$records" "pkg${T}flask${T}'flask[async]>=2'"
assert_contains "a file: URL is a path with a normalized name" "$records" "path${T}../liba${T}\"Lib_A @ file:../liba\"${T}lib-a"
assert_contains "an absolute file: URL is still a path line" "$records" "path${T}///opt/abs${T}"
assert_contains "another URL scheme is an external requirement" "$records" "pkg${T}git-dep${T}"
assert_contains "a non-string array element is unread" "$records" "unread${T}{include-group = \"x\"},"
assert_contains "optional-dependencies are read" "$records" "pkg${T}pytest${T}"
assert_contains "a poetry path entry is a path line" "$records" "path${T}../libb${T}lib-b = { path = \"../libb\", develop = true }${T}lib-b"
assert_contains "a poetry version string is a requirement" "$records" "pkg${T}httpx${T}httpx = \"^0.27\""
assert_not_contains "the poetry python entry is not a requirement" "$records" "pkg${T}python"
assert_contains "an inline table split across lines is one unread declaration" "$records" "unread${T}split = { version = \"1\", extras = [\"a\"] }"
assert_contains "a list of poetry constraints is unread" "$records" "unread${T}several = "
assert_contains "a poetry group entry is read" "$records" "pkg${T}black${T}"
assert_contains "a poetry dependency written as a table is unread" "$records" "unread${T}[tool.poetry.dependencies.sub]"
assert_contains "a uv path source is a path line" "$records" "path${T}../libc${T}lib-c = { path = \"../libc\" }${T}lib-c"
assert_contains "a uv workspace source is unread" "$records" "unread${T}lib-w = { workspace = true }"
assert_not_contains "a uv git source adds nothing" "$records" "from-git"
assert_not_contains "text inside a multi-line string is skipped" "$records" "ghost"
assert_not_contains "dynamic without dependencies is not unread" "$records" "dynamic"

dyn="$TEST_TMPDIR/dyn.toml"
cat >"$dyn" <<'EOF'
[project]
name = "d"
dynamic = [
  "version",
  "dependencies",
]
EOF
assert_contains "dynamic dependencies is unread" "$(py_project_records "$dyn")" "unread${T}dynamic = [ \"version\", \"dependencies\", ]"

printf '[project]\nname = "o"\ndependencies = [\n  "a",\n' >"$TEST_TMPDIR/open.toml"
assert_contains "an unterminated array is unread" "$(py_project_records "$TEST_TMPDIR/open.toml")" "unread${T}<unterminated array: dependencies>"

req="$TEST_TMPDIR/requirements.txt"
cat >"$req" <<'EOF'
# comment
-r base.txt
--requirement=../shared/extra.txt
-e ./libs/foo[dev]
-e git+https://example.com/a.git#egg=Bee_Pkg
-e git+https://example.com/b.git
../other
Django==4.2 \
    --hash=sha256:abc
--index-url https://example.com/simple
-c constraints.txt
--weird-option
requests>=2 ; python_version<"3.9"
https://example.com/pkg.whl
foo @ file:./vendored/foo
EOF
rrecords="$(py_requirements_records "$req")"
assert_contains "-r is an include" "$rrecords" "include${T}base.txt${T}-r base.txt"
assert_contains "--requirement= is an include" "$rrecords" "include${T}../shared/extra.txt${T}"
assert_contains "-e ./ is a path line with extras cut" "$rrecords" "path${T}./libs/foo${T}-e ./libs/foo[dev]"
assert_contains "-e VCS with an egg fragment is a normalized requirement" "$rrecords" "pkg${T}bee-pkg${T}"
assert_contains "-e VCS with no egg fragment is unread" "$rrecords" "unread${T}-e git+https://example.com/b.git"
assert_contains "a plain ../ line is a path line" "$rrecords" "path${T}../other${T}../other"
assert_contains "a named requirement is read across a continuation" "$rrecords" "pkg${T}django${T}Django==4.2"
assert_not_contains "a hash option is not part of the declaration" "$rrecords" "sha256"
assert_not_contains "an index option gives no line" "$rrecords" "index-url"
assert_not_contains "a constraints include gives no line" "$rrecords" "constraints.txt"
assert_contains "an unknown option is unread" "$rrecords" "unread${T}--weird-option"
assert_contains "a marker is cut from the name" "$rrecords" "pkg${T}requests${T}"
assert_contains "a bare URL is unread" "$rrecords" "unread${T}https://example.com/pkg.whl"
assert_contains "name @ file: in a requirements file is a path with its name" "$rrecords" "path${T}./vendored/foo${T}foo @ file:./vendored/foo${T}foo"

ws="$TEST_TMPDIR/ws.toml"
cat >"$ws" <<'TOML'
[tool.uv.workspace]
members = ["packages/*", 'libs/core']
exclude = [
  "packages/legacy",
]
TOML
wrecords="$(py_project_records "$ws")"
assert_contains "a uv workspace members glob is a member line" "$wrecords" "member${T}packages/*${T}members \"packages/*\""
assert_contains "a single-quoted uv workspace member is read" "$wrecords" "member${T}libs/core${T}members 'libs/core'"
assert_contains "a multi-line uv workspace exclude is read" "$wrecords" "exclude${T}packages/legacy${T}exclude \"packages/legacy\""
printf '[tool.uv.workspace]\nmembers = "packages/*"\n' >"$TEST_TMPDIR/ws2.toml"
assert_contains "a uv workspace members value that is not an array is unread" "$(py_project_records "$TEST_TMPDIR/ws2.toml")" "unread${T}members = \"packages/*\""

assert_equals "a missing file gives nothing" "$(py_project_records "$TEST_TMPDIR/absent")$(py_requirements_records "$TEST_TMPDIR/absent")" ""

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
