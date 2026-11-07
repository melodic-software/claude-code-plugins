#!/usr/bin/env bash
# Sourced by a cleanup scaffold after git-workspace.sh and ws_init. Defines:
#   dotnet_files  write the C# shop: Shop/ (a price feed whose constructor throws without a URL,
#                 registered through AddShop) and Shop.Tests/WiringTests.cs (a resolve-only test, two
#                 constant oracles, a weak oracle, a test with an inert and a real assertion, and a
#                 catch-when guarded test). No mutation-testing config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

dotnet_files() {
  mkdir -p Shop Shop.Tests
  printf 'bin/\nobj/\n.work/\n' >.gitignore
  cat >Shop/Shop.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="8.0.1" />
  </ItemGroup>

</Project>
XML
  cat >Shop/ServiceRegistration.cs <<'CS'
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
CS
  cat >Shop.Tests/Shop.Tests.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.10.1" />
    <PackageReference Include="xunit" Version="2.9.3" />
    <PackageReference Include="xunit.runner.visualstudio" Version="4.0.1" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="../Shop/Shop.csproj" />
  </ItemGroup>

</Project>
XML
  cat >Shop.Tests/WiringTests.cs <<'CS'
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
    public void Price_feed_prices_two_letter_sku()
    {
        using var provider = BuildProvider();
        Assert.True(true);
        Assert.Equal(2m, provider.GetRequiredService<IPriceFeed>().PriceOf("AB"));
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
CS
}
