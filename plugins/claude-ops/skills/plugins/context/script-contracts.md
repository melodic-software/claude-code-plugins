# Script contracts: `fleet-state.sh`, `cache-content-check.sh`, `normalize-enabled-plugins.sh`

The three read-and-write contracts `sync-run.sh` and `converge` are bound to. Each script's own
header carries the same contract; this file restates it once for the caller's side. Read it when a
step misbehaves, when `converge` needs an id list, or when a caller other than `sync-run.sh` is
about to invoke one of the scripts.

## `fleet-state.sh`: the only reader of the internal files

Every action starts by calling the bundled read-only script, never hand-parse the internal JSON
files directly, and never write them:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name> | --all]
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh [--marketplace <name>] --ids <selector>
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/fleet-state.sh --ids <selector> --from <report.json>
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
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> [--scope user|project|all]
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/cache-content-check.sh --marketplace <name> --ids
```

`--ids` emits the stale ids alone, one per line, CR-free, the same contract and for the same reason
as `fleet-state.sh --ids`. Step 5b does not use it beside the JSON form: the ids are already in that
JSON, and a second call would repeat the run's most expensive read. It is the fallback for a JSON
that could not be produced. The script never writes anything and never runs `git fetch`; a commit
that is not in the local marketplace clone is reported as `sha-not-local`, not fetched. See
[sync.md](sync.md) Step 5b, [stale-records-cache-content.md](stale-records-cache-content.md) for
how the finding is reported, and [scope-semantics.md](scope-semantics.md) for the mechanism that
makes a cache directory and its recorded sha disagree in the first place.

## `normalize-enabled-plugins.sh`: the one writer, user scope only

After Step 4 installs anything, reorder user-scope `enabledPlugins` with the bundled writer.
Never hand-edit `~/.claude/settings.json`:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/plugins/scripts/normalize-enabled-plugins.sh
```

That write is user-scope only. A project-scope map is inspected with `--report-project` and never
rewritten. See [sync.md](sync.md).
