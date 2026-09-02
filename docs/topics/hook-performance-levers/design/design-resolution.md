---
outcome: early-exit
tier: B
reason: config and script changes throughout; one Tier B type sketch for the hook-utils.sh split in phase 4
---

# Design resolution: hook-performance-levers

## Per-phase gate verdict

| Phase | Tier | Verdict | Reason |
|---|---|---|---|
| 1 dotfiles harness extension | C | early-exit | One bash script gains samples and two status classes. No new contract: the TSV columns and the seven legacy payload lines stay byte-identical. |
| 2 async on non-deciding hooks | C | early-exit | `hooks.json` field additions only. The field's semantics are upstream's (ledger H10 to H14), not ours. |
| 3 `if` gates, matcher scoping, timeouts | C | early-exit | `hooks.json` rows and README residual notes. No script changes beyond a jq assertion in a test. |
| 4a guard hot path | C | early-exit | Removes external spawns inside existing guards behind their existing contract tests. No interface changes. |
| 4b hook-utils.sh split | B | early-exit with type sketch | Splits one 2,139-line library into a core plus lazily sourced modules. New sourcing contract, one new sync script and CI job per module. Sketch below. |
| 4c per-Write hook hot path | C | early-exit | Removes external spawns inside three formatter hooks behind their existing contract tests. No interface changes. |
| 5 Windows path-form correctness | C | early-exit | Path normalization in three scripts plus documented host skips in four tests. Follows the `REPO_ROOT_ALT` pattern provenance already carries. |
| 6 skill listing budget | C | early-exit | Frontmatter flags on a human-gated skill list. |
| 7 statusline cost | C | early-exit | Measurement plus removal of spawns inside one tee script. |
| 8 docs and accounting | C | early-exit | Markdown only. |

## Tier B type sketch: hook-utils.sh core plus modules (phase 4b)

Source of truth today: `lib/hook-utils.sh`, 2,139 lines, 42 functions, copied byte-identical into
17 plugins (`plugins/*/hooks/hook-utils.sh`) by `scripts/sync-hook-utils.sh`. Every hook pays the
whole parse on every spawn. The dispatcher (`plugins/guardrails/hooks/run-guards.sh`) sources it once
per event and relies on two properties: the double-source guard makes each guard's own `source`
return at once, and `hook::jq_fields` is a plain function it can re-declare under another name with
`eval "$(declare -f ...)"`.

### Module boundaries

| Unit | Functions (by line in `lib/hook-utils.sh` today) | Loaded when |
|---|---|---|
| **core** (`hook-utils.sh`) | Prerequisite visibility and emit family (39 to 255): `is_enabled`, `check_enabled`, `json_escape`, `emit_channels`, `emit_skip_notice`, `format_path_probed`, `emit_system_message`, `notice_once`. jq gate and paths (257 to 734): `raw_file_path`, `require_jq`, `require_jq_blocking`, `normalize_path`, `physical_path`, `under_temp_root`, `in_git_working_tree`, `read_file_path`, `repo_root`, `repo_relative_path`. stdin and jq (735 to 1183): `read_supports_nchars`, `json_complete`, `resolve_read_timeout`, `resolve_read_slice`, `buffer_stdin`, `jq_field`, `jq_fields`, `extract_bash_subject`. `emit_additional_context` (1331). | Always, by every hook's unchanged `source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"` line. |
| **module git-argv** (`hook-utils.d/git-argv.sh`) | 1345 to 2139: `ansi_c_decode`, `env_s_split`, `shell_c_operand`, `git_is_bin`, `wrapper_chdir_record`, `git_resolve_index`, `git_resolve_subcommand`, `git_alias_expansion`, `bash_parse_segments`. | On first call from a git guard (block-dangerous-git, block-noncanonical-commit, block-convention-violation, block-no-verify, flag-commit-pr-skill-bypass). Formatter and telemetry hooks never load it. |
| **module telemetry** (`hook-utils.d/telemetry.sh`) | 1184 to 1330: `append_jsonl`, `ctx_reset`, `ctx_append`, `ctx_flush`, `telemetry_enabled`, `emit_telemetry`. | On first call, only when `hook::telemetry_enabled` is true; the core keeps a cheap `telemetry_enabled` check and a stub `emit_telemetry` that returns 0 without loading when disabled. 41 hook scripts call these helpers, so this module is on the common path whenever telemetry is on; the consumer inventory (phase 4b item 1) decides whether it moves at all. |

