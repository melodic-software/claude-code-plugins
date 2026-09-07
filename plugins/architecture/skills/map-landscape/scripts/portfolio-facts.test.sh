#!/usr/bin/env bash
# Self-contained tests for portfolio-facts.sh (skill-script shape, per
# docs/conventions/shell-test-helpers/README.md: per-plugin assertion
# primitives are duplicated on purpose, never shared across plugins).
#
# Every fixture is built in a mktemp directory and torn down on exit; nothing
# here reads or writes a real repository.
set -uo pipefail

# Isolate the fixture repositories from any ambient git environment. `git -C`
# changes directory but does not override discovery, so an exported absolute
# GIT_DIR would land these throwaway identities in the CALLER's .git/config,
# and GIT_CONFIG is a second leak path that survives a cleared GIT_DIR.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/portfolio-facts.sh"
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

# A committed fixture repository with an isolated identity, so a machine
# without a global git identity still produces a commit (and therefore a
# last_touched value).
make_repo() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet 2>/dev/null
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  printf '%s' "$dir"
}

# A fresh `git init` has no hooks, so --no-verify is belt-and-braces rather
# than a bypass of anything the fixture installed.
commit_repo() {
  git -C "$1" add -A 2>/dev/null
  git -C "$1" commit --quiet --no-verify -m "fixture" 2>/dev/null
}

