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

    [Fact]
    public void Transport_Receives_And_Confirms()
    {
        // NSubstitute chain plus a same-line real assertion — the strip is
        // bounded to the chain and must not eat the assertion after it
        var transport = Substitute.For<ITransport>();
        var ok = Sender.Ping(transport);
        transport.Received(1).Send("ping"); Assert.True(ok);
    }

    [Fact]
    public void Fib_Recurrence_Holds()
    {
        // same callee, different arguments — not a recomputed expectation
        Assert.Equal(Fib.Of(9) + Fib.Of(8), Fib.Of(10));
    }
}
