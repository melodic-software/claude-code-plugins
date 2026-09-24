# Changelog

All notable changes to the `instruction-placement` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.15.2] - 2026-09-23

### Changed

- hook-utils.sh: the builtin JSON parse (`hook::_fast_file_path_to`, `hook::_fast_fields`, `hook::json_compact_to`) runs in the C locale and puts the caller's `LC_ALL` back afterwards. Under a UTF-8 locale bash split and scanned the payload one multibyte character at a time, and the cost grew faster than the payload; under C it is a byte walk. Every answer is still proven equal to jq's or handed to jq. A raw C1 character (U+0080 to U+009F) in a string is now proven by the builtin parse instead of sent to jq.
- hook-utils.sh: `hook::buffer_stdin_to` validates an object payload that the builtin JSON skeleton accepts without spawning `jq -e .`; any other payload still goes to jq.
- hook-utils.sh: `hook::begin` reads the file path from the payload it already buffered, through the new `hook::read_file_path_to`, instead of piping it through a capture subshell to `hook::read_file_path`, and takes the raw path with the new `hook::raw_file_path_to`. `hook::read_file_path` and `hook::raw_file_path` keep their print forms.
- hook-utils.sh: `hook::repo_relative_path_to` looks for `cygpath` only on a Windows bash (`OSTYPE` msys, cygwin or win32). Elsewhere the lookup always missed and probed every `PATH` directory, which on WSL includes the `/mnt/c` entries. Windows behavior is unchanged.
- hook-utils.sh: `hook::read_file_path_uncached_to` and `hook::repo_root_uncached_to` name the bodies behind `hook::read_file_path_to` and `hook::repo_root_to`, for a dispatcher that caches in front of them.
- index-drift.sh: `file_dir` is initialized before `hook::dirname_to` writes it, so ShellCheck sees the assignment (SC2154). No behavior change.
- hook-utils.sh: on Linux, `hook::physical_path_to` and `hook::_physical_prime` read a physical path with `cd -P` in one subshell (the new `hook::_physical_builtin_to`) instead of starting `realpath`, when every path is absolute and is an existing directory or an existing file that is not a symlink. Any other path, and every path on Git Bash and macOS, still goes to realpath. The answer is realpath's.
- hook-utils.sh: the builtin JSON skeleton finds a raw control byte and an invalid escape with one regex search each instead of glob scans and escape deletions, and the key walks in `hook::_fast_file_path_to` and `hook::_fast_fields` take a key's text from its split part when no escape was rewritten in it, instead of slicing the whole payload for every short string. Same verdicts and values; a large payload parses in about half the time.

## [0.15.1] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.15.0]

### Added

- `migrate` gained `reference/sources.md`: one four-part dated record (claim, basis, as-of date, recheck trigger) per upstream fact the AGENTS.md cutover turns on. The GrowthBook flag `tengu_agents_md_mod` and how its code default is resolved from the shipped bundle without hardcoding the minifier-assigned identifier; the `env-vars` section "Features that need feature-flag fetching" and its AGENTS.md bullet, quoted; the CLI floor of 2.1.277; the `claude-code-action` release to installed CLI map, re-derived per tag from `base-action/action.yml` rather than copied (`v1.0.213` installs 2.1.258, `v1.0.222` 2.1.269, `v1.0.228` 2.1.275, `v1.0.231` 2.1.278, so only the last clears the floor); the CI canary result on a fresh-install runner, including that `claude-code-action` rejects the `push` event and has to be dispatched by REST; and what shim removal costs, which is that a directly read `AGENTS.md` is not listed in `/memory` or `/context` and fires no `InstructionsLoaded` hook. The canary recipe is pointed at, not restated.
- A record in that file for what the observability loss means for measurement: `verify-load.sh` detects a load through the `InstructionsLoaded` hook, so it measures a shimmed surface and reports `VERDICT FAIL` for an `AGENTS.md` Claude reads directly, even when a headless canary from the same directory shows the file loaded. Measured on 2.1.278.

- `migrate` gained two arguments and the two scripts behind them. `scripts/cutover-check.sh` is read-only: it grades the four cutover conditions, prints `[MET]`, `[UNMET]` or `[UNREACH]` per condition with the evidence the verdict rests on, and exits non-zero unless every one is `[MET]`. Condition 1 resolves the flag's code default out of the installed bundle at run time (`grep -abo` for every occurrence, a byte window flattened with `tr`, the minifier-assigned identifier captured from `isOnByDefault:()=>X` and resolved from `var X=!0|!1`, so neither the identifier nor the offsets are ever hardcoded) and fetches the `env-vars` feature-flag list; either the default being true or the AGENTS.md bullet being gone satisfies it, and a bundle with no readable window or a page with no such heading is `[UNREACH]`. Condition 2 maps every `claude-code-action` pin from `plan-migration.sh`'s `ACTION` rows to the CLI it installs and compares it against the floor, and reads the CI canary from its record. Condition 3 is a token canary from a cwd under home and a cwd on a second drive or path, in scratch directories the script creates and removes, run with **no tools available** (`--tools ""`): with a `Read` tool and an `AGENTS.md` in the working directory, a reply quoting that file is equally consistent with the model having read it for itself, so the tool-less session is what makes the quotation evidence of a load. Proven before adoption on 2.1.278 (a lone `AGENTS.md` returned its token line with no tools; a directory without one answered `NONE`). A scratch root inside a git repository is refused, and every scratch directory is removed by the `EXIT`/`INT`/`TERM` trap. Condition 4 matches every `PATHDET` row against the repository's reviewed `.claude/cutover-pathdet-ack.txt`. A `--repo` the plan cannot read exits 2 rather than grading anything, and a plan carrying no `ACTION` or no `PATHDET` row at all, or one carrying that kind's new `ERROR` row, is `[UNREACH]` for the condition that reads it: a scan that failed and a scan that found nothing are the same empty output, and both conditions would otherwise pass on that silence. A pin whose ref the script cannot parse is `[UNREACH]` too, rather than prefix-matching the release map's first row and borrowing its CLI version. Condition 1's env-vars probe uses `curl --fail`, checks its exit status, requires a marker from later in the page before an absent bullet means anything, and reports `[UNREACH]` when the bullet left the list while the page still ties `AGENTS.md` to a flag elsewhere: a moved bullet and a deleted one look identical from inside one section. Condition 4's unmet line carries its denominator. The floor, the release map and the canary run are parsed from `reference/sources.md` rather than copied into the script, and an unparsable record exits 2 rather than skipping the check.
- `scripts/remove-shims.sh`, the skill's only deleting surface, behind six fail-closed gates: it prints what removal costs, refuses without `--confirm`, refuses unless the installed `claude-memory` and `instruction-placement` are at or above the corrected-doctrine releases (0.12.9 and 0.15.0, the release where the last of the old doctrine left this plugin's own `apply-recipes.md` and `routing-rubric.md`), read as the **lowest** version installed in any scope, because a stale project-scope copy beside a newer user-scope one is the copy that answers in the repository being de-shimmed, refuses unless `cutover-check` reports every graded condition `[MET]` in the same run, refuses unless every instruction directory is already at the target shape (a zero-byte `AGENTS.md` cannot be canaried, so it is never de-shimmed), and resolves a canary line and a trigger file for every directory before it removes anything. Root and nested shims come out together, because a lone nested `AGENTS.md` never attaches while a root `CLAUDE.md` exists. The post-removal canary runs against a distinctive line of each directory's own `AGENTS.md` with no tools available, so no token is written into a real repository, and any miss, any unmeasurable result, any failure part way through the removal and any signal restores every shim the run removed: the restore hangs off one `EXIT` trap rather than a list of signals that has to stay complete, because a named `INT`/`TERM` pair left `HUP` and `PIPE` out and `remove-shims | head` was enough to leave a repository de-shimmed and unverified. The restore writes the one import line back and verifies it byte for byte rather than taking git's index copy, which a staged edit would have replaced; a restore that did not land says so by name and the run still exits non-zero.
- `PATHDET` stops being a list of existence-test spellings. A list missed `-e`, `test -e`, `Test-Path`, `os.stat`, `File.exist?`, `fs.accessSync`, `Path(...).exists()` and a variable holding the name, and every miss reported a clean tree and cleared the condition. Any existence-ish mention in a code file is now a row, comments and longer filenames aside, so prose in an eval file lands there too: over-reporting costs one line in the acknowledgement list, under-reporting clears a cutover that breaks a repository. Measured on this repository: 8 rows before, 54 after, against 519 for a bare "any mention of the name", which is the point at which a list stops being read and starts being rubber-stamped.
- `remove-shims`' canary line must appear in no other `AGENTS.md` that loads beside it, by **containment** rather than equality. The index is built from the filesystem (every `AGENTS.md` under the repository, tracked or not, symlinked or not, plus every ancestor up to and including the drive or filesystem root), because Claude Code loads by filesystem and a gitignored intermediate file is in no plan row while still answering a nested directory's probe. The walk prunes `.git` and `node_modules` and prints what it pruned; it refuses on a non-zero `find` status and on any de-shimmed directory whose own `AGENTS.md` did not reach the index, because a walk that saw nothing scores every line unique. The canary passes on a substring match, so an ancestor line that merely contains the nested one (the same sentence plus a clause) answers the probe just as well as an identical one, and the nested surface passed while loading nothing of its own: a fail-open in the only deleting script. A file with no such line is refused before anything is removed. A session started in a nested directory loads that directory's file AND every ancestor's (measured on 2.1.278 with no tools available, which also settles how the nested leg triggers its load: running from the directory is the trigger, so no Read is needed), so a line the nested file shares with the root file is answered by the root file and the nested surface would pass its canary while loading nothing of its own.
- A source line carrying a literal tab is compared as a space on both sides, because the tab-separated acknowledgement file cannot otherwise express such a row, and a row nobody can write down fails closed forever.
- `cutover-check.sh` keys its per-repository plan files by position rather than by a punctuation-normalized path: `/repos/foo-bar` and `/repos/foo_bar` normalized the same, so the second plan overwrote the first and one repository was graded twice while the other was not graded at all. A repeated `--repo` is now a usage error rather than a doubled count.
- `plan-migration.sh` scans `.claude/` for path detection like any other tree, minus each repository's own `.claude/cutover-pathdet-ack.txt`, whose every line quotes a detector by design; a hook or helper script there locates a path exactly as one anywhere else does. `ACTION` also scans `.github/actions/` and matches the `claude-code-action/base-action@...` subpath form, so a composite action that pins the CLI is no longer reported as no pin at all. Both scans distinguish "found nothing" (`NONE`) from "did not complete" (a new `ERROR` row carrying the exit status).
- Condition 4's acknowledgement mechanism, and this repository's own file. A grep cannot tell "reads `CLAUDE.md` as an instruction file" from "locates a path by its existence", and that distinction is the condition, so the judgment lives in a reviewed per-repository `.claude/cutover-pathdet-ack.txt` of tab-separated path, trimmed source line and one-line reason. Matching is on path plus exact source text, never line number, so a row that moves still matches and a row whose code changed falls out and has to be re-reviewed. An unacknowledged row is `[UNMET]` and is named, acknowledged rows are printed with their reasons as evidence, and no path convention exempts anything: excluding test trees is the obvious shortcut and would hide the one real blocker in this fleet, a repository-root finder under `tests/`.

