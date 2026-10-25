# Leftover sandboxes

How preflight fills `leftover_sandboxes` and `tmp_free`. `<tmp>` is `$TMPDIR`, else `/tmp`.

Probe read-only:

```bash
find <tmp> -maxdepth 1 -type d -name 'claude-eval-*'
du -skc <tmp>/claude-eval-*
df -k <tmp>
```

The `find` lines are the count, the `du` `total` line is the size, and `df` gives `tmp_free`. An
unreadable path reports `unknown`, never `0`. A non-zero `du` exit or a permission error means a
partial total: report the size as `unknown` or `at least <total>`.

Preflight removes nothing and blocks on neither field. When the count is above zero, print these
for the user to run:

```bash
chmod -R u+w <tmp>/claude-eval-*
rm -rf <tmp>/claude-eval-*
```

A directory `chmod` cannot enter still needs `sudo rm -rf`.

## Sandbox start

A run under the default `<tmp>`, or under a long `$TMPDIR`, can end with no session or no shell:
the validity gate's `session started` check fails it. Rerun with `TMPDIR` set to a short directory
outside the system temp directory.

- **Pointer:** [anthropics/claude-code#104631](https://github.com/anthropics/claude-code/issues/104631)
  and [anthropics/claude-code#104797](https://github.com/anthropics/claude-code/issues/104797) for
  the default temp directory (the cause is each reporter's attribution); for a long `$TMPDIR`,
  correlate with the socket path limit in [unix(7)](https://man7.org/linux/man-pages/man7/unix.7.html),
  which no upstream source names as the cause. Probes on Claude Code 2.1.310 are in
  [#9514](https://github.com/melodic-software/claude-code-plugins/issues/9514#issuecomment-6400874417)
  and [#9611](https://github.com/melodic-software/claude-code-plugins/issues/9611).
- **As of:** 2026-10-25.
- **Recheck when:** either upstream issue closes, or a release note touches `plugin eval` sandbox
  paths or `TMPDIR`.

## Record

- **Pointer:** the `--keep-temp` row of <https://code.claude.com/docs/en/plugin-evals#command-options>
  documents a per-run sandbox directory but not its name or location. The `claude-eval-*` name in
  the temp directory, the read-only `sealed/`, `out/` and `config/` subdirectories, and the
  `sealed/` directories only `sudo` could remove come from an observation on a WSL2 host on
  2026-10-13 (569 directories after about an hour of runs, issue #7431), and match the sandbox
  paths in `plugins/testing/evals/sandbox-probe-plain/samples/echo-printed.json`.
- **As of:** 2026-10-20.
- **Recheck when:** a `--keep-temp` run prints a sandbox path outside `<tmp>/claude-eval-*`, the
  docs name the sandbox directory, or a release note says runs remove their sandboxes.
