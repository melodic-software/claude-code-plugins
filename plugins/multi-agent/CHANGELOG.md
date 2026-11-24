# Changelog

All notable changes to the `multi-agent` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [5.1.0] - 2026-11-24

### Changed

- While trials run, `/multi-agent:route vendors` tries the first model each vendor's `external-agents models` lists, at that model's default effort, instead of the model and effort a benchmark board leads with, and fetches no support-only or provider-own board.

### Fixed

- `vendor-state record` no longer fails on Windows when a concurrent record holds a file open in the trial folder it is removing; the rename is retried briefly.

## [5.0.0] - 2026-11-24

### Changed

- `/multi-agent:route vendors` fetches, and dispatches a board reader for, only registry rows that can lead (`status` not `support-only`, `provider_own` false). Support-only and provider-own rows are still fetched while trials are active, because their records seed trial candidates. A skipped row is listed in the decision's sources as `not-read` with its link. Registry rechecks (`/multi-agent:audit-defaults registry`) are unchanged.

### Removed

- **Breaking:** `vendors.tiebreak` is gone from `multi-agent.schema.json`, so a config that sets it fails validation; delete the key. `resolve-roles.sh` now ignores it as an unknown key, `/multi-agent:setup apply` no longer writes it, and `vendor-decide` no longer takes `--tiebreak` or `--usage`. A consensus tie now always resolves as it did with no tiebreak set: the work stays on Claude unless exactly one non-Claude vendor remains eligible. `/multi-agent:route vendors` no longer reads plan usage (`external-agents usage`, the `rate-limits` status tool).

## [4.0.0] - 2026-11-24

### Removed

- **Breaking:** `vendors.promotion_audits` and `vendors.promotion_days` are gone from `multi-agent.schema.json`, so a config that sets either fails validation; delete both keys. `resolve-roles.sh` now ignores them as unknown keys.
- `/multi-agent:audit-defaults registry` no longer records per-machine audit history or proposes promoting a `support-only` row to `permanent`: `skills/audit-defaults/scripts/registry-history.mjs` is deleted, and the registry judge no longer returns `error_range` or `tests_required_vendors`. A row leads only with an error range and consensus needs two clusters, so with today's rows a promotion could never change a routing decision. Demotion is unchanged.
- `reference/vendor-routing-audit.md` is deleted; nothing referenced it.

## [3.8.2] - 2026-11-24

### Fixed

- `/multi-agent:route vendors` no longer loses board-reader records to a display name: the
  VerdictRecord schema and the `board-reader` rules now require `model` to be a current model id
  copied verbatim and `version` and `effort` to be id tokens or null, the shape `vendor-decide`
  already accepts. Before, a reader wrote names such as `GPT-6.2 Astra` into `version` and the
  decider dropped the record.
- `fetch-boards` no longer dates a page from a model snapshot suffix such as
  `Qwen Image 2.0 Pro (2026-04-22)` or a model id such as `gpt-5.4-mini-2026-03-17`.
- The `vals-vibe-code` registry row also counts for `coding`: the board scores agents building
  complete applications with file-editing and shell tools.

## [3.8.1] - 2026-11-24

### Fixed

- `vendor-state record` no longer fails with `ENOTEMPTY` when a concurrent record writes a trial into the key's trial folder while it is being removed. The folder is renamed to a unique name before removal, so the removal never walks a path a writer opens.

## [3.8.0] - 2026-11-24

### Added

- `/multi-agent:audit-defaults registry` proposes promoting a shipped `support-only` benchmark row to `permanent` once it has passed every check (page read live, dated within 6 months, an error range stated, current models tested from every vendor its work types need) in at least 3 audits spanning at least 30 days, listing the audit dates as evidence. The promotion ships only through the existing reviewed apply step.
- The registry judge returns closed `error_range` and `tests_required_vendors` fields (`yes`, `no` or `unclear`). Promotion reads `tests_required_vendors`. Demotion still reads only `tests_current_models`, so a row that tests current models from only some vendors is not demoted.
- Each completed registry audit records its per-row check outcomes in this machine's plugin data directory (`registry-history/`) through `skills/audit-defaults/scripts/registry-history.mjs`, keeping only the records the promotion window needs plus a margin.
- New settings `vendors.promotion_audits` (default 3) and `vendors.promotion_days` (default 30), resolved through the usual config layers.

## [3.7.0] - 2026-11-24

### Added

- Nine `support-only` rows in `reference/benchmarks.json`, so every work type has candidate sources for a consensus once they pass longevity, accuracy and coverage: `vals-terminal-bench` and `arena-agent-code` (coding), `vals-vibe-code` and `designarena-code` (web-ui), `vals-finance-agent` and `arena-agent-work` (knowledge), `arena-text-to-image` and `designarena-image` (image), and `aa-intelligence-index` (coding, knowledge). `www.designarena.ai` joins the `registry-fetcher` gate and `workflows/registry-audit.js`.

### Changed

- The vendor-routing audit names the failing-test skill `/testing:fix-failing`.

### Fixed

- `/multi-agent:route vendors` counts a board record that names a model without the effort
  suffix the vendor's current ids carry (a base name such as `gemini-4-neon` for
  `gemini-4-neon-high`), canonicalized to `<model>-<record effort>` when that id exists, else to
  the first such id the vendor lists; it no longer abstains for that vendor. A version or other
  non-effort suffix still abstains.
- Route's board fetch (`fetch-boards`) passes each registry row's `expect` marker and
  `--render-fallback`, so a blocked or script-drawn board page renders through the Firecrawl CLI
  when the docs-cache `renderer` is `firecrawl`, and a page without its marker is unread.

- `vendor-decide` takes `--use <investigate|task>` (default `task`). With `investigate`, the
  `--needs-tools` gate checks the vendor's `read_only_tools` from `external-agents models`,
  falling back to `tools` when the entry has none, so a read-only brief no longer routes to a
  vendor whose read-only mode refuses a tool it needs. The route skill passes the brief's use, and
  a research or fact-check brief names `web` in `--needs-tools`.

## [3.6.5] - 2026-11-24

### Changed

- The vendor-routing audit names the lyric revision skill `/songwriting:revise`.

- Skill bodies mark each mention of another plugin's skill "(if enabled)", so a profile that switches that plugin off leaves no dead reference.

## [3.6.4] - 2026-11-24

### Fixed

- let route's `delegate` script accept the `~/` user-file path the route skill passes

  `delegate` refused `--user-file '~/.config/multi-agent/role-map.yaml'` as not absolute, so
  every auto-delegated brief failed. It now expands a leading `~/` to `HOME`, as the resolver does.

## [3.6.3] - 2026-11-24

### Fixed

- keep every registry and docs fetch under the 30,000 characters of Bash output Claude Code reads back

  `docs-raw.sh` returns a section map for a page over 28,000 bytes and caps every body there, and
  registry-audit reads sections in calls under that cap. A fetch Claude Code saved to a file is
  reported as `output-over-readback-limit`, not as a missing header.

