using Xunit;

namespace Shop.Specs;

public class OtherSpecs
{
    [Fact]
    public void Add_OfZero_IsIdentity() => Assert.Equal(7, Calculator.Add(7, 0));
}
