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
assert_contains "interface hop is unresolved with mechanism interface" "$blob" '"resolution":"unresolved","mechanism":"interface"'
assert_not_contains "interface hop does not guess OrdersImpl" "$blob" "OrdersImpl"
handle_line="$(grep -n '_service.Handle' "$repo/src/Transport/OrdersEndpoint.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "concrete hop cites the call site" "$blob" "\"file\":\"src/Transport/OrdersEndpoint.cs\",\"line\":\"$handle_line\""
handle_hop="$(grep -F '"call":"Handle"' "$record")"
assert_contains "field-typed hop cites the call site and the callee" "$handle_hop" "\"file\":\"src/Transport/OrdersEndpoint.cs\",\"line\":\"$handle_line\",\"callee_file\":\"src/Application/OrdersService.cs\",\"callee_line\":\"3\""
assert_contains "a receiver typed by a field resolves statically, across files" "$handle_hop" '"resolution":"statically-resolved","mechanism":"","handoff":"no"'
pub_line="$(grep -n 'Publish<OrderPlaced>' "$repo/src/Application/OrdersService.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "publish cites its call site" "$blob" "\"file\":\"src/Application/OrdersService.cs\",\"line\":\"$pub_line\""
assert_contains "publish is a handoff" "$blob" '"handoff":"yes"'
assert_contains "publish is asynchronous" "$blob" '"sync":"asynchronous"'
assert_contains "publish is an unresolved broker hand-off" "$blob" '"sync":"asynchronous","resolution":"unresolved","mechanism":"broker","handoff":"yes"'
save_line="$(grep -n 'Repository.Save' "$repo/src/Application/OrdersService.cs" | awk -F: 'NR==1{print $1}')"
assert_contains "save cites its call site" "$blob" "\"line\":\"$save_line\""
assert_contains "save is synchronous" "$blob" '"sync":"synchronous"'
assert_contains "trace is complete" "$blob" '"truncated": "no"'

render_out="$(bash "$RENDER" --record "$record" --out "$out")"
assert_equals "render mermaid exits 0" "$?" "0"
md="$(cat "$out/flow.md")"
assert_contains "summary names the entry" "$render_out" "entry=/orders/{id}"
assert_contains "summary splits the unresolved hops" "$render_out" "unresolved=2 external=0 di=1 handoffs=1"
assert_contains "async arrow" "$md" "-->>"
assert_contains "sync arrow" "$md" "->>"
assert_contains "handoff names map-events" "$md" "handoff /architecture:map-events"
assert_contains "unresolved label is on the diagram" "$md" "unresolved"
assert_contains "statically-resolved label is on the diagram" "$md" "statically-resolved"
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