- read script-drawn and bot-blocked benchmark boards

  The registry fetcher may pass `--render`: `docs-raw.sh` checks the row's `expect` marker and,
  with the docs-cache `renderer` set to `firecrawl`, renders the page through the Firecrawl CLI.
  The Terminal-Bench row now points at the site root, where its current leaderboard moved.

- demote a benchmark row only on definitive evidence

  A registry recheck proposes a status change for an unread page only when the host reports it
  gone (404 or 410). Every other unread reason (a missing expect marker, a block, a rate limit,
  a moved page, a failed fetch) leaves the row partial with the fix to try and no proposal, so a
  page-format change or a transient fault never demotes a board.

## [3.6.2] - 2026-11-23

### Changed

- add a `## Related` section to audit-defaults and route, matching the committed skill-link table

  Each now lists its context-dependent links after `## Next`, one condition
  per line.

## [3.6.1] - 2026-11-23

### Added

- Eval case `evals/ro-vendor-caller-auto-delegation-off/`: a Caller contract request with `vendors.auto_delegation` off makes `/multi-agent:route vendors` stop after `route.sh` and return only `run here`, with no board fetch, no `vendor-decide`, no `delegate` run and no vendor recommendation.

### Fixed

- carry a named agent's definition into a delegated brief

  The route caller contract now has a step that dispatches a named agent
  open its delegated brief with that agent's definition body, so another
  vendor gets the agent's instructions and report shape.

## [3.6.0] - 2026-11-23

### Added

- A Caller contract section in `reference/vendors.md` for skill steps that ask `/multi-agent:route vendors` which vendor runs a task: with `vendors.auto_delegation` off, route returns only `run here` and the step runs as before with no extra output; with it on and a vendor other than Claude chosen, the step sends its task text through route's `delegate` script and Claude reviews the report (and, for `task`, the changed files), which replaces the subagent's; text the user or caller did not write is framed as data; a skill asks route once per run per work type and passes route's `delegate:` line back with each later task; each call site carries one seam-phrased sentence.
- `skills/route/scripts/delegate --use investigate` runs `external-agents run <product> --use investigate --mode read-only`; `--use task` (the default) keeps `--use task --mode write`. Every other external-agents flag is still refused.
- `/multi-agent:route vendors` step 12 delegates `coding`, `web-ui` and `knowledge` work: with auto-delegation on and a non-Claude vendor chosen it prints one `delegate:` line naming the product, `--use` and any non-default model and effort, and runs a caller's brief through `delegate`. With auto-delegation off its output is unchanged.

### Changed

- Shared `html2md.py` and `suppression-scan.py` synced where this plugin carries them: comments removed, no behavior change.

## [3.5.0] - 2026-11-23

### Added

- Harness gating in `vendor-decide` (`--needs-tools <list>`, `--context <tokens>`) and `scripts/lib/gating.mjs`: skips harnesses lacking a needed tool, models whose `context_window` is below `--context` (keeping Claude when its window is unknown), and vendors with `breaker.open: true` (naming `reset_at`), each with one note.
- Usage tiebreak in `vendor-decide` (`--usage <file>`): `most-usage-left` compares per-vendor `UsageReading.remaining` and falls back to `vendor-order` with one note when any tied vendor's reading is missing or `unavailable`.
- Eval cases `evals/ro-vendor-image-recommend/` (image recommendation with `auto_delegation: false`) and `evals/ro-vendor-unavailable-line/` (one-line notice for an unavailable `in_use` vendor).
- Benchmark registry recheck agents `agents/registry-fetcher.md` (Bash-only, gated by a second `PreToolUse` `Bash` entry in `hooks/hooks.json` to the exact host list of `reference/benchmarks.json` with `onFailure: "block"`) and `agents/registry-judge.md` (TodoWrite only, closed JSON verdict, never quotes page text).
- Three `support-only` rows in `reference/benchmarks.json`: `vals-index` (coding, knowledge), `gdpval-aa` (knowledge) and `aa-image-t2i` (image), with `www.vals.ai` and `artificialanalysis.ai` added to the `registry-fetcher` gate and `workflows/registry-audit.js`.
- `workflows/registry-audit.js` and `skills/audit-defaults/scripts/list-registry.mjs` (plus tests `hooks/registry-fetcher-gate.test.mjs`, `tests/registry-audit.test.mjs`, and `skills/audit-defaults/scripts/list-registry.test.mjs` with `.test.sh` wrappers) for read-only benchmark registry rechecks across shipped and team rows.

### Changed

- `/multi-agent:route vendors` now grants `external-agents usage:*` and the bundled `scripts/delegate` (the only route to `external-agents run`: it refuses unless `vendors.auto_delegation` resolves `true` from a user layer file outside any git work tree, takes a product with `--model` and `--effort` only, and always runs `--use task --mode write` on a prompt it reads from stdin), passes harness facts (`tools`, `image`, `breaker`, `context_window`) into `--models`, queries plan usage only when `vendors.tiebreak` names `most-usage-left` (`external-agents usage` per in-use vendor plus `mcp__rate-limits__status` when enabled), handles `image` auto-delegation with task-only prompts naming the vendor's built-in image tool, reviews generated images with `Read` before `vendor-state record`, and recommends nothing (`basis: user-choice`) when every image-capable vendor has failed its trial.
- `resolve-roles.sh` reads `vendors.auto_delegation` from the user layer only and ignores it, with a note, in the team and personal-override layers, so no file inside a repository can turn on external-agent runs.
- `reference/vendors.md` and `reference/config.md` document harness gating, breaker skipping, usage tiebreak fallback, image auto-delegation, and Claude's live model-overview context-window pointer.
- `/multi-agent:audit-defaults` gains read-only `registry` mode (always runnable manually regardless of `vendors.*` switches) with an explicit opt-in apply step that writes the proposed `reference/benchmarks.json` diff in a worktree and opens a PR through `/source-control:pull-request create` in `melodic-software/claude-code-plugins` only; `allowed-tools-pairing.test.sh` and `README.md` are updated for `Workflow(multi-agent:registry-audit)` and the `registry-fetcher` gate.

## [3.4.1] - 2026-11-23

### Added

- **Vendor routing audit.** New `reference/vendor-routing-audit.md` lists the skill steps that delegate a whole task, each with its work type and whether it could take its vendor from `/multi-agent:route vendors` (keep or route, with the reason). Each row cites the `file:line` that shows its delegating step.

## [3.4.0] - 2026-11-23

### Added

- Trust-model vendor routing core for `/multi-agent:route vendors`: closed JSON Schemas (`benchmark-registry.schema.json`, `verdict-record.schema.json`), pointer-only `reference/benchmarks.json`, `fetch-boards` wrapper over `scripts/fetch-docs.sh`, Read-only `board-reader` agent, and `vendor-decide` script with command-line tests.
- Vendor routing eval cases `ro-vendor-cites-sources` and `ro-vendor-unread-page-abstains` on fixture pages, plus fixture-page staging for `ro-vendor-everyday-default` and `ro-vendor-heavy-above-default`.
- `vendors` configuration block in `schemas/multi-agent.schema.json` and shipped switch defaults in `reference/defaults.yaml` (`routing: true`, `trials: false`, `auto_delegation: false`, plus `tiebreak`, `trials_prove`, `trials_fail`, per-vendor `in_use`/`rank`, and `sources.<id>.enabled`).
- Team benchmark rows support in `fetch-boards` and `vendor-decide` via `<repo>/docs/conventions/multi-agent/benchmarks.json` (appended after shipped rows; duplicate shipped ids refused with a note).
- Trial state script `skills/route/scripts/vendor-state` (`record`, `outcome`, `send-back`, `seen`) with `O_EXCL` outcome creation, per-machine data-folder resolution, machine-neutral outcomes keyed by `vendor:model:version:effort:work_type`, and command-line tests in `vendor-state.test.mjs`.
- Eval case `evals/ro-vendor-routing-off/` covering `vendors.routing: false` in the team layer.

