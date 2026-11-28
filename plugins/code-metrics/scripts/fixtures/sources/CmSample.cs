namespace Fixture;

public static class Sample
{
    public static string Classify(int value)
    {
        if (value > 0)
        {
            return "positive";
        }
        return value == 0 ? "zero" : "negative";
    }
}
