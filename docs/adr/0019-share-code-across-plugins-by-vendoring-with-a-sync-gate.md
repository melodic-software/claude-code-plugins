# Share code across plugins by vendoring with a sync gate, not a shared package

- Status: accepted; amended 2026-10-02 (copies are generated output, see the amendment below);
  delivery amended by [ADR 0048](0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)
  for plugins in fragment mode (see the amendment at the end)
- Date: 2026-07-04

## Decision

Decided when four plugins carried byte-identical `hooks/hook-utils.sh` copies, the Rule-of-Three
threshold below, exceeded. The mechanism is **single source of truth at authoring time, plain copies
at runtime**:

- `lib/hook-utils.sh` is the only copy to edit. `scripts/sync-shared-copies.sh` generates it into
  every carrying plugin; a plugin opts in by registering its `hooks/hook-utils.sh` copy in
  `scripts/shared-copies.txt`.
- CI fails a PR when any plugin copy drifts from the source, and when the lib
  changed but a carrying plugin's manifest version did not: the plugin `version` is the update cache
  key, so an unbumped plugin never delivers the change to consumers. A bump that only carries a sync
  gets the standard CHANGELOG entry, "Shared `hook-utils.sh` synced (<link to the change>); no
  change to this plugin's hooks." (every cluster names its own source file and the directory its
  copies live in), not a copy of another plugin's release note.
- Runtime is untouched: each installed plugin stays self-contained under cache isolation, with no
  cross-plugin coupling and no change to the one-plugin install UX.

Alternatives weighed (docs verified 2026-07-03):

