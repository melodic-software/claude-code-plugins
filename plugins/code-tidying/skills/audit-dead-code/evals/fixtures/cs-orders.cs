// Trap corpus for the grep lane's C# pass. Each declaration's role is listed
// in context/lanes.md, never here: a name in this comment would save it.
namespace Fixture.Orders;

public interface IRequestHandler
{
    void Handle();
}

public sealed class OrderService
{
    private readonly int _retryLimit = 3;
    private int _staleCounter;

    public int Submit(int quantity)
    {
        return QuantityRules.Clamp(Normalize(quantity)) * _retryLimit;
    }

    private int Normalize(int quantity) => quantity < 0 ? 0 : quantity;

    private int Clamp(int quantity) => quantity;

    private string FormatLegacyOrder(int orderId)
    {
        return "legacy-" + orderId;
    }

    private void OnAudit()
    {
    }
}

internal static class QuantityRules
{
    internal static int Clamp(int value) => value > 100 ? 100 : value;
}

internal sealed class LegacyOrderExporter
{
}

internal sealed class AuditRequestHandler : IRequestHandler
{
    public void Handle()
    {
    }
}

public sealed record OrderPlaced
{
    public string Sku { get; init; } = "";
}
