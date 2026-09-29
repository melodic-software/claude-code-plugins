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
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "unexpected [$3]" ;; *) pass "$1" ;; esac }
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
    m.Configure(OrderState.Submitted).PermitIf(OrderTrigger.Cancel, OrderState.Cancelled, () => true).PermitReentry(OrderTrigger.Retry);
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
assert_contains "stateless terminal is inferred" "$blob" '"kind":"terminal_inferred","entity":"OrderState","state":"Cancelled"'
assert_not_contains "stateless terminal is not a dead-end" "$blob" '"kind":"dead_end"'
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
assert_contains "summary counts terminal_inferred and missing_guards" "$sum" "terminal_inferred=1 missing_guards=1"
assert_contains "summary counts unreachable and dead_ends" "$sum" "unreachable=1 dead_ends=0"
assert_contains "unreachable on the artifact" "$md" "unreachable"
assert_contains "guard label in the diagram" "$md" "Submitted --> Cancelled: Cancel [true]"
assert_contains "reentry is a self transition" "$md" "Submitted --> Submitted: Retry"

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
if [[ ! -f "$out/fresh/states.md" ]]; then
  pass "ad hoc writes no diagram"
else
  fail "ad hoc wrote a diagram" "present"
fi

flat="$out/flat.json"
tr '\n' ' ' <"$out/states.json" >"$flat"
mkdir -p "$out/flatdir"
set +e
msg="$(bash "$RENDER" --record "$flat" --out "$out/flatdir" 2>&1)"
rc=$?
set -e
assert_equals "flat exits 1" "$rc" "1"
assert_contains "flat names layout" "$msg" "one-object-per-line"
if [[ ! -f "$out/flatdir/states.md" ]]; then
  pass "flat writes nothing"
else
  fail "flat wrote a diagram" "present"
fi

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
assert_not_contains "final is not a dead-end" "$xblob" '"state":"cancelled","detail"'
mkdir -p "$out/xsdir"
xsum="$(bash "$RENDER" --record "$out/xs.json" --out "$out/xsdir")"
assert_equals "xstate render" "$?" "0"
assert_contains "xstate arrow" "$(cat "$out/xsdir/states.md")" "new --> submitted: SUBMIT"
assert_contains "xstate confidence" "$xsum" "confidence=high"

typo="$TEST_TMPDIR/typo"
init_repo "$typo"
mkdir -p "$typo/src"
sed 's/SUBMIT: "submitted"/SUBMIT: "archived"/' "$xs/src/machine.js" >"$typo/src/machine.js"
git -C "$typo" add src && git -C "$typo" commit -q -m x
bash "$COLLECT" --repo "$typo" --out "$out/typo.json" >/dev/null
assert_contains "an undeclared xstate target is refused" "$(cat "$out/typo.json")" '"reason": "undeclared-target"'

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
if [[ ! -f "$out/invdir/states.md" ]]; then
  pass "invoke writes no diagram"
else
  fail "invoke wrote a diagram" "present"
fi
assert_contains "invoke names the reason" "$imsg" "unsupported-syntax"

commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m t; }
render_rc() { # <record> <outdir> [renderer args]: sets rc and msg
  local rec="$1" dir="$2"; shift 2
  mkdir -p "$dir"
  set +e
  msg="$(bash "$RENDER" --record "$rec" --out "$dir" "$@" 2>&1)"
  rc=$?
  set -e
}

one="$TEST_TMPDIR/one"
init_repo "$one"
cat >"$one/M.cs" <<'CS'
class M {
  void Wire() {
    var o = new StateMachine<OrderState, OrderTrigger>(OrderState.New);
    var s = new StateMachine<ShipState, ShipTrigger>(ShipState.Idle);
    o.Configure(OrderState.New).Permit(OrderTrigger.Submit, OrderState.Submitted);
    s.Configure(ShipState.Idle).PermitIf(ShipTrigger.Go, ShipState.Moving, () => ready).PermitIf(ShipTrigger.Stop, ShipState.Idle, () => true);
  }
}
CS
commit_all "$one"
bash "$COLLECT" --repo "$one" --generated-on 2026-09-28 --out "$out/one.json" >/dev/null
oblob="$(cat "$out/one.json")"
assert_contains "two machines in one file: first id" "$oblob" '"id":"OrderState"'
assert_contains "two machines in one file: second id" "$oblob" '"id":"ShipState"'
assert_contains "two machines in one file: transitions stay with their machine" "$oblob" '"from":"Idle","entity":"ShipState","to":"Moving","trigger":"Go","guard":"declared"'
assert_contains "two machines in one file: first machine kept" "$oblob" '"from":"New","entity":"OrderState","to":"Submitted"'
assert_contains "high confidence with two machines" "$oblob" '"confidence": "high"'
render_rc "$out/one.json" "$out/onedir"
assert_equals "two entities without --entity exit 3" "$rc" "3"
assert_contains "exit 3 names the first entity" "$msg" "OrderState"
assert_contains "exit 3 names the second entity" "$msg" "ShipState"
assert_contains "exit 3 asks for --entity" "$msg" "pass --entity"
render_rc "$out/one.json" "$out/onedir" --entity ShipState
assert_equals "--entity picks one" "$rc" "0"
assert_contains "--entity summary names the pick" "$msg" "entity=ShipState"
assert_contains "--entity draws the picked machine" "$(cat "$out/onedir/states.md")" "Idle --> Moving: Go [declared]"
assert_not_contains "--entity leaves the other machine out" "$(cat "$out/onedir/states.md")" "Submitted"
render_rc "$out/one.json" "$out/onedir2" --entity Nope
assert_equals "entity not in the record exits 3" "$rc" "3"
assert_contains "entity not in the record is named" "$msg" "entity not in the record: Nope"