- **Dependency plugin carrying the lib: rejected as not viable.** A hook sees only its own
  `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; no variable or documented mechanism exposes a
  *dependency's* install path, and cache directories are per-version (with a commit-SHA suffix for
  tag-resolved dependencies), so computing the path is unsupported by design
  (<https://code.claude.com/docs/en/plugins/loading#find-plugins-on-disk>;
  <https://code.claude.com/docs/en/plugins/dependencies>). **Recheck trigger:** Claude Code
  ships a documented dependency-path variable; that would also allow sharing the lib beyond this
  marketplace.
- **Marketplace-internal symlinks: rejected (amended 2026-10-02, was deferred).** Documented
  mechanism: a symlink from a plugin to a file elsewhere in the same marketplace is dereferenced at
  install, copying the target's content into the cache: native SSOT with no sync script
  (<https://code.claude.com/docs/en/plugins/host-marketplace#share-files-within-a-marketplace-with-symlinks>).
  Rejected because default Git for Windows does not create symlinks: it ships with symlink support
  disabled (<https://gitforwindows.org/symbolic-links.html>), and with `core.symlinks` false Git
  checks a symlink out as a small plain file containing the link text
  (<https://git-scm.com/docs/git-config#Documentation/git-config.txt-coresymlinks>), both fetched
  2026-10-02. Windows is the primary environment on both the authoring and consuming side, so a
  default clone there would carry text stubs where the library should be. Such symlinks are also
  *skipped* for `--plugin-dir` / local-path installs, which breaks the local development loop.
  **Recheck trigger:** Git for Windows enables symlinks by default, and the documented
  `--plugin-dir` / local-path handling stops skipping marketplace symlinks.
- **Copies with only a byte-identity CI gate: subsumed.** The chosen shape is that gate plus a
  canonical source and one sync script, removing the edit-×N-by-hand step at negligible cost.

The lib's unit tests live beside the source as one consolidated suite (`lib/hook-utils.test.sh`,
run by the same CI lane) rather than as per-plugin copies: byte-identity of the copies means
testing the source covers them. Plugins keep only their own black-box hook contract tests.

### Vendored Node packages: the `file:` + `--install-links` convention

Shared **Node** source (not a shell lib) is vendored as a plain package tree and consumed through
npm's `file:` link, because a cache-isolated plugin cannot reference a package outside its own
directory:

- The vendored package is a self-contained runtime-source copy (its own test suite, build config,
  and `node_modules` omitted). A consumer `package.json` depends on it with `"@scope/name":
  "file:<relative-path>"`.
- The skill's `setup-deps.mjs` installs it into `${CLAUDE_PLUGIN_DATA}` with
  `npm install --omit=dev --install-links <package-dir>`: `--install-links` packs the `file:`
  package as a real install (copied source) rather than a symlink back into the plugin cache, so it
  survives cache isolation. Install is idempotent: a stored fingerprint hashes `package.json` **and
  the entire vendored tree** (the packages install from source, not by version, so a source change
  with no manifest bump must still reinstall).
- Runtime resolves bare specifiers (`@scope/name/subpath`) from `${CLAUDE_PLUGIN_DATA}/node_modules`
  via an ESM resolve-hook (`run.mjs` → `register-hook.mjs`/`resolve-hook.mjs`), never a hardcoded
  path into the plugin cache.

### Intra-plugin sharing: one committed copy, no sync script

When the second consumer is **another skill in the same plugin** (not another plugin), the
cross-plugin machinery collapses: put the vendored source once at the plugin root (`vendor/`), and
point every consuming skill's `file:` link and `setup-deps.mjs` fingerprint at that single copy
(`file:../../../vendor/*` from `skills/<skill>/extraction/`). No `sync-*.sh` propagation and no
byte-drift CI gate are needed: there is only one committed copy, so nothing can drift. The
invariant that **replaces** the byte-drift gate is delivery-by-version: editing the shared source
obligates a plugin `version` bump, since the version is the update cache key. (`knowledge`'s
`repo-analysis` + `video-digestion`, shared by its `video-digest` and `course-digest` skills, is the
reference instance.) Reach for the cross-plugin shape above only once a *second plugin* genuinely
needs the same source.

## Amendment (2026-10-02): one canonical source, every copy generated

This amends the decision above; it does not supersede it. Each shared library has exactly one
canonical source, and every per-plugin copy is **generated output**, not a hand-synced duplicate:

- `scripts/shared-copies.txt` registers each copy as a `<canonical> <copy>` line.
  `scripts/sync-shared-copies.sh` is the one regen command: it rewrites every registered copy, and
  running it twice produces no diff. Run it after editing a canonical; a contributor may wire it, or
  its `--check`, into a local pre-commit hook.
- A generated copy is the canonical with a two-line header after any shebang line. The header says
  the file is generated, names its canonical source and the regen command, and tells the reader to
  edit the canonical instead. The header names no plugin, so copies of one canonical stay
  byte-identical to each other, which is what `check-cross-plugin-source-drift.sh` compares.
- CI only verifies. `sync-shared-copies.sh --check` fails when any copy differs from what its
  canonical generates, and it never writes; CI never runs the regen and never commits.
- The version-bump gate stays. `sync-shared-copies.sh --check-bump <base-ref>` fails a change to a
  canonical when any carrying plugin's manifest version did not move, with the same sync-only
  CHANGELOG wording as above and the same exemption for a plugin absent at the base ref.
- `--print-manifest` publishes one `src` block per canonical, followed by its `copy` lines, and
  `scripts/affected-tests.sh` reads every block for its shared-lib fan-out.

Settled with this amendment and not reopened by it: copies, not symlinks (the alternative above);
no dependency plugin (the alternative above); and no versioning of the copy or registry format,
since a format change migrates every copy in the same change.

The html-escape cluster (`lib/html-escape.mjs`, one carrier: `review`) was the pilot: its hand-run
`scripts/sync-html-escape.sh` is deleted and its copy is generated. Every other cluster has since
moved the same way, `lib/hook-utils.sh` last: its copies are registered, regenerated, its
`sync-*.sh` script and test are deleted, and its CI steps call the generator. No hand-run sync
script and no shared sync-cluster helper remain.

A canonical that lived inside one plugin moved to `lib/` when its cluster migrated, so that plugin's
copy is generated like the rest and every copy of a library stays byte-identical to every other. A
Markdown canonical gets the header as an HTML comment after any frontmatter block. The standards
contract keeps one gate the generator does not own: `scripts/check-standards-contract-bump.sh`
requires its frontmatter semver and CHANGELOG entry to move with a change to the contract or its
schema.

## Addendum (2026-09-07): one sync lane with N steps, not one lane per library

Recorded by the ci-perf program (melodic-software/github-iac#378, Phase 9). The decision above is
unchanged: a shared source still has one canonical copy, a `sync-*.sh` script still propagates it,
and CI still fails a pull request when a copy drifts or when the lib changed without a plugin
version bump. What changed is where that gate runs.

Each shared source used to get **its own CI job**. Before claude-code-plugins#3696
(`31dc91ded6cc51cac47c6cb27c49788ba9cde449`, merged 2026-09-04) `ci.yml` carried thirteen
`*-sync` jobs, one per library: `hook-utils-sync`, `rewrite-guard-sync`,
`parse-concern-value-sync`, `managed-scope-sync`, `state-key-sync`, `spawn-noise-sync`,
`check-retirements-sync`, `legacy-statusline-detect-sync`, `unwrap-before-compose-sync`,
`resolve-convention-home-sync`, `resolve-convention-pattern-sync`, `index-regen-sync` and
`standards-contract-sync`. Each was a runner, a pinned `actions/checkout`, a
`checkout-with-base` deepen to full history plus a base fetch, the `--check` and `--check-bump`
steps, and in eleven of the thirteen a per-library test step as well. No toolchain install: these
are shell scripts, and the toolchains belonged to the test lane. The cost was the runner, the
checkout and the unshallow, paid thirteen times over.

**The cost is latency here and money on the fleet.** This repository is public and the jobs ran on
`ubuntu-24.04`, a standard runner, so nothing was billed: what thirteen jobs bought was thirteen
runner startups and thirteen unshallows on the critical path, and thirteen concurrency slots taken
from every other lane in the run. In the private repositories the same ci-perf program covers, the
identical shape spends the metered minute pool instead, because GitHub rounds the minutes and
partial minutes each job uses up to the nearest whole minute
(<https://docs.github.com/en/billing/reference/actions-runner-pricing>), so a per-library job floor
is a per-library pooled minute there. That organization caps Actions spend at `$0` with
`prevent_further_usage` (melodic-software/github-iac ADR 0008), so the failure mode is not a line
item but a hard stop on every private repository's hosted CI once the pool is gone.

**They are now steps, not jobs.** Every shared-library gate, the generator's `--check` and
`--check-bump` (see the amendment above), runs as a step of `check-plugins`, the job that holds the
plugin contracts across files, which performs that same deepen and base fetch once for every bump
check. Adding a fourteenth shared source therefore adds a step to an existing job, and adding a job
is the thing to justify rather than the default.

One thing was lost and is worth naming rather than glossing. The old **job** name
(`state-key-sync`, `index-regen-sync`) was the discriminator that said which library failed. Every
step kept the name it had, but those names were never carrying that load: seven of the twelve drift
checks name their library and five do not, and none of the `--check-bump` steps do, seven of them
sharing the string "Verify carrying plugins bumped when canonical changed". So a red bump check now
needs its log read to say which library it was. That is the price paid for the consolidation, and a
new sync step should name its library in its step name so the price stops growing.

Nothing about the invariant moved: byte-drift is still fatal, the `--check-bump` half still fails a
lib change whose carrying plugin's manifest version did not move, and the intra-plugin `vendor/`
shape above still replaces the byte-drift gate with delivery-by-version
(`check-vendor-version-bump.sh`, its own gate). **Recheck trigger:** a sync gate that needs a
different runner, a different toolchain, or an isolation the consolidated job cannot give it earns
its own job again; say which of the three when adding one.

## Amendment (2026-10-04): fragment-mode plugins deliver through a changelog fragment

[ADR 0048](0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)
moves the version bump out of pull requests. For a plugin listed in `scripts/fragment-plugins.txt`,
"bump every carrying plugin" (the Decision and the 2026-10-02 amendment) reads "add a fragment whose
`bump` is not `none` for every carrying plugin"; the release pull request then raises the version.
`--check-bump` accepts either through the shared predicate in `scripts/lib/changelog-fragments.sh`,
and a plugin not yet listed still bumps per pull request. The sync-only wording moves into the
fragment body under `### Changed`. One command writes it for every fragment-mode carrier:

```bash
scripts/new-changelog-fragment.sh --stdin --carriers-of lib/hook-utils.sh patch <<'EOF'
### Changed

- Shared `hook-utils.sh` synced (<link to the change>); no other change to this plugin.
EOF
```

The version is still the update cache key; only the change that raises it moved.
