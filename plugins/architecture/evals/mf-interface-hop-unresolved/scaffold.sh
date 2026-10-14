#!/usr/bin/env bash
# OrdersController.Place calls the service through an interface, then publishes an event.
# OrderService is the only class that implements IOrderService, and it calls the repository.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src/Controllers src/Application src/Infrastructure

cat >src/Controllers/OrdersController.cs <<'CS'
using System.Threading.Tasks;
using MassTransit;
using Microsoft.AspNetCore.Mvc;

namespace Shop.Controllers;

public class OrdersController : ControllerBase
{
    private readonly IOrderService _service;
    private readonly IPublishEndpoint _bus;

    public OrdersController(IOrderService service, IPublishEndpoint bus)
    {
        _service = service;
        _bus = bus;
    }

    [HttpPost("/orders")]
    public async Task<IActionResult> Place(PlaceOrder command)
    {
        var id = _service.Place(command);
        await _bus.Publish<OrderPlaced>(new { OrderId = id });
        return Ok(id);
    }
}
CS

cat >src/Application/OrderService.cs <<'CS'
namespace Shop.Application;

public interface IOrderService
{
    int Place(PlaceOrder command);
}

public class OrderService : IOrderService
{
    private readonly OrderRepository _repo;

    public OrderService(OrderRepository repo)
    {
        _repo = repo;
    }

    public int Place(PlaceOrder command)
    {
        return _repo.Save(command);
    }
}
CS

cat >src/Infrastructure/OrderRepository.cs <<'CS'
namespace Shop.Infrastructure;

public class OrderRepository
{
    public int Save(PlaceOrder command)
    {
        return 42;
    }
}
CS

git add -A
git commit -q -m "Orders endpoint, service and repository"
mkdir -p docs/architecture
