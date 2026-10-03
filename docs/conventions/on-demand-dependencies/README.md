# On-demand dependencies: install pinned packages, never vendor them

Version: 2.2.0
Last updated: 2026-10-02

A marketplace-wide rule for **third-party packages a plugin needs at run time**: commit the pinned
manifest and lockfile, install from them on demand into the plugin's data directory, and fail
closed with the exact repair command when the install cannot happen. No committed `node_modules`,
no committed bundle of third-party code. Rules 1-4 are the npm form; the [Python](#python) section
is the same contract for pip.

The operator set this rule repo wide on 2026-10-01, while planning the inventory parser
([#5640](https://github.com/melodic-software/claude-code-plugins/issues/5640)): a one-time install
of pinned, publicly available packages is preferred over committing a vendored bundle.

## Boundary

- **In scope:** packages from a public registry that a plugin component loads at run time (a
  skill's helper script, a hook, an MCP or LSP server). npm and Python (pip) are in use; a plugin
  adopting another ecosystem applies the same four rules with that ecosystem's frozen-install
  command.
- **Out of scope:** first-party code shared between plugins, which
  [ADR 0019](../../adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md) vendors with
  a sync gate; CI and lint toolchains, which `.github/workflows/` installs; packages a plugin only
  builds or tests with.

## Rule 1: commit the manifest and the lockfile, nothing else [SPEC]

The component's directory carries a `package.json` naming each dependency and a `package-lock.json`
recording the exact version, tarball URL and integrity hash of every package in the tree. Both are
committed. `node_modules/` stays ignored, and no build output containing third-party code (an
esbuild bundle, a minified `dist/`) is committed.

Each lockfile directory gets a Dependabot `npm` entry in `.github/dependabot.yml`, so a security
release reaches users as a reviewed lockfile bump.

## Rule 2: install on first use with `npm ci` into the plugin data directory [SPEC]

On the first run that needs the packages, the component copies `package.json` and
`package-lock.json` into an install directory and runs
`npm ci --ignore-scripts --no-audit --no-fund` there. Later runs reuse the directory.

- **`npm ci`, never `npm install`.** `npm ci` needs an existing lockfile, exits with an error
  instead of updating it when it disagrees with `package.json`, and never writes either file
  ([npm-ci](https://docs.npmjs.com/cli/v11/commands/npm-ci)). Each tarball is checked against the
  lockfile's `integrity` hash: a lockfile with one altered `acorn` hash failed `npm ci` with
  `EINTEGRITY` and installed nothing (npm 11.19.0, probed 2026-10-02).
- **`--ignore-scripts`**, so no package's install script runs on the user's machine.
- **Where:** `<plugin data dir>/<component>/<first 12 hex of the lockfile's sha256>/`. Keying by
  the lockfile means a plugin update that changes it installs beside the old set rather than
  mutating a directory a running session may be using. This is a machine-wide cache keyed by
  content, so the per-project keying in
  [plugin-data-report-keying](../plugin-data-report-keying/README.md) does not apply to it.
- **Atomic:** install into a sibling directory and rename it into place, so an interrupted install
  leaves nothing that looks complete and two concurrent first runs end with one good directory.
- **Readiness is a load probe, not a version check.** Start the dependency and have it answer (for
  a helper process, a `ping` that requires every package). No Node.js version floor is guessed.

### Finding the plugin data directory

`${CLAUDE_PLUGIN_DATA}` is the documented home for installed dependencies, but a script cannot
rely on reading it from its environment when Claude runs it through the Bash tool. Resolve the
install base in this order and record which rule chose it:

1. An explicit flag (the inventory's `--deps-dir`). A skill body may pass
   `--deps-dir "${CLAUDE_PLUGIN_DATA}"`, since that reference is substituted inline in skill
   content; the inventory's `SKILL.md` does.
2. `$CLAUDE_PLUGIN_DATA` from the environment, accepted only when its last path segment names the
   plugin: a skill subprocess has been observed holding another plugin's value (recorded in
   `plugins/harness-ops/skills/audit-skill-visibility/scripts/audit_skill_visibility.py`,
   `report_path`).
3. The repository's gitignored `.work/` when the script runs from a marketplace checkout.
4. `<config dir>/plugins/data/<plugin>-<marketplace>/`, the documented resolution of
   `${CLAUDE_PLUGIN_DATA}` (config dir: `$CLAUDE_CONFIG_DIR`, else `~/.claude`).

## Rule 3: fail closed with the exact command [SPEC]

When `npm` is missing, the network is down, `npm ci` fails, or the installed set does not load, the
component reports itself **broken** and prints one command line that repairs it: remove the install
directory, recreate it, copy the two manifests in, and run `npm ci --prefix` on it with the flags
above. The line is POSIX shell, except on Windows, where it is Windows PowerShell 5.1 (no `&&`,
single quotes doubled, `npm.cmd` named because the default execution policy blocks `npm.ps1`). When only `node` is missing, the packages are fine and reinstalling them repairs nothing, so
the report says to install Node.js and rerun instead of printing that line. It never falls back to a different implementation that could return a different
value, and never reports a partial result as complete.

## Rule 4: no committed third-party bundles [SPEC]

A plugin that today commits a bundle of third-party code is an exception to be brought under rules
1-3, listed below with its tracking issue. A new one is not added. When a component genuinely
cannot run an install step (for example a start path with no way to report breakage), the
exception is recorded here with that reason, not decided silently in the plugin.

## Python

The operator settled two points for Python on 2026-10-02 ([#5844](https://github.com/melodic-software/claude-code-plugins/issues/5844)):
no `uv run` fetching at run time, and hash-locked requirements only. The rules below are the four
npm rules with pip's frozen install. The reference implementation is the `animation` plugin:
`requirements.in`, `requirements.txt`, `hooks/install-python-deps.sh` and `scripts/pydeps.py`.

### Rule P1: commit the pins and a hash-locked requirements file [SPEC]

The component's directory carries `requirements.in`, the direct pins (`name==version`, edited by
hand), and `requirements.txt`, compiled from it with
`uv pip compile requirements.in --universal --generate-hashes --python-version <floor> --only-binary :all: -o requirements.txt`.
The compiled file pins every package in the tree, transitive ones included, with a
`--hash=sha256:` for every wheel on every platform. Both files are committed; no virtual
environment, `site-packages` or wheel is. Only wheels: `--only-binary :all:` means no source
distribution is built, so no package's build script runs on the user's machine.

Each directory holding a lock gets a Dependabot `pip` entry in `.github/dependabot.yml`, so a
security release reaches users as a reviewed lock change.

### Rule P2: install from a hook, never while a skill runs [SPEC]

**Install trigger:** a `SessionStart` hook runs
`python -m pip install --require-hashes --only-binary :all: --no-deps --target <dir> --requirement requirements.txt`
and does nothing when the set already loads (Rule P3). pip refuses the install when any
requirement, transitive ones included, is unpinned or unhashed, or a wheel's hash differs from the
lock ([pip secure installs](https://pip.pypa.io/en/stable/topics/secure-installs/)).

**Nothing else fetches.** No skill body, script or hook other than the install hook runs
`uv run`, `uvx`, `pip install` or `--with-requirements`. A skill runs its scripts against the
installed set through a launcher that puts the install directory on `PYTHONPATH` and never
installs (the reference's `pydeps.py run`). The component's tests assert this by scanning its
skills and scripts.

### Rule P3: install into the plugin data directory, keyed by lock and interpreter [SPEC]

- **Where:** `<plugin data dir>/python/<first 12 hex of requirements.txt's sha256>-<interpreter tag>/`,
  the tag being `sys.implementation.cache_tag` (`cpython-312`). Compiled wheels belong to one
  interpreter, so a different Python or a changed lock installs beside the old set. The data
  directory is found in the order of [Finding the plugin data directory](#finding-the-plugin-data-directory).
  The hook receives `CLAUDE_PLUGIN_DATA`; a skill passes `--data-dir "${CLAUDE_PLUGIN_DATA}"`.
- **`--target`, not a virtual environment.** A venv's entry-point scripts embed its path, so one
  built beside the target and renamed into place has scripts that fail to start (probed
  2026-10-02, Python 3.14, pip 26.2.1: `bin/pip` of a renamed venv exec'd the old path and exited
  `not found`).
- **Atomic:** install into `<dir>.partial-<pid>`, probe it, then `os.replace` it into place. A
  failed or interrupted install leaves nothing that looks complete, and a concurrent install that
  won the rename is accepted when its copy loads. A `.partial-*` sibling older than twice the pip
  timeout is removed.
- **Readiness is a load probe:** the component names the top-level modules to import (the
  distribution and import names differ, `opencv-python-headless` and `cv2`) and imports them with
  the install as the only third-party path (`PYTHONPATH` set to it, `-S` so no ambient
  `site-packages`), so an ambient copy never passes for the locked set. The launcher runs scripts
  the same way. A directory that is present but no longer loads is rebuilt.
- **Floor:** the component states its Python floor and the hook looks for an interpreter at or
  above it, so a host with an older Python gets Rule P4's notice, not a failed install.

### Rule P4: surface every failure with the repair command [SPEC]

No interpreter at the floor, no pip, no network, a hash mismatch, or a set that does not import:
the hook emits a notice on both channels (`systemMessage` and `additionalContext`, per
[hook-observability](../hook-observability/README.md)) with the reason and one repair line, which
is the installer run in the foreground with the same interpreter and data directory (POSIX shell,
or Windows PowerShell 5.1 on Windows, as in Rule 3). The hook exits
0, so a failed install never blocks the session, and it leaves no partial directory. A launcher run
with no installed set prints the same line and exits 2. Neither falls back to another interpreter's
packages, installs on its own, or reports a partial result as complete.

## Exceptions

None.

## Adoption

| Component | State |
|---|---|
| `animation` numpy and opencv | Conforms (Python rules). `requirements.in` and the universal, hash-locked `requirements.txt` are committed; the `SessionStart` hook `hooks/install-python-deps.sh` installs them through `scripts/pydeps.py install` into `<data>/python/<lock hash>-<interpreter tag>/`; the skills run scripts through `pydeps.py run`. `test_pydeps.py` and `install-python-deps.test.sh` cover the first install, the no-op rerun and a failed install |
| `speech` numpy and onnxruntime | Conforms (Python rules), on the `animation` pattern: the same hook and launcher, probing `numpy` and `onnxruntime`. `/speech:narrate` runs `narrate.py` through `pydeps.py run`. The Kokoro model files are data, not packages: `/speech:setup apply install-model` downloads them from a pinned revision and checks each sha256 |
| `harness-ops` inventory, `--reader=parser` / `--reader=compare` | Conforms. `skills/inventory/scripts/js/` holds the lockfile for acorn and eslint-scope; `parser_reader.py` installs into `<base>/inventory-parser/<lock hash>/`, probes the helper with `ping`, and turns every failure into a broken binary source carrying the repair command. CI installs it the same way so the parser test suites run on every pull request |

## Upstream facts this rests on

Each row is a verification record in the
[upstream-drift](../upstream-drift/README.md#required-parts) shape.

| Claim | Basis | As of | Recheck trigger |
|---|---|---|---|
| `${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/<id>/`, `<id>` being the plugin identifier with characters other than letters, digits, `_` and `-` replaced by `-`; it is created on first reference, kept across plugin updates, and its stated use is "installed dependencies such as `node_modules`, generated code, and caches" | [Plugins reference, Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables) | 2026-10-02, Claude Code 2.1.287 | A Claude Code release note or a re-fetch of that section changing the path, the lifetime, or the stated uses |
| The directory is deleted when the plugin is uninstalled from the last scope it is installed in, unless `--keep-data` is passed | Same page, Environment variables, linking [plugin uninstall](https://code.claude.com/docs/en/plugins/cli-reference#plugin-uninstall) | 2026-10-02, Claude Code 2.1.287 | Same trigger. A deleted install is rebuilt by the next first run, so the trigger matters only if the data directory stops surviving updates |
| `pip install --require-hashes` requires every requirement, transitive ones included, to be pinned and hashed and refuses the install otherwise; `--only-binary :all:` disables source packages; `--target <dir>` installs into that directory; `--no-deps` skips dependencies | [pip secure installs](https://pip.pypa.io/en/stable/topics/secure-installs/) and [pip install options](https://pip.pypa.io/en/stable/cli/pip_install/) | 2026-10-02, pip 26.2.1 (docs) | A pip release note changing hash-checking mode or one of these options |
| `CLAUDE_PLUGIN_DATA` is exported to hook commands, MCP `stdio` servers and LSP servers; `${...}` resolves inline in skill, command and agent content; the variables are not in the environment of commands Claude runs through the Bash tool | Same page, [Where each variable resolves](https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves) | 2026-10-02, Claude Code 2.1.287 | A re-fetch of that table showing the Bash tool receiving the variable, which would let step 1 of the resolution order read the environment directly |

## Related

- [#5640](https://github.com/melodic-software/claude-code-plugins/issues/5640): the inventory parser
  plan, where the operator decisions behind this rule are recorded.
- [#5752](https://github.com/melodic-software/claude-code-plugins/issues/5752): done; the miro MCP
  server, formerly a committed bundle, installs on first launch under this rule.
- [#5844](https://github.com/melodic-software/claude-code-plugins/issues/5844): the Python section and
  its `animation` reference implementation (spec container #5835, item A3).
- [plugin-data-report-keying](../plugin-data-report-keying/README.md): how reports, not
  dependencies, are named under the same directory.
