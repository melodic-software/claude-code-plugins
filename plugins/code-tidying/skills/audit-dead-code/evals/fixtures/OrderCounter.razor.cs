using Microsoft.AspNetCore.Components;

namespace Fixture.Orders;

public partial class OrderCounter
{
    [Parameter] public int Total { get; set; }

    private void HandleRefresh()
    {
        Total++;
    }
}
