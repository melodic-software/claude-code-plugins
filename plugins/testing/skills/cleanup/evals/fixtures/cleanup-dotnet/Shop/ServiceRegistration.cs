using System;
using Microsoft.Extensions.DependencyInjection;

namespace Shop;

public interface IPriceFeed
{
    decimal PriceOf(string sku);
}

public sealed class PriceFeed : IPriceFeed
{
    private readonly Uri _endpoint;

    public PriceFeed(ShopOptions options)
    {
        _endpoint = options.PriceFeedUrl
            ?? throw new InvalidOperationException("ShopOptions.PriceFeedUrl is not set");
    }

    public decimal PriceOf(string sku) => sku.Length;
}

public sealed class ShopOptions
{
    public Uri? PriceFeedUrl { get; init; }
}

public static class ServiceRegistration
{
    public static IServiceCollection AddShop(this IServiceCollection services, ShopOptions options) =>
        services.AddSingleton(options).AddSingleton<IPriceFeed, PriceFeed>();
}
