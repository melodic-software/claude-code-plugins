# Script contracts: `fleet-state.sh`, `cache-content-check.sh`, `converge-plan.sh`, `normalize-enabled-plugins.sh`

The four read-and-write contracts `sync-run.sh` and `converge` are bound to. Each script's own
header carries the same contract; this file restates it once for the caller's side. Read it when a
step misbehaves, when `converge` needs an id list, or when a caller other than `sync-run.sh` is
about to invoke one of the scripts.

## `fleet-state.sh`: the only reader of the internal files

Every action starts by calling the bundled read-only script, never hand-parse the internal JSON
files directly, and never write them. The one sanctioned exception is `converge`'s committed-enable
check ([converge.md](converge.md) Step 2), which reads one `enabledPlugins` key in a tracked project
settings file:

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
`sync` and of `audit` calls it ONCE per marketplace:

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
committed-enable read are in its header comment and in [converge.md](converge.md) Steps 1 and 2.

## `normalize-enabled-plugins.sh`: the one writer, user scope only

After Step 4 installs anything, reorder user-scope `enabledPlugins` with the bundled writer.
Never hand-edit `~/.claude/settings.json`:

```bash
"<skill-dir>/scripts/normalize-enabled-plugins.sh"
```

That write is user-scope only. A project-scope map is inspected with `--report-project` and never
rewritten. See [sync.md](sync.md).
