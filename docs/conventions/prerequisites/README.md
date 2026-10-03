# Prerequisites Convention

A plugin declares every external dependency it needs in one file, `prerequisites.json` at the
plugin root. One checker reads that file for setup skills, check skills, hooks and the fleet
report, and one CI gate keeps the file honest. The absence classes, and the rule that a skipped
feature is never silent, stay in
[`docs/plugin-philosophy.md`](../../plugin-philosophy.md#prerequisites-and-failure-behavior); this
document owns the file, the checker and the gate.

## What the file declares, and what it does not

Declare a tool, runtime, system library, package, environment variable or foreign MCP server
that the plugin's files run or read. A plugin with no such dependency ships no file. git, bash,
sh and the POSIX utilities are assumed and never declared.

Three needs use a native surface instead, so the file never declares them:

| Need | Declare it in | Why |
| --- | --- | --- |
| Another plugin that must be enabled | `dependencies` in `plugin.json` | Claude Code resolves and enforces it. An optional collaborator stays presence-gated in prose. |
| A secret a hook or MCP server reads | a `userConfig` option with `sensitive: true` | Claude Code stores it in the credential store and hands it to hooks and servers. |
| Node packages at the plugin root | `package.json` and a lockfile | Claude Code installs them. Packages it cannot install follow the [on-demand dependencies convention](../on-demand-dependencies/README.md); declare those as `node-pkg`. |

The `env` kind is for a variable a command run through the Bash tool reads, such as a CLI's API
key. `userConfig` values do not reach that environment.

As of 2026-10-02 the [plugin manifest reference](https://code.claude.com/docs/en/plugins-reference)
has no field for external binaries, runtimes, environment variables or system libraries, and
the Bash tool's environment carries no plugin variables. Recheck when that page adds such a
field; a native field replaces this file.

## The file

[`prerequisites.schema.json`](prerequisites.schema.json) is the schema. A file has one key,
`requires`, a list of entries. There is no version key: a change to the format migrates every
file and every reader in the same change, and this document changes with it.

```json
{
  "requires": [
    {
      "id": "gh",
      "kind": "cli",
      "need": "required",
      "for": ["skill:work", "hook:claim-guard.sh"],
      "detect": {
        "any": ["gh"],
        "version": { "args": ["--version"], "pattern": "gh version ([0-9.]+)", "min": "2.94.0" }
      },
      "degrade": "Without gh, /work-items:work stops before it claims an item.",
      "install": { "docs": "https://cli.github.com/", "brew": "gh", "winget": "GitHub.cli", "apt": "gh" },
      "check": "/work-items:check"
    }
  ]
}
```

Every entry carries all eight fields:

| Field | Meaning |
| --- | --- |
| `id` | Unique in the file, lowercase. The row key in every report and the name the gate matches. |
| `kind` | `cli`, `runtime`, `system-lib`, `python-pkg`, `node-pkg`, `env` or `mcp`. It sets the shape of `detect`. |
| `need` | `required` or `optional`, relative to the scopes in `for`. |
| `for` | Who needs it: `plugin`, `skill:<name>`, `hook:<script>` or `mcp:<server>`. |
| `detect` | How the checker finds it. The shape depends on `kind` (next table). |
| `degrade` | What stops working without it, and what still works. The checker prints it. |
| `install` | Hints keyed by package manager or `docs`. The checker prints them and never runs them. Key order is not a preference. |
| `check` | The skill a person runs to re-check, such as `/<plugin>:check`. |

`need` and `for` together give the absence class. `required` for `plugin` means the plugin cannot
work without it; hook plugins use that for `node`. `required` for `skill:x` means skill `x` stops
at its entry point. `optional` means the scope continues with a reduced result and says so.

| `kind` | `detect` | Resolves when |
| --- | --- | --- |
| `cli`, `runtime` | `any` (names, first match wins), optional `local_bin` (paths tried upward from the working directory, up to eight levels), optional `version` (`args`, a `pattern` whose first group is the version, `min`) | A name is on `PATH` or a `local_bin` path is executable, and the version is at least `min`. A runtime lists its ladder in `any`, such as `["python3", "python", "py"]`. |
| `system-lib` | `probe`: `args` (the first item is the binary) and `pattern` | The probe output matches the pattern, for example `ffmpeg -encoders` listing `libx264`. |
| `python-pkg` | `any` (interpreters) and `import` (a module name) | The first interpreter found imports the module. |
| `node-pkg` | `module` and `paths` (relative to the plugin root, or starting with `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_PLUGIN_DATA}`) | `<path>/<module>/package.json` exists under one of the paths. |
| `env` | `name` | The variable is set and not empty. The value is never printed. |
| `mcp` | `server` | Only the agent can tell, from its tool list. The checker reports `agent-check` and never fails on it. |

A version floor compares dotted numbers numerically, so `2.10` is newer than `2.9`. When the
version cannot be read, the entry reports `unverified` and does not fail.

## The checker

`lib/prerequisites.mjs` is the one reader. It uses the Node standard library only, never installs
anything, and never prints an environment value. Each plugin with a valid file carries a generated
copy in its own `lib/`, because an installed plugin cannot see the repository root. The copies are
listed in `scripts/shared-copies.txt` and regenerated by `scripts/sync-shared-copies.sh`
([ADR 0019](../../adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)).

| Mode | Use | Output |
| --- | --- | --- |
| `check <plugin-root> [--for <scope>] [--data-dir <dir>]` | Setup and check skills, and a skill's own entry point | One `PASS`, `FAIL`, `WARN` or `INFO` line per entry, with the `degrade`, `install` and `check` text on a failure, then a summary line. `--for` keeps that scope's entries plus the `plugin` ones. |
| `report --plugin-root <dir>...` | The fleet table | A TSV table (`plugin id kind need status check install`) and `missing=N present=M`. |
| `probe <plugin-root> [--run-if-unset-or-true <OPTION>]` | A SessionStart hook | A notice on both hook channels for each missing entry a `hook:` scope needs, once per session. `--run-if-unset-or-true` closes the probe when `CLAUDE_PLUGIN_OPTION_<OPTION>` is set to anything but `true`, so the plugin's kill switch silences it. |

Exit codes: 0 when every required entry resolves, 1 when a required entry is missing or below its
floor, 2 on a usage error or a file that fails the schema. `probe` exits 0 after a notice, because
Claude Code reads a hook's JSON output only from a zero exit; it still exits 2 on a bad file.

A hook plugin registers the probe as its SessionStart row, with no bash probe script beside it:

```json
"command": "node",
"args": ["${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs", "probe", "${CLAUDE_PLUGIN_ROOT}", "--run-if-unset-or-true", "BIOME_FORMAT_ENABLED"]
```

A skill runs the checker with the plugin's paths substituted inline, because the Bash tool's
environment has no plugin variables:

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --for skill:<name> --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Only dependencies a hook needs notify at session start. A dependency only a skill needs reports
when that skill runs, so a person who never runs the skill is never asked to install its tools.
`probe` keeps its once-per-session latch in `${CLAUDE_PLUGIN_DATA}/skip-notices/`, under the same
marker name `hook::notice_once` uses for its `prerequisite` class.

### When node is absent

The checker needs `node`, so each copy ships two stubs beside it. `lib/prerequisites.sh` (POSIX
sh) and `lib/prerequisites.ps1` (Windows PowerShell or pwsh) run the checker with the same
arguments and exit code when `node` is on `PATH`. Without `node` they print this one line and exit
1:

```text
prerequisites: node was not found on PATH, so no prerequisite was checked. Install Node.js from https://nodejs.org/en/download, then run this check again.
```

## Hook notices

Two notices cover a hook's dependencies. Both name `/<plugin>:check`, never `/<plugin>:setup`,
because `setup` is manual-only (the
[philosophy](../../plugin-philosophy.md#setup-is-explicit-and-repeatable) explains the split). A
plugin whose `check` skill already means something else (`instruction-placement`, `skill-quality`
and `toolchain`) ships `check-prerequisites` and names that. No hook installs anything.

| Notice | Fires | How |
| --- | --- | --- |
| `node` is missing | `SessionStart`, once per session across every plugin | Each hook plugin carries one shell-form `SessionStart` row that runs `lib/prerequisites.sh node-notice`, then `lib/prerequisites.ps1 node-notice`. bash takes the first and leaves at `${BASH_VERSION:+exit}`; PowerShell, the default shell on Windows without Git Bash, has no `sh`, skips to the second. Both stubs share a latch keyed by session id in the temp directory, so a session with several hook plugins sees one notice. A plugin's `<name>_enabled` kill switch, passed as the last argument, silences its row. |
| Another hook dependency is missing | `SessionStart` for an entry whose `for` names a hook, via `probe`; and at the point of use | `hook::require <id>` in `lib/hook-utils.sh`. It fails open: when `<id>` is not on `PATH` it prints one skip notice per session and agent and exits 0. The text comes from the plugin's declared entry: `degrade`, the `docs` install link and `check`. An entry that names only a skill never notifies at session start. |

`hook::require` reads an entry with bash alone, from its `id` to the next one, so write `id` first in every entry.

`hook::require_jq_blocking` stays separate. It denies the call, so it prints its reason every time
and does not latch.

## The CI gate

`node scripts/check-declared-prerequisites.mjs` runs in CI and checks three things:

1. Every `plugins/*/prerequisites.json` passes the schema.
2. Every plugin with a valid file carries the three generated checker copies.
3. No plugin file runs a tool from `scripts/prerequisites-tools.txt` that its file does not
   declare. A declaration covers its `id`, every name in `detect.any`, and a `system-lib` probe
   binary.

The scan reads scripts (`.sh`, `.bash`, `.mjs`, `.js`, `.cjs`, `.py`, `.ps1`, `.psm1`) and the
shell blocks and `` !`...` `` lines of each `SKILL.md`. It skips comments, heredoc bodies,
single-quoted text, case labels, and test, fixture and eval files. It finds a tool at a command
position or in a call such as `spawnSync("gh", ...)` or `shutil.which("uv")`. A tool run through a
variable is invisible to it. A line that carries `prereq-ok: <reason>` is exempt.

`scripts/prerequisites-baseline.txt` lists today's gaps, one `<plugin> <gap>` row each. The gap is
a tool name, or `schema` for a file not yet in the schema's shape. The gate fails on a gap the
baseline does not list and on a row with no gap behind it, so the list only shrinks. After
declaring a tool or converting a file, regenerate the list:

```bash
node scripts/check-declared-prerequisites.mjs --write-baseline
```

To watch for a new tool, add its command name to `scripts/prerequisites-tools.txt` and regenerate
the baseline in the same change.
