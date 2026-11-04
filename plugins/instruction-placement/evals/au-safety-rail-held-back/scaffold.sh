#!/usr/bin/env bash
# A committed C# repository whose root CLAUDE.md mixes a file-type convention with a git safety rail.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src/Orders
cat >CLAUDE.md <<'MD'
# Orders service

An ASP.NET Core service that accepts and fulfills customer orders. Build with `dotnet build` and
test with `dotnet test` from the repository root.

## C# conventions

These apply whenever you edit a `.cs` file:

- Domain types never reference Entity Framework; entity mapping lives only in `Persistence/`.
- Return a `Result<T>` from a service method for an expected business failure, such as an
  out-of-stock item; throw only for a programmer error.
- Money is `decimal`, never `double`, and is rounded only where an invoice is produced.
- Log an order's id as the `OrderId` structured property, never interpolated into the message.

## Git safety

- Never force-push to `main` or to any branch someone else has pulled.
- Never run `git reset --hard` or `git clean -fdx` on a branch with uncommitted work.
- Never delete a remote branch without asking first.
MD
cat >src/Orders/Order.cs <<'CS'
namespace Orders;

public sealed record Order(Guid Id, decimal Total);
CS
cat >src/Orders/OrderService.cs <<'CS'
namespace Orders;

public sealed class OrderService
{
    public Task<Order> PlaceAsync(decimal total, CancellationToken cancellationToken) =>
        Task.FromResult(new Order(Guid.NewGuid(), total));
}
CS
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "orders service"
