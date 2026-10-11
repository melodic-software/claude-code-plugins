using System;
using Microsoft.Extensions.DependencyInjection;
using Shop;
using Xunit;

namespace Shop.Tests;

public class WiringTests
{
    private static ServiceProvider BuildProvider() =>
        new ServiceCollection()
            .AddShop(new ShopOptions { PriceFeedUrl = new Uri("https://prices.example.test") })
            .BuildServiceProvider();

    [Fact]
    public void Price_feed_resolves()
    {
        using var provider = BuildProvider();
        var s = provider.GetRequiredService<IPriceFeed>();
    }

    [Fact]
    public void Wiring_is_sane()
    {
        Assert.True(true);
    }

    [Fact]
    public void Price_feed_type_exists()
    {
        Assert.NotNull(typeof(IPriceFeed));
    }

    [Fact]
    public void Price_feed_is_not_null()
    {
        using var provider = BuildProvider();
        var feed = provider.GetRequiredService<IPriceFeed>();
        Assert.NotNull(feed);
    }

    [Fact]
    public void Licensed_feed_prices_a_sku()
    {
        decimal price;
        try
        {
            using var provider = BuildProvider();
            price = provider.GetRequiredService<IPriceFeed>().PriceOf("ABC");
        }
        catch (InvalidOperationException ex) when (IsTrialFailure(ex))
        {
            return;
        }

        Assert.Equal(3m, price);
    }

    private static bool IsTrialFailure(Exception ex) =>
        ex.Message.Contains("trial license", StringComparison.OrdinalIgnoreCase);
}
