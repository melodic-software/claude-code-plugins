#!/usr/bin/env bash
# Billing publishes Billing.Contracts.OrderPlaced; Shipping consumes a different type,
# Shipping.Contracts.OrderPlaced. Same short name, two messages, and neither side has a
# partner. Billing also publishes a variable whose type the scan cannot resolve.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/Billing src/Shipping

cat >src/Billing/OrderPlaced.cs <<'CS'
namespace Billing.Contracts;

public record OrderPlaced(int OrderId);
CS

cat >src/Billing/CheckoutService.cs <<'CS'
using System.Threading.Tasks;
using Billing.Contracts;
using MassTransit;

namespace Billing;

public class CheckoutService
{
    private readonly IPublishEndpoint _bus;

    public CheckoutService(IPublishEndpoint bus) => _bus = bus;

    public async Task Complete(int orderId, object audit)
    {
        await _bus.Publish(new OrderPlaced(orderId));
        await _bus.Publish(audit);
    }
}
CS

cat >src/Shipping/OrderPlaced.cs <<'CS'
namespace Shipping.Contracts;

public record OrderPlaced(int OrderId, string Address);
CS

cat >src/Shipping/OrderPlacedConsumer.cs <<'CS'
using System.Threading.Tasks;
using MassTransit;
using Shipping.Contracts;

namespace Shipping;

public class OrderPlacedConsumer : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}
CS

git add -A
git commit -q -m "Billing publisher and Shipping consumer"
mkdir -p docs/architecture