sep="$TEST_TMPDIR/sep"
init_repo "$sep"
printf '%s\n' 'var o = new StateMachine<OrderState, OrderTrigger>(OrderState.New);' 'o.Configure(OrderState.New).Permit(OrderTrigger.Submit, OrderState.Submitted);' >"$sep/A.cs"
printf '%s\n' 'var l = new StateMachine<LoneState, LoneTrigger>(LoneState.Start);' >"$sep/B.cs"
commit_all "$sep"
bash "$COLLECT" --repo "$sep" --out "$out/sep.json" >/dev/null
sblob="$(cat "$out/sep.json")"
assert_contains "two machines in separate files: first id" "$sblob" '"id":"OrderState"'
assert_contains "two machines in separate files: second id" "$sblob" '"id":"LoneState"'
assert_contains "an initial state with no way out is a dead end" "$sblob" '"kind":"dead_end","entity":"LoneState","state":"Start"'
render_rc "$out/sep.json" "$out/sepdir"
assert_equals "separate files: two entities exit 3" "$rc" "3"

dup="$TEST_TMPDIR/dup"
init_repo "$dup"
printf '%s\n' 'var a = new StateMachine<OrderState, OrderTrigger>(OrderState.New);' 'a.Configure(OrderState.New);' >"$dup/A.cs"
printf '%s\n' 'var b = new StateMachine<OrderState, OrderTrigger>(OrderState.New);' 'b.Configure(OrderState.New);' >"$dup/B.cs"
commit_all "$dup"
bash "$COLLECT" --repo "$dup" --out "$out/dup.json" >/dev/null
assert_contains "the same entity id twice is refused" "$(cat "$out/dup.json")" '"reason": "duplicate-entity"'

for call in 'PermitDynamic(T.Go, () => S.B)' 'PermitReentryIf(T.Go, () => true)' 'SubstateOf(S.B)' 'InternalTransition(T.Go, t => { })' 'Ignore(T.Go)' 'OnEntry(() => { })' 'OnExit(() => { })'; do
  name="${call%%(*}"
  ur="$TEST_TMPDIR/un-$name"
  init_repo "$ur"
  printf '%s\n' 'var m = new StateMachine<S, T>(S.A);' "m.Configure(S.A).Permit(T.Next, S.B).$call;" 'm.Configure(S.B);' >"$ur/M.cs"
  commit_all "$ur"
  bash "$COLLECT" --repo "$ur" --out "$out/un-$name.json" >/dev/null
  ublob="$(cat "$out/un-$name.json")"
  assert_contains "stateless $name is refused" "$ublob" "\"reason\": \"unsupported-syntax: .$name\""
  assert_contains "stateless $name draws nothing" "$ublob" '"transitions": []'
done

cmp_repo="$TEST_TMPDIR/cmp"
cp -R "$repo" "$cmp_repo"
printf '%s\n' 'class C { bool Done(Order order) { return order.Status == OrderStatus.Shipped; } }' >"$cmp_repo/Cmp.cs"
commit_all "$cmp_repo"
bash "$COLLECT" --repo "$cmp_repo" --out "$out/cmp.json" >/dev/null
assert_contains "a status comparison is not an assignment" "$(cat "$out/cmp.json")" '"confidence": "high"'

beside="$TEST_TMPDIR/beside"
cp -R "$repo" "$beside"
printf '%s\n' 'class C { void Ship(Order order) { order.Status = OrderStatus.Shipped; } }' >"$beside/Ship.cs"
commit_all "$beside"
bash "$COLLECT" --repo "$beside" --out "$out/beside.json" >/dev/null
bblob="$(cat "$out/beside.json")"
assert_contains "ad hoc assignment beside a table still draws" "$bblob" '"status": "drawn"'
assert_contains "ad hoc assignment beside a table lowers confidence" "$bblob" '"confidence": "medium"'
assert_contains "ad hoc assignment beside a table says why" "$bblob" '"reason": "ad-hoc-status-assignments-beside-table"'
render_rc "$out/beside.json" "$out/besidedir"
assert_equals "medium confidence renders" "$rc" "0"
assert_contains "summary carries the medium confidence and reason" "$msg" "reason=ad-hoc-status-assignments-beside-table confidence=medium"
assert_contains "artifact carries the medium confidence" "$(cat "$out/besidedir/states.md")" "Confidence: medium (ad-hoc-status-assignments-beside-table)"

printf 'failed=%s\n' "$FAILED"
exit "$FAILED"
