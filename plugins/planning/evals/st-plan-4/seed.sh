#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p Data Import Sms .work/review-target/design

cat >Clinic.Reminders.csproj <<'XML'
<Project Sdk="Microsoft.NET.Sdk.Worker">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="8.0.8" />
    <PackageReference Include="Microsoft.Extensions.Hosting" Version="8.0.0" />
  </ItemGroup>
</Project>
XML

cat >Program.cs <<'CS'
using Clinic.Reminders.Data;
using Clinic.Reminders.Import;
using Clinic.Reminders.Sms;
using Microsoft.EntityFrameworkCore;

var environment = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? "Production";

var builder = Host.CreateEmptyApplicationBuilder(new HostApplicationBuilderSettings
{
    EnvironmentName = environment,
});

builder.Configuration
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile($"appsettings.{environment}.json", optional: true);

builder.Services.AddDbContext<ClinicDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("Clinic")));
builder.Services.Configure<SmsOptions>(builder.Configuration.GetSection("Sms"));
builder.Services.AddSingleton<ISmsGateway, HttpSmsGateway>();
builder.Services.AddHostedService<AppointmentImporter>();

await builder.Build().RunAsync();
CS

cat >appsettings.json <<'JSON'
{
  "ConnectionStrings": { "Clinic": "Data Source=clinic.db" },
  "Clinic": { "TimeZone": "America/Denver" },
  "Import": { "Directory": "inbox", "PollSeconds": 300 },
  "Sms": { "BaseUrl": "http://localhost:9090", "FromNumber": "+15550100" }
}
JSON

cat >appsettings.Production.json <<'JSON'
{
  "ConnectionStrings": { "Clinic": "Data Source=/var/lib/clinic/clinic.db" },
  "Import": { "Directory": "/var/lib/clinic/inbox" },
  "Sms": { "BaseUrl": "https://sms.example.invalid/v2" },
  "Reminders": { "Enabled": false, "HoursBefore": 48 }
}
JSON

cat >Data/Appointment.cs <<'CS'
namespace Clinic.Reminders.Data;

public enum AppointmentStatus { Booked, Confirmed, Cancelled, Completed }

public class Patient
{
    public int Id { get; set; }
    public required string Name { get; set; }
    public required string MobileNumber { get; set; }
    public bool SmsOptOut { get; set; }
}

public class Appointment
{
    public int Id { get; set; }
    public int PatientId { get; set; }
    public Patient Patient { get; set; } = null!;
    public DateTime StartsAt { get; set; }
    public AppointmentStatus Status { get; set; }
}

public class SentReminder
{
    public int Id { get; set; }
    public int AppointmentId { get; set; }
    public required string Kind { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public string? ProviderMessageId { get; set; }
    public int Attempts { get; set; }
}
CS

cat >Data/ClinicDbContext.cs <<'CS'
using Microsoft.EntityFrameworkCore;

namespace Clinic.Reminders.Data;

public class ClinicDbContext(DbContextOptions<ClinicDbContext> options) : DbContext(options)
{
    public DbSet<Patient> Patients => Set<Patient>();
    public DbSet<Appointment> Appointments => Set<Appointment>();
    public DbSet<SentReminder> SentReminders => Set<SentReminder>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Appointment>().HasIndex(a => a.StartsAt);
        modelBuilder.Entity<SentReminder>()
            .HasIndex(r => new { r.AppointmentId, r.Kind })
            .IsUnique();
    }
}
CS

cat >Import/AppointmentImporter.cs <<'CS'
using System.Globalization;
using Clinic.Reminders.Data;
using Microsoft.EntityFrameworkCore;

namespace Clinic.Reminders.Import;