### Changed

- `/multi-agent:route vendors` now fetches enabled registry pages through `fetch-boards`, dispatches `board-reader` per read page, decides via `vendor-decide` with `--settings` from the resolved `vendors` object, cites every source with its read state, carries the untrusted-content framing inline, names each tool's own skill for MCP-vs-CLI decisions, grants `vendor-state`, runs `vendor-state seen` to relay `registry recheck due` on new model ids, records reviewed `trial` verdicts with `vendor-state record`, and reports rejected `proven` results without re-entering trial automatically.
- `scripts/resolve-roles.sh` and `skills/setup/scripts/setup.sh` validate `vendors.*` across layers (rejecting `trials_fail: 1` and unknown tiebreak steps) and emit the resolved `vendors` object with per-key source layers.
- `vendor-decide` accepts `--state-dir` (defaulting to the plugin data-folder rule), routes proven pairs with basis `proven`, excludes failed pairs, routes active trials with basis `trial`, writes nothing on routine runs, and honors `--settings` for routing-off decisions, silent `in_use: false` skipping, one-line unavailable notes for `in_use: true`, ordered `tiebreak` steps and vendor ranks, per-source enable overrides, and inactive-trials notices when counts are unset.
- `reference/vendors.md` now states the trust model and points to `reference/benchmarks.json`, with the dated checked column and model names removed; `reference/config.md` and `README.md` document the `vendors` keys, layers, team rows file, trial state location, and `send-back` command.

- Synced shared `fetch-docs.sh` and `docs-cache.sh` with opt-in generic-profile `--expect` and `--render-fallback` support behind the `renderer` master setting (default `none`), and declared `firecrawl` as an optional CLI prerequisite.

### Fixed

- `vendor-decide` now reads Claude's base model and effort from `roles.worker.single` in `route.sh` `--settings` output (falling back to `--models` defaults and bundled `defaults.yaml` only when absent) before applying the heavy-task effort raise.
- `vendor-decide` enforces the default-effort floor on `coding` consensus and trial recommendations, raising any effort below the selected model's default to that default with one note.
- `vendor-decide` no longer copies `board-reader` `findings` strings into `Decision.notes` (emitting one fixed non-relayed note per flagged source instead); `agents/board-reader.md` restricts `findings` to reader-authored labels and `skills/route/SKILL.md` relays only that fixed note.
- `vendor-decide` drops records whose `model`, `version`, or `effort` fails `^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$` with one note naming source and field (never the value), constrains decision `effort` to the vendor/model's listed efforts in `--models` (falling back to the model/vendor default), and sources `version` exclusively from `--models` (never from page records, falling back to `null`).

## [3.3.1] - 2026-11-23

### Changed

- `scripts/check-hook-registration.sh` now runs the shared hook registration check (`lib/hook-registration-check.sh`, generated from the repository's `lib/`); its rows, wording and exit codes are unchanged.

## [3.3.0] - 2026-11-22

### Added

- `/multi-agent:route vendors <task>` picks the vendor (Claude, Codex or Gemini), model and effort for one delegated task: each vendor's default for everyday work, one effort step up with a named basis for a heavy whole-task delegation. Codex and Gemini facts come only from `external-agents models <product>`; without external-agents it covers Claude. The rules and the checked benchmark sources live in `reference/vendors.md`.

## [3.2.0] - 2026-11-22

### Added

- A `role_map_file` option (type `file`) names your own role map file, the user layer of the config cascade. `/multi-agent:route` and `/multi-agent:setup` pass it to the resolver, and `/multi-agent:setup apply --layer user` writes to it. A leading `~/` expands against your home; any other path that is not absolute is refused by `setup` and skipped with a note by the resolver ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).
- `/multi-agent:setup apply --migrate` moves each old file into its new location after a preview and a yes: `~/.claude/multi-agent.yaml` into the `role_map_file` file, `.claude/multi-agent.local.yaml` into `<home>/multi-agent.local.yaml`, and a retired `.claude/multi-agent.yaml` into the team YAML. A key the new file already sets keeps its value and is named. The command reads the new file back and checks the layers still resolve the same values before it deletes the old file ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).

### Changed

- The personal override is now `<home>/multi-agent.local.yaml`, and `setup check` recommends the `<home>/**/*.local.*` ignore line. An old `~/.claude/multi-agent.yaml` or `.claude/multi-agent.local.yaml` is still read while its new file is absent. Each run names each old file in `notes`, with its new location and the migrate command. `setup apply --layer user` and `--layer local` refuse while that layer's old file exists ([#17998](https://github.com/melodic-software/claude-code-plugins/issues/17998)).

## [3.1.6] - 2026-11-21

### Changed

- Carries a generated copy of the config-cascade contract's config locations page at `reference/config-locations.md`, the one list of where plugin config lives.

## [3.1.5] - 2026-11-21

### Changed

- the shared prerequisites checker gains a latest-release mode

## [3.1.4] - 2026-11-19

### Changed

- `reference/config.md` no longer paraphrases Claude Code's effort precedence, `maxEffortLevel` behavior or alias resolution; its "Where effort applies" and "Hard cap" sections state what the resolver does and point at the docs sections.

## [3.1.3] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [3.1.2] - 2026-11-17

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

## [3.1.1] - 2026-11-16

### Changed

- The worker, verifier and retrieval defaults are rechecked against `CLAUDE_CODE_SUBAGENT_EFFORT` and the Opus 5.5 end-of-turn completion check, with no value changed. Their recheck conditions now fire when the docs say where that variable ranks, and the verifier's model reason records why a smaller completion-check model is not a verifier.

## [3.1.0] - 2026-11-16

### Added

- The fan-out guard section now asks for one pilot worker and a check that plan usage remains before a fan-out wider than about four workers, since a usage limit reached mid-fan-out stops every worker at once.

## [3.0.7] - 2026-11-16

### Changed

- The bundled prerequisites stubs' node notice names the plugin whose hook printed it, and names a check skill of another plugin with the condition that that plugin is enabled.

## [3.0.6] - 2026-11-15

### Changed

- The config reference points at the upstream pages for subagent `model` values and the effort
  cap's scopes instead of restating them. Skill headings and the drift-audit skeptic prompt use
  plain emphasis instead of capital letters.
- The `su-apply-guard-off-confirms` eval no longer expects a local-layer offer, which its own
  description says cannot arise at a home root.

