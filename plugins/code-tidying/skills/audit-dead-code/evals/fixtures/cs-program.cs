using System;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using Fixture.Orders;

var service = new OrderService();
service.Submit(1);

var hook = "On" + "Audit";
typeof(OrderService).GetMethod(hook, BindingFlags.NonPublic | BindingFlags.Instance)?.Invoke(service, null);

foreach (var type in typeof(OrderService).Assembly.GetTypes()
    .Where(t => typeof(IRequestHandler).IsAssignableFrom(t) && !t.IsInterface))
{
    ((IRequestHandler)Activator.CreateInstance(type)!).Handle();
}

Console.WriteLine(JsonSerializer.Serialize(new OrderPlaced()));
