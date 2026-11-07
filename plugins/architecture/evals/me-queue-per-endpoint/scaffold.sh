#!/usr/bin/env bash
# Setup.cs binds OrderHandler and BillingHandler on ReceiveEndpoint("orders"), AuditHandler on
# ReceiveEndpoint("audit"), then registers LateHandler with AddConsumer outside any endpoint and
# publishes OrderPlaced. All four handlers consume OrderPlaced and are declared below the setup.
# The convention home declares architecture_dir docs/architecture.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git AGENTS.md docs src
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
bash "${here}/../fixtures/convention-home.sh"
mkdir -p src/Orders

cat >src/Orders/OrderPlaced.cs <<'CS'
namespace Orders.Contracts;

public record OrderPlaced(int OrderId);
CS

cat >src/Orders/Setup.cs <<'CS'
using System.Threading.Tasks;
using MassTransit;
using Microsoft.Extensions.DependencyInjection;
using Orders.Contracts;

namespace Orders;

public static class Setup
{
    public static void AddBus(IServiceCollection services) =>
        services.AddMassTransit(x =>
        {
            x.UsingRabbitMq((ctx, cfg) =>
            {
                cfg.ReceiveEndpoint("orders", e => { e.ConfigureConsumer<OrderHandler>(ctx); e.ConfigureConsumer<BillingHandler>(ctx); });
                cfg.ReceiveEndpoint("audit", e => e.ConfigureConsumer<AuditHandler>(ctx));
            });
            x.AddConsumer<LateHandler>();
        });

    public static Task Announce(IPublishEndpoint bus) => bus.Publish(new OrderPlaced(1));
}

public class OrderHandler : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}

public class BillingHandler : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}

public class AuditHandler : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}

public class LateHandler : IConsumer<OrderPlaced>
{
    public Task Consume(ConsumeContext<OrderPlaced> context) => Task.CompletedTask;
}
CS

git add -A
git commit -q -m "Order consumers on two receive endpoints"
mkdir -p docs/architecture
