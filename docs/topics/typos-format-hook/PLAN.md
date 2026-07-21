# typos-format hook plugin

## Brief

Issue melodic-software/claude-code-plugins#831 (epic #830, sub-item 1 of
docs/topics/lint-static-analysis-gaps/PLAN.md, merged via PR #829). New hook
plugin `plugins/typos-format/`: per-file `typos -w` autofix on Write/Edit,
mirroring the existing `plugins/markdown-format/` and `plugins/ruff-format/`
patterns. Opt-in via consumer typos config ancestor walk-up (no config = no-op,
never impose typos' defaults on a repo that hasn't adopted it — same posture as
ruff-format). Advisory only, hook-precision + hook-telemetry conventions,
setup skill (check/apply).

Scope: Tier C (no design) — pure pattern replication of two already-shipped,
gate-passing plugins; no new types, no new architecture.

## Plan

### Phase 1: Hook plugin skeleton [TODO]

Files (new):

- `plugins/typos-format/.claude-plugin/plugin.json` — mirrors ruff-format's
  shape: `userConfig.typos_format_enabled` (boolean, default true).
- `plugins/typos-format/hooks/hooks.json` — `PostToolUse`, matcher `Write|Edit`,
  command `"${CLAUDE_PLUGIN_ROOT}"/hooks/typos-format.sh`, timeout 15.
- `plugins/typos-format/hooks/hook-utils.sh` — byte-identical copy of
  `lib/hook-utils.sh` (repo root), produced by `scripts/sync-hook-utils.sh`
  (never hand-authored).
- `plugins/typos-format/hooks/typos-format.sh` — core hook, detailed below.
- `.claude-plugin/marketplace.json` — new entry, `category: "development"`
  (matches ruff-format/markdown-format), `tags: ["typos", "spelling",
  "formatter", "linter", "hook"]`.

**Hook control flow** (`typos-format.sh`, modeled on `ruff-format.sh`):

1. `hook::check_enabled "TYPOS_FORMAT"`.
2. `start=${EPOCHREALTIME:-}`, `emit_tel` wrapper gated on `-n "$start"`.
3. `INPUT=$(hook::buffer_stdin) || exit 0`.
4. No extension pre-filter — typos is language-agnostic (unlike ruff/markdown,
   scoped to one file type). `RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0`
   is still used only to skip the `require_jq` gate when no file_path is
   present at all (matches the applicability-pre-filter *purpose*, not an
   extension check).
5. `hook::require_jq PostToolUse typos-format "$INPUT"`.
6. `FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0`.
7. `REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"`; compute `FILE_REL`
   via the same cygpath-aware normalization block as ruff-format.sh:84-93.
8. **Binary-file skip**: typos itself already skips binary content
   heuristically, but to avoid a wasted process-per-edit on obviously binary
   extensions, no explicit extension allowlist is added (would reintroduce the
   opinion the plugin philosophy forbids) — reuse typos' own detection,
   verified empirically to `exit 2`-report cleanly on text, silently pass
   binaries (confirm in Phase 1 sanity check; if typos errors hard on a binary
   path, fall back to `git check-attr` / a `file`-based skip — decide only if
   the empirical check fails).
