# Script contracts: `fleet-state.sh`, `cache-content-check.sh`, `converge-plan.sh`, `normalize-enabled-plugins.sh`

The four read-and-write contracts `sync-run.sh` and `converge` are bound to, stated once for the
caller's side. Read it when a step misbehaves, when `converge` needs an id list, or when a caller other than `sync-run.sh` is
about to invoke one of the scripts.

## `fleet-state.sh`: the only reader of the internal files

Every action starts by calling the bundled read-only script, never hand-parse the internal JSON
files directly, and never write them. `converge`'s committed-enable check
([converge.md](converge.md) Step 2) takes each path's `enabledPlugins` entry from the report's
`projectEnabledEntry` and reads no settings file:

```bash
"<skill-dir>/scripts/fleet-state.sh" [--marketplace <name> | --all]
"<skill-dir>/scripts/fleet-state.sh" [--marketplace <name>] --ids <selector>
"<skill-dir>/scripts/fleet-state.sh" --ids <selector> --from <report.json>
```

The second form emits the plain id list a mutating step loops, instead of the JSON report. One
tab-separated record per line, first field always the fully-qualified `<name>@<marketplace>`. Use it
whenever a step needs ids; never hand-write a `jq` extraction over the JSON, which reintroduces a
trailing `\r` on Windows and silently corrupts every id but the last (see
[gotchas.md](gotchas.md)).

The third form projects that same id list from a report already on disk rather than recomputing the
fleet, and is the form `sync`'s steps use: each step re-reads the full report anyway, and every
selector is derivable from it. Same script, same projection, so the `\r` protection is unchanged.

`sync-run.sh` is what calls these scripts during `sync` and `audit`; the contracts here are what it
and any other caller are bound to.

Read [scope-semantics.md](scope-semantics.md) before interpreting the report. In particular the
`versionsMatch` filter rule, never count or present a raw `divergences[]` length, is defined once
there, under "Divergence is not automatically actionable"; every other mention in this skill points
at it rather than restating it.

## `cache-content-check.sh`: does the cache match the recorded commit

A second read-only script answers the question `fleet-state.sh` structurally cannot: whether the
files in a plugin's cache directory actually match the commit its install record claims. Step 5b of
`sync` and of `audit` calls it once per marketplace:

```bash
"<skill-dir>/scripts/cache-content-check.sh" --marketplace <name> [--scope user|project|all]
"<skill-dir>/scripts/cache-content-check.sh" --marketplace <name> --ids
```

`--ids` emits the stale ids alone, one per line, CR-free, the same contract and for the same reason
as `fleet-state.sh --ids`. Step 5b does not use it beside the JSON form: the ids are already in that
JSON, and a second call would repeat the run's most expensive read. It is the fallback for a JSON
that could not be produced. The script never writes anything and never runs `git fetch`; it
compares only installs recorded at the marketplace clone's HEAD, and reports every other install as
`not-at-head`, counted in `not_checked`. See
[sync.md](sync.md) Step 5b, [stale-records-cache-content.md](stale-records-cache-content.md) for
how the finding is reported, and [scope-semantics.md](scope-semantics.md) for the mechanism that
makes a cache directory and its recorded sha disagree in the first place.

Each install record gets one `verdict`:

| Verdict | Meaning |
|---|---|
| `match` | every file at the recorded sha is in the cache with the same blob id, and the cache has no extra file |
| `stale-content` | at least one file differs, is missing from the cache, or is in the cache and not at the sha; `paths[]` lists some of them |
| `not-at-head` | the recorded `gitCommitSha` is not the clone's HEAD, so the record is not compared; counted in `not_checked` |
| `no-clone-head` | the clone's HEAD names no commit (an unborn branch) |
| `no-git-commit-sha` | the record has no `gitCommitSha` |
| `no-install-location` | the marketplace has no `installLocation`, or it is not a directory here |
| `not-a-git-worktree` | the `installLocation` is not a git work tree |
| `no-source` | the plugin is absent from `marketplace.json` at the recorded sha, its `source` is not a plain path, or that commit has no `marketplace.json` |
| `no-source-at-sha` | the plugin's source directory names no path at that sha, so there is no expected tree to compare |
| `install-path-missing` | the record's `installPath` is not a directory |
| `hash-batch-misaligned` | `git hash-object --stdin-paths` returned fewer hashes than paths, so the two sides cannot be lined up |

The JSON object is `{marketplace, scope, checked, match, stale_content, unverifiable, not_checked,
skipped_absent_project_paths, installs: […]}`. `unverifiable` counts every verdict other than
`match`, `stale-content` and `not-at-head`; `checked` is the sum of `match`, `stale_content`,
`unverifiable` and `not_checked`. `skipped_absent_project_paths` counts project and local records
whose `projectPath` is not a directory on this machine; they are not in `checked`.
`installs[].unreleased_changes` is true when the clone's work tree holds `.changes/<plugin>/`. With
`--all` the output is `{marketplaces: {"<name>": <one marketplace's object>}}`, and a marketplace
that fails appears as `{"<name>": {error: …}}` without stopping the others.

## `converge-plan.sh`: the converge plan, read-only

`converge` Step 1 calls it once. It reads a `fleet-state.sh` report and prints one JSON plan, one row
per lagging `(projectPath, id)` pin grouped by path, each with its strategy, exact command and class:

```bash
"<skill-dir>/scripts/converge-plan.sh" [--marketplace <name>]
"<skill-dir>/scripts/converge-plan.sh" --from <report.json> [--marketplace <name>]
```

The first form runs `fleet-state.sh` itself; the second plans a single-marketplace report already on
disk. Exit `0` is a plan (an empty one is success), `1` a marketplace that could not be resolved, `2`
a usage error or an unusable report (an `--all` envelope is refused by name). The script never runs a
`claude plugin` command and never writes a file. The classes, the strategy rules and the
committed-enable read are in [converge.md](converge.md) Steps 1 and 2.

## `normalize-enabled-plugins.sh`: the one writer, user scope only

After Step 4 installs anything, reorder user-scope `enabledPlugins` with the bundled writer.
Never hand-edit `~/.claude/settings.json`:

```bash
"<skill-dir>/scripts/normalize-enabled-plugins.sh"
```

That write is user-scope only. A project-scope map is inspected with `--report-project` and never
rewritten. See [sync.md](sync.md).

It prints one line. `normalized moved=K keys=N` is a reorder that moved K of the N keys, K being the
fewest keys the reorder moves, so one appended key reads `moved=1` at any N. `--check` prints
`would-normalize moved=K keys=N` and exits `1`. A map already in order prints
`already-sorted keys=N`. A `--file` path that does not exist prints `missing-file keys=0` and exits
`0`: nothing is written, and it is never reported as `already-sorted`. The report renders it as
`Normalized: skipped, no user settings file` (`Would normalize:` in audit).