The exact line split is a phase 4a profiling output and a phase 4b consumer inventory, not a
commitment: a function moves to a module only when the parse-cost measurement shows the module's
share is material (switch condition in the plan) and the inventory shows the module stays off the
common path for a material set of hooks. If parse cost is immaterial, 4b does not run.

### Sourcing contract

1. **Entry point unchanged.** Every hook keeps its one `source .../hook-utils.sh` line. The
   double-source guard variable keeps its name so the dispatcher's overrides stay in force.
2. **Lazy stubs in core.** For each module function `hook::X`, core defines
   `hook::X() { hook::_load <module>; hook::X "$@"; }`. `hook::_load` sources
   `"${HOOK_UTILS_DIR}/hook-utils.d/<module>.sh"` once, guarded by a per-module variable
   (`HOOK_UTILS_GIT_ARGV_LOADED`, `HOOK_UTILS_TELEMETRY_LOADED`), which redefines the real
   functions. A hook that never calls a module function never pays its parse. **Recursion guard:**
   bash has no default `FUNCNEST`, so a stub whose module file is absent would call itself until
   the hook timeout and a gate would fail open. After `hook::_load` the stub checks the module's
   guard variable; if it is still unset it emits a skip notice through the core visibility helpers
   and returns 2. Every stub takes that shape.
3. **Module location is relative to the core file**, computed as `${BASH_SOURCE[0]%/*}` at core
   load (never `$(dirname ...)` or `$(cd ... && pwd)`, each of which is a spawn on the binding
   host), so each plugin copy finds its own sibling modules and the dispatcher's `dirname` shell
   override is not needed for this path.
4. **Modules depend on core only.** No module sources another module; `git-argv` may call core
   helpers, never telemetry, and the reverse.
5. **Dispatcher eager load.** `run-guards.sh` runs each guard in a `$(source ...)` subshell, so a
   lazy load performed inside one guard is discarded before the next guard runs; without an eager
   load, git-argv would parse up to five times per Bash call across the five git guards. The
   dispatcher gains a `--module <name>` flag beside `--lib` that calls `hook::_load` once in the
   parent process before fan-out; guards then find the functions already defined. The lazy path
   remains for hooks that run standalone.
6. **Byte-identical fleet copies.** Every carrying plugin receives core plus every module, so the
   sync lanes' byte-equality checks keep one answer per file. `scripts/lib/sync-cluster.sh` supports
   one `src`/`copies` pair per `scripts/sync-*.sh` script, each with its own CI job, so each module
   gets its own `scripts/sync-hook-utils-<module>.sh` and CI job beside `hook-utils-sync`;
   `--print-manifest` on each emits its pair so `scripts/affected-tests.sh` rule R5 keeps deriving
   the fan-out. `sync-cluster.sh` copies only onto existing files and exits 2 on an empty glob, so
   the 17 by N module copies are seeded as committed files before the first sync run.
7. **Tests.** `lib/hook-utils.test.sh` gains a lazy-load case (module function called without a
   prior explicit source; module guard prevents a second parse), a negative case (a
   formatter-shaped hook loads no module), and an absent-module case (returns 2 with a notice, no
   recursion). `plugins/guardrails/hooks/run-guards.test.sh` gains a case proving the dispatcher's
   `hook::jq_fields` override survives a module load inside a guard and a case counting module
   loads across a dispatcher run (exactly one).

### What this is not

Not a behaviour change to any function. Not a new plugin. Not a change to how a consumer
receives the library: delivery is still the plugin version bump plus `claude plugin update`.
Not a change to `scripts/lib/sync-cluster.sh` itself: the one-cluster-per-script shape is reused,
not replaced.

Design threads beyond this sketch (whether to promote 4b to its own topic, and the parse-cost
threshold) are decisions recorded in `../PLAN.md`.
