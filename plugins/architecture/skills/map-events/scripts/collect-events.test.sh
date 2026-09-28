#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-events.sh"
RENDER="$SCRIPT_DIR/render-events.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASE_NUM=$((CASE_NUM + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2; }
assert_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected [$3] in [$2]" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "unexpected [$3]" ;; *) pass "$1" ;; esac; }
assert_equals() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3] got [$2]"; fi; }

REPO="$TEST_TMPDIR/bus"
mkdir -p "$REPO/src/Billing/Contracts" "$REPO/src/Shipping/Contracts" "$REPO/src/Api" "$REPO/src/Worker"
cat >"$REPO/src/Billing/Contracts/OrderPlaced.cs" <<'EOF'
namespace Billing.Contracts;
public record OrderPlaced;
EOF
cat >"$REPO/src/Shipping/Contracts/OrderPlaced.cs" <<'EOF'
namespace Shipping.Contracts;
public record OrderPlaced;
EOF
cat >"$REPO/src/Billing/Contracts/ChargeCard.cs" <<'EOF'
namespace Billing.Contracts;
public record ChargeCard;
EOF
cat >"$REPO/src/Api/Publisher.cs" <<'EOF'
namespace Billing.Api;
public class Publisher
{
    public void Run(IBus bus, object message)
    {
        bus.Publish<Billing.Contracts.OrderPlaced>(new Billing.Contracts.OrderPlaced());
        bus.Send<Billing.Contracts.ChargeCard>(new Billing.Contracts.ChargeCard());
        bus.Publish(message);
    }
}
EOF
cat >"$REPO/src/Worker/Consumers.cs" <<'EOF'
namespace Billing.Worker;
public class OrderHandler : IConsumer<Billing.Contracts.OrderPlaced>
{
    public void Consume() {}
}
public class ShippingHandler : IConsumer<Shipping.Contracts.OrderPlaced>
{
    public void Consume() {}
}
public class LoneHandler : IConsumer<Billing.Contracts.NobodySent>
{
    public void Consume() {}
}
EOF
git -C "$REPO" init -q
git -C "$REPO" config user.email "fixture@example.invalid"
git -C "$REPO" config user.name "Fixture"
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" add -A
git -C "$REPO" commit -q -m fixture
OUT="$TEST_TMPDIR/out"
mkdir -p "$OUT"
bash "$COLLECT" --repo "$REPO" --generated-on 2026-09-28 --out "$OUT/events.json"
assert_equals "collect exits 0" "$?" "0"
rec="$(cat "$OUT/events.json")"
assert_contains "publish cites the call" "$rec" '"file":"src/Api/Publisher.cs"'
assert_contains "consumer cites the registration" "$rec" '"file":"src/Worker/Consumers.cs"'
assert_contains "billing order is a contract" "$rec" 'Billing.Contracts.OrderPlaced'
assert_contains "shipping order is a different contract" "$rec" 'Shipping.Contracts.OrderPlaced'
assert_contains "orphan publisher for the send with no consumer" "$rec" '"kind":"orphan-publisher","contract":"Billing.Contracts.ChargeCard"'
assert_contains "orphan consumer for shipping" "$rec" '"kind":"orphan-consumer","contract":"Shipping.Contracts.OrderPlaced"'
assert_contains "orphan consumer for nobody" "$rec" '"kind":"orphan-consumer","contract":"Billing.Contracts.NobodySent"'
assert_contains "unresolved publish is kept" "$rec" '"kind":"unresolved-publish"'
assert_not_contains "billing order is not an orphan publisher" "$rec" '"kind":"orphan-publisher","contract":"Billing.Contracts.OrderPlaced"'
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" --dialect mermaid >"$OUT/render.out"
assert_equals "render exits 0" "$?" "0"
md="$(cat "$OUT/events.md")"
assert_contains "broadcast is dotted" "$md" "-.->"
assert_contains "point-to-point is solid" "$md" "-->"
assert_contains "handoff form for map-flow" "$md" "handoff: map-events contract=Billing.Contracts.OrderPlaced direction=publish file=src/Api/Publisher.cs line="
assert_contains "findings survive the diagram" "$md" "orphan-consumer"
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" --dialect mermaid --unrouted-only >"$OUT/unrouted.out"
assert_contains "unrouted filter is reported" "$(cat "$OUT/unrouted.out")" "unrouted_only=yes"
assert_contains "findings remain when filtered" "$(cat "$OUT/events.md")" "orphan-publisher"
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" --dialect structurizr >/dev/null
assert_contains "structurizr tags broadcast" "$(cat "$OUT/events.dsl")" "Broadcast"

cat >"$TEST_TMPDIR/bad.json" <<'EOF'
{ "schema_version": 1, "messages": [{"id":"a"}], "edges": [], "findings": [] }
EOF
set +e
bash "$RENDER" --record "$TEST_TMPDIR/bad.json" --out "$OUT" >/dev/null 2>"$OUT/bad.err"
rc=$?
set +e
assert_equals "bad layout exits 1" "$rc" "1"

printf 'cases=%s failed=%s\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
