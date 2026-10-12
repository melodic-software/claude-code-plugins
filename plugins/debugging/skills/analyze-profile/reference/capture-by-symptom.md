# Capture by symptom

Load this page in capture mode, after a human present has described the symptom and named the
process. Pick the row for the symptom, then the column for the runtime. Every tool below changes
its flags between releases, so this page names the tool and links its manual; read the current
flags there before writing the command you show the user.

| Symptom | What to record | Node.js | Browser page | Python | JVM | .NET | Go | Native (Linux / macOS) |
|---|---|---|---|---|---|---|---|---|
| A core pinned near 100% (spin) | CPU profile | built-in CPU profile flag | Performance panel recording | py-spy record | JFR recording | dotnet-trace | pprof CPU profile | perf record / `sample` |
| Memory that keeps growing (leak) | Two heap snapshots minutes apart | built-in heap snapshot signal or inspector | Memory panel heap snapshot | memray | `jcmd` heap dump | dotnet-gcdump | pprof heap profile | heaptrack / `leaks` |
| UI that stutters or drops frames (jank) | Timeline trace with CPU samples | n/a | Performance panel recording (saves a Chrome trace) | n/a | JFR recording | dotnet-trace | execution trace | perf record with call graphs |
| A process that stops responding (hang) | Stack sample of every thread | inspector pause or diagnostic report | Performance panel recording | py-spy dump | `jcmd` thread dump | dotnet-stack | goroutine dump | `gdb` thread backtrace / `spindump` |

Launch the target as a child of the profiler where the tool supports it; that records only the
command the user approved and needs no elevation. Attaching to a running process often needs
elevated rights (ptrace scope on Linux, the debugging entitlement on macOS, an administrator token
on Windows); that path goes through the script file the skill body describes.

## Manuals

Each record: pointer, as-of date, recheck trigger.

- Node.js CLI options (CPU profile, heap profile, heap snapshot signal):
  <https://nodejs.org/api/cli.html>. As of 2026-10-04. Recheck on a Node.js major release.
- Chrome DevTools Performance panel: <https://developer.chrome.com/docs/devtools/performance/reference>.
  Memory panel heap snapshots: <https://developer.chrome.com/docs/devtools/memory-problems/heap-snapshots>.
  As of 2026-10-04. Recheck when either page changes how a recording is saved.
- py-spy: <https://github.com/benfred/py-spy>. memray: <https://bloomberg.github.io/memray/>. As of
  2026-10-04. Recheck on a new major release of either.
- JDK `jcmd`: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jcmd.html>. JDK `jfr`:
  <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jfr.html>. As of 2026-10-04. Recheck
  when the project moves to a newer LTS JDK.
- .NET diagnostics tools: <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack>. As of 2026-10-04.
  Recheck on a .NET major release.
- Go profiling endpoints: <https://pkg.go.dev/net/http/pprof>; the pprof tool:
  <https://github.com/google/pprof>. As of 2026-10-04. Recheck on a Go minor release.
- Linux `perf record`: <https://man7.org/linux/man-pages/man1/perf-record.1.html>. As of
  2026-10-04. Recheck when the host kernel's perf version changes.
- heaptrack: <https://github.com/KDE/heaptrack>. GDB: <https://sourceware.org/gdb/documentation/>.
  As of 2026-10-04. Recheck on a new major release of either.
- macOS `sample`, `spindump` and `leaks`: the man pages on the host (`man sample`). Recheck on a
  macOS major release.
