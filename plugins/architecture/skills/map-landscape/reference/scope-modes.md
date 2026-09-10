# Scope modes beyond the default

The default scope, the current repository plus its reference graph, needs nothing from this file.
Read this when the invocation carries `--root` or `--remote`.

## `--root <dir>` discovery

Repeatable. Discovers repositories under each root, then charts them.

### When the `repo-fleet-hygiene` plugin is installed

That plugin owns bounded fleet discovery and canonical-checkout resolution, so delegate rather than
walking. Resolve the memory slice per `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`, `mkdir -p` it,
then invoke via the Skill tool:

```text
/repo-fleet-hygiene:audit <root>... --plan-file <memory_dir>/<topic-slug>/fleet-plan.json
```

Confirm the plan's `schema_version` is `1` before reading `repositories[]`. Use each entry's
`canonical` path and its `remote`. Announce that the collaborator's audit collects GitHub evidence
and may need `gh` authentication.

**Filter `repositories[]` on `discovered` before charting anything.** That collaborator's scope is
additive: it merges the roots you asked for with the roots its own config declares. Keep only
entries whose `discovered` path lies under a root this invocation named. An unfiltered read charts
the operator's whole configured fleet, including personal directories nobody asked about.

`fleet-plan.json` is a temp artifact. It lives in the memory slice of the topic-docs convention,
which self-ignores. Never commit it, and never copy it into the architecture directory as a record
of the fleet.

### When the plugin is absent

Fall back to the bundled walk, and ANNOUNCE the fallback: the operator has to know the collaborator
did not run. Fall back the same way when the plan file is missing or carries a `schema_version`
other than `1`, rather than parsing a plan shape nothing verified.

The walk: recurse from each root to depth 5; a `.git` entry marks a repository and is not descended
into; skip `node_modules`, `vendor`, and `.venv`; the canonical checkout is the first record of
`git worktree list --porcelain`, not `git rev-parse --show-toplevel`.

## `--remote` facts

`--remote` collects facts for referenced repositories that are not checked out locally.
`--remote=all` extends that to external ones. Without the flag no network call is made at all, and
the record says `remote: not used`.

- **Presence-gate first.** Use the GitHub MCP tools when they resolve, otherwise an authenticated
  `gh`. When neither is available, name the missing backend in the closing report and continue
  local-only rather than failing the run. Never prompt for credentials.
- **A local checkout always wins.** A repository probed from a local checkout keeps those facts;
  remote facts fill only what no local checkout could supply.
- **Fetch these and nothing else**: primary language, default branch, `pushed_at` (recorded as
  `last_touched`), archived, visibility, and the CODEOWNERS default rule when readable. Manifests
  only through the contents API, only at the repository root, and only the manifest names the
  runtime probe already knows.
- **Every remote fact names its call.** Its `evidence` entry is the API call or `gh` command that
  supplied it, and it reads `pushed_at (remote)` rather than the local-HEAD wording, so a later
  local-only run can explain why `last_touched` moved backwards.
- **An archived repository is charted and marked.** Archiving is a fact about the system, not a
  reason to hide it: a landscape that quietly drops archived repositories hides exactly the
  dependencies worth acting on. Mark it in the node annotation and in the portfolio row.
- **Externals stay read-only.** `--remote=all` reads facts about an external repository. It never
  writes to one, and it does not extend the graph a second hop.