## [3.0.5] - 2026-11-15

### Changed

- The worker role's mechanical-model reason records a third fix-docs measurement, in which Sonnet 5.5 passed the meaning-change case after the ai-slop fix guidance changed, and its recheck condition names any audit-fix case that fails a majority of its runs.

## [3.0.4] - 2026-11-15

### Changed

- The worker role's mechanical-model reason now says the fix-docs measurement's cases did not check whether a fix changed a sentence's meaning, and records a six-case Sonnet 5.5 and Opus 5.5 measurement that left the default on Sonnet.

## [3.0.3] - 2026-11-15

### Changed

- The mechanical worker default's measurement note in `reference/defaults.yaml` states its
  limits: five cases, no Opus arm run, and no claim about how the two models compare.

## [3.0.2] - 2026-11-15

### Changed

- The mechanical worker default's reason in `reference/defaults.yaml` records a measurement:
  Sonnet 5.5 passed every run of the `ai-slop` `audit-fix-*` eval cases, so the default stays on
  Sonnet. No default changes.

## [3.0.1] - 2026-11-14

### Changed

- The verification level reader now reads the team file through the shared default-branch reader, `lib/default-branch-file.sh`, which this plugin now carries; levels and messages are unchanged.

### Fixed

- `route`'s argument hint marks the role as a placeholder, `<<role>|all>`, so `all` is the only literal choice and the generated skill cheat sheet lists only `all` as its action.

## [3.0.0] - 2026-11-13

### Changed

- **Breaking:** `/multi-agent:audit-defaults` now reads the `verification` level (`lib/read-verification.sh`, team file `<home>/multi-agent.yaml` at the default branch) and passes it to the `drift-audit` workflow. At the default `light`, and at `off`, the workflow dispatches no skeptic, reports every finding `unverified`, and proposes no diff. Set `verification: standard` to restore the skeptic panel.
- `scripts/resolve-roles.sh` passes over the `verification` keys in every layer, and `/multi-agent:setup apply` writes them to the team layer only.

## [2.1.5] - 2026-11-13

### Changed

- The vendored prerequisites checker's usage and schema errors give `EXAMPLE_ENABLED` as the sample option name, one that names no plugin.

## [2.1.4] - 2026-11-12

### Changed

- The orchestrator default's recheck trigger now includes a change to the Projects page's coordinator default.

## [2.1.3] - 2026-11-12

### Changed

- The orchestrator role's `reason_model` cites ADR 0100 (session model, Opus by default, Fable for long-horizon work).

## [2.1.2] - 2026-11-12

### Changed

- defaults: the worker, verifier and retrieval roles record the model-config section on subagent effort as `pointer_subagent_effort`, and their recheck triggers include a change to the default subagent effort setting. Role values are unchanged.
- routing-rubric: "Evidence so far" points at the cost page's orchestrator-strategy section for upstream evidence on Haiku subagents for coding. The rule is unchanged.

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [2.1.1] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [2.1.0] - 2026-11-11

### Changed

- `/multi-agent:audit-defaults repo` takes a pointer to the live source as conforming without an as-of date or recheck trigger; `copied-current` now means a restated upstream fact with no pointer, or a stored value (a recorded default, limit, version gate or price) with no as-of date and recheck trigger.

## [2.0.16] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [2.0.15] - 2026-11-11

### Changed

- The route skill points at Claude Code's model aliases section for why only aliases are accepted. No behavior change.

## [2.0.14] - 2026-11-10

### Changed

- Internal simplification, no behavior change.

## [2.0.13] - 2026-11-10

### Changed

- The routing rubric, README and `/multi-agent:route`'s haiku note state the owner's rule that no role routes to Haiku; a routing-eval pass is now the evidence for the owner to reopen it, not a gate that lifts it on its own.

## [2.0.12] - 2026-11-10

### Changed

- The retrieval role's effort now records an upstream basis in model-config's effort table, and the orchestrator's `high` effort, the worker's `mechanical` model and the retrieval model give the task table in Anthropic's model-choice guide as the context for their judgment. No resolved value changes.
- The routing rubric records the owner's decision that no role routes to Haiku, with the guide's Haiku rows as the disagreeing source.

## [2.0.11] - 2026-11-09

### Changed

- The routing rubric's model-change pointer is rechecked against the selection matrix that now lists Claude Fable 5.2; no routing changes.

## [2.0.10] - 2026-11-09

### Changed

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

- Simplified the internals of the docs fetcher script; its behavior is unchanged.

## [2.0.9] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

- Simplified `docs-cache.sh`: one routine now warns on a bad summary or note file, and the UTC formatter picks its format once. Outputs, exit codes and messages are unchanged.

## [2.0.8] - 2026-11-06

### Changed

- The assess, audit-defaults, route and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). New cases: `as-disabled-switch-downgrade` (a `disableWorkflows` project setting downgrades a workflow verdict to subagent, with the switch on the reason line and no suggestion to unset it), `as-race-best-one-no-rule` ("keep the best one" is not a selection rule, so the race waits for one), `ad-fanout-fallback-unread` (with no Workflow tool and no network, the fanout audit runs the main-thread fallback, marks both sources unread, proposes no change and never proposes turning the guard off), `ro-all-fable-args-roles` (under Fable the orchestrator, worker and verifier fan-out variants name opus and every inherit reads `inherit: omit the model option`), `ro-rejected-model-id-layer-below` (a full model id in the personal override is reported from the notes as rejected, with the layer below supplying the model), `ro-mechanical-workload-picked` (a table reformat is routed as the mechanical workload, sonnet for both variants, with the opt-out key named), `ro-all-sonnet-cap-note` (the JSON keeps its efforts, the hard-cap line follows the role lines, and no settings file is read), `ro-agent-dispatch-single-variant` (an Agent dispatch with no named type omits `model` and passes the single variant's effort) and `su-apply-team-preview-asks` (a team-layer apply previews without `--write`, names `docs/conventions/multi-agent.yaml` and asks for a yes). Existing cases gain graders: `as-forty-files-no-workflow-tool` (availability script run, item count on the reason line, no workflow, write or edit), `as-small-task-single` (size and dependency shape on the reason line), `ro-unknown-role-stops` (no layer file written), `setup-check-shows-role-map-and-ignore-gap` (`session=opus` passed, inherit wording) and `su-apply-guard-off-confirms` (pricing or costs page linked, no price figure, local layer offered). `ro-worker-mechanical-fable`'s worker line takes any basis word, since the resolver's basis for that worker now reads judgment. The full-audit and repo-mode launches stay out: an eval run has no Workflow tool and no network.

## [2.0.7] - 2026-11-05

### Added

- Eval case `setup-check-shows-role-map-and-ignore-gap` for `/multi-agent:setup check` ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)): grades the bundled setup.sh check run, the per-role single and fan-out lines, the recommended ignore line, and no write.

## [2.0.6] - 2026-11-04

### Changed

- Prose uses the vocabulary the planning chain settled on (scope, fallback chain, personal override, the Brief), and names the file or setting it means.

## [2.0.5] - 2026-11-04

### Fixed