### Changed

- `migrate`'s description drops the closing "Not for removing shims" sentence, which stopped being true, and names the two new arguments in the room that bought. The trigger 'make AGENTS.md the source of truth' goes with it, for the remaining characters: 'migrate to AGENTS.md' and 'move CLAUDE.md content to AGENTS.md' carry that intent, and 'can we drop the CLAUDE.md shims yet' is the one the skill could not be reached by before.
- The old shim doctrine survived in two places and is corrected: `realign`'s apply recipe B said "Claude-specific additions go in the `CLAUDE.md` below the import line", and `context/routing-rubric.md` said the same in passing. Under the target shape a `CLAUDE.md` beside an `AGENTS.md` is exactly the one import line, and genuinely Claude-specific text goes to a `.claude/rules/` file scoped to the subtree.
- `plan-migration.sh --help` documents the `RULES` row and its columns, which it has emitted since 0.14.0 without listing them, and the header comment gains the same row.

## [0.14.0]

### Added

- New skill `/instruction-placement:migrate`: moves a repository's instruction content to `AGENTS.md` as the one content home and keeps a one-line `@AGENTS.md` `CLAUDE.md` shim while a shim is still what makes it load. `scripts/plan-migration.sh` is the read-only plan (`--dry-run` is the only mode): one state per directory (`content-in-claude`, `shim`, `agents-only`, `both-with-content`, `zero-byte`), Codex's 32,768-byte project-doc budget summed along each root-to-directory path, case-variant filenames, bare `~/CLAUDE.md` suppressors, code that finds a path by the existence of `CLAUDE.md`, markdown links resolving into `CLAUDE.md`, the detected docs home, and every `claude-code-action` pin. Removing shims is a separate cutover and has no code path here.

### Changed

- `render-index.sh reachable` and `wiring` decide on what a repository can show rather than on the claim that Claude Code never reads `AGENTS.md`. A `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` on the file's own path is what makes an unimported `AGENTS.md` inert, so `UNREACHABLE` and `UNWIRED` now fire only where one of those is read instead of the file. A file nothing blocks gets the new `NATIVE` verdict, which is not a pass either: availability, and a `CLAUDE.md` above the repository root, are outside what a static check can see. Exit codes are unchanged for the blocked case.
- `lib/discover.sh`'s `ip_index_target_loaded` gained the `NATIVE` verdict on the same rule, and only for the `AGENTS.md` names Claude Code reads on its own.
- `ip_discover_nested_instructions` skips another tool's `AGENTS.md` under `.codex`, `.cursor` and `.github`. It was listed in the rendered index as a Claude on-demand surface and reported `UNWIRED` by the wiring gate, so `check` failed on any repository carrying a `.cursor/AGENTS.md`. The skip is keyed on the FILE, not the directory: a `CLAUDE.md` in one of those directories is Claude's (`.github/CLAUDE.md` is how a repository states conventions for its workflow files) and is still discovered. Two variables now carry the rule, `IP_EXCLUDED_TREES` (unconditional: `.claude`, `node_modules`, `vendor`, `.git`) and `IP_FOREIGN_AGENT_TREES`, and the index, the wiring gate and `plan-migration.sh` all read them.
- `ip_index_target_loaded` and the wiring gate share one entry-point walk, `ip_entry_points_on_path`. The reachability verdict previously checked only the root triple while its NATIVE branch matched nested targets, so a `svc/CLAUDE.md` beside a `svc/AGENTS.md` produced `NATIVE` from `reachable` and `UNWIRED` from `wiring` for the same tree.
- That walk counts `.claude/CLAUDE.md` at every level, not only at the repository root, as both a blocker and an entry point. The memory page counts "a CLAUDE.md, .claude/CLAUDE.md, or CLAUDE.local.md in your working directory or any directory above it" (fetched 2026-09-19), so a subdirectory's own `.claude/CLAUDE.md` displaces the `AGENTS.md` beside it and an import from it wires that file.
- `plan-migration.sh` resolves `--root` to the repository toplevel before planning: pointed at a subdirectory it described that subtree as if it were the whole repository. It also reports a new state, `shim-with-comment`, for a `CLAUDE.md` that is the import plus an HTML comment and nothing else (single-line or spanning lines). That file loads like a shim but is not the target shape, and both `dotfiles` and `medley` are in it today; it used to read as `both-with-content`.
- `CODEX_PROJECT_DOC_BUDGET` carries its four-part dated record, sourced to `openai/codex` `codex-rs/config/defaults.toml` (`project_doc_max_bytes = 32768`) and `codex-rs/core/src/agents_md.rs`, which seeds one shared remaining-bytes counter and so makes the budget cumulative rather than per file. The published config reference documents the key but no default.
- `setup`'s `check` verdict table gained a `NATIVE` row, reported as unblocked and never as loaded, naming `verify-load.sh` as the only proof of an actual load. `setup` and `realign` each gained an eval case covering that branch, and `setup` gained the `## Next` section that routes a repository to `audit`, `migrate` or `check` by outcome.
- `render-index.sh write` writes no block when there is nothing to index, and removes one that is already there, reporting `NO-INDEX-NEEDED`. It used to append an always-loaded block whose entire content was "No path-scoped rules or nested instruction files are present in this repository": 202 bytes of every-session text that says nothing, which is the cost the index exists to avoid and which the script's own pure-shim rule already refuses one row of. `check` agrees with the writer: no block and nothing to index is `IN-SYNC`, and a block left behind after the last rule went away is `DRIFTED`. `index-drift` already treated a repository with no block as one that never opted in, and is unchanged. Observed on the first real migration run (`songwriting`).
- `migrate`'s body: `--root` is shown on the plan command, since a shell's working directory does not survive between tool calls; the `shim-with-comment` state and its treatment are documented; `CASE` is a step-0 fix, `CITE` is retargeted in the same change, and `PATHDET`, `ACTION` and `SUPPRESS` are stated as reported-not-acted-on with where each goes; moved text moves verbatim, with write-side doctrine governing new text only; the canary's clean-tree check is stated for after the token is removed rather than before, since the tree is dirty by construction during the run; "nothing to split" is named as a valid outcome; a dispatched run's brief is the acceptance, with the plan still returned to the dispatcher; and Apply ends by running the repository's own markdown lint, which a regenerated block or a moved heading can trip.
- `CITE` matches a path-plus-heading citation (`` `CLAUDE.md` "Verify your changes" ``, backticked or bare, quoted or section-signed) as well as a markdown link, over `*.md` and `*.mdc`. `medley` uses that form exclusively and enforces it on pre-commit; `CITE` reported `NONE` against thirteen live citations, and a migration trusting that ships thirteen dead cites.
- `.lefthook/`, `.husky/` and `.githooks/` join `.claude/` and `.github/` in the never-rolled-up set. `medley` rolled `.lefthook/` up to 15 rows and buried two hooks that key on `CLAUDE.md`.
- `ACTION` matches a `uses:` line, not a comment naming the action.
- A `CLAUDE.md` carrying more than one `@AGENTS.md` import is no longer reported as `shim`: the target shape is exactly one line, so a repeated import is content to resolve.
- New `RULES` row: how many `.claude/rules/**/*.md` exist, how many lack `paths:`, and the total bytes of the unscoped ones, so "is this text already homed, and what is always-loaded today" is answerable without reading a hundred files by hand.
- `plan-migration.sh --help` lists the `DOCSHOME` row kind it already emitted, documents every row's columns (`DIR` and `BUDGET` were guesswork before), and describes `--dry-run` as accepted and ignored, which it always was.
- `MENTION` includes `.claude/`, which is where a Claude-configured repository most often enumerates its own instruction files (settings, bootstrap hooks, rules). Only `.claude/CLAUDE.md` is excluded, as an instruction file rather than a reference to one.
- `MENTION` rolls a directory holding more than ten rows up to one `<dir>/ <count> rows` line, with `--expand-mentions` to print them all. A corpus repository produced 108 rows of captured third-party prose, and a report nobody reads is the same as no report. Ten is a judgment call, stated as one in the code. `.claude/` and `.github/` are never rolled up at any count: they are precisely where an instruction-surface leak lives, so summarizing them would hide the rows the kind exists to show.
- `SUPPRESS` prints its path through `cygpath -m` where that exists, so a Windows operator gets a path their own tools resolve instead of `/c/Users/...`. Hosts without cygpath pass the path through unchanged.
- `render-index.sh wiring` prints `NONE` when a repository has no nested instruction files, for the same reason the plan rows do. The line is emitted by the subcommand, not by `nested_agents_wiring`, so the write-time warning that consumes those rows and filters on `UNWIRED` never sees it. `check/SKILL.md` says so too.
- `render-index.sh --help` states the split between `render`, which always prints a well-formed block because it answers "what would the index hold", and `write`, which decides whether one is worth writing.
- The generated rules index is opt-in in `migrate`, not a default Apply step. It is a Claude-only block inside the tool-agnostic `AGENTS.md`: in `medley` the render was 6,860 bytes, +52% on the always-loaded file, pushing the worst Codex path to 28,870 of 32,768. Apply now runs `render` first, reports the byte cost and the resulting worst-path `BUDGET`, and writes only on acceptance. A repository that declines it is not broken: `check` reports `NO-BLOCK` and `index-drift` stays quiet, because one that never adopted an index is not drifting from one.
- `migrate`'s body: every bundled-script invocation is written in the form its `allowed-tools` grant matches (direct path, unquoted, no `bash` wrapper), per the pairing contract in `plugins/docs-hygiene/scripts/allowed-tools-pairing.test.sh`; a step to find repository gates that classify changed paths by directory prefix, which read `<dir>/CLAUDE.md` as code and tripped a pre-push gate in `medley`, with the fix belonging to the gate and its tests rather than a bypass; and the two forward references to `cutover-check` marked as shipping separately.
- `reference/verification.md`: grep the chosen token rather than the word `CANARY`, since a repository can legitimately contain it; the nested canary's trigger must be a non-instruction file, because reading the `AGENTS.md` under test puts the token in the transcript by hand; and a stated fallback when the migration created no new `paths:` rules file (canary an existing one and report that none was created).
- `migrate`'s body: a table of the shortest Apply path per `DIR` state, because no step created a shim and `agents-only` (three of the repositories migrated so far) is a one-step job where four steps are no-ops; who triages rows under a dispatched run; the before-and-after `reachable` capture as the root-level parallel of `wiring`. The worked verification detail moved to `reference/verification.md` to keep the hub navigable: `verify-load.sh` per surface, where the canary token goes (its own paragraph under the first heading, never under a pointer), that `git grep -c CANARY` prints nothing and **exits 1** on success, the Codex rollout check as a dated record (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, a `custom_tool_call` record, observed on codex-cli 0.155.1), and a caveat that the progressive-disclosure detector assigns a root `AGENTS.md` the wrong tier and counts only markdown-link pointers, so its findings are hand-checked (#4292).
- `plan-migration.sh` gained a `MENTION` row: every other tracked occurrence of the literal `CLAUDE.md` outside the instruction files themselves, outside changelogs, and outside what `CITE` and `PATHDET` already report. A YAML list entry and a comment are neither a markdown link nor a filesystem-existence call, so both older rows missed them; `claude-code-proxy` carried the case, a `DOCUMENTATION_ROOTS` list in a CI workflow whose gate the new top-level `AGENTS.md` failed.
- Every row kind that can be empty prints a tab-separated `<KIND>` / `NONE` row rather than nothing. "Checked, and there is none" and "this kind never ran" were the same output, so a clean repository was indistinguishable from a broken script.
- `render-index.sh` resolves a relative `--file` against `--root` when `--root` was given. `check --file AGENTS.md --root <repo>` from outside the repository died with "--file is not a readable file", which is what an agent whose working directory does not survive between tool calls writes. Without `--root` the caller's directory is still the anchor, so nothing is re-anchored that was not asked for.
- `migrate`'s body: the "never write into `.cursor`/`.codex`/`.github`" rule is restated by purpose (never create or move instruction files there; a CI or tooling file that merely enumerates instruction-file paths is in scope for the move and is edited minimally as its own item); worked `verify-load.sh` invocations for the root, nested and rules-file cases, each with `--root`; a presence-gated Codex canary with the rollout check that no shell command searched for the token; a provisioning caveat on the lint step; a destination row for tool-agnostic text about one file or area; and "no Claude-specific text" named as a result rather than a skipped step.
- The plugin description, `README.md`, `setup`, `check` and `realign` bodies, `context/routing-rubric.md`, `context/verified-mechanics.md` and `realign/context/apply-recipes.md` restate the shim as conditional, each with the four-part dated record. `realign` and `migrate` are named as the two mutating surfaces, replacing "the only mutating surface".

