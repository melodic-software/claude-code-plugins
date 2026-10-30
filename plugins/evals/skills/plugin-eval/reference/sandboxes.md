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

Preflight removes nothing and blocks on neither field. When the count is above zero, print this
for the user to run. A kept sandbox can hold a mode-000 `sealed/` directory that a recursive
`chmod -R u+w` cannot enter, so each sandbox and its `sealed/` are opened first:

```bash
for d in <tmp>/claude-eval-*; do chmod 700 "$d" "$d/sealed"; chmod -R u+rwx "$d"; rm -rf "$d"; done
```

A directory `chmod` cannot enter still needs `sudo rm -rf`.

## Removing a read's sandboxes

After the `read` action's promote line (SKILL.md, Reading the delta), or wherever the reading
stopped, remove the sandboxes the run in this file kept. First finish everything the traces are
needed for: the spot-read, the trace evidence an INVALID cause needs for its fix, and whether a
without-arm trace loads a large skill (the Cost anchor). A relative `tracePath` resolves against
the JSON file's directory. Its sandbox is the nearest directory named `claude-eval-*`, the path
itself or an ancestor ([Record](#record)). The JSON file is untrusted input: a checked-in sample or
a downloaded artifact can name any path. Collect the distinct sandboxes that still exist and keep
one for removal only when all of these hold:

- the `tracePath` has no `..` segment and is the sandbox's `out/trace.jsonl`;
- the sandbox is not a symlink, and its `realpath` is a direct child of the `realpath` of `<tmp>`
  (`$TMPDIR`, else `/tmp`, as above); a sandbox under any other directory, a run made with a
  different `TMPDIR` included, is not removed;
- the sandbox holds `out/` and `sealed/` directories;
- the path holds no `'` and no control character, so it goes inside single quotes literally.

List every other candidate for the user with the condition it failed, and remove nothing for it.
Remove exactly the kept ones by literal path, each single-quoted. The loop checks the symlink,
location, name and layout conditions again itself, so it confines `chmod -R` and `rm -rf` to
layout-bearing `claude-eval-*` directories directly under `<tmp>`. It does not check the other
conditions again (the `tracePath` segments, that the sandbox is the one the `tracePath` names, the
quoting), and a concurrent run's `--keep-temp` sandbox passes it, so picking the right sandboxes
remains the selection step's job. It opens the sandbox directory before the layout test, since a
kept sandbox can be one the test cannot read, and it prints each skipped path with the reason:

```bash
t=$(realpath "${TMPDIR:-/tmp}"); for d in '<sandbox>' '<sandbox>'; do r=$(realpath "$d"); if [ -L "$d" ] || [ ! -d "$d" ] || [ "$(dirname "$r")" != "$t" ]; then echo "skipped (not a directory directly under $t): $d"; continue; fi; case $(basename "$r") in claude-eval-*) ;; *) echo "skipped (not named claude-eval-*): $d"; continue;; esac; if ! chmod u+rwx "$r"; then echo "skipped (chmod cannot open it): $d"; continue; fi; if [ ! -d "$r/out" ] || [ ! -d "$r/sealed" ]; then echo "skipped (no out/ and sealed/): $d"; continue; fi; chmod 700 "$r/sealed"; chmod -R u+rwx "$r"; rm -rf "$r"; done
```

Then check each path. A `chmod cannot open it` skip is a path left behind that needs the
`sudo rm -rf` fallback below; any other skip is a deliberate refusal, so remove nothing for it. A
path the loop did not print as skipped that still exists was left behind too, since the loop's
exit status is only the last `rm`'s. Remove nothing else: never a glob over
`<tmp>/claude-eval-*`, which also holds other runs' sandboxes, and nothing for a `tracePath` with
no `claude-eval-*` directory on it. A run
without `--keep-temp` has none left to remove; say so. When the removal is refused (a declined
prompt, a denied command, a path left behind), print that command with the remaining paths for
the user to run, and note that a directory `chmod` cannot enter still needs `sudo rm -rf`.
Preflight's `leftover_sandboxes` count stays the backstop for a run that never reached a read.

A later read of the same file finds its traces gone: the gate's unresolved-trace INVALID then comes
from this removal, not the run. Say so and report the earlier read's verdict if it is known; do not
prescribe a rerun for that reason alone.

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

## Docker link swap

When the user says yes to the swap, wrap the run step's CLI command, unchanged:

```bash
python3 "<skill-dir>/scripts/docker-links.py" run -- env TMPDIR=<dir> claude plugin eval …
```

It changes `~/.docker` outside the repository, so it runs only after the user agrees. It replaces
every link the preflight's `find` lists, or `~/.docker` when that is itself a link, with a copy of
its target, runs the command, and puts the links back when the command exits, fails, or is
interrupted. Anything written into the copies is discarded. It refuses and changes nothing on a
dangling link. Overlapping runs on one machine share one swap, and the last to exit restores. A
run killed before it could restore (`~/.docker-link-swap.json` names no live run) is put back by
the next run's start, or by `docker-links.py restore`, which refuses while a live run still
holds the copies. Never edit, move or delete the links any other way, and never repoint
`DOCKER_CONFIG`. A plugin in this repository's
own checkout still meets the linked-worktree refusal after the swap; take that route from the hub
as well. Why every link and not a list of names: [records.md](records.md#sandbox-and-credential-store).

## Record

- **Pointer:** the `--keep-temp` row of <https://code.claude.com/docs/en/plugin-evals#command-options>
  documents a per-run sandbox directory but not its name or location. The `claude-eval-*` name in
  the temp directory, the read-only `sealed/`, `out/` and `config/` subdirectories, and the
  `sealed/` directories only `sudo` could remove come from an observation on a WSL2 host on
  2026-10-13 (569 directories after about an hour of runs, issue #7431), and match the sandbox
  paths in `plugins/testing/evals/sandbox-probe-plain/samples/echo-printed.json`. The mode-000
  `sealed/` that refused `chmod -R u+w` and yielded to the per-sandbox loop above comes from a
  WSL2 host on Claude Code 2.1.309 on 2026-10-23 (issue #9414). A kept run's `tracePath` lies
  inside its `claude-eval-*` sandbox, as the `read` action's removal assumes; the validity gate
  reads it as the sandbox's `out/trace.jsonl` (`scripts/run-validity.py`).
- **As of:** 2026-10-23.
- **Recheck when:** a `--keep-temp` run prints a sandbox path outside `<tmp>/claude-eval-*` or a
  `tracePath` with no `claude-eval-*` directory on it, the docs name the sandbox directory, or a
  release note says runs remove their sandboxes.
