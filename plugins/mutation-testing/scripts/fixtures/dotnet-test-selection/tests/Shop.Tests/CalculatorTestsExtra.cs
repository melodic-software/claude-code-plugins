using Xunit;

namespace Shop.Tests
{
    public class CalculatorTestsExtra
    {
        [Fact]
        public void Discount_OfZeroRate_KeepsPrice() => Assert.Equal(10m, Calculator.Discount(10m, 0m));

        [Fact]
        public void Discount_OfHalfRate_HalvesPrice() => Assert.Equal(5m, Calculator.Discount(10m, 0.5m));
    }
}