9. **Consumer opt-in walk-up** (closest-first, git-root-bounded, same loop
   shape as ruff-format.sh:131-146): from `FILE_DIR_POSIX` upward, at each
   directory check in this exact order — per crate-ci/typos' own official
   docs (docs/reference.md: "Search parents of specified file / directory for
   one of `typos.toml`, `_typos.toml`, `.typos.toml`, `Cargo.toml`, or
   `pyproject.toml`", precedence order as listed; corroborated empirically —
   same-directory `typos.toml` beat `_typos.toml` — and by tracing typos'
   `Config::from_dir`/`find_project_files`, which checks all 5 names together
   per-directory before ascending, confirming closest-directory-wins matches
   this hook's ruff-format-style loop shape): `typos.toml`, `_typos.toml`,
   `.typos.toml` (first found wins, same-dir), else `Cargo.toml` containing
   `[workspace.metadata.typos]` or `[package.metadata.typos]`, else
   `pyproject.toml` containing `[tool.typos]` (regex-gated like ruff-format's
   pyproject check). No config found anywhere on the walk → `emit_skipped`
   (status `skipped`), file untouched.
10. **Binary resolution**: `command -v typos` on PATH only — no `.venv`-style
    per-repo binary convention exists for typos (it's a standalone Rust
    binary, not a language-ecosystem-scoped tool); absent → `hook::notice_once`
    plus `hook::emit_skip_notice` (install link:
    https://github.com/crate-ci/typos#install), then `emit_skipped`.
11. **Fix pass**: `typos -w --format json "$RUFF_ARG"`-equivalent
    (`typos --write-changes --format json "$FILE_REL_or_FILE"`, cd'd to
    `REPO_ROOT` so config discovery matches typos' own CWD-relative behavior)
    — capture stdout (jsonlines, one object per finding) and exit code.
    Verified empirically (typos-cli 1.44.0): exit 0 = clean/fully-fixed after
    write; exit 2 = residual (unfixable, e.g. blank-correction "disallowed")
    findings remain; other = typos itself errored (config parse, etc.).
12. **Residual reporting**: on exit 0 → `emit_tel ok '[]'`, exit 0. On exit 2 →
    parse each jsonlines object (`jq -R 'fromjson?'` per line, drop parse
    failures), build one human-readable line per finding
    (`hook::ctx_append`) plus a findings JSON array
    (`{typo, corrections}` per finding, mirroring markdown-format's
    MD-rule-code extraction shape but typos-specific fields), `hook::ctx_flush
    PostToolUse`, `emit_tel ok "$FINDINGS_JSON"`, exit 0. On any other exit
    code → treat as tool break (same as ruff-format's `RC` fallthrough
    branch): advisory diagnostic via `additionalContext`, `emit_tel skipped
    '[]'`, exit 0.
13. Telemetry `data` schema: `{tool, file, findings:[{typo, corrections}]}` —
    publish `docs/conventions/hook-telemetry/data/typos-format.schema.json`
    and add a row to that README's Implementers table. Model this on
    `markdown-format`'s schema+registry-row pair, not `ruff-format`'s — stress
    test (below) found `ruff-format` calls `hook::emit_telemetry` but never
    shipped its own schema/registry row (a pre-existing, dormant docs-drift
    gap in that plugin, out of this PR's scope; file a short follow-up issue
    noting it).
14. **False-positive remediation guidance (epic-named deliverable — do not
    drop)**: the epic contract (docs/topics/lint-static-analysis-gaps/PLAN.md:22-25)
    names "false-positive remediation via consumer allowlist entries
    (`extend-words` / `extend-identifiers` / `extend-ignore-re`)" as a
    distinct, in-scope capability alongside residual-only advisory context —
    not merely "report the finding." The residual-finding `additionalContext`
    text (step 12) must include one line pointing at the remediation path,
    e.g. "If `<typo>` is intentional, add it to `extend-words` /
    `extend-identifiers` (or an `extend-ignore-re` pattern) in your
    `_typos.toml`." This is advisory text only — the hook never writes to the
    consumer's config itself (would violate the "setup owns the config
    surface, not a per-edit hook" boundary).
15. **Known, pre-existing, out-of-scope risk — concurrent same-file hook
    writes**: Claude Code runs every matching `PostToolUse` hook in parallel
    for one tool call. `typos-format` has no extension filter (by design —
    typos is language-agnostic), so on a repo with both a Ruff config and a
    typos config, editing a `.py` file fires `ruff-format.sh` and
    `typos-format.sh` concurrently, each independently reading-then-writing
    the same file with no locking — a nondeterministic clobber is possible
    (whichever write lands last wins, silently discarding the other's fix).
    This race class already exists today between `eol-normalizer` (also
    extension-unscoped) and every formatter hook; `typos-format` is the
    second unscoped writer, not the first. **Not fixed in this PR** — no
    hook-level locking or ordering primitive exists in Claude Code today (no
    sequential-hook-execution feature). Document the risk in the hook's
    header comment (mirroring ruff-format.sh's header-comment style) and file
    a separate fleet-scoped follow-up issue tracking it (owner: whichever repo
    owns cross-hook coordination — likely this repo's PLUGIN-PHILOSOPHY.md or
    a new convention, not a single plugin's fix).

**Hook-precision conformance**: the convention doc states plainly (README.md:3)
that "every plugin hook follows" this discipline — it is fleet-wide by intent,
even though today's CI-audited enforcement surface is narrower
(`plugins/guardrails/hooks/**` only; stress-test confirmed via grep that no
non-guardrails hook currently references the convention, including
ruff-format/markdown-format). typos-format opts in voluntarily as good
practice, same as any new hook should, rather than treating the narrower
CI-audit scope as "not applicable to me." Rule-by-rule: rule 1 (N/A — whole
file is genuinely new content from typos' perspective on every Write, and
ruff-format/markdown-format independently confirmed to scan whole-file on
Edit too, not just the changed hunk — this is an accepted posture for
formatter/autofix hooks specifically, not a rule-1 violation, since the
"changed hunk" framing is aimed at detector/guard hooks flagging pre-existing
lines the edit never touched), 3 (bounded stdin via `hook::buffer_stdin` —
inherited), 4 (N/A — no canonical-marker gating in this hook), 5 (N/A — no
repo-path/home-directory branch in this hook). Document applicability (or the
N/A reason) in the hook's header comment, mirroring ruff-format.sh:1-24.

**Sanity Check:** `bash -n plugins/typos-format/hooks/typos-format.sh`
(syntax); manual run against a throwaway repo with `_typos.toml` +
fixable/unfixable fixture, confirming exit 0 / additionalContext / telemetry
envelope shapes match the empirical CLI behavior recorded above.

### Phase 2: Setup skill + docs [TODO]

Files (new):

- `plugins/typos-format/skills/setup/SKILL.md` — `check`/`apply` contract per
  PLUGIN-PHILOSOPHY.md:221-231, modeled on markdown-format's setup skill:
  `check` probes Bash version, `jq`, `typos` binary resolution + `--version`
  liveness, consumer `_typos.toml`-family config discovery, the
  `typos_format_enabled` toggle. `apply install-lint` installs `typos-cli` via
  the consumer's detected package manager where sensible — but typos is a
  standalone binary (not an npm/pip dependency in most repos); the `apply`
  path likely just points at `https://github.com/crate-ci/typos#install`
  (cargo/brew/winget/pip alternatives) rather than writing a dependency file —
  **decide the exact `apply` scope during implementation** by checking what
  install channels are realistic for a cross-platform standalone Rust binary
  (this differs materially from markdown-format's npm-dev-dependency `apply`;
  confirm via `crate-ci/typos` README install section before writing).
- `plugins/typos-format/README.md` — behavior, requirements (Bash 3.2+, `jq`,
  `typos` on PATH), opt-in config discovery, `setup check|apply`,
  `typos_format_enabled` userConfig, MIT license.
- `plugins/typos-format/CHANGELOG.md` — Keep-a-Changelog, starts at `0.1.0`
  matching `plugin.json`'s initial version (changelog-parity-gate requires a
  `## [0.1.0]` heading on the version-introducing PR).

**Sanity Check:** `grep -c '## \[0.1.0\]' plugins/typos-format/CHANGELOG.md`
returns 1; `SKILL.md` frontmatter has `disable-model-invocation: true`.

### Phase 3: Contract test [TODO]

File (new): `plugins/typos-format/hooks/typos-format.test.sh` — black-box
Bash contract test, same hand-rolled ok/fail-counter shape as
`markdown-format.test.sh`/`ruff-format.test.sh` (no framework). Fixture
corpus (minimum, extend as needed):

- Fixable-only typo → exit 0, empty additionalContext, file content corrected
  in place.
- Fixable + unfixable (blank-correction `extend-words` entry) → unfixable
  fixed... no: fixable auto-corrected, unfixable surfaces via
  additionalContext with `corrections: null`, exit 0 (hook never blocks).
- No consumer config anywhere on the walk → skip, file untouched, `skipped`
  telemetry status.
- `typos.toml` vs `_typos.toml` both present in same dir →`typos.toml` wins
  (empirically confirmed precedence), asserted via which correction fired.
- Missing `typos` binary → advisory notice on both channels, `skipped` status,
  never invokes a download/install command.
- Missing `jq` → advisory on both channels.
- Kill switch (`CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false`) → hard no-op.
- Telemetry: sink-unset parity, full envelope schema validation via stub sink,
  envelope never leaks into hook's own stdout (mirrors markdown-format's
  telemetry test block).

**Sanity Check:** `bash plugins/typos-format/hooks/typos-format.test.sh` exits
0, all assertions pass; `scripts/run-plugin-tests.sh` picks it up (it globs
`plugins/**/*.test.sh`).

### Phase 4: Local CI-equivalent verification [TODO]

Run every gate this new directory will trip in `plugin-gate` +
`hygiene` locally before opening the PR:

- `scripts/sync-hook-utils.sh --check` (after Phase 1's copy).
- `scripts/run-plugin-tests.sh` (picks up the new `.test.sh`).
- `scripts/validate-plugins.sh` (manifest schema + `claude plugin validate`,
  no-npx contract check).
- `scripts/check-silent-skips.sh` — every prerequisite-exit path in
  `typos-format.sh` must carry a visible notice (they do, per Phase 1 design)
  or a `# silent-skip-ok:` annotation.
- `scripts/check-changelog-parity.sh --check`.
- `node scripts/generate-catalog.mjs --check` (marketplace entry + README
  catalog block drift).
- markdownlint/typos/shellcheck/exec-bit on the new files themselves (the
  `hygiene` job's repo-wide sweep) — run `typos` on the new plugin's own
  files as a self-check, since this plugin's entire purpose is that gate.

**Sanity Check:** every command above exits 0 locally before PR creation.

## Blast radius

**LOW.** New, additive plugin directory; zero changes to existing plugins,
hooks, or shared infra beyond the synced `hook-utils.sh` copy (mechanical,
gated by CI drift-check) and the two doc/registry additions (marketplace
entry, hook-telemetry Implementers row) — both purely additive rows, no
existing row edited. No consumer repo is affected unless it explicitly
installs the plugin AND adopts a typos config (opt-in twice over).

## Stress-test summary

Skipped: blast radius LOW, no triggers matched (pure pattern replication of
two already-shipped, gate-passing sibling plugins; no new types, no
cross-module coupling, no data-model or security-boundary change). A
fresh-context plan-reviewer pass still runs per this skill's mandatory Step 3
before implementation begins.

## Execution shape

Single-session, sequential (all 4 phases touch/depend on the same new
directory; no parallel-safe file-disjoint split worth the multi-agent
overhead for ~8 files). Main-session execution throughout.

## Open questions

1. **Binary-file behavior** — does `typos -w` on a genuinely binary file
   error hard, or silently pass? Empirical check deferred to Phase 1 Sanity
   Check rather than blocking planning (low risk: worst case is one extra
   `file`-based guard, not a redesign).
2. **Setup `apply` scope for a standalone Rust binary** — markdownlint-cli2
   and ruff both have clean per-repo dependency-manager install paths; typos
   does not (it's usually a machine-level tool: cargo/brew/winget/pip). Decide
   during Phase 2 implementation by reading crate-ci/typos' own install docs;
   default assumption: `apply` is check-only + a printed install command,
   never a silent auto-install (PLUGIN-PHILOSOPHY.md never-download-silently
   rule).

## Handoff to implementation

### User-approval gates

None beyond this plan's own approval — no `[FALLBACK]` tags, no scope
expansion proposed. Standing epic authorization
(`.work/lint-static-analysis-gaps/handoff.md`) covers PR creation and merge
for this lane once CI is green and an independent review has run.

### Execution shape (`[EXEC-SHAPE]` tagged)

Sequential, main-session, all 4 phases. `[EXEC-SHAPE]`: no parallel fan-out —
justification in "Execution shape" above.

### Mechanical work

Commit at each phase boundary (skeleton → setup/docs → test → verified-green).
After Phase 4 all-green: independent review via a fresh-context
`review:code-reviewer` pass (or `codex:codex-rescue` if the stronger
cross-vendor lens is warranted for a contract-gated plugin) before PR
creation, per the epic's producer≠critic≠tester requirement. Then
`/pull-request` for PR lifecycle (create → monitor → merge), per the epic
directive.
