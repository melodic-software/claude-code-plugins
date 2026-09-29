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
cat >"$REPO/src/Billing/Contracts/NobodySent.cs" <<'EOF'
namespace Billing.Contracts;
public record NobodySent;
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
assert_contains "unresolved publish is kept" "$rec" '{"from":"src/Api/Publisher.cs","to":"-","kind":"publish","resolution":"unresolved","file":"src/Api/Publisher.cs","line":8,'
assert_contains "unresolved publish is a finding" "$rec" '"detail":"unresolved publish - src/Api/Publisher.cs:8"'
assert_not_contains "billing order is not an orphan publisher" "$rec" '"kind":"orphan-publisher","contract":"Billing.Contracts.OrderPlaced"'
assert_not_contains "a consumer class is not a message" "$rec" '{"id":"Billing.Worker'
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" >"$OUT/render.out"
assert_equals "render exits 0" "$?" "0"
md="$(cat "$OUT/events.md")"
assert_contains "broadcast is dotted" "$md" "-.->"
assert_contains "point-to-point is solid" "$md" "-->"
assert_contains "handoff line is keyed by file and line" "$md" "handoff: map-events contract=Billing.Contracts.OrderPlaced direction=publish file=src/Api/Publisher.cs line="
assert_contains "findings survive the diagram" "$md" "orphan-consumer"
assert_contains "summary counts only used messages" "$(cat "$OUT/render.out")" "events: messages=4 publishers=3 consumers=3 unresolved=1"
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" --unrouted-only >"$OUT/unrouted.out"
assert_contains "unrouted filter is reported" "$(cat "$OUT/unrouted.out")" "unrouted_only=yes"
assert_contains "findings remain when filtered" "$(cat "$OUT/events.md")" "orphan-publisher"
bash "$RENDER" --record "$OUT/events.json" --out "$OUT" --dialect structurizr >/dev/null 2>&1
rc=$?
assert_equals "no dialect option" "$rc" "2"
assert_equals "no structurizr file" "$(ls "$OUT"/events.dsl 2>/dev/null)" ""

# Short names, file-scoped namespaces, registrations, and a dynamic send.
SHOP="$TEST_TMPDIR/shop"
mkdir -p "$SHOP/src/Contracts" "$SHOP/src/Legacy" "$SHOP/src/Orders"
cat >"$SHOP/src/Contracts/OrderPlaced.cs" <<'EOF'
namespace Contracts;
public record OrderPlaced(int Id);
EOF
cat >"$SHOP/src/Legacy/OrderPlaced.cs" <<'EOF'
namespace Legacy;
public record OrderPlaced(int Id);
EOF
cat >"$SHOP/src/Orders/OrderService.cs" <<'EOF'
using Contracts;
namespace Shop.Orders;
public class OrderService
{
    public async Task Place(IBus bus, ISendEndpoint endpoint)
    {
        await bus.Publish(new OrderPlaced(42));
        await endpoint.Send(new X());
    }
}
EOF
cat >"$SHOP/src/Orders/OrderPlacedConsumer.cs" <<'EOF'
using Contracts;
namespace Shop.Orders;
public class OrderPlacedConsumer : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}
EOF
cat >"$SHOP/src/Orders/Ambiguous.cs" <<'EOF'
namespace Shop.Audit;
public class Auditor
{
    public void Run(IBus bus) => bus.Publish(new OrderPlaced(1));
}
EOF
cat >"$SHOP/src/Orders/Registration.cs" <<'EOF'
namespace Shop.Orders;
public static class Registration
{
    public static void Add(IBusRegistrationConfigurator x)
    {
        x.AddConsumer<OrderPlacedConsumer>();
        x.UsingRabbitMq((ctx, cfg) => cfg.ReceiveEndpoint("orders", e => e.ConfigureConsumer<OrderPlacedConsumer>(ctx)));
    }
}
EOF
git -C "$SHOP" init -q
git -C "$SHOP" config user.email "fixture@example.invalid"
git -C "$SHOP" config user.name "Fixture"
git -C "$SHOP" config commit.gpgsign false
git -C "$SHOP" add -A
git -C "$SHOP" commit -q -m fixture
bash "$COLLECT" --repo "$SHOP" --generated-on 2026-09-28 --out "$OUT/shop.json"
assert_equals "shop collect exits 0" "$?" "0"
shop="$(cat "$OUT/shop.json")"
assert_contains "message record cites path and integer line" "$shop" '{"id":"Contracts.OrderPlaced","name":"OrderPlaced","file":"src/Contracts/OrderPlaced.cs","line":2}'
assert_equals "every line field is an integer" "$(grep -c '"line":[^0-9]' "$OUT/shop.json")" "0"
assert_not_contains "file-scoped namespace drops the semicolon" "$shop" ';.'
assert_contains "short-name publish resolves through using" "$shop" '{"from":"src/Orders/OrderService.cs","to":"Contracts.OrderPlaced","kind":"publish","resolution":"static","file":"src/Orders/OrderService.cs","line":7,'
assert_contains "short-name consumer resolves through using" "$shop" '{"from":"src/Orders/OrderPlacedConsumer.cs","to":"Contracts.OrderPlaced","kind":"consume","resolution":"static","file":"src/Orders/OrderPlacedConsumer.cs","line":3,"queue":"orders",'
assert_not_contains "no orphan for the published message" "$shop" '"kind":"orphan-'
assert_not_contains "a registered consumer is not a contract" "$shop" '"to":"Shop.Orders'
assert_not_contains "a registered consumer is not a message" "$shop" '{"id":"Shop.Orders'
assert_not_contains "a service class is not a message" "$shop" '{"id":"Shop.Orders'
assert_not_contains "an unused type is not a message" "$shop" '{"id":"Legacy'
assert_contains "dynamic send is an unresolved edge" "$shop" '{"from":"src/Orders/OrderService.cs","to":"-","kind":"send","resolution":"unresolved","file":"src/Orders/OrderService.cs","line":8,'
assert_contains "an ambiguous short name stays unresolved" "$shop" '"detail":"unresolved publish OrderPlaced src/Orders/Ambiguous.cs:4"'
assert_contains "dynamic send is a finding" "$shop" '{"kind":"unresolved","contract":"-","detail":"unresolved send X src/Orders/OrderService.cs:8"}'

