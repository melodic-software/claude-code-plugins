#!/usr/bin/env bash
# Five request handlers under src/Orders/Handlers, each implementing IRequestHandler<TRequest> and
# registered in src/Orders/Startup.cs, each added by its own feature commit. No paved-path index,
# no recorded boundary rule, no ADR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git src
# shellcheck source=../fixtures/git-history.sh
. "${here}/../fixtures/git-history.sh"

repo_init
mkdir -p src/Orders/Handlers
cat >src/Orders/IRequestHandler.cs <<'CS'
namespace Orders;

public interface IRequestHandler<TRequest>
{
    Task HandleAsync(TRequest request, CancellationToken cancellationToken);
}
CS
cat >src/Orders/Startup.cs <<'CS'
namespace Orders;

public static class Startup
{
    public static void AddOrderHandlers(IServiceCollection services)
    {
    }
}
CS
git add -A
git commit -q -m "feat(orders): handler interface and startup"
for name in PlaceOrder CancelOrder RefundOrder ShipOrder ReturnOrder; do
  cat >"src/Orders/Handlers/${name}Handler.cs" <<CS
namespace Orders.Handlers;

public sealed record ${name}Request(Guid OrderId);

public sealed class ${name}Handler : IRequestHandler<${name}Request>
{
    public Task HandleAsync(${name}Request request, CancellationToken cancellationToken) => Task.CompletedTask;
}
CS
  sed -i "s|^    {\$|    {\n        services.AddScoped<IRequestHandler<${name}Request>, ${name}Handler>();|" src/Orders/Startup.cs
  git add -A
  git commit -q -m "feat(orders): add ${name} handler"
done
