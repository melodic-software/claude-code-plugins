#!/usr/bin/env bash
# Short and dotted contract names. Contracts/OrderPlaced.cs declares Contracts.OrderPlaced;
# OrderService in Shop.Orders publishes it by its short name through `using Contracts;`, its consumer
# is registered with AddConsumer, and InventoryReport is a class nothing publishes, sends or
# consumes. Shop/Contracts.cs declares Shop.Contracts.InvoiceIssued; Publisher in namespace Shop
# publishes Contracts.InvoiceIssued (resolvable only through the enclosing namespace) and
# Vendor.Sdk.Ping, which is declared nowhere. The convention home declares architecture_dir
# docs/architecture.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"
mkdir -p src/Contracts src/Orders src/Shop

cat >src/Contracts/OrderPlaced.cs <<'CS'
namespace Contracts;

public record OrderPlaced(int OrderId);
CS

cat >src/Orders/OrderService.cs <<'CS'
using System.Threading.Tasks;
using Contracts;
using MassTransit;

namespace Shop.Orders;

public class OrderService(IPublishEndpoint bus)
{
    public Task Place() => bus.Publish(new OrderPlaced(42));
}
CS

cat >src/Orders/OrderPlacedConsumer.cs <<'CS'
using System.Threading.Tasks;
using Contracts;
using MassTransit;

namespace Shop.Orders;

public class OrderPlacedConsumer : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}
CS

cat >src/Orders/InventoryReport.cs <<'CS'
namespace Shop.Orders;

public class InventoryReport
{
    public int Count { get; set; }
}
CS

cat >src/Orders/Startup.cs <<'CS'
using MassTransit;
using Microsoft.Extensions.DependencyInjection;

namespace Shop.Orders;

public static class Startup
{
    public static void AddBus(IServiceCollection services) =>
        services.AddMassTransit(x => x.AddConsumer<OrderPlacedConsumer>());
}
CS

cat >src/Shop/Contracts.cs <<'CS'
namespace Shop.Contracts;

public record InvoiceIssued(int InvoiceId);
CS

cat >src/Shop/Publisher.cs <<'CS'
using System.Threading.Tasks;
using MassTransit;

namespace Shop;

public class Publisher(IPublishEndpoint bus)
{
    public async Task Run()
    {
        await bus.Publish<Contracts.InvoiceIssued>(new { InvoiceId = 7 });
        await bus.Publish<Vendor.Sdk.Ping>(new { });
    }
}
CS

cat >src/Shop/InvoiceIssuedConsumer.cs <<'CS'
using System.Threading.Tasks;
using MassTransit;
using Shop.Contracts;

namespace Shop.Billing;

public class InvoiceIssuedConsumer : IConsumer<InvoiceIssued>
{
    public Task Consume(ConsumeContext<InvoiceIssued> context) => Task.CompletedTask;
}
CS

git add -A
git commit -q -m "Order and invoice contracts, publishers and consumers"
mkdir -p docs/architecture
