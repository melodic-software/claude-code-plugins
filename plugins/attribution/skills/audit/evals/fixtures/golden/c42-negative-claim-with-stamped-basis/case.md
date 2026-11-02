# Ridge surfaces

What the sandbox holds and fails to hold on a Ridge machine, one note per claim. Each note gives
its source, the day it was checked, and the change that should send it back for another look.

*Claim:* the sandbox needs Ridge 2 or later with the relay helper installed.
*Source:* [Platform support](https://example.invalid/harbor/docs/sandboxing#platform-support),
fetched as markdown. *Checked:* 2026-09-23. *Revisit when:* the Harbor changelog mentions sandbox
platform support, or a fresh read of that section disagrees with this note.

*Claim:* Ridge passes any start of a host program, for example a binary under `/host/bin/`, across
to the host through a relay socket, and that socket is closed only by the sandbox's optional
syscall filter. If the filter is absent, or `allowRelaySockets` is on, the socket remains open. A
program started that way runs on the host, beyond every Ridge boundary.
*Source:* the Ridge notes in [Set up Ridge](https://example.invalid/harbor/docs/sandboxing#set-up-ridge),
fetched as markdown. *Checked:* 2026-09-23. *Revisit when:* the Harbor changelog mentions the Ridge
relay, relay socket blocking or the syscall filter, or a fresh read of that section disagrees with
this note.

## Checks that follow

The setup check starts `/host/bin/true` inside the sandbox and fails if it runs.