# Read one JSON field out of a single-object JSON Lines record without jq.
field() {
  printf '%s' "$1" | awk -v key="$2" '
    {
      pat = "\"" key "\":\""
      i = index($0, pat)
      if (i == 0) { print ""; exit }
      rest = substr($0, i + length(pat))
      j = index(rest, "\"")
      print substr(rest, 1, j - 1)
    }
  '
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

# --- Case group 1: a .NET repository ----------------------------------------
dotnet_repo="$(make_repo dotnet-svc)"
mkdir -p "$dotnet_repo/src"
cat >"$dotnet_repo/src/Billing.csproj" <<'CSPROJ'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog" Version="4.0.0" />
    <PackageReference Include="MediatR" Version="12.4.0" />
  </ItemGroup>
</Project>
CSPROJ
commit_repo "$dotnet_repo"
out="$(bash "$SCRIPT" "$dotnet_repo")"
assert_equals "dotnet: name" "$(field "$out" name)" "dotnet-svc"
assert_contains "dotnet: path is the resolved absolute path" "$(field "$out" path)" "dotnet-svc"
assert_equals "dotnet: runtime" "$(field "$out" runtime)" "dotnet"
assert_equals "dotnet: target_framework from the first csproj" "$(field "$out" target_framework)" "net9.0"
assert_contains "dotnet: PackageReference collected (MediatR)" "$out" '"MediatR"'
assert_contains "dotnet: PackageReference collected (Serilog)" "$out" '"Serilog"'
assert_contains "dotnet: last_touched is an ISO timestamp" "$out" '"last_touched":"20'
assert_contains "dotnet: evidence names the csproj" "$out" 'src/Billing.csproj'

# --- Case group 2: a Node repository ----------------------------------------
node_repo="$(make_repo web-app)"
cat >"$node_repo/package.json" <<'PKG'
{
  "name": "web-app",
  "engines": { "node": ">=22" },
  "dependencies": { "react": "^19.0.0", "zod": "^3.23.0" },
  "peerDependencies": { "typescript": "^5.6.0" },
  "devDependencies": { "vitest": "^2.0.0" }
}
PKG
commit_repo "$node_repo"
out="$(bash "$SCRIPT" "$node_repo")"
assert_equals "node: runtime" "$(field "$out" runtime)" "node"
assert_equals "node: target_framework from engines.node" "$(field "$out" target_framework)" ">=22"
assert_contains "node: dependencies key collected" "$out" '"react"'
assert_contains "node: peerDependencies key collected" "$out" '"typescript"'
assert_not_contains "node: devDependencies are NOT collected" "$out" '"vitest"'
assert_not_contains "node: version ranges are not mistaken for keys" "$out" '"^19.0.0"'

# --- Case group 3: a Python repository --------------------------------------
py_repo="$(make_repo data-pipeline)"
cat >"$py_repo/pyproject.toml" <<'PYPROJ'
[project]
name = "data-pipeline"
requires-python = ">=3.12"
dependencies = [
  "httpx>=0.27",
  "pydantic==2.9.0",
]
PYPROJ
commit_repo "$py_repo"
out="$(bash "$SCRIPT" "$py_repo")"
assert_equals "python: runtime" "$(field "$out" runtime)" "python"
assert_equals "python: target_framework from requires-python" "$(field "$out" target_framework)" ">=3.12"
assert_contains "python: dependency name without its specifier" "$out" '"httpx"'
assert_contains "python: second dependency name" "$out" '"pydantic"'
assert_not_contains "python: the version specifier is stripped" "$out" '>=0.27'

# --- Case group 4: a Go repository ------------------------------------------
go_repo="$(make_repo edge-proxy)"
cat >"$go_repo/go.mod" <<'GOMOD'
module example.invalid/edge-proxy

go 1.23

require (
  github.com/spf13/cobra v1.8.1
  golang.org/x/sync v0.8.0
)
GOMOD
commit_repo "$go_repo"
out="$(bash "$SCRIPT" "$go_repo")"
assert_equals "go: runtime" "$(field "$out" runtime)" "go"
assert_equals "go: target_framework from the go directive" "$(field "$out" target_framework)" "1.23"
assert_contains "go: require-block module collected" "$out" '"github.com/spf13/cobra"'
assert_contains "go: second require-block module collected" "$out" '"golang.org/x/sync"'

# --- Case group 5: an empty repository --------------------------------------
empty_repo="$(make_repo blank)"
printf 'nothing here\n' >"$empty_repo/README.md"
commit_repo "$empty_repo"
out="$(bash "$SCRIPT" "$empty_repo")"
assert_equals "empty: runtime is unknown" "$(field "$out" runtime)" "unknown"
assert_equals "empty: target_framework is unknown" "$(field "$out" target_framework)" "unknown"
assert_equals "empty: owner is unknown" "$(field "$out" owner)" "unknown"
assert_equals "empty: remote is unknown" "$(field "$out" remote)" "unknown"
assert_contains "empty: dependencies list is empty" "$out" '"dependencies":[]'
assert_not_contains "empty: no runtime is guessed from the directory name" "$out" '"runtime":"shell"'

# --- Case group 6: CODEOWNERS wins the owner ladder -------------------------
owned_repo="$(make_repo owned-svc)"
mkdir -p "$owned_repo/.github"
cat >"$owned_repo/.github/CODEOWNERS" <<'CO'
# comment line, skipped
docs/   @docs-team
*       @platform-team @second-team
CO
git -C "$owned_repo" remote add origin "https://example.invalid/remote-owner/owned-svc.git"
commit_repo "$owned_repo"
out="$(bash "$SCRIPT" "$owned_repo")"
assert_equals "owner ladder: CODEOWNERS default rule beats the remote" "$(field "$out" owner)" "platform-team"
assert_contains "owner ladder: evidence names the CODEOWNERS path" "$out" '.github/CODEOWNERS'
assert_not_contains "owner ladder: the non-default rule owner is not taken" "$out" '"owner":"docs-team"'

# --- Case group 7: remote owner is the fallback rung ------------------------
remote_repo="$(make_repo remote-only)"
printf 'x\n' >"$remote_repo/README.md"
git -C "$remote_repo" remote add origin "git@example.invalid:fallback-owner/remote-only.git"
commit_repo "$remote_repo"
out="$(bash "$SCRIPT" "$remote_repo")"
assert_equals "owner ladder: scp-style remote owner segment" "$(field "$out" owner)" "fallback-owner"
assert_contains "owner ladder: evidence names the remote" "$out" 'origin remote URL'
assert_contains "remote: URL is reported verbatim" "$out" 'fallback-owner/remote-only.git'

# --- Case group 7a: a port in the authority is not an owner ------------------
# With a scheme, a colon in the authority is a PORT. An unconditional scp-style
# conversion promotes it to a path segment, so `https://host:8080/acme/repo`
# resolves to owner `8080` — the same fabricated-fact-with-a-citation the
# host-required guard exists to stop, arriving by a different route.
port_repo="$(make_repo ported-remote)"
printf 'x\n' >"$port_repo/README.md"
git -C "$port_repo" remote add origin "https://example.invalid:8080/ported-owner/ported-remote.git"
commit_repo "$port_repo"
out="$(bash "$SCRIPT" "$port_repo")"
assert_equals "owner ladder: a scheme URL with a port keeps its real owner" "$(field "$out" owner)" "ported-owner"
assert_not_contains "owner ladder: the port never becomes the owner" "$out" '"owner":"8080"'

ssh_port_repo="$(make_repo ssh-ported)"
printf 'x\n' >"$ssh_port_repo/README.md"
git -C "$ssh_port_repo" remote add origin "ssh://git@example.invalid:22/ssh-owner/ssh-ported.git"
commit_repo "$ssh_port_repo"
out="$(bash "$SCRIPT" "$ssh_port_repo")"
assert_equals "owner ladder: ssh URL with a port keeps its real owner" "$(field "$out" owner)" "ssh-owner"

# --- Case group 7b: a local-path remote names no owner -----------------------
# A git remote is often a plain filesystem path, and a path's first segment is a
# directory, not an owner. Reporting one would be a fabricated fact carrying an
# "origin remote URL" citation.
#
# The remote is RELATIVE on purpose. An MSYS bash rewrites a POSIX-absolute
# argument into a Windows path before git ever sees it, so an absolute fixture
# would assert against `C:/Program Files/Git/...` on one platform and the
# original on another. A relative path is left alone everywhere and exercises
# the same branch.
localpath_repo="$(make_repo local-remote)"
printf 'x\n' >"$localpath_repo/README.md"
git -C "$localpath_repo" remote add origin "../sibling-upstream"
commit_repo "$localpath_repo"
out="$(bash "$SCRIPT" "$localpath_repo")"
assert_equals "owner ladder: a path remote yields unknown, not its first segment" \
  "$(field "$out" owner)" "unknown"
assert_not_contains "owner ladder: no fabricated owner from the path" "$out" '"owner":"sibling-upstream"'
assert_not_contains "owner ladder: an unknown owner is not cited to the remote" "$out" '"owner":"origin remote URL"'
assert_contains "owner ladder: the remote itself is still reported" "$out" 'sibling-upstream'

# The same rule through a scheme with an empty authority: no host, no owner.
fileurl_repo="$(make_repo file-url-remote)"
printf 'x\n' >"$fileurl_repo/README.md"
git -C "$fileurl_repo" remote add origin "file:///opt/mirrors/upstream"
commit_repo "$fileurl_repo"
out="$(bash "$SCRIPT" "$fileurl_repo")"
assert_equals "owner ladder: file:// with an empty authority yields unknown" \
  "$(field "$out" owner)" "unknown"
assert_not_contains "owner ladder: no fabricated owner from a file URL" "$out" '"owner":"opt"'

# --- Case group 7c: a nested member must not shadow the top-level one --------
nested_repo="$(make_repo nested-deps)"
cat >"$nested_repo/package.json" <<'PKG'
{
  "name": "nested-deps",
  "pnpm": { "overrides": { "dependencies": { "ghost-from-nested": "1.0.0" } } },
  "dependencies": { "real-dep-a": "^1.0.0", "real-dep-b": "^2.0.0" }
}
PKG
commit_repo "$nested_repo"
out="$(bash "$SCRIPT" "$nested_repo")"
assert_contains "nested: the top-level dependencies win (a)" "$out" '"real-dep-a"'
assert_contains "nested: the top-level dependencies win (b)" "$out" '"real-dep-b"'
assert_not_contains "nested: a same-named nested member does not shadow them" "$out" '"ghost-from-nested"'

# --- Case group 8: the dependency cap ---------------------------------------
capped_repo="$(make_repo capped)"
{
  printf '{\n  "dependencies": {\n'
  for i in $(seq -w 1 40); do
    if [[ "$i" == "40" ]]; then
      printf '    "pkg-%s": "1.0.0"\n' "$i"
    else
      printf '    "pkg-%s": "1.0.0",\n' "$i"
    fi
  done
  printf '  }\n}\n'
} >"$capped_repo/package.json"
commit_repo "$capped_repo"
out="$(bash "$SCRIPT" "$capped_repo")"
dep_count="$(printf '%s' "$out" | grep -o '"pkg-[0-9][0-9]"' | wc -l | tr -d '[:space:]')"
assert_equals "cap: dependencies truncated to 25" "$dep_count" "25"
assert_contains "cap: sorted, so the first name survives" "$out" '"pkg-01"'
assert_not_contains "cap: sorted, so the last name is dropped" "$out" '"pkg-40"'

# --- Case group 9: shell only when nothing else claims the repository -------
shell_repo="$(make_repo tooling)"
printf '#!/usr/bin/env bash\necho hi\n' >"$shell_repo/run.sh"
commit_repo "$shell_repo"
out="$(bash "$SCRIPT" "$shell_repo")"
assert_equals "shell: only-shell repository" "$(field "$out" runtime)" "shell"

mixed_repo="$(make_repo mixed)"
printf '#!/usr/bin/env bash\necho hi\n' >"$mixed_repo/run.sh"
printf '{"name":"mixed"}\n' >"$mixed_repo/package.json"
commit_repo "$mixed_repo"
out="$(bash "$SCRIPT" "$mixed_repo")"
assert_equals "shell: suppressed when another runtime matched" "$(field "$out" runtime)" "node"

# --- Case group 10: multiple repositories, and a bad path -------------------
out="$(bash "$SCRIPT" "$dotnet_repo" "$node_repo")"
line_count="$(printf '%s\n' "$out" | grep -c '^{')"
assert_equals "multi: one JSON object per repository" "$line_count" "2"

bad_out="$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist" "$node_repo" 2>&1)"
bad_rc=$?
assert_equals "bad path: exits 1" "$bad_rc" "1"
assert_contains "bad path: names the skipped path on stderr" "$bad_out" "not a directory, skipped"
assert_contains "bad path: still emits the good repository" "$bad_out" '"name":"web-app"'

# --- Case group 11: usage ---------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1
assert_equals "usage: no arguments exits 2" "$?" "2"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