# Dotted names resolve against declared types, never verbatim.
DOTS="$TEST_TMPDIR/dots"
mkdir -p "$DOTS/src"
cat >"$DOTS/src/Contracts.cs" <<'EOF'
namespace Shop.Contracts;
public record OrderPlaced;
public record Refund;
EOF
cat >"$DOTS/src/Publisher.cs" <<'EOF'
namespace Shop;
public class Publisher
{
    public void Run(IBus bus)
    {
        bus.Publish<Contracts.OrderPlaced>(new Contracts.OrderPlaced());
        bus.Publish<global::Shop.Contracts.Refund>(new global::Shop.Contracts.Refund());
        bus.Publish<global::Contracts.OrderPlaced>(new Contracts.OrderPlaced());
        bus.Publish<Vendor.Sdk.Ping>(new Vendor.Sdk.Ping());
    }
}
EOF
cat >"$DOTS/src/Consumers.cs" <<'EOF'
using Shop.Contracts;
namespace Shop.Worker;
public class OrderHandler : IConsumer<OrderPlaced> {}
public class RefundHandler : IConsumer<Refund> {}
public class PingHandler : IConsumer<Vendor.Sdk.Ping> {}
EOF
git -C "$DOTS" init -q
git -C "$DOTS" config user.email "fixture@example.invalid"
git -C "$DOTS" config user.name "Fixture"
git -C "$DOTS" config commit.gpgsign false
git -C "$DOTS" add -A
git -C "$DOTS" commit -q -m fixture
bash "$COLLECT" --repo "$DOTS" --generated-on 2026-09-28 --out "$OUT/dots.json"
assert_equals "dots collect exits 0" "$?" "0"
dots="$(cat "$OUT/dots.json")"
assert_contains "a dotted name resolves through the enclosing namespace" "$dots" '"to":"Shop.Contracts.OrderPlaced","kind":"publish","resolution":"static"'
assert_contains "the short-name consumer joins the same contract" "$dots" '"to":"Shop.Contracts.OrderPlaced","kind":"consume","resolution":"static"'
assert_contains "a global:: name resolves as written" "$dots" '"to":"Shop.Contracts.Refund","kind":"publish","resolution":"static"'
assert_contains "global:: skips namespace prefixes" "$dots" '"detail":"unresolved publish global::Contracts.OrderPlaced src/Publisher.cs:8"'
assert_contains "an undeclared dotted publish is unresolved" "$dots" '"detail":"unresolved publish Vendor.Sdk.Ping src/Publisher.cs:9"'
assert_contains "an undeclared dotted consumer is unresolved" "$dots" '"detail":"unresolved consume Vendor.Sdk.Ping src/Consumers.cs:5"'
assert_not_contains "no orphan from a dotted name" "$dots" '"kind":"orphan-'
assert_not_contains "an undeclared dotted name is not a message" "$dots" '{"id":"Vendor'

