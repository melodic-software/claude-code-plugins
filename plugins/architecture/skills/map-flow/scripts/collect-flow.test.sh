#!/usr/bin/env bash
# Tests for collect-flow.sh and render-flow.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-flow.sh"
RENDER="$SCRIPT_DIR/render-flow.sh"
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

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: names schema_version" "$help_out" "schema_version"

repo="$TEST_TMPDIR/billing"
init_repo "$repo"
git -C "$repo" remote add origin "https://github.com/acme/billing.git"
mkdir -p "$repo/src/Transport" "$repo/src/Application" "$repo/src/Infrastructure" "$repo/src/DecoyWorker"
cat >"$repo/src/Transport/OrdersEndpoint.cs" <<'CS'
namespace Billing.Transport;
public class OrdersEndpoint {
    private readonly IOrders _orders;
    private readonly OrdersService _service;
    [HttpGet("/orders/{id}")]
    public async Task Get(string id) {
        await _orders.Place(id);
        await _service.Handle(id);
    }
}
CS
cat >"$repo/src/Application/OrdersService.cs" <<'CS'
namespace Billing.Application;
public class OrdersService {
    public async Task Handle(string id) {
        await Publisher.Publish<OrderPlaced>(id);
        Repository.Save(id);
    }
}
CS
cat >"$repo/src/Infrastructure/Repository.cs" <<'CS'
namespace Billing.Infrastructure;
public class Repository {
    public void Save(string id) {
    }
}
CS
cat >"$repo/src/DecoyWorker/OrdersImpl.cs" <<'CS'
namespace Billing.DecoyWorker;
public class OrdersImpl {
    public void Place(string id) {
    }
}
CS
git -C "$repo" add src
git -C "$repo" commit --quiet -m "fixture"

out="$TEST_TMPDIR/out"
mkdir -p "$out"
record="$out/flow.json"
bash "$COLLECT" --repo "$repo" --entry "/orders/{id}" --generated-on 2026-09-28 --out "$record" >/dev/null
assert_equals "collect exits 0" "$?" "0"
blob="$(cat "$record")"
assert_contains "subject is the github repo name" "$blob" '"subject": "billing"'
assert_not_contains "record names no dialect key" "$blob" "dialect_key"
place_line="$(grep -n '_orders.Place' "$repo/src/Transport/OrdersEndpoint.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "interface hop cites the call site" "$blob" "\"file\":\"src/Transport/OrdersEndpoint.cs\",\"line\":\"$place_line\""
assert_contains "interface hop is unresolved dependency-injection" "$blob" '"resolution":"unresolved","mechanism":"dependency-injection"'
assert_not_contains "interface hop does not guess OrdersImpl" "$blob" "OrdersImpl"
handle_line="$(grep -n '_service.Handle' "$repo/src/Transport/OrdersEndpoint.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "concrete hop cites the call site" "$blob" "\"file\":\"src/Transport/OrdersEndpoint.cs\",\"line\":\"$handle_line\""
assert_contains "cross-file unique method is inferred" "$blob" '"call":"Handle","file":"src/Transport/OrdersEndpoint.cs"'
assert_contains "Handle resolution inferred" "$blob" '"resolution":"inferred"'
pub_line="$(grep -n 'Publish<OrderPlaced>' "$repo/src/Application/OrdersService.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "publish cites its call site" "$blob" "\"file\":\"src/Application/OrdersService.cs\",\"line\":\"$pub_line\""
assert_contains "publish is a handoff" "$blob" '"handoff":"yes"'
assert_contains "publish is asynchronous" "$blob" '"sync":"asynchronous"'
save_line="$(grep -n 'Repository.Save' "$repo/src/Application/OrdersService.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "save cites its call site" "$blob" "\"line\":\"$save_line\""
assert_contains "save is synchronous" "$blob" '"sync":"synchronous"'
assert_contains "trace is complete" "$blob" '"truncated": "no"'

render_out="$(bash "$RENDER" --record "$record" --out "$out")"
assert_equals "render mermaid exits 0" "$?" "0"
md="$(cat "$out/flow.md")"
assert_contains "summary names the entry" "$render_out" "entry=/orders/{id}"
assert_contains "async arrow" "$md" "-->>"
assert_contains "sync arrow" "$md" "->>"
assert_contains "handoff names map-events" "$md" "handoff /architecture:map-events"
assert_contains "unresolved label is on the diagram" "$md" "unresolved"
assert_contains "inferred label is on the diagram" "$md" "inferred"
assert_not_contains "render writes no dsl file" "$(ls "$out")" "flow.dsl"
assert_not_contains "guessed implementation is not a participant" "$md" "OrdersImpl"

assert_contains "render is a mermaid sequence diagram" "$md" "sequenceDiagram"
bash "$RENDER" --record "$record" --out "$out" --dialect structurizr >/dev/null 2>&1
assert_equals "a dialect argument is a usage error" "$?" "2"

depth_record="$TEST_TMPDIR/depth.json"
bash "$COLLECT" --repo "$repo" --entry "/orders/{id}" --depth 1 --out "$depth_record" >/dev/null
depth_blob="$(cat "$depth_record")"
assert_contains "depth 1 truncates" "$depth_blob" '"truncated": "yes"'
assert_not_contains "depth 1 does not enter Handle" "$depth_blob" "Publish<OrderPlaced>"
depth_md_dir="$TEST_TMPDIR/depth-md"
mkdir -p "$depth_md_dir"
bash "$RENDER" --record "$depth_record" --out "$depth_md_dir" >/dev/null
assert_contains "artifact states the stopping point" "$(cat "$depth_md_dir/flow.md")" "Depth truncated at 1"

