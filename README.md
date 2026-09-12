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
[`docs/migration-playbook.md`](docs/migration-playbook.md) ("Same-version commit drift") and
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
ignored if the locally registered marketplace came from a different source. That rule stops an
unrelated catalog from registering under an allowlisted name to get its plugins suggested.
Reference: [Recommend plugins for your org](https://code.claude.com/docs/en/plugin-relevance).

A few personal or external-service plugins install disabled (`defaultEnabled: false`) until the
user opts in with `/plugin enable`; an existing install is never flipped by catalog changes.

## Finding your way

- Not sure which skill to invoke? Start at the [skill cheat sheet](docs/skill-cheat-sheet.md). A
  scan-and-go map from what you are doing to the skill that does it.
- [Plugin catalog](docs/catalog.md). Every plugin by category, generated from the manifests and
  kept in sync by CI. New plugins clear the per-plugin migration gate in
  [`docs/migration-playbook.md`](docs/migration-playbook.md).
- [Catalog taxonomy](docs/catalog-taxonomy.md). The category vocabulary the catalog is grouped by.

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
- `docs/migration-playbook.md`, design charter, extensibility model, the per-plugin migration
  gate, and the local development loop.
- `docs/`, further design records and audits (CI runner routing, extensibility-contract smoke
  tests, migration audits).
- `CLAUDE.md`, operating rules for AI agents working in this repo (fresh-docs mandate + plugin
  design rules).
- `docs/official-docs.md`, canonical index of the official Claude Code doc pages the mandate
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

`--run` is a Linux gate. On a Windows Git Bash host a standing set of suites
fails for reasons that belong to the host rather than to the tree: text-mode
CRLF translation (a native jq and Git Bash line-ending handling), no
unprivileged symlink right, MSYS drive-letter paths against the POSIX form in
fixture assertions, and a missing `scc`. Its exit code there reports host
capability, not whether your change is good, so Windows is not a supported host
for the full `--run` gate ([#3966](https://github.com/melodic-software/claude-code-plugins/issues/3966)).
Selection itself is host-neutral: on Windows, use the listing forms above to see
what your change affects and run individual suites by hand. CI's Linux lanes are
the gate that decides.

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
to fail here. A **deletion** is the one exception: a changed path that no longer
exists and that nothing claims is reported as a visible `deleted:` note instead
of the error, because there is no content left to cover. A deletion that a
surviving suite still names (a co-located test left behind, a suite that
references the dead path) keeps selecting those suites, which are exactly what
fails loudly if the deletion broke something.

The runner is deliberately sequential: parallelising it measured sublinear
(the suites are spawn-bound), and several guardrails suites assert wall-clock
ceilings that fail spuriously under concurrency. Selection is the lever.

CI is unaffected, it still runs everything.

### The check-script contract

`scripts/check-*.sh` is one family with one caller-visible interface, so a CI
lane, a wrapper, or an agent reads a run's outcome without knowing which member
produced it.

| Exit | Meaning |
|---|---|
| `0` | Clean. The check ran over its whole corpus and found nothing. |
| `1` | Findings. The check ran and something in the tree is wrong. |
| `2` | Environment or usage. The check could not run: a missing tool, a bad argument, a repo root or shared library that did not resolve, a git query that failed. Nothing was inspected, so this is never a pass. |

Findings and diagnostics go to **stderr**; **stdout** carries the clean-run
statement and, for the discovery or list modes some members offer, the report
that mode exists to print.

Keeping `1` and `2` apart is the whole point: "your tree is wrong" and "I could
not look" are different answers, and a lane that reads only success or failure
collapses them into one. This is the mechanical form, for this family, of the
fail-loud rule in
[`docs/conventions/liveness-assertion/`](docs/conventions/liveness-assertion/README.md).
An environment failure is spelled out rather than left to `set -e`: resolving the
repo root and sourcing a shared library each end in `|| exit 2`, because `set -e`
would exit with the failing command's own status and hand the caller a `1` that
reads as findings.

[`scripts/check-script-contract.test.sh`](scripts/check-script-contract.test.sh)
holds the contract. Every member is registered there and a new one fails as
unregistered. Each member that declares a prerequisite is run with that
prerequisite taken away and must exit `2` on stderr; each member with a fixture
recipe is also run clean (exit `0`, statement on stdout) and against a seeded
violation (exit `1`, finding on stderr and not on stdout). A member with no
recipe yet is held to those last two halves by its own co-located suite.

Three readings diverge on purpose and are recorded here rather than forced into
line:

- `scripts/check-hook-exec-form.sh` treats a hook declaration it cannot parse as
  a finding (`1`), not an environment problem. The input is what is wrong, and
  clearing a file the gate never read is the silent no-op it exists to catch.
- `scripts/check-killswitch-hoist.sh` stops at `1`, not `2`, when the hook corpus
  scans to empty or the inlined kill-switch predicate no longer agrees with the
  `hook::is_enabled` it duplicates. Both are statements about the tree, not about
  the host.
- `scripts/check-changelog-parity.sh` discusses exit `128` and `141` at length
  and emits neither. Those are git's "no merge base" and a reader killed by
  SIGPIPE, each converted to an `exit 2` or read correctly. Grepping the file for
  those numbers finds the guards, not divergence.

The contract governs the observable interface, not the option set: `set -euo`
and `set -uo` both appear in the family and neither is required, which is why
the prologue states its own `|| exit 2` instead of depending on which one is in
force. Members still resolving the repo root under `set -e` alone are aligned on
touch.

## Official documentation

This repo tracks policy and wiring only; authoritative behavior lives in the official docs, which must
be read fresh rather than recalled. Start at the
[Claude Code plugins guide](https://code.claude.com/docs/en/plugins).

## What this marketplace actually publishes

This repository is the only authoritative listing of what this marketplace publishes. The plugins and
skills it ships are the ones present in `plugins/` on the default branch, and the
[marketplace manifest](.claude-plugin/marketplace.json) is the machine-readable form of that list.

Several third-party aggregator and directory sites republish Claude Code skill listings, and some of
them attribute skills to this publisher that have never existed here. A search of the full commit
history of this repository found no trace of them. If you find a skill credited to this marketplace
that you cannot locate in `plugins/` on the default branch, it is not ours, whatever a directory
says. Install from the source above rather than from a mirror or a directory listing, and treat an
aggregator's metadata as unverified.

## License

[MIT](LICENSE).