public class AppointmentImporter(IServiceScopeFactory scopes, IConfiguration configuration) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var directory = configuration["Import:Directory"]!;
        var period = TimeSpan.FromSeconds(configuration.GetValue("Import:PollSeconds", 300));
        using var timer = new PeriodicTimer(period);
        do
        {
            foreach (var path in Directory.EnumerateFiles(directory, "*.csv"))
            {
                await ImportFile(path, stoppingToken);
                File.Delete(path);
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }

    // Rows come from the practice system's export: patient id, "yyyy-MM-dd HH:mm" as shown on the
    // clinic's front desk calendar, status.
    private async Task ImportFile(string path, CancellationToken stoppingToken)
    {
        using var scope = scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ClinicDbContext>();
        foreach (var line in await File.ReadAllLinesAsync(path, stoppingToken))
        {
            var fields = line.Split(',');
            var startsAt = DateTime.ParseExact(fields[1], "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture);
            var patientId = int.Parse(fields[0], CultureInfo.InvariantCulture);
            var existing = await db.Appointments.FirstOrDefaultAsync(
                a => a.PatientId == patientId && a.StartsAt == startsAt, stoppingToken);
            var status = Enum.Parse<AppointmentStatus>(fields[2], ignoreCase: true);
            if (existing is null)
            {
                db.Appointments.Add(new Appointment { PatientId = patientId, StartsAt = startsAt, Status = status });
            }
            else
            {
                existing.Status = status;
            }
        }
        await db.SaveChangesAsync(stoppingToken);
    }
}
CS

cat >Sms/ISmsGateway.cs <<'CS'
using System.Net.Http.Json;
using Microsoft.Extensions.Options;

namespace Clinic.Reminders.Sms;

public class SmsOptions
{
    public required string BaseUrl { get; set; }
    public required string FromNumber { get; set; }
}

public interface ISmsGateway
{
    Task<string> SendAsync(string to, string body, CancellationToken stoppingToken);
}

public class HttpSmsGateway(IOptions<SmsOptions> options) : ISmsGateway
{
    private readonly HttpClient _http = new() { BaseAddress = new Uri(options.Value.BaseUrl) };

    public async Task<string> SendAsync(string to, string body, CancellationToken stoppingToken)
    {
        var response = await _http.PostAsJsonAsync(
            "messages", new { from = options.Value.FromNumber, to, body }, stoppingToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync(stoppingToken);
    }
}
CS

cat >.work/review-target/PLAN.md <<'MD'
# Appointment SMS reminders

## Brief

### Problem
Front desk staff phone patients the day before each appointment. They reach about half, and the
clinic's no-show rate stays high.

### Goal
Patients with a confirmed appointment get one SMS reminder a day ahead, with no staff involved.

### Acceptance criteria
- AC1: A confirmed appointment produces one SMS 24 hours before its start, give or take ten minutes.
- AC2: An appointment cancelled before the send time produces no SMS.
- AC3: A failed send is tried up to three times, and each delivered reminder records the provider's
  message id.
- AC4: A patient with `SmsOptOut` set receives no reminder.

### Out-of-scope
- Patient replies and two-way messaging.
- Reminder wording per clinic location.

### Captured assumptions
- Quality bar: production
- One clinic and one time zone.

## Plan

### Phase 1: Options and worker skeleton [STATUS]
**Satisfies:** AC1

- Add `ReminderOptions` with `Enabled`, `HoursBefore` and `PollSeconds`.
- Add a `Reminders` section to `appsettings.json` with `Enabled: true`, `HoursBefore: 24` and
  `PollSeconds: 300`, bound in `Program.cs` with `Configure<ReminderOptions>`.
- Add `Reminders/ReminderWorker.cs`, a `BackgroundService` on a `PeriodicTimer`, and register it in
  `Program.cs` next to `AppointmentImporter`.

**Sanity Check:** `DOTNET_ENVIRONMENT=Development dotnet run` logs one tick line every 300 seconds
with `HoursBefore=24` and `Enabled=True`.

### Phase 2: Selecting and claiming due reminders [STATUS]
**Satisfies:** AC1, AC2, AC4

- Each tick selects appointments with `Status == Confirmed` whose `StartsAt` falls between
  `DateTime.UtcNow` and `DateTime.UtcNow.AddHours(HoursBefore)`, and with no `SentReminder` row of
  kind `day-before`.
- For each one, insert the `SentReminder` row and save before calling the gateway. The unique index
  on `(AppointmentId, Kind)` in `ClinicDbContext` makes a second insert for the same appointment
  throw, and the tick skips that appointment, so a restart or an overlapping tick sends nothing new.
- Status is re-read at each tick, and the importer updates it as new exports arrive, so a
  cancellation before the tick removes the appointment from the selection.

**Sanity Check:** seed one confirmed appointment 23 hours ahead and one cancelled appointment 23 hours
ahead. One tick calls the fake gateway once, and a second tick does not call it.

### Phase 3: Sending and retries [STATUS]
**Satisfies:** AC3

- `ISmsGateway.SendAsync` is called with the patient's `MobileNumber`.
- On success, store the return value in `SentReminder.ProviderMessageId`.
- On an exception, increment `Attempts`. Each tick also picks up rows with no `ProviderMessageId` and
  `Attempts` below 3.

**Sanity Check:** a fake gateway that fails twice and then succeeds leaves `Attempts == 2` and a stored
message id after three ticks.

### Load-bearing assumptions
- `Appointment.StartsAt` is stored in UTC, so comparing it with `DateTime.UtcNow` gives the correct
  24-hour window.
- The practice system's export contains confirmed appointments at least a day ahead.
- The poll interval of 300 seconds keeps sends inside the ten-minute tolerance in AC1.

### Test strategy
xUnit tests run `ReminderWorker.TickAsync` against an in-memory SQLite `ClinicDbContext` and a fake
`ISmsGateway`, one test per acceptance criterion's main path.

### Files affected
| File | Action |
|---|---|
| `Reminders/ReminderWorker.cs` | create |
| `Reminders/ReminderOptions.cs` | create |
| `Program.cs` | modify: options binding, worker registration |
| `appsettings.json` | modify: `Reminders` section |
| `Clinic.Reminders.Tests/ReminderWorkerTests.cs` | create |
MD

# Each phase heading takes its status tag here, outside the heredoc.
plan=.work/review-target/PLAN.md
text="$(cat "$plan")"
printf '%s\n' "${text//'[STATUS]'/[TODO]}" >"$plan"

cat >.work/review-target/design/design-resolution.md <<'MD'
outcome: early-exit
tier: C
reason: The worker follows the importer's hosted service shape and uses the existing data model and gateway.
MD
