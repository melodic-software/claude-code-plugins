# Melodic Software. Claude Code plugins

A public [Claude Code](https://code.claude.com/docs) plugin marketplace of reusable, repo-agnostic
skills, hooks, and agents. Each plugin is designed to work in any repository and to be customized by
consumers without editing the plugin itself.

## Use this marketplace

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install <plugin-name>@melodic-software
```

Browse and manage with `/plugin`. To refresh after updates: `/plugin marketplace update melodic-software`.

When you consume this repo from a local `directory` source, the install cache keys on semver
`version`, not commit, so several commits under one version leave early installs on a stale
snapshot and `plugin update` can report "already at the latest version" while SHA lags. See
[`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md) ("Same-version commit drift") and
[#2061](https://github.com/melodic-software/claude-code-plugins/issues/2061).

### Enable plugin suggestions for an organization

Some catalog entries declare `relevance` signals so Claude Code can suggest the plugin when a
session's work matches (matching runs locally; nothing is reported anywhere). Suggestions are
opt-in per marketplace: they surface only after an administrator allowlists the marketplace in
[managed settings](https://code.claude.com/docs/en/settings#settings-files). Declare the
marketplace source AND allowlist its name in the same file:

```json
{
  "extraKnownMarketplaces": {
    "melodic-software": {
      "source": {
        "source": "github",
        "repo": "melodic-software/claude-code-plugins"
      }
    }
  },
  "pluginSuggestionMarketplaces": ["melodic-software"]
}
```

The source declaration is required for any non-official marketplace: the allowlisted name is
ignored if the locally registered marketplace came from a different source, which stops an
unrelated catalog from registering under an allowlisted name to get its plugins suggested.
Reference: [Recommend plugins for your org](https://code.claude.com/docs/en/plugin-relevance).

A few personal or external-service plugins install disabled (`defaultEnabled: false`) until the
user opts in with `/plugin enable`; an existing install is never flipped by catalog changes.

## Finding your way

- Not sure which skill to invoke? Start at the [skill cheat sheet](docs/SKILL-CHEAT-SHEET.md). A
  scan-and-go map from what you're doing to the skill to use.
- [Plugin catalog](docs/CATALOG.md). Every plugin by category, generated from the manifests and
  kept in sync by CI. New plugins clear the per-plugin migration gate in
  [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md).
- [Catalog taxonomy](docs/CATALOG-TAXONOMY.md). The category vocabulary the catalog is grouped by.

## What's here

- `.claude-plugin/marketplace.json`, the marketplace catalog.
- `plugins/`, one directory per plugin.
- `lib/`, single source of truth for the shared shell helpers; the self-contained copies vendored
  under `plugins/`, into hook and skill-script directories alike, are synced from here by
  each helper's own `scripts/sync-<helper>.sh` and CI rejects drift, so never edit a copy.
- `scripts/`, repo-level CI checks, sync scripts, and catalog generators, with their tests
  alongside.
- `prompts/`, launch-prompt templates meant to be filled in and pasted into a session; unlike
  `lib/`, nothing copies them, and plugin skills cite them by path.
- `.claude/`, this checkout's own Claude Code configuration (session and PR-linkage hooks, the
  source-control convention). It governs work done here and ships to no one.
- `.github/`, workflows plus the policy files they read (runner policy, security paths, recurring
  schedule, PR template).
- `docs/MIGRATION-PLAYBOOK.md`, design charter, extensibility model, the per-plugin migration
  gate, and the local development loop.
- `docs/`, further design records and audits (CI runner routing, extensibility-contract smoke
  tests, migration audits).
- `CLAUDE.md`, operating rules for AI agents working in this repo (fresh-docs mandate + plugin
  design rules).
- `docs/OFFICIAL-DOCS.md`, canonical index of the official Claude Code doc pages the mandate
  sends you to.

## Validate a change

The shell suites here are spawn-bound, and Git Bash on Windows pays roughly
140 ms per process spawn against roughly 3 ms on Linux, so running every
`**/*.test.sh` locally is an hours-long wall on a Windows box and nobody does
it. Run the suites that actually cover your change instead:

```shell
scripts/affected-tests.sh                 # list the suites covering your diff vs origin/main
scripts/affected-tests.sh --run           # ... and run them, sequentially
scripts/affected-tests.sh --explain       # ... and say why each one was selected
scripts/affected-tests.sh path/to/file.sh # explicit paths instead of a diff
```

It maps a changed file to its co-located suite, to any suite that names it, and
to its dependents transitively, and it fans a shared-lib change out to every
carrying plugin by reading the `copies=(...)` array out of that lib's
`scripts/sync-*.sh` manifest, the same manifest CI's `*-sync` lanes enforce. The
fan-out is derived on every run, never transcribed, so a new carrying plugin is
covered the moment it exists.

All four ecosystems that carry suites here are selected, each by its own naming
convention: shell `*.test.sh`, Node `*.test.js` and `*.test.mjs`, Python
`test_*.py`, and Pester `*.Tests.ps1`. Only the shell suites are executed by
`--run`, because the others are driven by lane-specific invocations that cannot
be derived from a suite path; those are named as `NOT RUN` and `--run` exits 3
rather than reporting success over suites that never executed.

A changed file that maps to nothing is an **error**, not an empty selection.
"zero suites" must never be read as "nothing to run". Path classes that
genuinely carry no suite are recorded, with the CI lane that does cover them, in
[`scripts/affected-tests-no-suite.txt`](scripts/affected-tests-no-suite.txt);
`--allow-unmapped` is the escape hatch for everything else. That list is for
prose and manifests, never for code: a source file with no coverage is supposed
to fail here.

The runner is deliberately sequential: parallelising it measured sublinear
(the suites are spawn-bound), and several guardrails suites assert wall-clock
ceilings that fail spuriously under concurrency. Selection is the lever.

CI is unaffected, it still runs everything.

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## License

[MIT](LICENSE).
