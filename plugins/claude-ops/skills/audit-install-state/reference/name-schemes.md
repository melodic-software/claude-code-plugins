# A number in a filename is not reliably a PID

This is the single highest-value rule in the skill, and it was learned from a near-miss.

An audit of a real install was one step from deleting `ide/22580.lock` because a process lookup for
"PID 22580" returned nothing. **22580 is a listening TCP port.** The real PID lived inside the file
body — `32324`, alive, the running VS Code integration for that very workspace. Deleting the file
would have broken a live IDE session, and the "evidence" authorising it was a lookup that was never
a valid question to ask.

The failure is structural, not careless. `Get-Process <n>` / `os.kill(<n>, 0)` against a non-PID
returns a *clean, confident, negative* answer. Nothing about that answer says "you asked the wrong
question." It reads exactly like a dead process.

## The rule

**Establish the naming scheme before applying any liveness check, and require positive evidence that
a number IS a PID before treating a lookup miss as "dead."**

The engine implements this as a gate, not as advice: `verdict_for()` classifies the name first and
calls the probe *only* when `number_meaning == "pid"`. Every other name returns
`liveness: not_applicable` **by construction** — including names the table has never seen. A test
injects a spy probe and asserts it is never invoked for a non-PID name, so the gate is a checked
property rather than a convention someone has to remember.

## Verified schemes

| Pattern | What the number actually is | Liveness valid? |
|---|---|---|
| `sessions/<n>.json` | Genuine OS process id | **yes** |
| `ide/<n>.lock` | Listening **TCP port**; real PID is in the body | no — and the body is not opened |
| `rate-limit-guard/*.tmp.<n>` | Git Bash / MSYS2 `$$` — a shell PID in its own namespace | no — judge by age and zero length |
| `shell-snapshots/snapshot-<shell>-<n>-<rand>` | Epoch milliseconds | no — no PID in the name at all |
| `backups/.claude.json.backup.<n>` | Epoch milliseconds | no |
| `paste-cache/<hex>` | Content hash | no |
| `session-env/<uuid>/`, `file-history/<uuid>/`, `tasks/<uuid>` | Session UUID | no |
| `projects/<project>/<uuid>.jsonl` | Session UUID | no |
| `~/.claude.json.tmp.<n>.<hash>` | *Probably* a PID — **unverified** | no, precisely because it is unverified |
| anything else carrying digits | **unknown** | no |

The last row is the safety property. A third-party plugin's own numeric scheme fails closed: it is
reported as `unknown`, and no lookup is attempted. Adding a pattern to the table is an optimisation;
the default is what keeps the engine correct on an install it has never seen.

## Three further traps in the same family

**A PID hit does not prove identity.** Operating systems reuse process ids. `alive` is a measurement
about *a* process with that id; "therefore this file is in use" is an inference. The engine tags the
verdict `measured` and leaves the second step to the reader.

**A staging temp is not a lock.** A `<name>.<pid>.<timestamp>` file is often the temp half of an
atomic write whose `rename` failed, with a normal lifetime of milliseconds and no cleanup path. The
PID in it is real; the semantics are not "this process holds a lock."

**The set moves while you look at it.** Session records are created and removed during a scan. A
session whose record vanished mid-run is *unknown*, not *dead*, and every orphan count derived from
that set inherits the uncertainty.
