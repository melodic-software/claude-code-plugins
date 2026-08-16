// Positive fixture (C#): one planted defect per rule.
using Moq;
using Xunit;

public class CantFailTests
{
    [Fact]
    public void Charge_Runs()
    {
        var gateway = new Gateway();
        gateway.Charge(100);
    }

    [Fact]
    public void Format_Matches_Itself()
    {
        Assert.Equal(Format.User(1), Format.User(1));
    }

    [Fact]
    public void Notify_Calls_Mailer()
    {
        var mailer = new Mock<IMailer>();
        Notifier.Notify(mailer.Object);
        mailer.Verify(m => m.Send(), Times.Once);
    }
}
