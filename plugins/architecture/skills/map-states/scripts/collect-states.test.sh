#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-states.sh"
RENDER="$SCRIPT_DIR/render-states.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }
assert_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "missing [$3]" ;; esac }
assert_equals() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3] got [$2]"; fi }
init_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email f@e.invalid
  git -C "$1" config user.name F
  git -C "$1" config commit.gpgsign false
}

help_out="$(bash "$COLLECT" --help)"
assert_equals "help" "$?" "0"
assert_contains "help schema" "$help_out" "schema_version"

repo="$TEST_TMPDIR/orders"
init_repo "$repo"
git -C "$repo" remote add origin https://github.com/acme/orders.git
mkdir -p "$repo/src"
cat >"$repo/src/Order.cs" <<'CS'
public class OrderMachine {
  public void Wire() {
    var m = new StateMachine<OrderState, OrderTrigger>(OrderState.New);
    m.Configure(OrderState.New).Permit(OrderTrigger.Submit, OrderState.Submitted);
    m.Configure(OrderState.Submitted).PermitIf(OrderTrigger.Cancel, OrderState.Cancelled, () => true);
    m.Configure(OrderState.Legacy);
    m.Configure(OrderState.Cancelled);
  }
}
CS
git -C "$repo" add src && git -C "$repo" commit -q -m f
out="$TEST_TMPDIR/out"
mkdir -p "$out"
bash "$COLLECT" --repo "$repo" --generated-on 2026-09-28 --out "$out/states.json" 2>"$out/collect.err"
assert_equals "collect" "$?" "0"
blob="$(cat "$out/states.json")"
assert_contains "subject" "$blob" '"subject": "orders"'
assert_contains "high confidence" "$blob" '"confidence": "high"'
assert_contains "library" "$blob" '"library":"stateless"'
assert_contains "evidence file" "$blob" 'src/Order.cs'
assert_contains "submit" "$blob" '"from":"New"'
assert_contains "unreachable" "$blob" '"kind":"unreachable"'
assert_contains "legacy" "$blob" 'Legacy'
assert_contains "dead end" "$blob" '"kind":"dead_end"'
assert_contains "missing guard" "$blob" 'missing_guard'

sum="$(bash "$RENDER" --record "$out/states.json" --out "$out")"
assert_equals "render" "$?" "0"
md="$(cat "$out/states.md")"
assert_contains "diagram" "$md" "stateDiagram-v2"
assert_contains "initial" "$md" "[*] --> New"
assert_contains "submit arrow" "$md" "New --> Submitted: Submit"
assert_contains "confidence line" "$md" "Confidence: high"
assert_contains "not a C4 type" "$md" "landscape_dialect is not read"
assert_contains "summary" "$sum" "confidence=high"
assert_contains "unreachable on the artifact" "$md" "unreachable"

adhoc="$TEST_TMPDIR/adhoc"
init_repo "$adhoc"
printf '%s\n' 'public class O { public void Go() { order.Status = OrderStatus.Shipped; } }' >"$adhoc/A.cs"
git -C "$adhoc" add A.cs && git -C "$adhoc" commit -q -m a
bash "$COLLECT" --repo "$adhoc" --out "$out/adhoc.json" >/dev/null
assert_equals "ad hoc collect exits 0" "$?" "0"
assert_contains "ad hoc status" "$(cat "$out/adhoc.json")" '"status": "refused"'
assert_contains "ad hoc reason" "$(cat "$out/adhoc.json")" 'ad-hoc'
mkdir -p "$out/fresh"
set +e
msg="$(bash "$RENDER" --record "$out/adhoc.json" --out "$out/fresh" 2>&1)"
rc=$?
set -e
assert_equals "ad hoc render exits 3" "$rc" "3"
assert_contains "ad hoc render names the reason" "$msg" "ad-hoc"
[[ ! -f "$out/fresh/states.md" ]] && pass "ad hoc writes no diagram" || fail "ad hoc wrote a diagram" "present"

flat="$out/flat.json"
tr '\n' ' ' <"$out/states.json" >"$flat"
mkdir -p "$out/flatdir"
set +e
msg="$(bash "$RENDER" --record "$flat" --out "$out/flatdir" 2>&1)"
rc=$?
set -e
assert_equals "flat exits 1" "$rc" "1"
assert_contains "flat names layout" "$msg" "one-object-per-line"
[[ ! -f "$out/flatdir/states.md" ]] && pass "flat writes nothing" || fail "flat wrote a diagram" "present"

xs="$TEST_TMPDIR/xstate"
init_repo "$xs"
mkdir -p "$xs/src"
cat >"$xs/src/machine.js" <<'JS'
export const machine = createMachine({
  id: "order",
  initial: "new",
  states: {
    new: {
      on: {
        SUBMIT: "submitted",
      },
    },
    submitted: {
      on: {
        CANCEL: { target: "cancelled", guard: "canCancel" },
      },
    },
    cancelled: { type: "final" },
    legacy: {},
  },
});
JS
git -C "$xs" add src && git -C "$xs" commit -q -m x
bash "$COLLECT" --repo "$xs" --generated-on 2026-09-28 --out "$out/xs.json"
assert_equals "xstate collect" "$?" "0"
xblob="$(cat "$out/xs.json")"
assert_contains "xstate library" "$xblob" '"library":"xstate"'
assert_contains "xstate submit" "$xblob" '"trigger":"SUBMIT"'
assert_contains "xstate cancel target" "$xblob" '"to":"cancelled"'
assert_contains "xstate guard kept" "$xblob" '"guard":"canCancel"'
assert_contains "xstate final" "$xblob" '"name":"cancelled","final":"yes"'
assert_contains "xstate unreachable" "$xblob" '"state":"legacy"'
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "unexpected [$3]" ;; *) pass "$1" ;; esac }
assert_not_contains "final is not a dead-end" "$xblob" '"state":"cancelled","detail"'
mkdir -p "$out/xsdir"
xsum="$(bash "$RENDER" --record "$out/xs.json" --out "$out/xsdir")"
assert_equals "xstate render" "$?" "0"
assert_contains "xstate arrow" "$(cat "$out/xsdir/states.md")" "new --> submitted: SUBMIT"
assert_contains "xstate confidence" "$xsum" "confidence=high"

inv="$TEST_TMPDIR/invoke"
init_repo "$inv"
printf '%s\n' 'createMachine({ id: "o", initial: "a", states: { a: { invoke: { src: "svc" }, on: { GO: "b" } }, b: {} } })' >"$inv/m.js"
git -C "$inv" add m.js && git -C "$inv" commit -q -m i
bash "$COLLECT" --repo "$inv" --out "$out/invoke.json" >/dev/null
assert_equals "invoke collect exits 0" "$?" "0"
assert_contains "invoke refused" "$(cat "$out/invoke.json")" '"reason": "unsupported-syntax"'
mkdir -p "$out/invdir"
set +e
imsg="$(bash "$RENDER" --record "$out/invoke.json" --out "$out/invdir" 2>&1)"
irc=$?
set -e
assert_equals "invoke draws nothing" "$irc" "3"
[[ ! -f "$out/invdir/states.md" ]] && pass "invoke writes no diagram" || fail "invoke wrote a diagram" "present"
assert_contains "invoke names the reason" "$imsg" "unsupported-syntax"

printf 'failed=%s\n' "$FAILED"
exit "$FAILED"