# Hops come in call order: a followed callee's hops sit right after the call that leads to it.
order="$TEST_TMPDIR/order"
init_repo "$order"
mkdir -p "$order/src/Application"
cat >"$order/src/Application/Flow.cs" <<'CS'
namespace Orders.Application;
public class Flow {
    public void Entry(string x) {
        Alpha(x);
        Beta(x);
        _internalService.Run(x);
        publicUrl = Build(x);
        publicApi.Handle(x);
        Bus.Send<Cmd>(x);
        await Bus.Publish<Evt>(x);
    }
    public void Alpha(string x) {
        Gamma(x);
    }
    public void Beta(string x) {
    }
    public void Gamma(string x) {
    }
    public string Build(string x) {
        return x;
    }
}
CS
git -C "$order" add src
git -C "$order" commit --quiet -m "order"
order_record="$TEST_TMPDIR/order.json"
bash "$COLLECT" --repo "$order" --entry "Entry" --out "$order_record" >/dev/null
assert_equals "order collect exits 0" "$?" "0"
order_blob="$(cat "$order_record")"
calls="$(grep -o '"call":"[^"]*"' "$order_record" | sed 's/"call":"//; s/"$//' | tr '\n' ' ')"
assert_equals "hops are in call order" "$calls" "Alpha Gamma Beta Run Build Handle Send<Cmd> Publish<Evt> "
assert_contains "identifier containing a modifier word still yields a hop" "$order_blob" '"call":"Run"'
assert_contains "a modifier-prefixed assignment still yields a hop" "$order_blob" '"call":"Build"'
assert_contains "an unawaited Send is asynchronous" "$order_blob" '"call":"Send<Cmd>"'
assert_contains "a Send hop is an unresolved broker hand-off" "$order_blob" '"sync":"asynchronous","resolution":"unresolved","mechanism":"broker","handoff":"yes"'
no_decl="$(bash "$COLLECT" --repo "$order" --entry "Handle" --out "$TEST_TMPDIR/handle.json" 2>&1)"
assert_equals "a call on publicApi is not a declaration of Handle" "$?" "3"
assert_contains "the Handle entry is not found" "$no_decl" "refused: entry point not found"

# A call binds only through the receiver's declared type. The hop lines of one call.
hops_of() { grep -F "\"call\":\"$2\"" "$1"; }

bind="$TEST_TMPDIR/bind"
init_repo "$bind"
mkdir -p "$bind/src/Application" "$bind/src/Domain" "$bind/src/Infrastructure"
cat >"$bind/src/Application/Checkout.cs" <<'CS'
namespace Shop.Application;
public class Checkout {
    private readonly Dictionary<string, int> _cache;
    private readonly Logger _log;
    private readonly Pricing _pricing;
    private readonly IShipper _shipper;
    private readonly Overloaded _over;
    private readonly Twin _twin;
    public void Run(string id) {
        _cache.Add(id, 1);
        _log.Info(id);
        _pricing.Quote(id);
        this._pricing.Quote(id);
        Console.WriteLine(id);
        string.IsNullOrWhiteSpace(id);
        var names = items.Where(x => x.Ok).ToList();
        var stock = new Stock();
        stock.Reserve(id);
        Stock spare = new();
        Local(id);
        _shipper.Dispatch(id);
        _over.Compute(id);
        _twin.Ping(id);
    }
    public void Local(string id) {
        Audit.Record(id);
    }
}
public class Ledger {
    public void Add(string id, int n) {
        Journal.Append(id);
    }
}
CS
cat >"$bind/src/Infrastructure/Diagnostics.cs" <<'CS'
namespace Shop.Infrastructure;
public class Diagnostics {
    public void Info(string message) {
        Sink.Emit(message);
    }
}
CS
cat >"$bind/src/Domain/Pricing.cs" <<'CS'
namespace Shop.Domain;
public class Pricing {
    public decimal Quote(string id) {
        Tax.Levy(id);
        return 1;
    }
}
CS
cat >"$bind/src/Domain/Tax.cs" <<'CS'
namespace Shop.Domain;
public class Tax {
    public decimal Levy(string id) {
        return 1;
    }
}
CS
cat >"$bind/src/Domain/Stock.cs" <<'CS'
namespace Shop.Domain;
public class Stock {
    public void Reserve(string id) {
    }
}
CS
cat >"$bind/src/Infrastructure/Shipper.cs" <<'CS'
namespace Shop.Infrastructure;
public interface IShipper {
    void Dispatch(string id);
}
public class Shipper : IShipper {
    public void Dispatch(string id) {
        Carrier.Book(id);
    }
}
CS
cat >"$bind/src/Domain/Overloaded.cs" <<'CS'
namespace Shop.Domain;
public class Overloaded {
    public void Compute(string id) {
        Hidden.One(id);
    }
    public void Compute(int n) {
        Hidden.Two(n);
    }
}
CS
cat >"$bind/src/Domain/Twin.cs" <<'CS'
namespace Shop.Domain;
public class Twin {
    public void Ping(string id) {
        Echo.Reply(id);
    }
}
CS
cat >"$bind/src/Infrastructure/Twin.cs" <<'CS'
namespace Shop.Infrastructure;
public class Twin {
    public void Ping(string id) {
        Echo.Reply(id);
    }
}
CS
git -C "$bind" add src
git -C "$bind" commit --quiet -m "bind"
bind_json="$TEST_TMPDIR/bind.json"
bash "$COLLECT" --repo "$bind" --entry "Run" --out "$bind_json" >/dev/null
assert_equals "bind: collect exits 0" "$?" "0"
bind_blob="$(cat "$bind_json")"
outside='"callee_file":"","callee_line":"","sync":"synchronous","resolution":"unresolved","mechanism":'
assert_contains "a dictionary field's Add is an external-call" "$(hops_of "$bind_json" Add)" "$outside\"external-call\""
assert_not_contains "Add is not walked into the unrelated same-file Add" "$bind_blob" "Append"
assert_contains "a Logger field's Info is an external-call" "$(hops_of "$bind_json" Info)" "$outside\"external-call\""
assert_not_contains "Info is not walked into the unrelated Info in another file" "$bind_blob" "Emit"
quote_hops="$(hops_of "$bind_json" Quote)"
assert_contains "a field-typed concrete receiver resolves and cites its class" "$quote_hops" '"callee_file":"src/Domain/Pricing.cs","callee_line":"3","sync":"synchronous","resolution":"statically-resolved"'
assert_equals "a this-qualified receiver resolves the same way" "$(printf '%s\n' "$quote_hops" | grep -c 'statically-resolved')" "2"
assert_contains "the followed callee's own call is a hop" "$bind_blob" '"call":"Levy","file":"src/Domain/Pricing.cs"'
assert_contains "a type name written at the call site resolves" "$(hops_of "$bind_json" Levy)" '"callee_file":"src/Domain/Tax.cs","callee_line":"3","sync":"synchronous","resolution":"statically-resolved"'
assert_contains "a static call on a type outside the tree is an external-call" "$(hops_of "$bind_json" WriteLine)" "$outside\"external-call\""
assert_contains "a call on a predefined type keyword is an external-call" "$(hops_of "$bind_json" IsNullOrWhiteSpace)" "$outside\"external-call\""
assert_not_contains "a target-typed new is not a call" "$bind_blob" '"call":"new"'
assert_contains "a call on an undeclared name has an unknown receiver type" "$(hops_of "$bind_json" Where)" "$outside\"receiver-type-unknown\""
assert_contains "a call chained on a result has an unknown receiver type" "$(hops_of "$bind_json" ToList)" "$outside\"receiver-type-unknown\""
assert_contains "a constructor of a tree class without one is callee-not-in-tree" "$(hops_of "$bind_json" Stock)" "$outside\"callee-not-in-tree\""
assert_contains "a var local initialised with new resolves" "$(hops_of "$bind_json" Reserve)" '"callee_file":"src/Domain/Stock.cs","callee_line":"3","sync":"synchronous","resolution":"statically-resolved"'
assert_contains "an unqualified call resolves in the enclosing class" "$(hops_of "$bind_json" Local)" '"callee_file":"src/Application/Checkout.cs","callee_line":"25","sync":"synchronous","resolution":"statically-resolved"'
assert_contains "the enclosing class's callee is walked" "$(hops_of "$bind_json" Record)" "$outside\"external-call\""
assert_contains "a tree interface is unresolved with mechanism interface" "$(hops_of "$bind_json" Dispatch)" "$outside\"interface\""
assert_not_contains "the interface's implementation is not walked" "$bind_blob" "Book"
assert_contains "overloads are ambiguous" "$(hops_of "$bind_json" Compute)" "$outside\"ambiguous-method\""
assert_not_contains "no overload is walked" "$bind_blob" "Hidden"
assert_contains "a type declared twice is ambiguous" "$(hops_of "$bind_json" Ping)" "$outside\"ambiguous-method\""
assert_not_contains "neither Twin is walked" "$bind_blob" "Echo"
bind_dir="$TEST_TMPDIR/bind-out"
mkdir -p "$bind_dir"
bind_summary="$(bash "$RENDER" --record "$bind_json" --out "$bind_dir")"
assert_contains "summary separates external hops from interface hops" "$bind_summary" "hops=16 truncated=no unresolved=11 external=8 di=1 handoffs=0"

# A receiver reached through a base class, a partial class in another file, or a base method is inferred.
infer="$TEST_TMPDIR/infer"
init_repo "$infer"
mkdir -p "$infer/src/Application" "$infer/src/Domain"
cat >"$infer/src/Application/BaseHandler.cs" <<'CS'
namespace Shop.Application;
public abstract class BaseHandler {
    protected readonly Pricing _pricing;
    public void Log(string id) {
        Trace.Write(id);
    }
}
CS
cat >"$infer/src/Application/OrderHandler.cs" <<'CS'
namespace Shop.Application;
public class OrderHandler : BaseHandler {
    public void Handle(string id) {
        _pricing.Quote(id);
        Log(id);
    }
}
CS
cat >"$infer/src/Application/Part.cs" <<'CS'
namespace Shop.Application;
public partial class Part {
    public void Go(string id) {
        _pricing.Quote(id);
    }
}
CS
cat >"$infer/src/Application/Part.Fields.cs" <<'CS'
namespace Shop.Application;
public partial class Part {
    private readonly Pricing _pricing;
}
CS
cat >"$infer/src/Application/Booking.cs" <<'CS'
namespace Shop.Application;
public class Booking(Pricing pricing, ILogger log) {
    public void Run(string id) {
        pricing.Quote(id);
        log.Info(id);
    }
}
CS
cat >"$infer/src/Domain/Pricing.cs" <<'CS'
namespace Shop.Domain;
public class Pricing {
    public decimal Quote(string id) {
        return 1;
    }
}
CS
git -C "$infer" add src
git -C "$infer" commit --quiet -m "infer"
infer_json="$TEST_TMPDIR/infer.json"
bash "$COLLECT" --repo "$infer" --entry "OrderHandler.Handle" --out "$infer_json" >/dev/null
assert_contains "a field declared in a base class is inferred" "$(hops_of "$infer_json" Quote)" '"callee_file":"src/Domain/Pricing.cs","callee_line":"3","sync":"synchronous","resolution":"inferred"'
assert_contains "a method declared in a base class is inferred" "$(hops_of "$infer_json" Log)" '"callee_file":"src/Application/BaseHandler.cs","callee_line":"4","sync":"synchronous","resolution":"inferred"'
part_json="$TEST_TMPDIR/part.json"
bash "$COLLECT" --repo "$infer" --entry "Part.Go" --out "$part_json" >/dev/null
assert_contains "a field declared in a partial class in another file is inferred" "$(hops_of "$part_json" Quote)" '"resolution":"inferred"'
booking_json="$TEST_TMPDIR/booking.json"
bash "$COLLECT" --repo "$infer" --entry "Booking.Run" --out "$booking_json" >/dev/null
assert_contains "a primary-constructor parameter types its receiver" "$(hops_of "$booking_json" Quote)" '"callee_file":"src/Domain/Pricing.cs","callee_line":"3","sync":"synchronous","resolution":"statically-resolved"'
assert_contains "a primary-constructor interface parameter stays unresolved" "$(hops_of "$booking_json" Info)" '"resolution":"unresolved","mechanism":"interface"'
infer_dir="$TEST_TMPDIR/infer-out"
mkdir -p "$infer_dir"
bash "$RENDER" --record "$infer_json" --out "$infer_dir" >/dev/null
assert_contains "inferred label is on the diagram" "$(cat "$infer_dir/flow.md")" "inferred"

# Entry grammar: Type.Method, an optional HTTP verb, and a refusal that names the accepted forms.
entry_repo="$TEST_TMPDIR/entry"
init_repo "$entry_repo"
mkdir -p "$entry_repo/src/Transport" "$entry_repo/src/Domain"
cat >"$entry_repo/src/Transport/OrdersController.cs" <<'CS'
namespace Shop.Transport;
[Route("api/orders")]
public class OrdersController {
    private readonly Pricing _pricing;
    [HttpGet("/orders/{id}")]
    public IActionResult Get(string id) {
        _pricing.Quote(id);
    }
    [HttpPut("/orders/{id}")]
    public IActionResult Put(string id) {
        _pricing.Adjust(id);
    }
    [HttpPost]
    [Route("/orders")]
    public IActionResult Create(string id) {
        _pricing.Quote(id);
    }
    [Route("/legacy")]
    [HttpGet("/legacy")]
    public IActionResult Legacy(string id) {
        _pricing.Quote(id);
    }
    [Route("/any")]
    public IActionResult Any(string id) {
        _pricing.Adjust(id);
    }
}
CS
cat >"$entry_repo/src/Domain/Pricing.cs" <<'CS'
namespace Shop.Domain;
public class Pricing {
    public decimal Quote(string id) {
        return 1;
    }
    public decimal Adjust(string id) {
        return 2;
    }
}
CS
cat >"$entry_repo/src/Transport/OrderEndpoints.cs" <<'CS'
namespace Shop.Transport;
public static class OrderEndpoints {
    public static void Map(WebApplication app) {
        app.MapGet("/minimal/{id}", Get).WithName("get");
        app.MapPut("/minimal/{id}", Put);
        app.MapPost("/inline", (Pricing p) => { p.Quote("x"); });
    }
    private static IResult Get(string id) {
        Pricing.Quote(id);
    }
    private static IResult Put(string id) {
        Pricing.Adjust(id);
    }
}
public static class Nested {
    public static class Registration {
        public static void Map(WebApplication app) {
            app.MapGet("/nested", Handle);
        }
    }
    private static IResult Handle(string id) {
        Pricing.Quote(id);
    }
}
CS
git -C "$entry_repo" add src
git -C "$entry_repo" commit --quiet -m "entry"
entry_json="$TEST_TMPDIR/entry.json"
run_entry() {
  bash "$COLLECT" --repo "$entry_repo" --entry "$1" --out "$entry_json" 2>&1
}
two="$(run_entry "/orders/{id}")"
assert_equals "one route on two handlers is a refusal" "$?" "3"
assert_contains "the refusal counts the sites" "$two" "matches 2 sites"
assert_contains "the refusal names the accepted forms" "$two" "an HTTP verb and a route (GET /orders/{id}), Type.Method (OrdersService.Handle)"
run_entry "GET /orders/{id}" >/dev/null
assert_equals "a verb selects the GET handler" "$?" "0"
assert_contains "the GET entry is the HttpGet attribute line" "$(cat "$entry_json")" '"entry": {"name":"GET /orders/{id}","file":"src/Transport/OrdersController.cs","line":"5"}'
assert_contains "the GET handler's call is traced" "$(cat "$entry_json")" '"call":"Quote"'
run_entry "put /orders/{id}" >/dev/null
assert_equals "the verb is case-insensitive" "$?" "0"
assert_contains "the PUT entry is the HttpPut attribute line" "$(cat "$entry_json")" '"entry": {"name":"put /orders/{id}","file":"src/Transport/OrdersController.cs","line":"9"}'
assert_contains "the PUT handler's call is traced" "$(cat "$entry_json")" '"call":"Adjust"'
missing_verb="$(run_entry "DELETE /orders/{id}")"
assert_equals "a verb no handler takes is not found" "$?" "3"
assert_contains "a verb no handler takes says so" "$missing_verb" "refused: entry point not found"
run_entry "POST /orders" >/dev/null
assert_equals "an Http verb attribute beside a Route attribute selects the handler" "$?" "0"
run_entry "GET /orders" >/dev/null
assert_equals "the Route handler does not take another verb" "$?" "3"
run_entry "/legacy" >/dev/null
assert_equals "Route and HttpGet on one method are one site" "$?" "0"
run_entry "DELETE /any" >/dev/null
assert_equals "a handler that names no verb takes any" "$?" "0"
two_maps="$(run_entry "/minimal/{id}")"
assert_equals "one Map route on two handlers is a refusal" "$?" "3"
assert_contains "the Map refusal names both Map lines" "$two_maps" "OrderEndpoints.cs:4 src/Transport/OrderEndpoints.cs:5"
run_entry "GET /minimal/{id}" >/dev/null
assert_equals "a verb selects the MapGet call" "$?" "0"
assert_contains "the MapGet entry cites the Map line and traces the handler it names" "$(cat "$entry_json")" '"entry": {"name":"GET /minimal/{id}","file":"src/Transport/OrderEndpoints.cs","line":"4"}'
assert_contains "the MapGet handler is Get" "$(cat "$entry_json")" '"call":"Quote"'
assert_not_contains "the MapGet trace does not enter Put" "$(cat "$entry_json")" '"call":"Adjust"'
run_entry "PUT /minimal/{id}" >/dev/null
assert_equals "a verb selects the MapPut call" "$?" "0"
assert_contains "the MapPut entry cites its own Map line" "$(cat "$entry_json")" '"entry": {"name":"PUT /minimal/{id}","file":"src/Transport/OrderEndpoints.cs","line":"5"}'
assert_contains "the MapPut handler is Put" "$(cat "$entry_json")" '"call":"Adjust"'
assert_not_contains "the MapPut trace does not enter Get" "$(cat "$entry_json")" '"call":"Quote"'
run_entry "/nested" >/dev/null
assert_equals "a Map handler declared in the enclosing outer class is bound" "$?" "0"
assert_contains "the outer-class handler is traced" "$(cat "$entry_json")" '"call":"Quote"'
lambda="$(run_entry "POST /inline")"
assert_equals "a lambda handler is a refusal" "$?" "3"
assert_contains "the lambda refusal points at Type.Method" "$lambda" "Name the handler as Type.Method"
lambda_verb="$(run_entry "DELETE /inline")"
assert_contains "a verb the lambda route does not take is not found" "$lambda_verb" "refused: entry point not found"
class_route="$(run_entry "api/orders")"
assert_equals "a class-level route is not bound to the first action" "$?" "3"
assert_contains "a class-level route is not found" "$class_route" "refused: entry point not found"
run_entry "OrdersController.Put" >/dev/null
assert_equals "Type.Method selects the method" "$?" "0"
assert_contains "the Type.Method entry is the declaration line" "$(cat "$entry_json")" '"entry": {"name":"OrdersController.Put","file":"src/Transport/OrdersController.cs","line":"10"}'
assert_contains "the Type.Method trace follows the method" "$(cat "$entry_json")" '"call":"Adjust"'
run_entry "Pricing.Quote" >/dev/null
assert_equals "Type.Method selects a method that calls nothing" "$?" "0"
no_type="$(run_entry "Nope.Put")"
assert_equals "an unknown type is not found" "$?" "3"
assert_contains "an unknown type says so" "$no_type" "refused: entry point not found"
no_method="$(run_entry "OrdersController.Missing")"
assert_equals "a method the type lacks is not found" "$?" "3"
assert_contains "a method the type lacks says so" "$no_method" "refused: entry point not found"
run_entry "Quote" >/dev/null
assert_equals "a unique bare method name still works" "$?" "0"
bad_form="$(run_entry "GET Quote")"
assert_equals "a verb without a route is refused" "$?" "3"
assert_contains "a verb without a route names the accepted forms" "$bad_form" "Accepted entry forms"
bad_form="$(run_entry "Orders Controller.Put")"
assert_equals "an entry with a space and no verb is refused" "$?" "3"
assert_contains "the malformed entry names the accepted forms" "$bad_form" "Accepted entry forms"
assert_not_contains "no refusal advises a file the grammar cannot name" "$two$bad_form" "name one file"

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
