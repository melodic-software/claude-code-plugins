# Other formats

Load this page when the artifact is not one of the three JSON formats the converter reads. Use
the format's own tool to export or summarize it first; convert to Chrome trace or `.cpuprofile`
JSON only when the tool offers that export, then run the converter on the export.

| Artifact | How to recognize it | Read it with | Notes |
|---|---|---|---|
| pprof (`.pb.gz`, `.pprof`) | gzipped protobuf from Go, or from other runtimes that emit pprof | `go tool pprof -top` or `-traces` on the file | Symbols are inside when the binary was built with them; otherwise pass the binary. |
| Linux `perf.data` | binary file named `perf.data` | `perf report --stdio` or `perf script` | `perf script` text feeds FlameGraph's `stackcollapse-perf.pl`. Needs the same binaries and debug symbols as the recorded host. |
| macOS spindump or `sample` output | text with per-thread call trees and counts | read the text directly | Find the thread burning CPU, or the one waiting, and what it waits on. |
| Python `py-spy dump` output | text, one call stack per Python thread, plus basic process info | read the text directly | Find threads idle or waiting in a lock, `wait` or I/O call, and the frame several threads share. |
| JVM `jcmd` thread dump | text from `jcmd <pid> Thread.print`: every thread with its stack trace and state, plus held `java.util.concurrent` locks with `-l` | read the text directly | Read blocked and waiting threads: the lock each waits on and which thread holds it; a deadlock section, when present, names the cycle. |
| .NET `dotnet-stack report` output | text, one block per thread headed `Thread (<thread-id>):`, frames as `Module!Method` | read the text directly | Find threads parked in `Monitor.Enter`, `Wait` or a task wait, and the frame several threads share. |
| Go goroutine dump | text, one block per goroutine with its state and stack, from `GOTRACEBACK=all` or a goroutine profile | read the text directly | Group goroutines by state and top frame; many in `chan receive`, `semacquire` or `sync.Mutex.Lock` on one frame point at the blocker. |
| gdb `thread apply all bt` output | text, one block per thread with numbered frames `#0`, `#1`, innermost first | read the text directly | Find threads in `futex`, `pthread_mutex_lock` or `pthread_cond_wait`, and which thread owns that mutex; needs debug symbols as below. |
| .NET `.nettrace` | binary from dotnet-trace | `dotnet-trace convert --format speedscope` or `chromium` | The `chromium` export is a Chrome trace the converter reads. |
| .NET `.gcdump` | binary from dotnet-gcdump | `dotnet-gcdump report` | Prints type counts and sizes. |
| JVM `.jfr` | binary from JFR | `jfr print` or `jfr summary` | `jfr print --json` gives JSON, but not in a shape the converter reads. |
| JVM `.hprof` | binary heap dump | a heap analyzer such as Eclipse MAT | No stdlib reader; report its size and ask the user which tool they have. |
| Python py-spy output | speedscope JSON or SVG | speedscope or the SVG itself | py-spy can also write Chrome trace JSON, which the converter reads. |
| memray `.bin` | binary from memray | `memray stats` or `memray flamegraph` | |

The rule from the JSON formats holds here too: an address that never maps back to a source file
and line does not count as a cause. Native code needs its debug symbols (`addr2line`, or the
platform's symbol server); say which are missing when they are.

## Pointers

- pprof: <https://github.com/google/pprof>. As of 2026-10-04. Recheck on a Go minor release.
- perf: <https://man7.org/linux/man-pages/man1/perf-record.1.html>; FlameGraph:
  <https://github.com/brendangregg/FlameGraph>. As of 2026-10-04. Recheck when the host's perf
  version changes.
- .NET diagnostics tools and symbols:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/symbols>. As of 2026-10-04. Recheck
  on a .NET major release.
- JFR: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jfr.html>. As of 2026-10-04.
  Recheck when the project moves to a newer LTS JDK.
- speedscope: <https://github.com/jlfwong/speedscope>; py-spy: <https://github.com/benfred/py-spy>;
  memray: <https://bloomberg.github.io/memray/>. As of 2026-10-04. Recheck on a major release of
  any of them.
- py-spy dump: <https://github.com/benfred/py-spy#dump>. As of 2026-10-23. Recheck on a py-spy
  major release.
- JDK `jcmd` `Thread.print`:
  <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jcmd.html#commands-for-jcmd>. As of
  2026-10-23. Recheck when the project moves to a newer LTS JDK.
- dotnet-stack output form:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack#report-managed-stacks-with-dotnet-stack>.
  As of 2026-10-23. Recheck on a .NET major release.
- Go `GOTRACEBACK`: <https://pkg.go.dev/runtime#hdr-Environment_Variables>. As of 2026-10-23.
  Recheck on a Go minor release.
- GDB backtraces and `thread apply all`:
  <https://sourceware.org/gdb/current/onlinedocs/gdb.html/Backtrace.html#backtrace_002dcommand>,
  <https://sourceware.org/gdb/current/onlinedocs/gdb.html/Threads.html#thread-apply-all>. As of
  2026-10-23. Recheck on a GDB major release.
- addr2line: <https://sourceware.org/binutils/docs/binutils/addr2line.html>. As of 2026-10-04.
  Recheck on a binutils major release.
