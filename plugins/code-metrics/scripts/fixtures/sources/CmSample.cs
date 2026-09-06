// Fixture source for the code-metrics suites: a C# file, so the deferred
// dotnet lane has something to detect and report as deferred.
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
