# Other formats

Load this page when the artifact is not one of the three JSON formats the converter reads. Use
the format's own tool to export or summarize it first; convert to Chrome trace or `.cpuprofile`
JSON only when the tool offers that export, then run the converter on the export.

| Artifact | How to recognize it | Read it with | Notes |
|---|---|---|---|
| pprof (`.pb.gz`, `.pprof`) | gzipped protobuf from Go, or from other runtimes that emit pprof | `go tool pprof -top` or `-traces` on the file | Symbols are inside when the binary was built with them; otherwise pass the binary. |
| Linux `perf.data` | binary file named `perf.data` | `perf report --stdio` or `perf script` | `perf script` text feeds FlameGraph's `stackcollapse-perf.pl`. Needs the same binaries and debug symbols as the recorded host. |
| macOS spindump or `sample` output | text with per-thread call trees and counts | read the text directly | Find the thread burning CPU, or the one waiting, and what it waits on. |
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
- addr2line: <https://sourceware.org/binutils/docs/binutils/addr2line.html>. As of 2026-10-04.
  Recheck on a binutils major release.
