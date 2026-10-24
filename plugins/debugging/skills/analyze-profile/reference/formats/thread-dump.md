# Thread dump

Load this page when the artifact is a text stack of every thread in one process at one moment, as
`/app-control:drive capture --kind threads` records for a hang. The first format with a page here
is `py-spy dump` text: a `Process <pid>: <command line>` line, a `Python v<version>` line, then one
block per thread headed `Thread <id> (<state>): "<name>"`, its frames listed innermost first as
`function (file:line)`. The text layout is py-spy's: read it at
<https://github.com/benfred/py-spy#dump> (as of 2026-10-23; recheck on a py-spy major release).

## Read it directly

A thread dump is short text. Read it with the Read tool; it skips the converter and the SQLite
step, so this run makes no `$work` directory and has nothing to delete. A dump too long for a
screen goes to a subagent under the same data rules, and its reply carries only the threads that
carry the finding.

## Where the reading begins

1. **Threads stopped in the same place.** Several threads whose innermost frames share a function
   or a file:line are waiting on one thing.
2. **Lock waits.** An innermost frame on a lock acquire (`with <lock>:`, `acquire`, `wait`, `join`,
   a queue `get`). Open the source at that file:line to name the lock or event. Then walk the outer
   frames of the same thread: a `with` block or an earlier acquire that encloses the call shows
   what the thread already holds.
3. **The main thread.** Where it sits says what the program as a whole is waiting for (often a
   `join` on a worker).

py-spy's `(idle)` and `(active)` labels are its own guess from the frame, not proof a thread is
stuck or free: how it decides is at <https://github.com/benfred/py-spy#how-do-you-detect-if-a-thread-is-idle-or-not>
(as of 2026-10-23; recheck on a py-spy major release). Judge a thread by its frames.

## Done when

Each waiting thread is named with what it waits on, at file:line, and with the thread that holds
it when the dump or the source shows one. Two threads each holding what the other waits for is a
lock-order cycle: name both acquire sites and the order each thread takes them in.

## Status from one dump

One dump is one moment; a thread passing through a lock looks the same as one stuck there. The
capture that settles it is a second dump taken some seconds later: the same threads in the same
frames show they are stuck.

## Data

Thread names, the command line on the `Process` line and every frame name come from the recorded
program: the skill's data rules apply, and so does its redaction rule. A command line can carry a
token or a password as an argument; write `<REDACTED>` in its place. A dump taken with local
variables printed holds their values, so quote only the frames that carry the finding.
