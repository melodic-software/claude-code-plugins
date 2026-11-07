#!/usr/bin/env bash
# Billing publishes Billing.Contracts.OrderPlaced; Shipping consumes a different type,
# Shipping.Contracts.OrderPlaced. Same short name, two messages, and neither side has a
# partner. Billing also publishes a variable whose type the scan cannot resolve, sends
# RefundRequested, a type declared nowhere, and sends Billing.Contracts.ChargeCard, which nothing
# consumes. The convention home declares architecture_dir docs/architecture and
# landscape_dialect structurizr.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh" --landscape structurizr
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

    public async Task Complete(int orderId, object audit, ISendEndpoint endpoint)
    {
        await _bus.Publish(new OrderPlaced(orderId));
        await _bus.Publish(audit);
        await endpoint.Send(new RefundRequested(orderId));
        await endpoint.Send<ChargeCard>(new { OrderId = orderId });
    }
}
CS

cat >src/Billing/ChargeCard.cs <<'CS'
namespace Billing.Contracts;

public record ChargeCard(int OrderId);
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
