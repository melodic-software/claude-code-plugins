using Xunit;

namespace Shop.Specs
{
    public class DiscountSpecs
    {
        [Fact]
        public void FullRate_MakesItFree() => Assert.Equal(0m, Calculator.Discount(8m, 1m));

        [Fact]
        public void ZeroRate_KeepsPrice() => Assert.Equal(8m, Calculator.Discount(8m, 0m));
    }

    public class RoundingSpecs
    {
        [Fact]
        public void Discount_KeepsCents() => Assert.Equal(9.9m, Calculator.Discount(11m, 0.1m));
    }
}