## [0.13.11]

### Changed

- hook-utils.sh: `hook::jq_fields` answers a well-formed payload's plain-string fields with the library's builtin JSON parser and spawns jq only for a shape it cannot prove (a NUL escape, a duplicate key, a non-string value), so a hook that reads `.tool_input.command` and `.tool_name` from an ordinary payload spawns nothing; `hook::jq_fields_uncached` names the same body for a dispatcher that caches in front of it; `hook::emit_document` is the one function every stdout document goes through; `hook::extract_bash_subject_to` is the in-shell form of the telemetry subject. Every hook's decision is unchanged: the builtin answer is proven equal to jq's, or jq runs.
- hook-utils.sh: the builtin field parser is gated on Bash 4.0, the floor its associative-array index needs. A 3.2 shell (what macOS ships, and the floor these hooks document support for) goes straight to jq instead of failing `local -A` on every `hook::jq_fields` call.
- hook-utils.sh: the builtin field parser skips a string body without decoding it only past six times the longest REQUESTED key name, the width of `\uXXXX` per identifier character, rather than past a fixed 60 bytes. A requested key longer than 60 characters is no longer proven absent while it is present, and a key of 11 or more characters spelled entirely with `\u` escapes is still recognized.

## [0.13.10]

### Changed

- Merge the exclusion and tier case arms, share the skip-row writer and the language-hint scan in detect, fold the brace-split and escape arms in glob-tools and share the first-heading read in render-index (behavior unchanged).

## [0.13.9]

### Changed

- Merge the trials and filler parse arms, accumulate adherence results per arm and route index-drift through the shared hook path helpers and fixture setup (behavior unchanged).

## [0.13.8]

### Changed

- Refreshes this plugin's vendored copy of the shared shell library from the marketplace's canonical lib/ source after a behavior-preserving simplification: hook-utils.sh folds two identical path-probe guards into one and shares the orphaned-redirect handling across the bash segment parser; index-regen.sh folds two identical frontmatter skip guards; resolve-convention-pattern.sh drops a redundant quote-match clause. Parser output, hook JSON, and every resolver result are byte-identical before and after.

## [0.13.7]

### Fixed

- **The remaining surfaces that priced demotion as unreachability now price it as non-inheritance and silence.** `skills/audit/SKILL.md` (its `description` and its Demote lane), `skills/realign/SKILL.md`'s index-regeneration gotcha, `skills/delta/SKILL.md`'s `index-drift` row, `context/routing-rubric.md`'s pricing instruction, and the `Cost:` line of the worked example in `context/findings-artifact.md` all said a deferred surface is invisible to, unreachable from, or absent from subagents. A first-party probe on Claude Code **2.1.268**, recorded with its four-part verification record in `context/verified-mechanics.md`, shows a non-fork subagent does receive a path-scoped rule or a nested `CLAUDE.md`/`AGENTS.md` pair when it reads a path that surface covers, with the glob matched against the requested path so even a read that finds no file fires it. Each surface now states the two claims that do hold: nothing is inherited, and no deferred surface announces that it exists, so an un-indexed rule goes unnamed until a read happens to match its glob. No rubric rung, hard-deny class, artifact field, or gate moved; only the stated cost.

- **`README.md` cites the measurement that stands rather than the one it supersedes.** The "why this is not just move things into `.claude/rules/`" section asserted "everything that defers is invisible inside subagents" on the **2.1.238** run. That run dispatched its subagent after the parent had loaded every surface and never had the subagent read a covered path, so it measured non-inheritance and was over-read as non-triggering. The paragraph now reports the **2.1.268** result, including the requested-path match, and re-states the index's value as inheritance plus naming rather than as the only route in. The full evidence pointer to `context/verified-mechanics.md` above it is unchanged, and that record carries the dated four-part verification.

- **The pricing line, the index's stated value, and the revisit trigger move with it.** `skills/audit/SKILL.md` step 6 and `skills/realign/SKILL.md`'s present-before-asking rule told the operator to price "subagent invisibility"; `skills/check/SKILL.md`'s missing-index paragraph and `hooks/index-drift.sh`'s `WHY IT EXISTS AT ALL` comment called the index what makes a rule reachable; `evals/adherence-results.md` listed reachability as one of the three demonstrable justifications. Each now states naming rather than reachability, which is what the index actually supplies. `README.md`'s revisit-trigger table asked what to do if Claude Code ever makes deferred surfaces visible to subagents, a trigger that has now fired and been acted on; the row is re-aimed at the residual, Claude Code announcing a deferred surface so an agent learns it exists without reading a covered path. The hook's emitted message, its test, and every exit code are untouched.

- **Three eval expected outputs stop grading the superseded rationale.** `skills/audit/evals/evals.json` case 2 and `skills/realign/evals/evals.json` case 3 justified holding back a safety rail with "deferred surfaces are invisible inside subagents"; `skills/check/evals/evals.json` case 2 explained the index as what makes deferred surfaces "reachable". All three now carry the corrected reason. The graded behavior is identical in every case: the safety rail is still held back with no destination, and a missing index is still a recommendation rather than a gate failure.

## [0.13.6]

### Fixed

- **The drift hook and the check skill no longer price a stale index as unreachability.** `hooks/index-drift.sh` told the operator that "an un-indexed rule is unreachable from subagents", and `skills/check/SKILL.md`'s What-it-checks table gave the same consequence for a failed sync check. A first-party probe on Claude Code **2.1.268** shows the injection does fire inside a subagent that reads a covered path, so the index was never what made a rule reachable. Both surfaces now state the consequence that actually holds: an un-indexed rule goes unnamed, and nothing tells any agent that it exists until a read happens to match its glob. The check's verdict, exit codes, and mechanisms are unchanged; only the stated failure meaning moves. `hooks/index-drift.test.sh` still asserts that the notice says why drift matters, now against the wording the notice actually carries.

- **A renderer assertion description no longer names a gap the rendered block stops describing.** `scripts/render-index.test.sh` labeled its `subagents` substring check "the block explains the subagent gap" while the block it guards now explains that the trigger fires in subagents as well as in the main session. The assertion itself is untouched, so the coverage is identical; the description now says what it is checking.

## [0.13.5]

### Fixed

- **The generated rules index no longer tells every session that on-demand loading skips subagents.** The always-loaded preamble `render-index.sh` renders stated that the read trigger "does **not** fire inside subagents". A first-party probe on Claude Code **2.1.268** shows it does: a general-purpose subagent that reads a path a surface covers receives that surface, for a path-scoped `.claude/rules/` file and for a nested `CLAUDE.md`/`AGENTS.md` shim pair alike, and the glob is matched against the **requested** path, so a read of a covered path that does not exist injects the rule onto the failed tool result. The preamble now states that, keeps the compaction half unchanged, and keeps the standing advice to read a covered surface directly when its content is not already in context. Consuming repositories pick the correction up by re-rendering their index.

- **`context/verified-mechanics.md` records what the 2.1.238 run actually measured.** Finding 4 observed that a subagent inherits none of its parent's deferred loads and was read as "deferred surfaces do not load inside subagents at all"; the run never had the subagent read a covered path, so it measured non-inheritance and not non-triggering. The finding is corrected in place, the surface table's subagent column is re-stated per row, and a new `Subagent visibility, re-measured on 2.1.268` section carries the repro, the two boundaries the measurement does not cross (it covers `Read` and says nothing about `Write`; the unscoped-rule row stays unmeasured at 2.1.268 for want of an unscoped rule to probe), and the four-part verification record the upstream-drift convention requires.

- **The subagent gap is re-stated rather than dropped.** Demotion still costs something real: a subagent starts without every surface the parent had loaded and re-acquires one only by reading a covered path, and no deferred surface announces that it exists to any context that has not touched one. The always-loaded index is still the mitigation, now for discoverability rather than for reachability. The manifest description and the generator's `WHY` comment carry the same correction.

## [0.13.4]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.13.3]

### Changed

- **`audit`: description prose no longer addresses the reader.** Anthropic's skill-authoring guidance keeps first and second person out of a description because it is injected into the system prompt; the rewritten clauses name the user, the session, or the repository instead. Quoted trigger phrases are unchanged.

## [0.13.2]

### Changed

- **Options reference drops its em dashes.** The generated How-to-set-these block is rewritten by `scripts/sync-plugin-options-docs.py`, which is the fix site: its output is regenerated, never hand-edited. The block no longer needs the ignore marker that exempted it from the repository's em-dash gate, so that marker is gone as well.

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.

## [0.13.1]

### Changed

- **Vendored `hook-utils.sh` refresh.** The shared library gained one exit arm
  (`hook::finish`) and one ceiling-bounded parent walk (`hook::walk_up_to`),
  and retired seven value-printing helpers whose whole body called their
  caller-writes-to-a-variable twin, so each call site stops paying a subshell
  fork for a value the shell already has. This plugin's own hooks are
  unchanged; the version moves so consumers receive the library.

