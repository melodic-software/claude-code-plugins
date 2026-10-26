using Xunit;

namespace Shop.Tests;

// class CommentedOut { } declares nothing, and its braces do not count.
public class CalculatorTests
{
    private const string Note = "class NotAClass { {";
    private const char Brace = '{';

    [Fact]
    public void Add_SumsBothOperands() => Assert.Equal(5, Calculator.Add(2, 3));

    [Fact]
    public void Add_IsCommutative() => Assert.Equal(Calculator.Add(4, 1), Calculator.Add(1, 4));

    public class Negatives
    {
        [Fact]
        public void Add_OfNegatives_IsNegative() => Assert.Equal(-3, Calculator.Add(-1, -2));
    }
}