- `fetch-docs.sh --profile generic`: a `text/plain` answer to a URL whose path ends in `.md` is
  read as markdown on the first request, so a host that serves `.md` files as `text/plain` no
  longer leaves the page unread `unexpected-content-type`
  ([#13354](https://github.com/melodic-software/claude-code-plugins/issues/13354)). A `text/plain`
  answer for any other path is still refused.

## [2.0.4] - 2026-11-04

### Changed

- The plugin now calls the config cascade's personal layer the personal override (the overlay name is retired); the layer id in `resolve-roles.sh` output and the `setup check` row changed from `overlay` to `personal-override` (#13191).

## [2.0.3] - 2026-11-04

### Changed

- Shared config-cascade library synced: comments now call the personal layer the personal override (#13187). No behavior or printed text changed.

### Fixed

- `reference/config.md`: a named agent that sets no `effort` runs at the session's level only on the
  main conversation's model.

## [2.0.2] - 2026-11-04

### Fixed

- The `check` line for a missing node no longer prints a literal `<plugin root>` in the registration probe command. It now says to run `bash scripts/check-hook-registration.sh` from the plugin root, the directory passed to `prerequisites.mjs check`, so the command runs as written.

## [2.0.1] - 2026-11-04

### Fixed

- Shared `fetch-docs.sh` synced where this plugin carries it ([#12945](https://github.com/melodic-software/claude-code-plugins/issues/12945)): with `--profile generic`, an x.com or twitter.com page that is X's logged-out shell (`redirect_after_login` links and no article text) is now `unread` with reason `login-wall` instead of `read`, whether fetched or served from the cache or a fixture, and is never cached; no other change to this plugin.

## [2.0.0] - 2026-11-03

### Removed

- The one-release reads of the old team locations, added in 0.13.0. `resolve-roles.sh`, and so `/multi-agent:route`, reads the team layer only from `docs/conventions/multi-agent.yaml` (under the convention home the repository binds), never from the config block in `docs/conventions/multi-agent.md` or from `.claude/multi-agent.yaml`. `/multi-agent:setup check` prints a `WARN team:` row for each old file it finds, with its next step. While the YAML is absent, the first `/multi-agent:setup apply --layer team` write still copies one old file's keys into it, the block's when there is one, and leaves that file in place. A repository that keeps its role map in an old file runs that write, then deletes the old file ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737)).

## [1.0.1] - 2026-11-03

### Changed

- The README no longer restates how Claude Code handles an undecided `PreToolUse` call or a failed hook with `onFailure: block`, or which release honors that key; it points at the hooks reference sections instead.

## [1.0.0] - 2026-11-03

### Removed

- `/multi-agent:check` is gone, with its probe file. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`, the command the hook notices already print. The fetch gate registration probe moved to `scripts/check-hook-registration.sh`, which runs after the checker.

## [0.14.10] - 2026-11-02

### Changed

- Hook notices name the bundled checker command; `check` is optional (#12485).

## [0.14.9] - 2026-11-02

### Changed

- The `SessionStart` node-notice row is gone (#6633): harness-ops' row reports a missing `node` for the whole fleet, once per session. Without harness-ops, no session-start notice says `node` is missing.
- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.

## [0.14.8] - 2026-11-02

### Changed

- the docs-fetcher gate loads less on every main-thread Bash call

  The `PreToolUse` `Bash` gate now loads `node:fs` and `node:crypto` only when it records the `multi-agent:docs-fetcher` agent's one allowed call. Every other Bash call, in the main thread and in other agents, skips them. On a WSL2 host this cut the gate's main-thread time from about 7.5 ms above a bare `node -e 0` to about 4 ms (3 rounds of 30 interleaved runs). What the gate allows and denies is unchanged.

## [0.14.7] - 2026-11-02

### Fixed

- leave release fragments out of the repo-mode sweep targets

  `/multi-agent:audit-defaults repo` now leaves `.changes/` release fragments out of its target list, as it already did changelogs, so a release no longer changes which files the sweep covers. The `multi-agent:drift-audit` workflow's repo-mode sources of record name the models overview at its current address, `models/overview`, which the platform docs index lists; the old `about-claude/models/overview` address was read as unread.

## [0.14.6] - 2026-10-31

### Fixed

- The fan-out guard's docs and `/multi-agent:route` say what the resolver emits instead of promising where an agent runs, and point at the upstream sections that decide it. The `mechanical` workload's `sonnet` default is recorded as this repository's judgment; the value is unchanged.

## [0.14.5] - 2026-10-31

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.

## [0.14.4] - 2026-10-30

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.14.3] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.14.2] - 2026-10-30

### Changed

- **Routing eval result.** The routing rubric's evidence now records the paired routing eval over the worker, retrieval and verifier cases. Haiku 5.5 at `high` matched each role's current default on accuracy, but used more tokens per completed task in every role, so every default in `defaults.yaml` stands. The advisor arm could not run under `claude plugin eval` ([#10022](https://github.com/melodic-software/claude-code-plugins/issues/10022), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).

## [0.14.1] - 2026-10-30

### Added

- **Routing eval: review cases.** Five cases under `evals/routing/review/` cover code review and verification with code from this repository. Three `rv-*` cases ask for the defect a diff introduces, a seeded defect beside a behavior-preserving decoy edit, in Bash, Python and JavaScript. Two `vf-*` cases ask whether each of four review findings is confirmed or refuted, two of them false. Every grader is a deterministic regex with must-pass and must-fail samples, so no judge model scores a run. Their README gives the arm configuration (model and effort level) for each setup the paired routing eval compares ([#10012](https://github.com/melodic-software/claude-code-plugins/issues/10012), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).

## [0.14.0] - 2026-10-30

### Changed

- The `drift-checker` fetch gate (`PreToolUse` `WebFetch`) and the `docs-fetcher` gate (`PreToolUse` `Bash`) set `"onFailure": "block"`, so on Claude Code 2.1.295 or later a gate that cannot start because `node` is missing, or that reaches its 10 s timeout, denies the call instead of letting it run unchecked ([#9982](https://github.com/melodic-software/claude-code-plugins/issues/9982)). Both rows match every call of their tool, so on such a host the main thread's `WebFetch` and `Bash` are denied too. An older client ignores the key.

## [0.13.5] - 2026-10-29

### Changed

- Synced the shared `yaml-subset.awk` parser, which now refuses what `yaml-subset.mjs` refuses: a key repeated in one mapping (before, only under `-v STRICT=1`), an unknown backslash escape in a double-quoted string, a nested flow sequence such as `a: [[1, 2]]`, a `%` directive line (before, skipped), and a sequence-item map whose later keys sit more than two columns past the dash. A config file holding one of these is now a parse error.

## [0.13.4] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

## [0.13.3] - 2026-10-25

### Added

- **Routing eval: retrieval cases.** Six `rt-*` cases under `evals/routing/retrieval/` ask codebase-retrieval questions (locate code, trace callers, where something happens) about a pinned snapshot of the `multi-agent` and `evals` plugins, each graded by deterministic regex graders with must-pass and must-fail samples. Their README gives the arm configuration (model and effort level) for each setup the paired routing eval compares ([#10009](https://github.com/melodic-software/claude-code-plugins/issues/10009)).

## [0.13.2] - 2026-10-25

### Added

- Three mechanical-edit cases for the model-routing eval under `evals/routing/mechanical-edit/`: a rename scoped to one file, a link repoint after a file move, and a table-to-list format change. Each case builds its workspace from `scaffold.sh` and is graded only by deterministic regexes over the workspace files. `arms.yaml` sets out the eight model and effort arms the cases run under ([#10017](https://github.com/melodic-software/claude-code-plugins/issues/10017), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).

## [0.13.1] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.13.0] - 2026-10-25

### Changed

- **The team layer is `docs/conventions/multi-agent.yaml`**, under the convention home the repository binds (`docs/conventions` when it binds none), validated by the new `schemas/multi-agent.schema.json`. `resolve-roles.sh` reads the old team locations, the `yaml config` block in `docs/conventions/multi-agent.md` and then `.claude/multi-agent.yaml`, only when the YAML is absent, for one release; when several exist it uses the first and names each one it ignored in `notes`. The `layers` rows and each role's `source` name the layer that supplied a value, as before.
- `/multi-agent:setup apply --layer team` writes the YAML. While the YAML is absent, the old team file the resolver still reads seeds its keys, and that file is left as it was. The skill no longer writes a `yaml config` block.
- The plugin ships `lib/resolve-convention-home.sh`, a generated copy of the shared helper.

## [0.12.1] - 2026-10-24

### Changed

- `/multi-agent:assess` points at the Claude Code subagent page's comparison of subagents and the main conversation for a close `subagent` or `single` call, with an as-of date and recheck trigger.

## [0.12.0] - 2026-10-22

### Changed

- **BREAKING:** the bundled YAML-subset reader (`yaml-subset.awk`) now refuses a flow mapping (`key: { a: 1 }`, `{}`, or a `{...}` item in a list) and a line opening with a `---` or `...` document marker, as the stricter `yaml-subset.mjs` grammar does. The error names the line and says to use block style; each caller adds the file. A `docs/conventions/*.yaml` file or `yaml config` block that used either one no longer parses, and its reader falls back to defaults until it is rewritten in block style, one key per line.

## [0.11.0] - 2026-10-20

### Added

- **A config layer declares its own workloads.** `workloads.<w>: true` in any layer declares workload `<w>`, so `roles.<role>.workloads.<w>.model` and `.effort` apply and `/multi-agent:route <role> <w>` resolves it; `false` withdraws one. The bundled layer declares `code`, `research` and `mechanical` the same way, in `reference/defaults.yaml`. A workload value for a name no layer declares is still reported and ignored, and an undeclared `--workload` exits 2 listing the declared ones.

### Changed

- `/multi-agent:route` takes the workload as its second bare argument, so a declared name passes through; `code`, `research` and `mechanical` work as before.

### Fixed

- `parse-concern-value.sh --strict` now exits 3 when a mapping repeats a key, as the CI config parser does; the shared awk YAML reader took the first value. Non-strict calls are unchanged.

- `best` is no longer a role model, a frontier alias or an accepted `--session-model`: the resolver rejects it as an unknown alias, and the bundled `frontier` default is `fable`. The config reference now points at sub-agents: choose a model for the subagent aliases and model fallback. (#7990)

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

## [0.10.1] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.10.0] - 2026-10-14

### Added

- Seven outcome eval cases (`as-`, `ro-`, `ad-`, `su-`) and frozen trigger-probe sets for `assess`, `audit-defaults`, `check` and `route`.

### Changed

- `assess` and `route` have shorter descriptions and bodies with the same rules, output templates and stop gates. `setup` has a one-line description and a shorter body. `audit-defaults` and `check` are unchanged.

## [0.9.0] - 2026-10-13

### Added

- **`/multi-agent:assess` names the run's shape.** A `workflow` or `subagent` verdict gains a third line, `shape: <sections|race (<selection rule>)|mixed>`. A race states its selection rule before any agent is spawned; one without a rule is reported, not run.
- **`/multi-agent:route` notes the effort cap.** The output ends with a line pointing at the new "Hard cap" section of `reference/config.md`, which documents `maxEffortLevel` and where role effort applies (workflow `agent()` calls, not Agent tool dispatches).

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.

- **The `mechanical` workload runs the worker on `sonnet` by default** (`roles.worker.workloads.mechanical.model: sonnet`); `code` and `research` keep the role's model. Opt out with `roles.worker.workloads.mechanical.model: inherit` in any layer.
- **`scripts/yaml-subset.awk` is now a generated copy of the repository's `lib/yaml-subset.awk`.** The parser also reads block and flow sequences, flow mappings, quoted keys, YAML quote escapes (`''`, `\"`, `\\`) and a document at a uniform base indent, so the shared concern reader can use it. Valid YAML inside the subset reads the same as before, except that an escape inside quotes now yields the character it stands for. Four non-standard forms the old parser read now make the layer a parse error, so it is skipped and named: a key indented between its parent and the block it closes (`planner:` at two spaces after `worker:` at four, both under `roles:`), text after a closing quote (`a: "x"y"`), an unclosed quote (`a: "x`), and a tag (`a: !true`). A sequence, which used to be an error, now flattens to indexed keys (`a.0`) that the resolver reports as unknown.

- The README, the `check` and `setup` skills, the drift-audit agents, `resolve-roles.sh` and the `assess` availability script point at the exact Claude Code docs sections for hook failure and timeouts, mod hook ordering, `disable-model-invocation`, subagent `maxTurns`, model aliases, effort levels and the workflow off switches, each with an as-of date and recheck trigger, instead of restating them.

- Every role default in `reference/defaults.yaml` now records a basis per value: `upstream`, naming the section and statement that set it (`pointer_<field>`, `claim_<field>`), or `judgment` with a `reason_<field>`. No model or effort value changed. Upstream: worker and verifier effort (model-config, choose an effort level), the worker's `mechanical` workload model (costs, choose the right model; recorded as `basis_mechanical_model`, the form every `workloads.<w>.<field>` value uses). Judgment: orchestrator model and effort, worker and verifier model, retrieval model and effort. The generic `pointer`, `pointer_cost` and `pointer_model_split` on the roles are gone; `pointer_skill` and `pointer_spawn` stay as mechanism pointers. (#6265)
- `/multi-agent:route` prints a `basis` (`upstream`, `judgment`, `config` or `unrecorded`) beside each role's model, fan-out model and effort; a guarded fan-out model takes the fan-out guard's basis.
- `/multi-agent:audit-defaults` reports `unsupported` when a cited section states neither the value nor a rule it follows from, proposing `basis_<field>: judgment` in the diff when the owner records an upstream basis for it, and lists judgment values with their reasons instead of checking them.

### Fixed

- **`/multi-agent:audit-defaults` no longer tells the caller to pass `defaults` to `list-pointers.sh`.** The script reads that word as an owner and exits 2. Step 3 now says to pass only a role or `fanout`, or nothing.
- **The `fanout` and `worker` defaults are rechecked as of 2026-10-10.** The cost page still recommends Opus 5.5 at medium effort, so no model or effort value changes. The two recheck triggers now say "a new model named on the cost page", because that page has no model table.

- **The shared `yaml-subset.awk` parser trims trailing blanks and strips trailing comments (a `#` after a space) in one pass**, where two regexes rescanned a long run of spaces from every start; a 200,000-space line now parses in well under a second with the same records.
- **`scripts/fetch-docs.sh` runs its address check and interpreter probe with `python -I`**, so a module planted in the working directory (an `ipaddress.py`, say) is never imported by the `--public-only` check.
- **The shared `yaml-subset.awk` refuses a tab indent and an unquoted colon followed by a space in a value (`key: a: b`).** Both parsed before although a YAML loader rejects them; a file holding either now reads as a parse error, so quote a value that holds a colon followed by a space. A tab in a markdown fence's base indent is still accepted.

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

## [0.8.0] - 2026-10-11

### Added

- `reference/routing-rubric.md` sets the rule for Haiku: no role routes to it until it passes the repository's routing eval ([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)), and a role that does runs at effort `high`, never `xhigh` or `max`. `/multi-agent:route` adds a note for any role that resolves to haiku, named or inherited from a Haiku session, and still resolves it.

### Changed

- config reference: the `effort` values row now points at the model-config section listing which levels each model supports.
- defaults: the worker, verifier and retrieval roles now record the Agent tool's per-spawn effort docs as `pointer_spawn`, and their recheck triggers include a change to that parameter. Role values are unchanged.

- The `retrieval` role's bundled effort is now `medium`, and the `research` workload no longer lowers the worker's effort, so research workers run at the worker's own `medium`.

## [0.7.0] - 2026-10-10

### Added

- **The drift-audit fetch and judging agents start without CLAUDE.md files.** `docs-fetcher` and `drift-checker` set `omitClaudeMd: true`, so a stage that reads untrusted pages opts out of the CLAUDE.md instruction hierarchy. The README records where the field is documented.

### Changed

- **`/multi-agent:route` says how to apply a role to an Agent tool dispatch.** Since Claude Code 2.1.292 the Agent tool takes an `effort` on each call, so the role map's effort now reaches subagents spawned without a named type, not only workflow `agent()` calls. The skill tells the caller to pass the variant's model (or omit it on `inherit`) and its effort on the call, and links the upstream sections that decide which source wins.

### Fixed

- **The routing skill no longer says a named agent always runs at its own pinned model and effort.** A dispatcher can pass `model` or `effort` on the call, so keeping a named agent off a frontier model is the dispatcher's rule. The route gotcha, the setup skill, and the README now say so.

## [0.6.5] - 2026-10-10

### Fixed

- The shared docs cache detects GNU `mv` from a here-string instead of `mv --version | grep -q GNU`. Under `pipefail` an early `grep -q` exit can break the pipe and fail the check, so a GNU `mv` was taken for a non-GNU one and directory renames took the check-and-undo fallback.

## [0.6.4] - 2026-10-08

### Fixed

- **`scripts/fetch-docs.sh` keeps a map lookup's value in the caller's own variable
  ([#6540](https://github.com/melodic-software/claude-code-plugins/issues/6540)).** Under
  `--public-only`, the address check during an origin's `llms.txt` fetch no longer overwrites the
  "no bundle" result, so an origin without `llms.txt` is never given a bundle channel.

- The `list-scripts` test suite passes on Git for Windows ([#6527](https://github.com/melodic-software/claude-code-plugins/issues/6527)): the quote-in-path case and the symlink case (`leaves out link.md`) are skipped there, since a Windows path cannot hold a quote and a plain `ln -s` copies the file. Both assertions are unchanged on Linux.

- **`scripts/docs-cache.sh slice` prints each line once, in page order
  ([#6501](https://github.com/melodic-software/claude-code-plugins/issues/6501)).** A slice that
  named a parent section and its child printed the child twice, because the parent's range already
  holds it; one measured request for 59193 unique bytes printed 75892. Overlapping and repeated ids
  now print their lines once, in the order they appear on the page.

## [0.6.3] - 2026-10-07

### Fixed

- **The shared docs lookup scripts run on Bash 3.2
  ([#6496](https://github.com/melodic-software/claude-code-plugins/issues/6496)).** `scripts/fetch-docs.sh`
  and `scripts/docs-cache.sh` no longer use `${x,,}`, `${x^^}`, `declare -A` or `printf '%(...)T'`,
  which stock macOS Bash 3.2 rejects, so a docs lookup there no longer exits with `bad substitution`.

## [0.6.2] - 2026-10-07

### Fixed

- The docs-fetcher gate's `CLAUDE_PLUGIN_DATA` citation points at
  `plugins/manifest-reference#environment-variables` in place of the retired `plugins-reference`
  page, re-verified 2026-10-07 ([#6523](https://github.com/melodic-software/claude-code-plugins/issues/6523)).

## [0.6.1] - 2026-10-07

### Security

- The docs-fetcher gate keeps its once-per-run markers in the plugin data directory instead of a
  shared temp directory, created with mode 0700, and denies the call when that directory is a
  link, is owned by another user, or others can reach it
  ([#6526](https://github.com/melodic-software/claude-code-plugins/issues/6526)).

## [0.6.0] - 2026-10-07

### Security

- The docs-fetcher gate passes its one `docs-raw.sh` command once per agent run, so a page cannot
  steer a second fetch, and denies when its input stream fails or the gate errors instead of
  failing open. `docs-raw.sh` fetches with `--public-only`: a host, a redirect or a DNS answer
  that leads to a non-global address is unread `private-address`, and curl (now run with `-q`)
  connects only to the checked address with no proxy. A generic page is cached in a per-run
  directory, never the shared docs cache
  ([#6486](https://github.com/melodic-software/claude-code-plugins/issues/6486),
  [#6488](https://github.com/melodic-software/claude-code-plugins/issues/6488)).
- `docs-raw.sh` prints `body_sha256` and normalizes CRLF; the workflow marks a slice unread when
  the body the fetcher returned differs from the header byte count or hash
  ([#6488](https://github.com/melodic-software/claude-code-plugins/issues/6488)).

## [0.5.1] - 2026-10-07

### Changed

- **`audit-defaults`'s main-thread fallback reads each pointer by the fetch-route rungs ([#6494](https://github.com/melodic-software/claude-code-plugins/issues/6494)).** Step 2 no longer says WebFetch: rung 1 with fresh bytes is the route, and WebFetch is the degraded rung 2. The workflow's `drift-checker` agent is unchanged.

## [0.5.0] - 2026-10-07

### Added

- The `multi-agent:docs-fetcher` agent and a `PreToolUse` Bash gate (`lib/docs-fetcher-gate.mjs`) that holds it to the plugin's `docs-raw.sh` on the first-party docs hosts. `drift-audit` now runs a Fetch stage first and passes the raw page slices inline to finders and skeptics. A finder or skeptic can request more sections or pages for one more round; it uses WebFetch for a page no slice covers, and in that last round for a section the slices still lack, naming in notes any claim it could not check. Ships generated copies of `fetch-docs.sh`, `docs-cache.sh`, `html2md.py` and `docs-raw.sh` ([#6020](https://github.com/melodic-software/claude-code-plugins/issues/6020)).

## [0.4.6] - 2026-10-04

### Changed

- The SessionStart node-notice rows now match `startup|resume|clear|fork`, so a compaction no longer starts them; the session and its notice latches survive a compaction, so a re-fire printed nothing (#6251).

## [0.4.5] - 2026-10-04

### Changed

- **Shared hook notice text ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)).** The SessionStart notice for a missing node goes to the user only, in one shorter line.

## [0.4.4] - 2026-10-03

### Changed

- The README notes that an installed mod can stop this plugin's `PreToolUse` hooks from running and can approve a call they blocked, with links to the two mods events sections. Nothing the plugin runs changed.

## [0.4.3] - 2026-10-03

### Fixed

- **The `SessionStart` node-notice row no longer runs `powershell` on Linux.** It stopped at `${BASH_VERSION:+exit}`, which only bash sets; Claude Code runs hooks with `/bin/sh`, which is dash on Debian and Ubuntu (WSL included), so every session printed `powershell: not found`. The row now stops at `${PPID:+exit}`, which every POSIX shell sets.

## [0.4.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.4.1] - 2026-10-03

### Changed

- `scripts/allowed-tools-pairing.test.sh` and `tests/drift-audit.test.sh` declare the files they read without naming them in `# test-scope:` headers, so CI's test selection runs them when one of those files changes. Nothing the plugin runs changed.

## [0.4.0] - 2026-10-03

### Added

- A `SessionStart` hook row reports a missing `node` once per session, on both hook channels, and works on Windows without Git Bash. The notice names `/multi-agent:check`. The row is shared across plugins, so a session with several of them sees one notice.
- `lib/prerequisites.mjs`, `lib/prerequisites.sh` and `lib/prerequisites.ps1`, the generated copies of the shared prerequisites checker and its `node-notice` stubs.

## [0.3.3] - 2026-10-02

### Changed

- **Shared `config-root.sh` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's lib.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.3.2] - 2026-10-03

### Changed

- `prerequisites.json` is converted to the schema `docs/conventions/prerequisites/` owns: a `requires` list whose entries carry `id`, `kind`, `need`, `for`, `detect`, `degrade`, `install` and `check`, in place of the retired `tools` list ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)). The plugin now ships the shared checker, `lib/prerequisites.mjs` with its `lib/prerequisites.sh` and `lib/prerequisites.ps1` stubs, generated from the repository's canonical copy.

## [0.3.1] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`, and its description is shortened to fit claude.ai's
  500-character limit. claude.ai's marketplace sync stripped `$schema` with a warning.

## [0.3.0] - 2026-10-02

### Added

- **`/multi-agent:check`**, a read-only check that reports whether `node` resolves, whether
  `hooks/hooks.json` registers the `drift-checker` fetch gate on `WebFetch`, and whether the gate
  denies a sample off-host drift-checker fetch, through its bundled `scripts/check.sh`. The
  registration row requires one `PreToolUse` entry to carry the matcher, command and script
  together when `node` resolves. The script takes no arguments, and the skill installs nothing. `prerequisites.json` declares
  `node` with this skill as its check.

### Changed

- **The README states that the fetch gate fails open without `node`**: the hook cannot start,
  Claude Code shows a non-blocking hook error notice, and the drift checker's fetches are held to
  first-party docs hosts only by the workflow's source filter and the agent's prompt.

## [0.2.0] - 2026-10-02

### Added

- **`multi-agent:drift-audit` workflow** (`workflows/drift-audit.js`). In `defaults` mode, one
  finder per owner rechecks each bundled default against its pointers; in `repo` mode, one
  reader per area quotes the repository's model, effort, subagent and workflow statements and
  one finder per area checks those quotes against upstream pages. Plain code dedups the
  findings, then three independent skeptics per batch try to refute each one, and a finding
  stands or falls on a majority. It returns confirmed, refuted and unverified findings with
  evidence URLs, plus a proposed `defaults.yaml` diff in `defaults` mode, built only from
  confirmed rows whose proposed value fits the key (a model alias, an effort level, and never
  `frontier_guard: false`) and that no skeptic corrected. A `current` verdict needs evidence
  from a vetted source host; without it the row is unverified. It never edits a file.
  Missing `pointers` (defaults mode) or `targets` (repo mode) returns an error and runs
  nothing. Under a frontier or unknown session, every stage runs on `opus`.
- **`drift-reader` and `drift-checker` agents**, the only agents the workflow runs. The reader
  has Read, Grep and Glob; the checker has WebFetch only. Neither has a shell or can
  edit, and no agent holds both file and web access. Repository text and pages reach their
  prompts only as fenced data, and a finding whose evidence URL is outside the vetted source
  hosts is reported unverified instead of going to a skeptic.
- **`drift-checker` fetch gate** (`hooks/drift-checker-fetch-gate.mjs`), a `PreToolUse` hook on
  `WebFetch`. Inside a `drift-checker` subagent it denies any fetch that is not an https URL on a
  first-party docs host with no query string; other agents and the main thread pass through.
  The workflow drops sources outside those hosts before any stage runs. Needs `node`.
- **`audit-defaults repo`**, a mode that sweeps the repository's tracked markdown;
  `scripts/list-targets.sh` computes the areas and skips symlinks.
- **`list-pointers.sh --json`**, which prints the rows as the workflow's `args.pointers`.

### Changed

- **`/multi-agent:audit-defaults` launches the workflow.** Its `allowed-tools` grants only
  `Workflow(multi-agent:drift-audit)`. When workflows are unavailable, `defaults` mode runs on
  the main thread as before, and `repo` mode stops and says so.

## [0.1.0] - 2026-10-02

### Added

- **Skills.** `assess` (workflow, subagent or single context for a task, with a Workflow
  availability check), `route` (the resolved role map for a workflow's `args.roles`),
  `audit-defaults` (rechecks each bundled default against its upstream pointer, for every
  owner or one named owner, and proposes changes, never applies them) and `setup` (`check` prints the resolved map and the overlay's
  gitignore state; `apply` previews a user, team or local layer change as a diff, writes it on
  an explicit yes, and shows the map before and after. It refuses a team or local path that is,
  or sits under, a symlink inside the repository, and replaces the file by rename).
- **Scope.** The role map governs generic `agent()` calls and Agent dispatches with no agent
  type. A named agent, such as `implementation:scoped-implementer`, keeps the tier in its own
  definition.
- **Role map.** `reference/defaults.yaml` with `orchestrator`, `worker`, `verifier` and
  `retrieval`, each with its pointer, as-of date and recheck trigger, layered through
  user-global, team and overlay files by `scripts/resolve-roles.sh`, which runs on Bash 3.2
  (stock macOS) and later.
- **Fan-out guard.** Each role resolves to a `single` and a `fanout` variant; with
  `fanout.frontier_guard` on (the default), a fan-out variant that would inherit a frontier or
  unknown session model, or that names a frontier alias, takes `fanout.model` (`opus` by
  default).
