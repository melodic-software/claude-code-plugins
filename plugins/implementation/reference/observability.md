# Observability by default

Read this before writing or changing code that runs at runtime: a service, an API handler, a
worker or job, a CLI, a hook or a script someone else runs. The rules hold in every language; the
two examples show one way to follow them in .NET and in JavaScript or TypeScript. Where the
repository already has a logging or telemetry setup, follow it, and apply these rules inside it.

## Rules

| Situation | Do | Reason |
|---|---|---|
| Writing a log line | Log a constant message template with named fields for the values (`"Order {OrderId} cancelled"` plus the id as a field), never a string built by concatenation or interpolation | The fields stay queryable, and one template groups every occurrence of the event |
| Values every line in a unit of work shares (request id, order id, tenant) | Attach them once with a logging scope or a child logger, not by repeating them in each call | Each line carries the context without each call site having to remember it |
| A log call on a hot path (a loop, a per-request or per-message path) | Use the language's compile-time or allocation-free logging form, and skip building costly arguments when the level is off | Logging that costs work while disabled taxes every call |
| Sending traces, metrics or logs to a collector | Read the exporter endpoint, headers and service name from the environment (the OpenTelemetry `OTEL_EXPORTER_OTLP_ENDPOINT` family of variables, or the platform's configuration layer), never a literal in code | One build runs in every environment, and no endpoint or key is committed |
| Logging or timing that every request, handler or command needs | Put it in one cross-cutting place: middleware, a decorator, a pipeline behavior, an interceptor | One owner for the concern, and handlers keep only their own logic |
| A method with its own decision worth recording (a branch taken, a retry, a fallback) | Log it inside that method, at the level the event deserves | The cross-cutting layer cannot see the method's own decisions |
| More detail needed while developing | Raise the level locally through untracked config: an environment variable, a git-ignored local settings file, user secrets. Committed config keeps the quiet default | Teammates and deployed environments keep their level; a raised level is never merged by accident |
| Catching an error | Catch where the code can act on it, and record it with the exception object (stack included) and the fields that identify the operation; rethrow or return a failure the caller can see | A message without the exception loses the stack, and a swallowed error leaves no trace |

Never log secrets, tokens or personal data in a field or a message; redact at the logging layer
when the platform offers it.

## .NET

```csharp
public static partial class OrderLog
{
    [LoggerMessage(Level = LogLevel.Information, Message = "Order {OrderId} cancelled")]
    public static partial void OrderCancelled(this ILogger logger, string orderId);

    [LoggerMessage(Level = LogLevel.Error, Message = "Payment gateway refused order {OrderId}")]
    public static partial void GatewayRefused(this ILogger logger, Exception error, string orderId);
}

using (logger.BeginScope(new Dictionary<string, object> { ["RequestId"] = requestId }))
{
    try
    {
        await gateway.RefundAsync(orderId);
        logger.OrderCancelled(orderId);
    }
    catch (GatewayException ex)
    {
        logger.GatewayRefused(ex, orderId);
        throw;
    }
}

// Exporter endpoint comes from OTEL_EXPORTER_OTLP_ENDPOINT; nothing is passed in code.
builder.Services.AddOpenTelemetry().UseOtlpExporter();
```

Raise a level locally with an environment variable such as `Logging__LogLevel__MyApp=Debug`, or
with user secrets, never by editing the committed `appsettings.json`.

## JavaScript and TypeScript

```ts
const log = baseLogger.child({ requestId, orderId });

try {
  await gateway.refund(orderId);
  log.info({ event: "order.cancelled" }, "order cancelled");
} catch (err) {
  log.error({ err }, "payment gateway refused order");
  throw err;
}

const exporter = new OTLPTraceExporter(); // reads OTEL_EXPORTER_OTLP_ENDPOINT from the environment
const logger = pino({ level: process.env.LOG_LEVEL ?? "info" });
```

Raise a level locally with `LOG_LEVEL=debug` in the shell or a git-ignored `.env.local`.

## Where to read the specifics

Read these live when a choice depends on the current API or option names.

- Message templates, scopes, exceptions and level configuration in .NET:
  [Log message template](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/overview#log-message-template),
  [Log scopes](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/overview#log-scopes),
  [Log exceptions](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/overview#log-exceptions),
  [Configure logging](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/overview#configure-logging).
- Compile-time logging in .NET:
  [Basic usage](https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/source-generation#basic-usage).
- OTLP exporter configuration from the environment:
  [Environment Variables](https://github.com/open-telemetry/opentelemetry-dotnet/blob/main/src/OpenTelemetry.Exporter.OpenTelemetryProtocol/README.md#environment-variables).
- Configuration layering and values kept out of source control in ASP.NET Core:
  [Security and user secrets](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/#security-and-user-secrets),
  [Environment Variables Configuration Provider](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/#environment-variables-configuration-provider).
- Middleware as the place for cross-cutting work in ASP.NET Core:
  [Create a middleware pipeline with WebApplication](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/middleware/#create-a-middleware-pipeline-with-webapplication).
- Child loggers in pino:
  [Child loggers](https://github.com/pinojs/pino/blob/main/docs/child-loggers.md#child-loggers).