# A ReceiveEndpoint queue holds for its own call only.
QUEUES="$TEST_TMPDIR/queues"
mkdir -p "$QUEUES/src"
cat >"$QUEUES/src/Setup.cs" <<'EOF'
namespace Shop;
public static class Setup
{
    public static void Add(IBusRegistrationConfigurator x, IBus bus)
    {
        x.AddConsumer<AuditHandler>();
        x.UsingRabbitMq((ctx, cfg) =>
        {
            cfg.ReceiveEndpoint("orders", e =>
            {
                e.ConfigureConsumer<OrderHandler>(ctx);
                e.ConfigureConsumer<BillingHandler>(ctx);
                bus.Publish<OrderPlaced>(new OrderPlaced());
            });
            cfg.ReceiveEndpoint("audit", e => e.ConfigureConsumer<AuditHandler>(ctx));
            x.AddConsumer<LateHandler>();
        });
    }
}
public class OrderHandler : IConsumer<OrderPlaced> {}
public class BillingHandler : IConsumer<OrderPlaced> {}
public class AuditHandler : IConsumer<OrderPlaced> {}
public class LateHandler : IConsumer<OrderPlaced> {}
public record OrderPlaced;
EOF
git -C "$QUEUES" init -q
git -C "$QUEUES" config user.email "fixture@example.invalid"
git -C "$QUEUES" config user.name "Fixture"
git -C "$QUEUES" config commit.gpgsign false
git -C "$QUEUES" add -A
git -C "$QUEUES" commit -q -m fixture
bash "$COLLECT" --repo "$QUEUES" --generated-on 2026-09-28 --out "$OUT/queues.json"
assert_equals "queues collect exits 0" "$?" "0"
queues="$(cat "$OUT/queues.json")"
assert_equals "two consumers sit on the orders endpoint" "$(grep '"kind":"consume"' "$OUT/queues.json" | grep -c '"queue":"orders"')" "2"
assert_equals "one consumer sits on the audit endpoint" "$(grep '"kind":"consume"' "$OUT/queues.json" | grep -c '"queue":"audit"')" "1"
assert_equals "a registration after the endpoint gets no queue" "$(grep '"kind":"consume"' "$OUT/queues.json" | grep -c '"queue":"-"')" "1"
assert_equals "a publish inside an endpoint carries no queue" "$(grep '"kind":"publish"' "$OUT/queues.json" | grep -c '"queue":"-"')" "1"
assert_contains "competing consumers share a message and a queue" "$queues" '{"kind":"competing","contract":"Shop.OrderPlaced","detail":"2 consumers on queue orders"}'
assert_not_contains "the audit queue has one consumer" "$queues" 'on queue audit'

cat >"$TEST_TMPDIR/bad.json" <<'EOF'
{ "schema_version": 1, "messages": [{"id":"a"}], "edges": [], "findings": [] }
EOF
set +e
bash "$RENDER" --record "$TEST_TMPDIR/bad.json" --out "$OUT" >/dev/null 2>"$OUT/bad.err"
rc=$?
set +e
assert_equals "bad layout exits 1" "$rc" "1"

# A tab inside a generic argument must not shift the internal TSV fields and
# forge record keys.
TABS="$TEST_TMPDIR/tabs"
mkdir -p "$TABS/src"
printf 'namespace T;\npublic class P { void Go() { bus.Publish<X\t1\tinjected\t-\t9\tstatic\tforged>(); } }\n' >"$TABS/src/P.cs"
git -C "$TABS" init -q
git -C "$TABS" config user.email "fixture@example.invalid"
git -C "$TABS" config user.name "Fixture"
git -C "$TABS" config commit.gpgsign false
git -C "$TABS" add -A
git -C "$TABS" commit -q -m fixture
bash "$COLLECT" --repo "$TABS" --generated-on 2026-09-28 --out "$OUT/tabs.json"
assert_equals "tab fixture collect exits 0" "$?" "0"
tabs="$(cat "$OUT/tabs.json")"
assert_not_contains "a tab in source does not forge a file field" "$tabs" '"file":"injected"'
assert_contains "the edge still cites the real file" "$tabs" '"file":"src/P.cs","line":2,'
assert_equals "every line field is still an integer" "$(grep -c '"line":[^0-9]' "$OUT/tabs.json")" "0"

printf 'cases=%s failed=%s\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
