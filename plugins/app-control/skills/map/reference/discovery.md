# Discovery rows

Read before step 2 of `create`. Every row is answered from the repository and the machine, read
only, before any question. A row ends `found`, with the file or command that showed it, or `open`.

| Row | What to find |
|---|---|
| Surfaces | The apps a person drives (web, API, CLI, desktop) and the workers with no UI; two apps that share one port |
| Run | The documented start command or launch recipe, launch profiles, ports, whether two instances can run side by side, and for a short-lived command-line or terminal app, its build step |
| Ready | A health signal, plus a signal that the instance uses the expected data and build, a way to tell the port belongs to this instance, and a read-only call that shows a credential is valid |
| Config | How the app layers its configuration, and which override it actually honors; never assume environment variables win |
| Environments | Names and URLs, each confirmed by a read-only call, never from docs alone |
| Identity | Where sign-in happens, the options shown, prompts that appear on some runs only, labels that change per tenant or configuration |
| Dependencies | Services a journey crosses, their URL per environment, and whether the app's real target can be read back |
| Side effects | Channels that reach real people (mail, SMS, chat, webhooks), and whether a local run still sends |
| Shared systems | Deployed systems a local run still writes to, such as a shared identity server whose failed sign-ins count toward an account's lockout |
| Data | Tenancy, where the app keeps its data and how to point it at a new directory, its migrations and seed data, and the app's own supported reset path |
| Harnesses | Existing end-to-end specs, test accounts, selector conventions |
| Evidence | Logs, a log server, telemetry endpoints, and what each capture tier (browser, server) can record |
| Data sources | Per environment, the logs, telemetry, databases, work-item tracker, error reporter and any conversations (meeting transcripts, call notes, support chats) an agent can reach, each with a read-only way to read it and the name of the credential variable it is read with (the contract's "Data sources"); the read level, the `grants` command (or `full-user-access` for a source with no scope control) and the `data` category, readers and review are asked, never found |
| Team vs personal | What is committed and team-wide, what is per user, and where per-user values live |
| Related repositories | Systems whose pages a journey crosses but live elsewhere, each one's repository and control skill, and whether this machine has a checkout of it (the contract's `checkouts.<app>`) |

A row the repository cannot answer becomes a question in step 3, or, under `--unattended`, an
open question in the dry run's report.
