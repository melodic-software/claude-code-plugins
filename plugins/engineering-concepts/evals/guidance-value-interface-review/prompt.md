---
description: "Value test, not for merge: does the team's design guidance change a code review? The prompt and the grader never state the position (no vendor name in an abstraction's name); the grader checks whether the reply proposes a vendor-free interface name. Compare run, merge base (no guidance skill) against head (design-guidance skill)."
tags: [engineering-concepts, guidance-value]
max_turns: 8
timeout_seconds: 300
expected_outcome: "The reply proposes renaming the interface to a vendor-free name such as IEmailSender."
---

Review this interface before we merge it, and say what, if anything, you would change. Keep it under 200 words.

```csharp
public interface ISendGridEmailService
{
    Task SendAsync(string to, string subject, string htmlBody, CancellationToken cancellationToken);
}
```
