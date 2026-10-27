namespace Shop;

public static class Calculator
{
    public static int Add(int a, int b) => a + b;

    public static decimal Discount(decimal price, decimal rate) => price - (price * rate);
}