bad="$(bash "$COLLECT" --repo "$repo" --entry "/missing" --out "$TEST_TMPDIR/missing.json" 2>&1)"
assert_equals "missing entry exits 3" "$?" "3"
assert_contains "missing entry states the reason" "$bad" "refused: entry point not found"
if [[ ! -f "$TEST_TMPDIR/missing.json" ]]; then
  pass "missing entry writes nothing"
else
  fail "missing entry wrote a record" "present"
fi

printf 'public class Short\n{\n    public Task Entry() => service.DoWork();\n    public void Other()\n    {\n        Helper.Run();\n    }\n}\n' >"$repo/src/Transport/Short.cs"
git -C "$repo" add src
git -C "$repo" commit --quiet -m "expression-bodied"
expr="$(bash "$COLLECT" --repo "$repo" --entry "Entry" --out "$TEST_TMPDIR/expr.json" 2>&1)"
assert_equals "expression-bodied entry exits 3" "$?" "3"
assert_contains "expression-bodied entry states the reason" "$expr" "no block body"
assert_not_contains "expression-bodied entry does not borrow the next method" "$expr" "Helper"
git -C "$repo" rm --quiet src/Transport/Short.cs
git -C "$repo" commit --quiet -m "drop expression-bodied"

printf 'outside.cs\n' >"$repo/.gitignore"
printf 'public class Outside\n{\n    public void LinkedEntry()\n    {\n        Helper.Run();\n    }\n}\n' >"$repo/outside.cs"
ln -s ../../outside.cs "$repo/src/Transport/Linked.cs"
git -C "$repo" add .gitignore src
git -C "$repo" commit --quiet -m "symlink"
linked="$(bash "$COLLECT" --repo "$repo" --entry "LinkedEntry" --out "$TEST_TMPDIR/linked.json" 2>&1)"
assert_equals "a tracked symlink is not a source" "$?" "3"
assert_contains "the symlinked entry is not found" "$linked" "refused: entry point not found"
git -C "$repo" rm --quiet src/Transport/Linked.cs
git -C "$repo" commit --quiet -m "drop symlink"

cp "$repo/src/Transport/OrdersEndpoint.cs" "$repo/src/Transport/OrdersEndpoint2.cs"
git -C "$repo" add src
git -C "$repo" commit --quiet -m "duplicate"
dup="$(bash "$COLLECT" --repo "$repo" --entry "/orders/{id}" --out "$TEST_TMPDIR/dup.json" 2>&1)"
assert_equals "duplicate entry exits 3" "$?" "3"
assert_contains "duplicate entry names both sites" "$dup" "OrdersEndpoint.cs"
assert_contains "duplicate entry names the copy" "$dup" "OrdersEndpoint2.cs"
git -C "$repo" rm --quiet src/Transport/OrdersEndpoint2.cs
git -C "$repo" commit --quiet -m "drop duplicate"

py="$TEST_TMPDIR/pyonly"
init_repo "$py"
printf 'print("hi")\n' >"$py/main.py"
git -C "$py" add main.py
git -C "$py" commit --quiet -m "py"
py_out="$(bash "$COLLECT" --repo "$py" --entry "main" --out "$TEST_TMPDIR/py.json" 2>&1)"
assert_equals "non-csharp exits 3" "$?" "3"
assert_contains "non-csharp states the adapter" "$py_out" "C#"
if [[ ! -f "$TEST_TMPDIR/py.json" ]]; then
  pass "non-csharp writes nothing"
else
  fail "non-csharp wrote a record" "present"
fi

flat="$TEST_TMPDIR/flat.json"
tr '\n' ' ' <"$record" >"$flat"
flat_dir="$TEST_TMPDIR/flat-out"
mkdir -p "$flat_dir"
flat_err="$(bash "$RENDER" --record "$flat" --out "$flat_dir" 2>&1)"
assert_equals "reformatted record exits 1" "$?" "1"
assert_contains "reformatted record names the layout" "$flat_err" "one-object-per-line"
if [[ ! -f "$flat_dir/flow.md" ]]; then
  pass "reformatted record writes nothing"
else
  fail "reformatted record wrote flow.md" "present"
fi

# Consecutive identical hops collapse.
collapse_json="$TEST_TMPDIR/collapse.json"
cat >"$collapse_json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-09-28",
  "subject": "billing",
  "entry": {"name":"Get","file":"src/A.cs","line":"1"},
  "depth": 5,
  "truncated": "no",
  "hops": [
    {"from_role":"transport","to_role":"application","call":"A","file":"src/A.cs","line":"2","callee_file":"","callee_line":"","sync":"synchronous","resolution":"statically-resolved","mechanism":"","handoff":"no"},
    {"from_role":"transport","to_role":"application","call":"B","file":"src/A.cs","line":"3","callee_file":"","callee_line":"","sync":"synchronous","resolution":"statically-resolved","mechanism":"","handoff":"no"}
  ]
}
JSON
collapse_dir="$TEST_TMPDIR/collapse-out"
mkdir -p "$collapse_dir"
bash "$RENDER" --record "$collapse_json" --out "$collapse_dir" >/dev/null
collapse_md="$(cat "$collapse_dir/flow.md")"
assert_contains "collapse is stated" "$collapse_md" "2 hops collapsed"
assert_contains "collapse keeps both citations in the table" "$collapse_md" "src/A.cs:3"

printf 'tests: %s passed, %s failed\n' "$((CASE_NUM - FAILED))" "$FAILED"
exit "$FAILED"
