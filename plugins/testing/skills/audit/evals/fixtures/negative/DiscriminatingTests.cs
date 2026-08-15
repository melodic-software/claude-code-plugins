// Negative fixture (C#): genuinely discriminating tests — zero findings.
using Moq;
using Xunit;

public class DiscriminatingTests
{
    [Fact]
    public void Add_Returns_Sum()
    {
        Assert.Equal(5, Calculator.Add(2, 3));
    }

    [Fact(Skip = "not implemented yet")]
    public void Pending_Work()
    {
        Calculator.Add(0, 0);
    }

    [Fact]
    public void Notify_Sends_And_Returns_Receipt()
    {
        // mock interaction PLUS a real value assertion — not a mock-only oracle
        var mailer = new Mock<IMailer>();
        var receipt = Notifier.Notify(mailer.Object);
        mailer.Verify(m => m.Send(), Times.Once);
        Assert.Equal(42, receipt.Total);
    }

    [Fact]
    public void Renders_Verbatim_Path() =>
        Assert.Contains(@"C:\temp", PathRenderer.Render("temp"));
}