## [0.13.0]

### Added

- **render-index:** a `wiring` subcommand reports, for every nested `AGENTS.md` the index lists, whether an instruction entry point reaches it (the `CLAUDE.md` or `CLAUDE.local.md` beside it, one in any ancestor directory, or the root `.claude/CLAUDE.md`, by symlink or by import within the loader's four hops), and exits 1 on any `UNWIRED` row. The shared import chase now stops examining imports at the fourth hop instead of accepting a fifth-hop match. Claude Code reads `CLAUDE.md`, not `AGENTS.md`, so an indexed nested file with no such sibling was in sync, reachable, and never loaded, and `check` could not tell because it compares text. `write` now warns on stderr for each unwired file it indexes; the row stays, since the shim is the fix.
- **check:** the gate's table and running steps carry the wiring row beside sync and reachability.

## [0.12.2]

### Changed

- realign: a dated record for the AGENTS.md nearest-wins and CLAUDE.md ancestor-chain claims (prompt-audit follow-up F6)
- **verify-load:** an expected surface is matched on a separator-normalized path, so a rule Claude Code reports with backslashes is no longer called MISSING after the probe watched it load (prompt-audit follow-up F10)
- **verify-load:** each InstructionsLoaded hook invocation writes its own record file instead of appending to one shared log that concurrent hook processes clobber (prompt-audit follow-up F10)
- **verify-load:** the probe prompt names the Read call as the measurement itself, so the session makes the call instead of answering from context (prompt-audit follow-up F10)

## [0.12.1]

### Changed

- **Vendored `hook-utils.sh` tells a hook payload cut short at EOF from
  stdin that is not JSON.** `hook::buffer_stdin` returns a new rc 3 when
  what arrived is a well-formed JSON prefix and the pipe then closed (jq's
  own "Unfinished" parse verdict on an end-of-file read), and rc 2 as before
  for text that never parsed and for a pipe that stayed open past the idle
  bound with an incomplete document (the "timed out before a complete JSON
  payload" line is unchanged; a stall stays fail-closed). New
  `hook::stdin_cut_short_notice` emits the exit-0 notice for callers that
  block on rc 2. The successful stdin path still probes with a direct
  `printf | jq` (no stderr-capturing subshell); the diagnostic jq runs only
  after that probe has failed. None of this plugin's hooks branches on which
  non-zero status the read returned, so their behavior is unchanged; the
  copy is bumped because `scripts/sync-hook-utils.sh` keeps every carrying
  plugin byte-identical.

## [0.12.0]

### Added

- **`reference/artifact-protocol.md`**: the marketplace's shared lifecycle artifact protocol,
  byte-identical to the canonical copy. This plugin is now a protocol participant, and
  `scripts/validate-plugin-contracts.mjs` checks its copy alongside the other five.
- **`reference/topic-docs.md`: the binding that resolves both memory-tier homes.** Constant slug
  `instruction-placement`, branch-keyed below it, with the rung order, the child-slice
  non-predicate, the detached-`HEAD` consequence, and the self-ignore guard all cited from the
  contract rather than restated. The slice root carries an `INDEX.md` because it holds two artifact
  families, written at the same first memory-tier write as the guard.
- **The spine baseline, in the protocol's `baselines/` slot.** `delta` captures
  `<branch-slug>/baselines/spine-baseline.md` at the end of a cycle that completed its comparison:
  this run's detector spine and nothing else. Its frontmatter, its one body table, and the four
  rules binding a capture are owned by `context/findings-artifact.md` under "The baseline-capture
  obligation"; a baseline whose `branch:` does not match is refused rather than compared.
- **`reference/consumer-config.md` and the tracked suppression surface
  `.claude/instruction-placement.md`.** A declined finding is recorded against the marketplace's
  finding-suppression contract, layered across the three config-cascade layers with per-key merge
  on `finding_id` and the policy-floor precedence inversion, and registered in the cascade's
  implementers table. `suppressions` is the surface's only key; the plugin's `userConfig` dials stay
  personal and are never keys here. One declared deviation, recorded in that document: a scoped run
  adds a fifth reporting-only disposition, `not evaluated this run`, for entries outside its scope.
- **`instruction-placement:realign` writes the decline.** Two writes: `declined` into the
  branch-scoped findings artifact, and an entry on the tracked surface. That entry is offered in
  full, written only on an explicit yes, team layer only, with a required operator-authored reason
  and the run stating that the file must be committed to reach another checkout.
- **Finding ids and their constituents**, in `context/findings-artifact.md`: what `check`, `claim`,
  and `sites` hold for a placement finding, and this plugin's `anchor/v1`, the `sha256` of the
  `US`-joined enclosing heading path, truncated to 8 hex. Deliberately not a digest of the section's
  bytes, so a copy-edit cannot resurrect an accepted decline; the collision that trade accepts is
  recorded beside it.
- **The Finding record carries its `Suppression key` and its ordered heading path**, written by
  `audit`, which holds the detector stream. `realign` has no detector and carries those values
  verbatim rather than re-deriving an anchor from its own heading parse. A second parse that
  disagreed would mint a well-formed entry nothing ever matches, losing the decline with no error.

### Changed

- **Persistence moves from the `${CLAUDE_PLUGIN_DATA}` state key to two homes chosen by what the
  state is** (#3811). Evidence and the diff spine are memory tier and branch-keyed
  (`<memory_dir>/instruction-placement/<branch-slug>/`), because both are recomputed by the next run
  and are worthless outside the checkout that produced them. The operator's judgment is tracked,
  because git is the only mechanism that reaches another checkout: the topic-docs contract states a
  memory document is visible only in the checkout that wrote it, marks a sibling worktree
  `invisible`, and refuses to carry this file class with `.worktreeinclude` ("never baselines or raw
  scratch"). This is the same split the sibling `overengineering` plugin makes.
- **The state key is removed rather than re-scoped.** Its second segment was a
  `<worktree-discriminator>`, a hash of the checkout root, present by design so two worktrees "must
  not share a report". Correct for a per-checkout report, and exactly wrong for a decline.
- **`audit` and `delta` read the suppression surface and never write it**, reporting every entry
  that did and did not suppress with its contributing layer, and excluding the surface and its
  layers from the candidate set after the detector has run. What `delta` detects, its noise budget,
  and its report shape are unchanged.
- **`delta` merges its discoveries into the findings artifact before it captures the spine.** A
  `new` finding and a re-derived `changed` line range are its only durable output for `realign`,
  which reads the artifact and never the spine; capturing first leaves a baseline that has moved on
  from a finding no record carries, so the discovery is lost with no error. It writes records, and
  the only status it ever writes is the `accepted` to `pending` reset below. All four
  baseline/artifact combinations are enumerated, including the bootstrap where an artifact exists
  and no baseline does, the shape a first run in a fresh worktree takes.
- **A `RULE` row in the spine carries its glob-validation verdict.** `broken-glob` is a transition,
  not a state, and a rule whose file and glob text are both unchanged is exactly the case where
  nothing else in the row moves when the code the glob described is renamed elsewhere. Without the
  stored verdict a re-run either re-announces every already-broken glob every cycle or reports none
  of them. It now fires on `valid` to invalid, counts invalid to invalid as still-broken in the
  suppressed total, and stays silent on a glob that started resolving again.
- **`realign` reads the suppression surface before it presents anything.** This checkout's artifact
  is whatever the last local `audit` left behind and knows nothing about a decline another checkout
  committed since; consulting the surface after presenting would ask the operator to re-judge what
  their team already settled. A suppressed finding is never presented, accepted, or applied.
- **An `accepted` finding whose source changed resets to `pending`.** An acceptance is scoped to the
  text the operator read and to the range they were shown, and `realign` excises by that range, so
  carrying it forward authorizes an edit to content nobody approved. `declined`, `applied`, and
  `blocked` are carried, for reasons stated per status rather than by symmetry.
- **A bootstrap cycle captures the detector's own output, not a spine derived from the artifact.**
  The artifact holds classified candidates and held-back records, not every `SECTION` and `RULE`,
  so an artifact-derived spine is partial and the next cycle reports every record it never carried
  as `new`. The bootstrap states its cost instead: no `new` and no `broken-glob` this cycle, and a
  candidate that arose between the audit and the bootstrap is absorbed unreported, which is the one
  sanctioned exception to the merge-before-capture rule and routes to a full `audit` when the
  artifact is old enough for the tree to have moved on.
- **The `Status` vocabulary gains its one backward arc, and the writer rule is stated per arc.**
  Every forward move is `realign`'s and records a decision; the `accepted` to `pending` reset is
  written by whichever skill re-derives the record and withdraws a decision whose subject is gone.
  A decline the operator gave no reason for has no suppression entry and is durable only within its
  checkout, which `realign` now says at the moment it records one.
- **`realign`'s missing-artifact stop names the branch, not the project key.** The refusal to act on
  another home's artifact is argued from stale line ranges rather than from cross-project collision,
  which is what the branch axis actually protects against.
- **`context/findings-artifact.md` is `schema: 2`.** Its location formula changed, which is
  reader-breaking under that document's own stability rule; the stability section says so, and the
  state-key language about identifiers being stable "within a key" is replaced by the resolved home
  plus the cross-checkout `finding_id`.

### Removed

- **`lib/state-key.sh`.** No skill in this plugin resolves a machine-global key any more, and the
  file is dropped from the `scripts/sync-state-key.sh` carrier list rather than left unreferenced.

## [0.11.32]

### Changed

- **Synced `hooks/hook-utils.sh` drops leftover forks in the command tokenizer
  and path helpers.** `hook::bash_parse_segments` walks `${cmd:i:1}` instead of
  `read -N1` from a process substitution, and `$'…'` bodies decode through
  `ansi_c_decode_to` (`printf -v`) instead of `$(ansi_c_decode)`. `repo_root`
  and `repo_relative_path` gain `_to` forms so a caller does not pay a capture
  subshell around the necessary git process or around builtins-only work.
  GNU Bash runs command substitution in a subshell even for builtins
  (Command Substitution, Bash Reference Manual;
  https://mywiki.wooledge.org/CommandSubstitution). Cygwin's fork is a
  non-copy-on-write Win32 CreateProcess (Cygwin User's Guide, Process
  Creation). Kernel census `strace -f -e trace=clone,clone3,fork,vfork,execve`
  over 5 plain parses plus 5 with a `$'…'` word: 15 clones → 0. Tokenizer
  argv, unresolved-root fallback, and relative-path redaction are unchanged.

## [0.11.31]

### Changed

- **Synced `hooks/hook-utils.sh` drops leftover forks on the stdin and notice
  paths.** `hook::json_escape` no longer pipes through `tr`; `hook::emit_channels`
  writes through `json_escape_to` instead of `$(json_escape)`; the fractional
  `read -t` slice uses a Bash 4+ version check (CHANGES bash-4.0-alpha)
  instead of a TMPDIR probe file; `notice_once`
  reads the marker with `read` and creates or prunes the skip-notice directory
  once per process. GNU Bash runs command substitution in a subshell even for
  builtins (Command Substitution, Bash Reference Manual;
  https://mywiki.wooledge.org/CommandSubstitution). Cygwin's fork is a
  non-copy-on-write Win32 CreateProcess (Cygwin User's Guide, Process
  Creation). Kernel census `strace -f -e trace=clone,clone3,fork,vfork,execve`
  over 20 calls: `json_escape` 60→0 creations (20 `tr` execs→0);
  `emit_channels` 240→0; `resolve_read_slice_to` 20→0; `notice_once` 79→3.
  Per `buffer_stdin_to` fire: 4→3 creations; PATH-visible `jq` execs unchanged.
  Notice JSON, timeout resolution, and skip-notice latching are unchanged.

## [0.11.30]

### Changed

- **Synced `hooks/hook-utils.sh`.** `hook::buffer_stdin_to` captures the
  hook payload in-process (no command-substitution subshell) and can fuse
  the JSON completeness check with field extraction so a caller that was
  about to run `jq` twice spends one process. This plugin's own hook
  behavior is unchanged.

## [0.11.29]

### Changed

- **`hooks/index-drift.sh` locates the hook directory and the edited file's
  directory with parameter expansion, not `dirname`.** GNU Bash forks a
  subshell for every command substitution even when the body is a builtin
  (Command Substitution, Bash Reference Manual). `${BASH_SOURCE[0]%/*}`
  and `${file_path%/*}` equal `dirname` for every shape those paths take. The
  hot-path guard (a write outside `.claude/rules/`) still returns before any
  subprocess. What the hook notices is unchanged.

## [0.11.28]

### Changed

- **Telemetry envelope at contract 1.1: the session id rides on the spine.**
  The synced `hooks/hook-utils.sh` copies the payload's `session_id`,
  `prompt_id`, `tool_use_id` and `agent_id` from the buffered `INPUT` onto
  every envelope this plugin's hook emits, each only when present as a plain
  id, so the claude-ops per-session report lists this hook with no change to
  the hook itself (#3758). `schema_version` reads `1.1`; no hook behavior
  changes.

## [0.11.27]

### Changed

- setup: no longer claims to be the only surface that verifies index reachability; `check` gates both sync and reachability on every run, and setup asks the reachability question once before the first audit.
- audit: the gotchas pointer drops its drifted "ten" count; the adherence paragraph points at the measurement file instead of restating its trial count and percentage; the empty-detector gotcha states the awk-panic cause in the present tense.
- check: the reachability row is introduced without "newest".
- delta: the quiet-run report states the window and the suppressed count instead of a one-line ceiling; eval case 1 renamed and reworded to match.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.11.26]

### Changed

- **`hooks/index-drift.sh` reads its kill switch before sourcing the library.**
  `index_drift_hook_enabled` was read through `hook::check_enabled`, which only
  exists once the 2,766-line `hook-utils.sh` is sourced, so a DISABLED hook
  parsed the whole library before learning it had nothing to do. The predicate
  is now inlined above the `source` line, in the one shape
  `scripts/check-killswitch-hoist.sh` pins to `hook::is_enabled` (the gate
  scans PostToolUse rows from this change on, so the order cannot drift back).
  Measured on the Linux CI host on three standalone hooks of this shape, N = 15:
  the disabled path drops from 6.1 to 6.5 ms to 3.1 to 3.2 ms against a 1.8 ms
  spawn floor, so a consumer who turns the hook off stops paying for the
  library. Enabled behavior is unchanged.

## [0.11.25]

### Changed

- **Vendored `hook-utils.sh` drops two `buffer_stdin` startup subshells and a
  `tr` exec on every `repo_root`.** Timeout and slice resolution write into
  caller variables (`printf -v`) instead of `$( )` / process substitution.
  GNU Bash forks a subshell for both even when the body is builtins only.
  `hook::repo_root` strips CR with parameter expansion, the same substitution
  `buffer_stdin` already uses for the payload. New `hook::json_str_object_to`
  builds compact string-field objects without jq, for telemetry data builders
  that only carry strings. Same verdicts; the copy is bumped because
  `scripts/sync-hook-utils.sh` keeps every carrying plugin byte-identical.

## [0.11.24]

### Added

- **`hooks/hooks.json` carries a top-level `description`.** The hooks reference
  documents the field as optional, and every hook set in this marketplace omitted
  it; it is the surface an operator reads when deciding what a plugin does to
  their session. One line naming what this plugin's hook set does. (#3719)

## [0.11.23]

### Changed

- **`index-drift.sh` derives its own directory once.** The always-on hook called
  `dirname "${BASH_SOURCE[0]}"` twice, once to source `hook-utils.sh` and once to locate the
  renderer; `hook_dir` is now computed once and reused, removing one subshell from the fire path
  and none from the early-exit path, which returns before the second use.
- **Two dead `SUBCOMMAND=""` stores removed**, from `glob-tools.sh` and `render-index.sh`. Neither
  script ever reads the name again; both dispatch on `"${1:-}"` directly.
- **The shared-sort claim in `render-index.sh` is corrected in place, because measurement
  contradicted it.** Sharing one sort between the listed head and the grouped tail removes a
  `sort` from the grouped-tail path only, which had sorted the same rows twice, and costs a
  subshell on the common path, where one sort already sufficed. The two-spawn saving the hook
  sees comes from the marker-count change in `check` and `write`, not from this sort.
- **`glob-tools.test.sh` names its over-budget row count.** Three budget cases repeated the same
  awk-and-count pipeline; a comment now records why the cases assert on the count rather than on
  a named pattern, since which of a rule's globs trips a shared budget is not part of the
  contract.

## [0.11.22]

### Changed

- **`glob-tools.sh` drops a temp-file lifecycle per pattern.** The match count
  wrote grep output to a `mktemp`, sorted it and removed it; it now pipes
  directly into the same `LC_ALL=C sort -u`. The old temp file was never in the
  trap, so it leaked on an abort. Deduplication scope is unchanged, which was the
  risk: the temp file was created inside the per-pattern block, so it was never
  global. Confirmed across 88 micro-cases and 52 fixture runs under four locales.
- **`lib/discover.sh` drops an unreachable awk guard** and the state variable
  that fed it. Instrumented in the original rule set, it fired zero times across
  20 input shapes including CRLF, CR-only, a missing closer and a byte-order
  mark, with identical output over all 1,389 tracked markdown files.
- **`detect.sh` merges two `trap ... EXIT` registrations** where the second
  silently replaced the first, combines two `BEGIN` blocks, and collects section
  markers directly instead of building a comma string and splitting it back to
  sort. That round trip would have shredded any marker containing a comma; the
  vocabulary happens never to contain one. Output byte-identical over the whole
  repository, 25,689 lines.
- **`render-index.sh` sorts its row array once** instead of up to three times per
  render, and four smaller cleanups. The generated index is byte-identical across
  80 render comparisons, and this repository's own index still reports IN-SYNC.
- **`index-drift.sh`** replaces a two-branch `case` whose default was a bare
  no-op with an `if`, keeping the rationale. Traced: identical external-command
  counts, one builtin removed, 11 ms per run before and after.

## [0.11.21]

### Changed

- **Vendored `hook-utils.sh` builds the telemetry envelope and reads `file_path`
  with shell builtins.** `hook::emit_telemetry` no longer spawns two jq
  processes, a mktemp and an rm per run: the envelope is assembled in the shell
  as one compact line (the same document jq produced, now `jq -c` shaped), with
  jq kept only as the fallback for a data object the builtin compactor cannot
  prove. `hook::read_file_path` takes `.tool_input.file_path` without jq on the
  well-formed payload shape and resolves the file, project root and temp roots
  with one batched `realpath` instead of one process each. Same verdicts, same
  emitted path, same sink record; phase 4b of the hook-performance program
  (#3623). The copy is bumped because `scripts/sync-hook-utils.sh` keeps every
  carrying plugin byte-identical.

## [0.11.20]

### Changed

- **`index-drift` carries an `if` filter, `Edit(**/.claude/rules/*.md)`.** The hook only
  ever acts on a rule file under `.claude/rules/`, which is also its own first check, so
  every other Write/Edit no longer spawns it.

## [0.11.19]

### Fixed

- **`render-index.sh` read a drive-letter `--file` and `--root` as relative, so the index-drift
  hook was a no-op on every Windows write.** `git rev-parse --show-toplevel` answers `C:/repo`
  under Git Bash, and that is the spelling `hooks/index-drift.sh` hands the renderer. The absolute
  test looked only for a leading `/`, so the target was joined to the calling directory, `check`
  died on an unreadable file, and the hook swallowed the error and exited 0. Nothing about the
  repository looked wrong and no stale-index notice ever appeared. `[A-Za-z]:[\/]` is now absolute.

- **`reachable` and `write`'s reachability warning stripped a root prefix that could not match.**
  Both strip `"$PWD"/` from the target after entering `--root`, and `$PWD` is the shell's own
  spelling (`/c/repo`) while the target stayed in git's (`C:/repo`), so the strip silently left the
  path absolute: `reachable` asked about a target it could not name, and `write` warned that a
  reachable index was unreachable. The target is now re-spelled through `cd "$dir" && pwd`, the
  same call that produced `$PWD`, for those two comparisons only. The path the caller wrote is
  untouched, so every read, write and status line still names it.

- **A backslash drive-letter `--file` or `--root` (`C:\repo\AGENTS.md`) is re-spelled with forward
  slashes at intake.** GNU `dirname` and `basename` do not treat `\` as a separator, so the target
  split to `.` plus the whole string, the re-spelled target became `$PWD/C:\repo\AGENTS.md`,
  `reachable` asked about a path that does not exist, and `write` could warn that a reachable
  index was unreachable. Only the drive-letter shape is touched; a POSIX path carrying a literal
  backslash passes through unchanged. Status lines for a backslash input now print the
  forward-slash form.

### Changed

- **`scripts/lib/discover.test.sh` reports a host skip instead of failing on a copied symlink.**
  Under MSYS without `winsymlinks`, `ln -s` copies its target. Most cases survive that, but the one
  asserting a `CLAUDE.md` symlinked to `AGENTS.md` is reachable has no subject at all. It now
  probes the link round trip and prints a visible `SKIP (host: ...)` line counted apart from the
  pass total.

## [0.11.18]

### Changed

- **Options reference cites the plugin-reconfiguration convention.** The generated
  How-to-set-these block no longer restates the 2.1.240 verified-version record.

## [0.11.17]

### Fixed

- **`lib/state-key.sh` now exits 2 when neither `sha256sum` nor `shasum` is on PATH, and prints no key.** The helper's `exit 2` ran inside a command substitution, so a host without either digest tool continued and printed a malformed key at exit 0. Synced from the canonical `claude-config` copy via `scripts/sync-state-key.sh`.

## [0.11.16]

### Changed

- **`routing-rubric.md`: Gate 0 names its deletion counterpart.** The six hard-deny classes now
  govern two operations across two owners. This rubric decides relocation, and the marketplace's
  instruction exception register adopts the same classes by reference to decide deletion. Gate 0
  gained a note saying so, and saying which question routes where, so a consumer asking "may this
  be deleted" does not read a relocation verdict as an answer. The class list is not re-enumerated
  anywhere else; this rubric stays its sole owner, which is what keeps one concern on one
  adjudication chain instead of two lists that drift apart.

## [0.11.15]

### Changed

- **`routing-rubric.md`: stamped the listing-cost restatement.** The rubric's step-3 note (a new
  skill's listing entry, truncated at 1,536 chars) cited nothing; it now cites the frontmatter
  reference with a verified date (2026-08-31) and a divergence trigger, per the marketplace's
  upstream-drift convention. Found in the frontmatter-alignment sweep.

## [0.11.14]

### Fixed

- **`render-index.sh` no longer corrupts brace globs in the rendered rule index.** The glob-list
  prettifier joined paths with `paste -sd,` and then padded every comma via
  `sed 's/,/, /g'`, which also padded commas inside brace expressions: `src/*.{ts,tsx}` rendered
  as `src/*.{ts, tsx}`. The join now inserts the `", "` separator directly in awk, so only
  join-inserted separators are padded and brace commas are never touched. Reproduced against a
  fixture rule before the fix and pinned by two new suite cases (one asserting the correct
  rendering, one asserting the corrupted form is absent); the suite grows from 61 to 63 cases.

## [0.11.13]

### Changed

- **Behavior-preserving simplification sweep (batch-simplify).** `detect.sh` collapses the
  manual `--` argument-capture loop into the marketplace's precedented `EXPLICIT+=("$@"); break`
  form and drops a dead `SECTION_COUNT=0` initializer (the variable is unconditionally
  reassigned before its only read). Emitted rows, exit codes, and `--help` text unchanged;
  refutation-verified across 23 argv edge cases and the full 40-case suite.

## [0.11.12]

### Changed

- **Vendored `hook-utils.sh` gained `hook::repo_relative_path`.** The shared lib
  now owns the repo-relative path computation twelve sibling hooks had each
  hand-copied, together with the absolute-path degrade only four of those twelve
  copies carried (#1133). This plugin's hooks do not call it; the copy is bumped
  because `scripts/sync-hook-utils.sh` keeps every carrying plugin
  byte-identical.

## [0.11.11]

### Fixed

- **`adherence-experiment.sh` scored its underscore criterion against the whole file.** The seeded
  `Billing.cs` already declares `private readonly decimal _unitPrice`, so the check returned 1
  before the model had written anything and no run could ever fail it. The check is now scoped to
  the body of the class the task asks for, by a scanner that biases toward under-crediting: a
  body-less primary-constructor declaration, a brace inside a string or comment, and any other
  shape that leaves the body undelimited all score 0 rather than running on into a later class and
  crediting a field the task never asked for. For an instrument whose numbers get published, a
  false 1 is the unrecoverable error. `adherence-results.md` carries a correction noting that the
  recorded run's `underscore` and `both` columns were constants, not measurements; the conclusion
  is unchanged, since it rests on the `sealed` criterion, which was scored correctly.
- **Both class matches now require a non-identifier boundary after the name.** `InvoiceTotal` is a
  prefix of `InvoiceTotals` and `InvoiceTotalizer`, so a trial that produced a differently named
  class scored full compliance on both criteria. The boundary still admits the three shapes that
  occur here: the bare name, `InvoiceTotal {`, and `InvoiceTotal(decimal seed);`.
- **The underscore criterion credits a FIELD, not any member carrying an underscore name.** The
  convention is about field naming, but the match accepted an auto-property
  (`private decimal _total { get; set; }`), an expression-bodied property (`private decimal _Total
  => x;`) and a method (`private decimal _GetTotal() => x;`). The name must now be followed by a
  `;` or by an initializer `=` that is not the `=>` of an expression-bodied member. A
  multi-declarator line credits on its first name only, per the same under-crediting bias.
- **The usage banner documents `--filler`.** The flag has always been parsed, and
  `adherence-results.md` gives `--filler 120` as the re-run command, but neither the banner nor the
  header comment listed it.

### Added

- **`adherence-experiment.test.sh` covers the experiment harness.** 52 cases driving the harness
  through a stub CLI, so every trial's output is controlled and nothing is skipped: argument
  validation and the exit-3 unmeasurable path, arm construction (identical filler and identical
  seed file in both arms, the convention delivered inline in one and as a `**/*.cs` path-scoped
  rule in the other), scoring asserted in both directions, against the three C# shapes that decide
  whether a field from another class is credited and the three near misses that carry the right
  characters in the wrong construct, per-trial reset, the ERROR row for a failed trial and its
  exclusion from the arm's `n`, and fixture cleanup. The file previously mapped to no suite under
  `scripts/affected-tests.sh`.

## [0.11.10]

### Changed

- **Shared `hook-utils.sh` comment cleanup.** Comment-only sync from `lib/hook-utils.sh`: history-narration comments rewritten as present-tense rules; no behavior change.

## [0.11.9]

### Changed

- **`glob-tools.sh` collapses a bracket-negation if/elif chain.** The two branches computed the
  same result; one expression now does. `render-index.sh` merges two consecutive `sed` passes
  into one. Output is byte-identical in both scripts. Code-tidying sweep, behavior-preserving.

## [0.11.8]

### Changed

- **The `@import` rule in `realign`'s apply recipes states the positive.** It said only what fails.
  It now says to cite the shared file by path, carrying the same prohibition and the same rationale.
  Docs-hygiene sweep, L5-noise.
- **The generated options block sits under `## Configuration`.** It was under `## Revisit triggers`,
  a maintainer watchlist whose own lead sentence says so. The generated table itself is unchanged; a
  `## Configuration` heading was added above it. Docs-hygiene sweep, L8-write-for-humans.

## [0.11.7]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.11.6]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** Corrected
  `hooks/index-drift.sh`'s header to the kill switch's real
  `CLAUDE_PLUGIN_OPTION_INDEX_DRIFT_HOOK_ENABLED` spelling; removed dead `tier` plumbing
  from `scripts/detect.sh`'s `emit_file_facts` (the awk program never read it); removed a
  redundant array re-initialization in `scripts/glob-tools.sh`; `scripts/lib/discover.sh`'s
  rule emitter streams to stdout instead of staging through a temp file (all consumers read
  to EOF and no caller runs errexit, so failure semantics are unchanged); dropped
  doubly-redundant `|| true` at two `branch()` call sites in `scripts/precompute.sh`.
  All seven suites green (38/40/56/23/61/18/17); independent refutation pass including a
  mid-failure streaming experiment found no counterexample reachable in this codebase.

## [0.11.5]

### Changed

- **Instruction-surface de-slop (#2891, instruction-placement cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.11.4]

### Fixed

- **Vendored `hook-utils.sh` skip latch (#3128).** The shared notice latch now
  keys on session and agent (a subagent gets its own first notice), stores a
  skip count in the marker (independent of `HOOK_TELEMETRY_SINK`), and emits a
  one-line re-notice every 8 skips instead of going silent after the first.
  The first `PATH probed:` dump omits other plugins' bin dirs. Copies stay
  byte-identical via `scripts/sync-hook-utils.sh`.

## [0.11.3]

### Fixed

Four defects raised in review on #3225, each reproduced before it was fixed.

- **The index-drift kill switch read a variable nothing sets, so the option did nothing.** The hook
  called `hook::check_enabled "INSTRUCTION_PLACEMENT_INDEX_DRIFT"`, which resolves to
  `CLAUDE_PLUGIN_OPTION_INSTRUCTION_PLACEMENT_INDEX_DRIFT_ENABLED`. The declared userConfig key is
  `index_drift_hook_enabled`, which Claude Code mirrors as
  `CLAUDE_PLUGIN_OPTION_INDEX_DRIFT_HOOK_ENABLED` -- the name `README.md` already documented.
  `hook::is_enabled` treats an unset variable as enabled, so setting the option `false` had no
  effect. The suite hid it twice over: the case set the same wrong name the implementation read, and
  it ran against a repository an earlier case had already brought in sync, so the hook was silent
  either way. Now `INDEX_DRIFT_HOOK`, tested on a freshly drifted fixture, with a control case
  proving the fixture drifts and a negative case proving the old spelling does **not** silence it.

- **`validate` pooled the brace budget across unrelated `--glob` flags.** Every CLI glob was tagged
  with the same `<cli>` source, and the budget resets on a source change, so two independently legal
  512-expansion globs in one invocation charged 1,024 against one budget and the first was reported
  `over-budget`. The budget belongs to a rule's whole `paths:` list; a standalone `--glob` is nobody's
  list. Budget grouping is now a key distinct from the displayed source.

- **The symlink backfill re-admitted files the corpus exclusions had just rejected.** `detect.sh`
  skips an excluded path in the tracked walk, then the backfill loop that recovers symlink-only rules
  added it back because it only asked whether the path was already in the file list -- emitting a
  `SKIP` row *and* a `FILE` row for one path and counting it in both summary totals. `context/corpus.md`
  states exclusions are absolute and applied before any classification; the second entry point now
  enforces the same rule.

- **An absolute index target outside `--root` was reported as not existing.** `ip_index_target_loaded`
  prefixed the root unconditionally, building `<root>//abs/path`, which collapses to a path under the
  root that is not there -- so `reachable` and `write`'s post-write check both said "does not exist"
  about a file plainly present. Easy to hit with the default `--root .` and a `--file` elsewhere.

### Known issue, not fixed here

- `lib/state-key.sh`'s `sha256` helper runs as a non-last pipeline stage, so its `exit 2` on a host
  with neither `sha256sum` nor `shasum` exits only that stage: `cut` reads nothing and the caller
  returns a malformed key with status 0 instead of failing cleanly. The file is byte-identical to the
  canonical `plugins/claude-config/lib/state-key.sh` and shared by six plugins, so the fix belongs
  with the canonical copy and its sync cluster rather than in this plugin's PR. Raised on #3225.

## [0.11.2]

### Fixed

- **`awk -v` mangled every value carrying a backslash, and it broke the suite on CI.** POSIX requires
  a `-v` assignment to process escape sequences, so the two awks disagree on any value containing
  one: gawk drops an unknown escape's backslash (`\[` becomes `[`, with a warning on stderr) and
  reads `\t` as a tab, while mawk passes both through untouched. Three sites were exposed.

  `glob-tools.test.sh`'s `row_field` helper passed the pattern under test through `-v`, so the
  escaped-literal case this suite exists to pin -- `photos \[2024/**` -- had its backslash stripped
  before the field comparison, matched nothing, and returned empty. **This was the real cause of the
  red `plugin-gate` on every CI run of this branch**, and it was invisible locally because this
  container has mawk and the runner has gawk.

  `render-index.sh` passed the generated index block through `-v repl=`, and `detect.sh` passed each
  file path through `-v path=`. Both carry repository-derived text: a rule path containing a
  backslash would have been silently rewritten on the way in, corrupting the written index in the
  first case and misattributing every emitted fact in the second.

  All three now travel through `ENVIRON`, which both implementations pass through literally. The
  whole suite is now run under **both mawk and gawk** -- 242 cases, 0 failures in each -- rather than
  under whichever one the box happens to have.

## [0.11.1]

### Fixed

- **Skill-header orientation counted rules with the open-coded pattern the shared layer replaced.**
  `precompute.sh audit` and the `check` skill's inline injection both ran a bare
  `find .claude/rules`, which is the exact line whose four bugs motivated `lib/discover.sh` in
  0.2.0: it sees only the root tree and only real directories. On a repository with a nested
  `packages/*/.claude/rules` and a symlinked shared set it reports **1** where the gate walks
  **3**. Nothing downstream used the number, since the engines were already consolidated, but the
  header is what the model reads before any work starts, and an orientation that understates the
  repository by two thirds sets the wrong expectation for the sweep it introduces. Both sites now
  count through `ip_discover_rules`, and the nested-instruction count through
  `ip_discover_nested_instructions`, so the header and the gate tell one story. Raised in review on
  #3225.

### Changed

- `precompute.sh` gains a `check` mode, so the `check` skill composes its header through the one
  script like every other skill in the plugin rather than open-coding three inline injections.
  Its presence probes drop their backticks to match the `audit` mode's wording.

### Added

- `precompute.sh` gets its own suite (23 cases), covering the count agreement on a fixture that
  hides rules from a root-only `find`, the corpus rules for nested instruction files, and the
  degradation contract every mode owes a skill header: exit 0 and a printable value even where
  there is nothing to read.

## [0.11.0]

### Fixed

Five defects raised in review on #3225, each reproduced first and then fixed. Four were P1.

- **A `.claude/rules` that is itself a symlink was invisible.** The outer `find` required `-type d`
  without `-L`, so a symlinked rules root never matched and the inner symlink-following scan was
  never reached. This is strictly worse than the symlink bug fixed in 0.2.0: that one lost a single
  linked rule, this one loses an **entire shared rule set**, and sharing a whole set by symlink is
  the documented layout. A symlinked `.claude` directory had the same shape one level up. Both are
  now covered.

- **Brace commas inside an inline flow list were treated as list separators.** A valid
  `paths: ["src/*.{ts,tsx}"]` was split into `src/*.{ts` and `tsx}`, two zero-match failures
  reported against a rule that was correct. The parser now splits only at brace depth zero and
  outside quotes.

  **The same bug existed in three copies**, in `glob-tools.sh`, `render-index.sh`, and `detect.sh`,
  so the fix is one parser (`ip_parse_paths` in `lib/discover.sh`) and the deletion of all three.
  Three copies meant three places to fix and three places to drift, the same reasoning that moved
  discovery into that file in 0.2.0.

- **The brace budget was charged per pattern instead of per rule.** The documentation is explicit
  that "a rule's whole `paths:` list shares one budget of 1,000 expanded patterns", quoted
  correctly in the script's own header while the code reset the counter for every pattern. A rule
  with two 512-expansion globs passed the gate while its combined 1,024 expansions exceed what the
  loader will expand, so `check` reported green for a rule Claude Code silently leaves unexpanded.
  Now tracked as a running total per rule, with a test that the budget does not leak between rules.

- **`verify-load.sh --expect` matched a bare substring.** `rules/rule.md` was reported `MET` when
  the only loaded path was `.../old-rules/rule.md`, letting the empirical verifier emit
  `VERDICT PASS` for a surface that never loaded. For a tool whose entire job is not lying about
  what loaded, a false `MET` is the worst available defect. Matching is now whole-path or
  path-component suffix, with a live-CLI test asserting the near-miss is `MISSING`.

- **The declared `userConfig` options did nothing.** `breadth_max` and `index_max_rows` were
  advertised in the manifest and reported by `setup`, while both scripts hardcoded their defaults
  and only command-line flags had any effect. An option that is documented and inert is worse than
  one that does not exist. Both scripts now read the native `$CLAUDE_PLUGIN_OPTION_<KEY>` mirror,
  fall back to the default on a non-numeric value, and still let an explicit flag win.

### Changed

- `declare -A` replaced with a running counter in `glob-tools.sh`: associative arrays are bash 4+
  and macOS ships 3.2, the same portability trap that `mapfile` hit in 0.4.0.

## [0.10.1]

### Changed

- **The findings artifact declares its stability guarantees, and its owner doc is deliberately not
  written.** Promoting the contract to a `docs/conventions/` cross-plugin convention was considered
  and declined *for now*: the artifact has three consumers, all inside this plugin, so a shared
  convention would fix a shape against requirements that do not exist yet. An interface with one
  implementation is a guess. The convention registry's rule is a deadline ("before a second plugin
  adopts it"), not an instruction to publish early.

  What landed instead is the part that is defensible today: explicit guarantees a future consumer
  can hold (`schema: 1` is a real version; field names and the status vocabulary are fixed within a
  version; fields may be added; identifiers are stable and never reused; the location formula is
  fixed), and the three prerequisites promotion would need: a real second consumer with stated
  needs, a decision on the auto-apply boundary that does not launder the per-item gate, and the
  owner doc landing before that consumer ships.

## [0.10.0]

### Added

- **`delta` skill: report only what moved.** A full audit is worth running rarely and reading
  carefully; this is the lane for the other times. The failure it exists to prevent is specific: a
  re-run that re-presents the same forty findings the operator already worked through trains them to
  skim, and a skimmed report is how a bad migration gets approved.

  The five movement shapes are `new`, `changed`, `broken-glob`, `index-drift`, and `stale`, with an
  explicit list of what is *not* movement. **`broken-glob` is the shape that most justifies a cadence**: a
  glob breaks when the code it described is renamed or moved, which is an ordinary refactor nowhere
  near the rules tree, produces no signal at the time, and leaves the rule silently not firing.
  Nothing else in the plugin notices between `check` runs.

  Decisions are respected rigorously: `declined` stays declined and is never resurrected as `new`,
  `changed`, or "for review". Suppression below the noise budget is always **counted in the report**.
  A delta that hides its own filtering is precisely the failure it was built to avoid. A quiet run
  is one line, with no padding to look useful.

## [0.9.0]

### Changed

- **Route-out is operative, not decorative.** The six sibling-plugin boundaries were prose in the
  README and nothing in the skill. They are now presence-gated Skill-tool invocations with a
  documented fallback each, owned by
  [`skills/audit/context/routing-out.md`](skills/audit/context/routing-out.md), plus two rules that
  keep routing from degrading into silent dropping: a routed candidate is reported *as routed*, and
  routing one question never cancels a placement finding on the same section. A section can be both
  misplaced and duplicated.

- **The audit skill practices the disclosure it preaches.** Adding the routing table pushed
  `SKILL.md` to 224 lines, past the soft target, in a plugin whose entire subject is progressive
  disclosure. The routing table and the gotchas moved to spokes behind conditioned pointers; the hub
  is back to 181 lines. `context/gotchas.md` remains a recognized gotchas surface, so the signal is
  relocated rather than lost.

## [0.8.0]

### Added

- **`PostToolUse` index-drift hook (14 contract tests).** Index drift is silent by construction: a
  rule added without regenerating the index is a rule no subagent can reach, and nothing about the
  repository looks wrong until someone runs the gate. This shortens the feedback loop from "next CI
  run" to "next tool call". Advisory and non-blocking: it always exits 0, and
  `/instruction-placement:check` remains the authoritative gate.

  **The matcher is `Write|Edit`, which the fleet hook-budget convention counts as always-on**, so
  the hot path was designed and then measured rather than assumed. After the kill switch, the first
  thing the hook does is a substring test on the written path; every write outside a `.claude/rules`
  tree returns before any subprocess, git call, or index render. Measured cost on that path: **~9 ms
  per invocation including bash startup**, against a ≤1 s per-tool-call budget. The suite asserts a
  generous ceiling so an accidental git or render call landing on the hot path fails a test.

  It stays quiet where quiet is right: an in-sync index emits nothing, and a repository that never
  adopted an index is never nagged into adopting one. Kill switch: `index_drift_hook_enabled`.

### Fixed

- **`hook::repo_root` was handed a file path instead of a directory** during development. It returns
  the input unchanged with a non-zero status, which an `|| true` swallowed into a silent no-op, the
  exact failure shape (`hook_non_blocking_error`, hook enforces nothing, nobody notices) that this
  repository's hook conventions exist to prevent. Caught by the drift-detection tests failing while
  every robustness test passed.

## [0.7.1]

### Changed

- **Eval fixtures replace narration.** Four of the audit's six cases were graded against a described
  situation rather than real content, which grades the description as much as the skill. They now
  run against two committed fixtures. The first is a bloated `AGENTS.md` carrying the full spread
  the rubric has to separate: safety rails, path-local conventions, a creation-governing checklist,
  and a derivable directory listing. The second is a contributor guide with genuine conventions
  buried among history, setup prose, and release process, which is the promote lane's actual
  discrimination problem.

  The two remaining cases keep `narration: true` honestly: both describe repository state (a repo
  with no Rust files; a bare invocation's coverage report) that no single fixture file can express.

## [0.7.0]

### Added

- **`setup` skill and consumer configuration.** The plugin earns one on all three of the setup
  contract's criteria, but one carries the weight: **the index target is an external referent whose
  validity a configuration prompt cannot establish.** A prompt stores the path you typed; it cannot
  tell you Claude Code will never read it. `check` runs the reachability probe and leads with that
  verdict, because it is the single failure every other gate reports green through.

  Also verifies `git` (tracked-file discovery degrades without it) and reports the Claude Code CLI
  and `jq` as *optional* prerequisites that affect only the empirical load probe. The report states
  "optional, absent" and "missing" as different things.

  Configuration reporting names each value's **source**, not just its value: "75 (default)" and
  "75 (configured)" are different facts about a repository, and only one of them explains a
  surprising result.

  `apply` writes nothing on its own. Every remediation here edits a file that steers agent behavior,
  so it presents the exact change and asks, then re-verifies, because an apply that does not
  re-verify has not finished.

- `userConfig`: `breadth_max` (default 75) and `index_max_rows` (default 40). Both have defaults that
  behave, so the plugin still runs with no configuration at all, and `setup` says so rather than
  presenting configuration as a prerequisite to a first audit.

## [0.6.0]

### Added

- **The index has a size posture.** It had none: no cap, no ranking, no truncation. Since the index
  is always-loaded, a large monorepo would have turned the mechanism that *frees* always-loaded
  budget into a consumer of it, and with the adherence claim gone (0.5.0), reachability is now the
  main thing the index is for, so it cannot be allowed to become the bloat it prevents.

  Past `--max-rows` (default 40, roughly a screenful), the index lists that many surfaces
  individually and groups the remainder by directory with a count. What was collapsed is **stated**,
  never silently dropped: a truncated index that reads as complete is the failure mode, and the
  grouped tail still tells a reader where to look and what to do.

## [0.5.0]

### Changed

- **The adherence claim was measured and removed.** This plugin shipped asserting that a convention
  delivered when a matching file is read is followed more reliably than the same text buried in a
  large always-loaded file. `evals/adherence-experiment.sh` tested exactly that, and it did not
  reproduce: **32 trials, two bloat levels, 100% compliance in every cell.** Even a 1,927-line
  always-loaded file, nearly ten times the official 200-line guidance, produced no measurable
  difference against a path-scoped rule.

  The claim is removed from the README and from the audit skill's framing rather than hedged; an
  unmeasured claim that measurement contradicts does not get to survive as a caveat. The plugin's
  justification now rests only on what is demonstrable: context economy, the promote lane (content
  Claude loads *never* has no presence to lose), and index reachability.

  The run's limits are stated as plainly as its result in
  [`evals/adherence-results.md`](evals/adherence-results.md). The control arm scored 100%, so the
  experiment had a ceiling and could not have detected a smaller effect. Untested: conventions that
  conflict with a strong default or with each other, many rivalrous conventions at once, weaker
  models, and instruction shapes subtler than a crisp checkable rule.

### Added

- **`evals/adherence-experiment.sh`**: the harness, kept so the result can be re-derived rather
  than trusted. Interleaves arms so service drift hits both alike, defines compliance before any
  trial runs, and takes `--filler` to vary bloat. It is built to be able to fail, and did.

## [0.4.1]

### Fixed

Hint precision, measured by running `detect.sh` over a real 1,137-file corpus rather than over
fixtures. Both over-firings were invisible at fixture scale and obvious at repository scale.

- **Directory names were being reported as file extensions.** `.claude` was the single most common
  "extension" in the corpus at 840 hits, with `.work`, `.github`, `.git`, and `.local` close behind.
  Three rules now apply: a token followed by `/` is a directory component, a known config dotdir or
  dotfile is never an extension, and an extension must be lowercase, which also drops `.NET` and
  `.DS_Store` without listing either.
- **Language hints matched ordinary English.** Lowercase `go` produced 338 false hits from the verb,
  and `shell`/`bash` produced 675 more from prose about shells. The table is now case-sensitive and
  split in two: spellings that are never ordinary English (`TypeScript`, `PowerShell`, `C#`) match in
  any case, while names that collide with common words (`Go`, `Rust`, `Swift`, `Java`) match only in
  their conventional capitalized form.

Net effect on the same corpus: 9,528 hints → 7,217, with the removed entries being false positives
and the genuine signal intact (`Go` mentions fell 338 → 33). Also confirms the detector handles
repository scale: 1,137 files and 11,084 sections in 11 seconds, with clean stderr.

## [0.4.0]

### Added

- **`scripts/verify-load.sh`: empirical load verification (16 tests, including a live one).** Every
  other check in this plugin is static: the glob parses, it matches tracked files, the index is in
  sync. None of them observes Claude Code actually loading anything, and that gap is precisely
  where this plugin's own four bugs lived. A rule can pass every static gate and still never enter
  context.

  It runs the real CLI with an `InstructionsLoaded` hook attached, reads a file the surface claims
  to cover, and reports which instruction files actually loaded and why. The repository under test
  is never modified: the hook lives in a temporary `--settings` file, the probe is read-only and
  confined to `--allowedTools Read`, and the log is written outside the tree.

  It is honest about not knowing. Absent CLI, missing `jq`, a timeout, or a hook that produced no
  records all report `VERDICT UNKNOWN` and exit 3, never a pass. A verification tool that reports
  success because it could not measure is worse than no tool.

  Its own suite drives the real CLI, and asserts **both directions**: reading a `.cs` file loads the
  C# rule and the imported root surface, and does *not* load the TypeScript rule. The negative case
  is what actually demonstrates that path scoping defers rather than assuming it.

  Wired as an escalation in `check` (for "why is my rule not firing despite a green gate") and as an
  optional post-apply step in `realign` (worth it on the first move of a migration, not on every
  finding, since it costs a model call).

## [0.3.0]

### Added

- **`scripts/detect.sh`: deterministic fact emitter for the audit (38 tests).** The judgment layer
  decides *where* content belongs; it should not also be enumerating the corpus, finding section
  boundaries, or counting normative markers by reading. Emits `FILE` / `SECTION` / `SIGNAL` / `HINT`
  / `RULE` / `SKIP` / `SUMMARY` records as sorted TSV and adjudicates nothing.

  Two consequences make this more than tidiness. **`realign` excises by the line range the finding
  carries**, so a range that came from a model reading a file is a guess about which text gets
  deleted from someone's instruction file; now it is a fact. And two audit runs over an unchanged
  repository now produce the same candidate set, which no amount of careful reading guarantees.

  `HINT` records are raw material for glob derivation, deliberately not decisions: literal `ext` and
  `dir` tokens found in the prose, plus `lang` hints from a small documented language→extension
  table. The skill derives a glob from them and still has to validate it.

### Fixed

- **`detect.sh` regex portability, caught before release.** The first implementation used an
  interval expression (`{0,7}`) in a hint pattern; mawk 1.3.4 does not merely mismatch it, it
  panics, and with stderr suppressed the script emitted an empty fact set, which reads exactly like
  "this file has no sections". Rewritten without intervals, stderr is no longer suppressed, and the
  suite asserts both that no panic reaches the output and that a headed file yields a non-zero
  section count.

## [0.2.0]

### Fixed

Four discovery-layer bugs, all found by probing 0.1.0 rather than by its own test suite. The suite
covered glob *semantics* exhaustively and file *discovery* barely. Every bug lived in one
open-coded `find .claude/rules` line, which is why discovery is now a shared `lib/discover.sh` with
its own fixtures and 24 tests of its own.

- **Nested `.claude/rules/` trees were invisible.** Only the root tree was scanned, so a monorepo's
  per-package rules passed `check` while being entirely unverified, and never reached the index.
- **Symlinked rules were invisible.** `find -type f` never matches a symlinked file and does not
  traverse a symlinked directory. Since symlinking is the *documented* way to share one rule set
  across projects, a team using it got zero coverage and zero index entries, silently.
- **Untracked and gitignored files were indexed.** `corpus.md` promises neither is swept, but both
  reached the generated index, including vendored third-party `AGENTS.md` files, which put someone
  else's instructions into the consuming repository's always-loaded surface.
- **The index could be written where Claude Code never reads it.** Claude Code reads `CLAUDE.md`,
  not `AGENTS.md`. A repository carrying both with no import between them got a correct, in-sync
  index that never entered context, the entire subagent-gap mitigation inert while every gate
  reported green.

### Added

- **`render-index.sh reachable`**: answers whether Claude Code would load a given index target at
  all, by walking the import graph from each root memory file (depth-bounded at the documented four
  hops, skipping fenced blocks and inline code spans, and honoring the `CLAUDE.md`-symlinked-to-
  `AGENTS.md` form). `write` now warns on stderr when it writes into an unreachable target rather
  than leaving it for a later gate, and the `check` skill gates on it. Sync and reachability are
  independent questions and a repository can pass one while failing the other.
- **`lib/discover.sh`**: the shared discovery layer, with the two asymmetries documented in
  `corpus.md`: rules follow symlinks and do not require tracked status; nested instruction files
  require tracked status and skip vendored trees.

### Changed

- **Two previously-inferred claims are now measured** on 2.1.238 and recorded in
  `verified-mechanics.md`: an undocumented `description:` key in rule frontmatter is harmless, and
  block-level HTML comments are stripped from an `AGENTS.md` reached by `@import`, which is what
  makes the index markers genuinely free.

## [0.1.0]

### Added

- **`audit`: read-only placement sweep.** Two lanes over a two-tier corpus: **demote** (content in
  an always-loaded `CLAUDE.md`/`AGENTS.md` or an unscoped rule whose real scope is one file kind or
  one subtree) and **promote** (normative conventions stranded in ordinary markdown that Claude
  loads never). Candidates are classified against a decision ladder, every path-scoped proposal
  carries a machine-validated `paths:` glob, and every proposal is priced with its cost as well as
  its saving. Emits a diffable findings artifact under a project-keyed plugin-data path; mutates
  nothing in the repository.

- **`realign`: per-item human-gated apply.** Consumes the audit's artifact and never re-judges the
  surface. Five recipes (path-scoped rule, nested `AGENTS.md` plus shim, promote-by-move or
  promote-by-pointer, re-scope in place, delete) each create before excising, so an interruption
  leaves content duplicated rather than deleted. Every accepted move regenerates the always-loaded
  index. No blanket-approve path exists, including on request.

- **`check`: deterministic gate.** Verifies every `.claude/rules/` glob still resolves and that the
  index matches the rules on disk. Read-only, CI-shaped, and deliberately blind to the findings
  artifact so a stale audit can never make a broken repository look healthy.

- **`scripts/glob-tools.sh`: glob validation engine (45 tests).** Validates `paths:` globs against
  the repository's tracked files: zero-match, malformed bracket expression, and the documented
  1,000-pattern / 4 MiB brace-expansion budget are all hard failures, over-broad is a warning. Brace
  expansion is hand-rolled rather than delegated to shell `eval`, because the input is repository
  content and a crafted rule file must not be able to run commands, covered by a test asserting
  exactly that.

- **`scripts/render-index.sh`: always-loaded index generator (47 tests).** Renders, checks, and
  writes a marked block listing every instruction surface that loads on demand. Indexes only
  surfaces that defer: an unscoped rule already loads every session, so indexing it would spend
  always-loaded budget restating what is already present. Delimited by HTML comments, which Claude
  Code strips from memory files before injection, so the markers cost no context.

- **First-party loading measurements on Claude Code 2.1.238**, recorded in
  `context/verified-mechanics.md` with the `InstructionsLoaded` payloads they came from. Four
  findings shape the design: an `@import` inside a *nested* `CLAUDE.md` defers with its parent
  (unlike one inside a path-scoped rule, which does not); a nested `AGENTS.md` with no `CLAUDE.md`
  shim is never loaded; a subagent sees only the root instruction pair, inheriting none of its
  parent's on-demand loads; and the index is therefore the only mechanism that reaches a subagent.

- **Hard-deny classes.** Irreversible actions, secret handling, data integrity, external
  publication, legal and compliance obligations, and bounds on the agent's own authority are
  excluded from the candidate set entirely rather than surfaced as risky options. `audit` reports
  what it held back; `realign` has no code path that can apply one. Two further structural denies
  come from the mechanics rather than from consequence: creation-governing content cannot use a
  path-scoped destination (the trigger is a read), and a candidate whose body is only an `@import`
  is never routed to one (the import inlines at session start and defeats the scoping).
