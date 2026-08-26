# Share code across plugins by vendoring with a sync gate, not a shared package

- Status: accepted
- Date: 2026-07-04

## Decision

Decided when four plugins carried byte-identical `hooks/hook-utils.sh` copies — the Rule-of-Three
threshold below, exceeded. The mechanism is **single source of truth at authoring time, plain copies
at runtime**:

- `lib/hook-utils.sh` is the only copy to edit. `scripts/sync-hook-utils.sh` propagates it into every
  carrying plugin; a plugin opts in by committing an initial `hooks/hook-utils.sh` copy.
- CI (`hook-utils-sync` lane) fails a PR when any plugin copy drifts from the source, and when the lib
  changed but a carrying plugin's manifest version did not — the plugin `version` is the update cache
  key, so an unbumped plugin never delivers the change to consumers.
- Runtime is untouched: each installed plugin stays self-contained under cache isolation, with no
  cross-plugin coupling and no change to the one-plugin install UX.

Alternatives weighed (docs verified 2026-07-03):

- **Dependency plugin carrying the lib — rejected as not viable.** A hook sees only its own
  `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; no variable or documented mechanism exposes a
  *dependency's* install path, and cache directories are per-version (with a commit-SHA suffix for
  tag-resolved dependencies), so computing the path is unsupported by design
  (<https://code.claude.com/docs/en/plugins-reference#plugin-caching-and-file-resolution>;
  <https://code.claude.com/docs/en/plugin-dependencies>). **Recheck trigger:** Claude Code
  ships a documented dependency-path variable — that would also allow sharing the lib beyond this
  marketplace.
- **Marketplace-internal symlinks — deferred.** Documented mechanism: a symlink from a plugin to a
  file elsewhere in the same marketplace is dereferenced at install, copying the target's content into
  the cache — native SSOT with no sync script
  (<https://code.claude.com/docs/en/plugins-reference#share-files-within-a-marketplace-with-symlinks>).
  Deferred because such symlinks are *skipped* for `--plugin-dir` / local-path
  installs (breaking the local development loop above) and are fragile to author and clone on Windows,
  the primary environment on both the authoring and consuming side. **Recheck trigger:** the dev
  loop stops depending on `--plugin-dir`, the documented `--plugin-dir` / local-path handling changes
  so marketplace symlinks are no longer skipped (the upstream premise this deferral rests on), or the
  Windows constraint lifts.
- **Copies with only a byte-identity CI gate — subsumed.** The chosen shape is that gate plus a
  canonical source and one sync script, removing the edit-×N-by-hand step at negligible cost.

The lib's unit tests live beside the source as one consolidated suite (`lib/hook-utils.test.sh`,
run by the same CI lane) rather than as per-plugin copies — byte-identity of the copies means
testing the source covers them. Plugins keep only their own black-box hook contract tests.

### Vendored Node packages — the `file:` + `--install-links` convention

Shared **Node** source (not a shell lib) is vendored as a plain package tree and consumed through
npm's `file:` link, because a cache-isolated plugin cannot reference a package outside its own
directory:

- The vendored package is a self-contained runtime-source copy (its own test suite, build config,
  and `node_modules` omitted). A consumer `package.json` depends on it with `"@scope/name":
  "file:<relative-path>"`.
- The skill's `setup-deps.mjs` installs it into `${CLAUDE_PLUGIN_DATA}` with
  `npm install --omit=dev --install-links <package-dir>` — `--install-links` packs the `file:`
  package as a real install (copied source) rather than a symlink back into the plugin cache, so it
  survives cache isolation. Install is idempotent: a stored fingerprint hashes `package.json` **and
  the entire vendored tree** (the packages install from source, not by version, so a source change
  with no manifest bump must still reinstall).
- Runtime resolves bare specifiers (`@scope/name/subpath`) from `${CLAUDE_PLUGIN_DATA}/node_modules`
  via an ESM resolve-hook (`run.mjs` → `register-hook.mjs`/`resolve-hook.mjs`), never a hardcoded
  path into the plugin cache.

### Intra-plugin sharing — one committed copy, no sync script

When the second consumer is **another skill in the same plugin** (not another plugin), the
cross-plugin machinery collapses: put the vendored source once at the plugin root (`vendor/`), and
point every consuming skill's `file:` link and `setup-deps.mjs` fingerprint at that single copy
(`file:../../../vendor/*` from `skills/<skill>/extraction/`). No `sync-*.sh` propagation and no
byte-drift CI gate are needed — there is only one committed copy, so nothing can drift. The
invariant that **replaces** the byte-drift gate is delivery-by-version: editing the shared source
obligates a plugin `version` bump, since the version is the update cache key. (`knowledge`'s
`repo-analysis` + `video-digestion`, shared by its `video-digest` and `course-digest` skills, is the
reference instance.) Reach for the cross-plugin shape above only once a *second plugin* genuinely
needs the same source.
