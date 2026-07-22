## Brief

Issue melodic-software/claude-code-plugins#832 (epic #830, sub-item 2 of
`docs/topics/lint-static-analysis-gaps/PLAN.md` lines 26-30). Two deliverables, one PR:

1. New `plugins/toolchain/reference/ecosystems/go.yaml` batch ecosystem entry + matching
   `docs/conventions/ecosystem-commands/examples/go.yaml` fixture.
2. New hook plugin `plugins/go-format/` — per-file `goimports` autofix on Write/Edit.

Scope boundaries: batch additions are rung-4 defaults only (consumer `.claude/ecosystems/*.yaml`
override ladder unchanged). `govulncheck` is explicitly "optional" per the brief — NOT shipped as a
default; documented as a consumer-addable local gate only. No `gofumpt` toggle in v1 (YAGNI — no
consumer has asked).

Success criteria: both new surfaces pass the plugin contract gate + fleet conformance audit
(acceptance criteria line 61 of the epic Brief); CI/local parity restored for the Go toolchain gap
identified 2026-07-21 (line 66-67).

## Open Decisions (resolved this session, recorded here for the approval gate)

1. **Formatter pick for the per-file hook: `goimports`.** Field survey against the Brief's own
   criteria (official/authoritative, maintained, feature-fit), researched fresh this session:
   - `gofmt` — non-configurable by design (go.dev/blog/gofmt, go.dev/doc/effective_go), but doesn't
     manage imports; an LLM edit that adds/removes symbol usage leaves a broken file.
   - `goimports` (golang.org/x/tools, v0.48.0, 2026-07-09; ~7,983 commits, last updated
     2026-07-20) — its own docs state it "formats your code in the same style as gofmt so it can be
     used as a replacement for your editor's gofmt-on-save hook." Direct official statement of
     intent for exactly this scenario. **Picked.**
   - `gofumpt` (mvdan/gofumpt v0.10.0, 2026-05-04) — self-branded "a stricter gofmt," third-party
     opinionated superset. Rejected as the unconditional default (same class of risk as why
     ruff-format/dotnet-format gate behind consumer config); not adding a toggle in v1.
   - `golangci-lint fmt` — rejected for the per-file hook. **Stress-test correction:** the plan's
     original citation was imprecise — `golangci-lint fmt --stdin` IS a genuine single-file,
     non-package-scoped invocation (empirically confirmed: no `go/packages` loading, formats piped
     stdin instantly). The "directories are NOT analyzed recursively... files must come from the
     same package" quote governs `golangci-lint run` (linters), not `fmt` (formatters) — don't
     misattribute it. The correct, empirically-confirmed rejection reason: with no config file
     present, `golangci-lint fmt` has **zero formatters enabled by default** (unlike `run`'s fixed
     "standard" 5-linter preset) — i.e. it silently does nothing, the opposite of a usable default.
     Conclusion (rejected for the hook) is unchanged; only the stated reason is corrected.
     Independently corroborates the Brief's own line 30 ("golangci-lint is batch-only by design")
     for the `run`/lint half of the tool.
   - **Consequence: `go-format` runs `goimports` unconditionally — no consumer-config opt-in gate.**
     This is the one deliberate shape difference from ruff-format/typos-format/dotnet-format's
     opt-in-gated pattern. Rationale: goimports has no meaningful config-divergence axis when left
     unconfigured, so gating it would be inert ceremony. Qualifies for
     `docs/PLUGIN-PHILOSOPHY.md` lines 143-147 lane-1 treatment (non-conflicting good-practice
     default) where gofumpt/golangci-lint-fmt would not.
   - **Stress-test correction (HIGH finding, folded in):** the "no config-divergence axis" claim
     was incomplete — empirically confirmed goimports rewrites files carrying the canonical
     `// Code generated ... DO NOT EDIT.` marker with zero awareness of that convention, while
     golangci-lint's own linters/formatters default to `issues.exclude-generated: strict` in v2.
     Generated Go files (protobuf, mockgen, sqlc, stringer, wire output) are common; an
     unconditional hook would silently rewrite them on any edit. **Fix, not a re-open of the
     unconditional-default decision:** `go-format.sh` adds a generated-file marker guard — skip
     (emit_skipped) when the marker appears anywhere in the file's leading
     comment/blank-line run (scanning stops at the first line that is neither blank nor a `//`
     comment), matching Go's own stated convention ("before the first non-comment, non-blank text
     in the file"), not just the first non-blank line. **Independent-review correction (CRITICAL,
     folded in post-stress-test):** the original implementation checked ONLY the first non-blank
     line, on the premise that a preamble before the marker is "uncommon" — that premise was
     false; a license/copyright header (common `addlicense`/`goheader` tooling output) routinely
     precedes the marker by several `//` lines, and this shape is empirically present in real Go
     stdlib-adjacent generated files. Fixed by scanning the full leading comment/blank block
     instead of only line one; also fixed two related defeat vectors caught by the same review
     (trailing CRLF `\r` not stripped before the `$` anchor; a leading UTF-8 BOM defeating the `^`
     anchor) and added five regression test cases (license-header preamble, CRLF, BOM, and a
     negative case confirming a marker appearing AFTER the leading block does NOT suppress a real
     edit). This is precision-scoping (same category as `--force-exclude` giving Ruff per-file skip
     precision), not a consumer-config
     walk-up, so it does not undermine Open Decision 1's "unconditional" framing.

2. **`golangci-lint` lint step gated behind an `opt-in` key** requiring
   `.golangci.yml`/`.golangci.yaml`/`.golangci.toml`/`.golangci.json` present (ancestor walk to
   repo root, mirroring `dotnet.yaml`'s `root = true` boundary if an analogous concept exists for
   golangci-lint — verified during Phase 1 to NOT exist, so ceiling at repo root only). Verified
   via WebFetch/WebSearch this session (golangci-lint.run/docs/configuration,
   github.com/golangci/golangci-lint discussions, 2026): golangci-lint v2 with **no config file
   present still runs its own fixed "standard" linter preset** (`linters.default: standard`)
   rather than erroring or running nothing — the same imposed-unconfigured-opinion risk class
   PR #890 (issue #835) just fixed for `dotnet format`'s unconfigured Roslyn defaults, and
   consistent with why `python.yaml` already gates ruff behind `[tool.ruff]`/`ruff.toml` presence.
   Mirrors `python.yaml:10` and `dotnet.yaml:34`'s `opt-in` key shape exactly.

3. **Single PR, closes #832.** Both deliverables are one Brief line ("Go coverage, both lanes"),
   share the same formatter research, and match the one-issue-one-PR precedent from #831/#835.

## Plan

### Phase 1: `go.yaml` ecosystem batch entry [DONE]

Files:

- `plugins/toolchain/reference/ecosystems/go.yaml` (new) — flat top-level keys, bundled-fallback
  disclaimer header (mirrors `dotnet.yaml:1-27` style):
  - `globs: ["*.go", "go.mod", "go.sum"]`
  - `project-discovery: ["go.mod"]` — **added per stress-test MEDIUM finding**: empirically
    confirmed `go build ./...`/`go test ./...`/`go list ./...` run from a repo root silently skip
    a nested module's packages (a nested `go.mod` bounds `./...` expansion; a root `go.work` file
    does NOT cross module boundaries for this either). Without `project-discovery`, a monorepo with
    a nested Go module gets silent incomplete build/test/lint, directly undercutting this issue's
    own "CI/local parity" success criterion. Mirrors `python.yaml`/`typescript.yaml`'s existing
    `project-discovery` handling for the same class of problem.
  - `build-cmd: "go build ./..."`
  - `test-cmd: "go test ./..."`
  - `check-cmd: "golangci-lint run ./..."`
  - `fix-cmd: "golangci-lint run --fix ./..."`
  - `opt-in`: text per Open Decision 2 above.
  - `install-hint`: **resolved per stress-test finding** — do NOT bake in a pinned
    `curl|sh -s -- -b ... vX.Y.Z` one-liner (upstream's own install docs explicitly state
    `go install`/`go get` "aren't guaranteed to work" for golangci-lint, and a version-pinned
    curl\|sh command drifts immediately). Use a durable pointer instead:
    `"Install golangci-lint: https://golangci-lint.run/docs/welcome/install/ | Go toolchain:
    https://go.dev/dl/"` — same durable-pointer style as `dotnet.yaml`'s
    `"Install .NET SDK from https://dot.net"`.
  - `gates`: one entry, `go-mod-tidy-drift`, `trigger-globs: ["go.mod", "go.sum"]`, `cmd:
    "go mod tidy -diff"` — **confirmed live** via `go help mod tidy` (Go 1.26.5 installed this
    session): "-diff causes tidy not to modify go.mod or go.sum but instead print the necessary
    changes as a unified diff. It exits with a non-zero code if the diff is not empty." Introduced
    Go 1.23 (2024) — note this as an implicit minimum-Go-version prerequisite in `context/go.md`.
    `remediation: "Run go mod tidy and commit the updated go.mod/go.sum."`
  - `notes`: mention `govulncheck` as an available consumer-addable local gate (not shipped by
    default per Open Decision brief-wording), pointing at `.claude/ecosystems/go.local.yaml`.
- `docs/conventions/ecosystem-commands/examples/go.yaml` (new) — richer worked-example fixture
  mirroring `examples/dotnet.yaml`'s structure (same keys as above plus the `gates` block spelled
  out). **Correction (stress-test finding):** only 3 of the 8 existing bundled ecosystem yamls
  (`bash`, `python`, `dotnet`) actually have a matching example fixture — `markdown`, `powershell`,
  `typescript`, `cross-cutting`, `yaml` do not, and no CI gate enforces 1:1 coverage. Add
  `examples/go.yaml` anyway (it's good practice and dotnet/python both have one), but don't claim
  in the PR body that this closes a universal-coverage gap — it doesn't exist as a gap.
- `plugins/toolchain/skills/check/context/go.md` (new) — Go-specific gotchas: `go test ./...`
  module-root requirement (must run from the module root or a path containing `go.mod`;
  `project-discovery` above handles nested-module walking), GOFLAGS interactions,
  golangci-lint's default-"standard"-preset caveat tied to the opt-in gate, AND (stress-test
  MEDIUM finding) golangci-lint's own config discovery falls back to the user's **home directory**
  with no `root = true`-equivalent stop marker when no repo-level config is found — a stray
  `~/.golangci.yml` on a developer's machine makes local runs diverge from a clean CI container;
  document this as a known local/CI divergence source. Mirrors the existing
  `context/dotnet.md`/`context/python.md` shape.
- `plugins/toolchain/skills/check/SKILL.md` — add `go` to the covered-ecosystems list (currently:
  dotnet, python, typescript, bash, powershell, markdown) and its alias table if one applies (no
  common alias needed — "go" is already short).
- `plugins/toolchain/skills/lint/SKILL.md` — same covered-ecosystems list addition if `lint` also
  enumerates them explicitly (verify during implementation; python's opt-in-gated lint precedent
  from #835 touched both `check/SKILL.md` and `lint/SKILL.md`, so `go` likely needs the same
  two-file touch).
- `plugins/toolchain/.claude-plugin/plugin.json` — version bump (minor: new ecosystem capability).
  **Verify current version live** (`git show origin/main:plugins/toolchain/.claude-plugin/plugin.json`
  at rebase time — do not assume 0.6.0 is still current, #833/#834 may have already bumped it).
- `plugins/toolchain/CHANGELOG.md` — `[Unreleased]`/new version entry under Added.

**Sanity Check:** `check-jsonschema --schemafile docs/conventions/ecosystem-commands/ecosystem.schema.json
<file>` passes for both `plugins/toolchain/reference/ecosystems/go.yaml` and
`docs/conventions/ecosystem-commands/examples/go.yaml`. **Independent-review correction:** no CI
job or repo script actually validates `reference/ecosystems/*.yaml`/`examples/*.yaml` against this
schema today (confirmed by grepping `.github/workflows/ci.yml` — its four `check-jsonschema` steps
cover only marketplace/plugin manifests, dependabot, and workflow files); the check above is a
manual `check-jsonschema` CLI run, not an existing repo script being reused. Both files validated
clean this way. This is a pre-existing gap in the repo's own CI coverage, out of scope for this
issue — noted here rather than silently left as an inaccurate claim.

### Phase 2: `plugins/go-format/` hook plugin [DONE]

Files (full new plugin directory, mirroring `plugins/typos-format/` structure):

- `.claude-plugin/plugin.json` — `userConfig.go_format_enabled` (boolean, default `true`), version
  `0.1.0`, keywords `["go","golang","goimports","formatter","hook"]`.
- `hooks/hooks.json` — `PostToolUse`, matcher `Write|Edit`, command
  `"${CLAUDE_PLUGIN_ROOT}"/hooks/go-format.sh`, timeout 15.
- `hooks/hook-utils.sh` — initial copy via `scripts/sync-hook-utils.sh` (never hand-copy).
- `hooks/go-format.sh` — control flow mirrors `ruff-format.sh`'s shape:
  - Extension pre-filter on `*.go` (jq-free, before requiring jq) — like ruff-format, unlike
    typos-format's no-filter shape.
  - `hook::check_enabled "GO_FORMAT"`, `hook::buffer_stdin`, `hook::require_jq`,
    `hook::read_file_path`, `hook::repo_root`.
  - **No ancestor consumer-config walk-up** (goimports is unconditional per Open Decision 1) —
    document this simplification explicitly in a short header comment referencing this PLAN's
    rationale, not just silently omitting the walk-up ruff-format/typos-format both have.
  - Binary resolution: PATH-only (`command -v goimports`) — no `.venv`-style walk (Go has no
    per-project virtualenv concept; mirrors typos-format's PATH-only resolution).
  - Invocation: **resolved via empirical stress-test verification (real goimports v0.48.0
    binary):** `goimports -w -l "$FILE"` in one pass — `-w` writes the fix, `-l` (list-only)
    combined with `-w` still lists the filename if changes were needed, giving a single-pass
    fix+detect (simpler than ruff-format's two-pass shape). Exit-code semantics confirmed: **`-l`
    ALWAYS exits 0**, even when it lists a file needing changes — there is no exit-1-style
    "findings" signal like ruff/typos have. Detect "changes were made" from **non-empty stdout**
    (the listed filename), not from exit code. Non-zero exit (confirmed: exit 2, parseable message
    on **stderr**) occurs only on a genuine parse/syntax error — surface that as a finding-text
    message (mirrors how ruff-format surfaces a mid-edit syntax error as a finding, not a
    tool-break), matching the doctrine even though the underlying signal shape differs from ruff.
    Skip entirely (before invoking goimports) when the file matches the generated-file marker guard
    from Open Decision 1's stress-test correction above.
  - Telemetry: `hook::emit_telemetry "go-format" "PostToolUse" <status> "$start" "$data_json"
    "$REPO_ROOT"`; `status` semantics per the shared doctrine (`ok` = ran to judgment, `skipped` =
    tool broke/missing prerequisite).
  - Always exits 0 (advisory only).
- `hooks/go-format.test.sh` — FAKEBIN-pattern contract test mirroring
  `ruff-format.test.sh`/`typos-format.test.sh`: gate-off, non-`.go` extension skip, clean file,
  import-added-by-edit auto-added, import-removed-by-edit auto-removed, **generated-file marker
  skip** (new case per the Open Decision 1 stress-test correction), missing-binary dim-9 visibility
  (once-per-session), missing-jq dim-9 visibility, kill-switch, telemetry envelope shape assertions
  (`schema_version`/`timestamp`/`hook`/`hook_event`/`status`/`duration_ms`/`data`), a
  syntax-error-mid-edit case surfaced as a finding (per the confirmed `-l` exit-2/stderr behavior
  above, not a tool-break).
- `skills/setup/SKILL.md` — `check`/`apply`, `disable-model-invocation: true`. `check` probes Bash,
  jq, `goimports` on PATH, the `go_format_enabled` toggle, hook registration. `apply`: **resolved
  per stress-test finding — guidance-only, no write path**, matching `typos-format`'s pattern
  (`plugins/typos-format/skills/setup/SKILL.md:57-64`), not `ruff-format`'s `.venv`-install path.
  `go install golang.org/x/tools/cmd/goimports@latest` writes to the machine-global
  `$GOBIN`/`$GOPATH/bin` (not project-scoped) and `@latest` is not idempotent-pinned (silently
  drifts over time) — structurally the same "no per-repo dependency-manager, machine-level binary"
  case as typos-format, not ruff-format's project-`.venv` case. Document the goimports install
  pointer (`go install golang.org/x/tools/cmd/goimports@latest` — a plain, uncaveated `go install`,
  unlike golangci-lint's own install docs which explicitly warn `go install`/`go get` "aren't
  guaranteed to work" for that tool specifically — don't let that caveat bleed across into this
  SKILL.md's goimports guidance).
- `README.md` — mirror typos-format's structure; explicitly document the "no config-gate,
  unconditional default" design choice (the one plugin in the family without an opt-in section) —
  say so plainly, don't silently omit the section.
- `CHANGELOG.md` — `[0.1.0]` initial release entry, telemetry-conformant from day one (matches
  typos-format's precedent, not ruff-format's later-follow-up pattern).
- `docs/conventions/hook-telemetry/data/go-format.schema.json` (new) — findings shape decided from
  Phase 2's live verification of goimports' actual diagnostic output (flat-string per ruff-format's
  shape unless goimports emits something structured — verify, don't assume).
- `docs/conventions/hook-telemetry/README.md` — add Implementers table row for `go-format`.
- `.claude-plugin/marketplace.json` — new entry: `category: "development"`,
  `tags: ["go","golang","goimports","formatter","hook"]`,
  `relevance: {topic: "Go", signals: {filesRead: ["**/*.go"], cli: ["goimports"]}}` (mirrors
  ruff-format/typos-format's relevance-block shape exactly).
- `README.md` (repo root) — regenerate catalog block via `node scripts/generate-catalog.mjs`.

**Sanity Check:** `plugins/go-format/hooks/go-format.test.sh` passes 100% when run directly
(`bash plugins/go-format/hooks/go-format.test.sh`), and `scripts/sync-hook-utils.sh --check`
reports no drift for the new copy.

### Phase 3: Cross-cutting verification + PR [DOING]

- Rebase onto latest `origin/main` (expect a benign conflict on
  `plugins/toolchain/.claude-plugin/plugin.json` + `plugins/toolchain/CHANGELOG.md` against
  #833/#834's already-merged or still-in-flight changes — resolve by reapplying this lane's version
  bump on top of theirs, not by discarding either).
- Run the full local CI-equivalent gate set: hygiene (schema/markdownlint/typos/shellcheck/exec-bit),
  hook-utils-sync, cross-plugin-source-drift, silent-skip-gate, changelog-parity-gate,
  skill-quality-gate + portability-lint, plugin-gate (`scripts/validate-plugin-contracts.mjs` +
  both new/changed test suites), `scripts/generate-catalog.mjs --check`.
- Mandatory fresh-context independent code review (per this session's established discipline).
- `gh pr create` — closes #832, body includes the two locked Open Decisions above (formatter pick +
  opt-in-gate rationale) so reviewers see the reasoning, not just the diff.
- Monitor CI, process every review thread to resolution (GraphQL `resolveReviewThread` for
  bot-authored addressed threads — this repo's ruleset requires
  `required_review_thread_resolution`), merge, remove worktree, delete branch, confirm issue
  auto-closed.
- `/planning:plan close-out`: paste this PLAN.md into the PR body `<details>` block, prune
  `docs/topics/832-go-ecosystem/` before merge.

**Sanity Check:** `gh pr view <N> --json state -q .state` returns `MERGED`; `gh issue view 832
--json state -q .state` returns `CLOSED`.

## Review history

An independent fresh-context code review ran before PR creation and found one CRITICAL and two
lower-severity items, all addressed and re-verified before opening the PR:

1. **CRITICAL — generated-file guard only checked the first non-blank line, missing the common
   license-header-then-marker layout** (and two related defeat vectors: CRLF, UTF-8 BOM).
   Reviewer empirically reproduced the miss against a real generated-file shape (a copyright
   header plus a `stringer`-style marker) and confirmed the hook silently rewrote it. Fixed: the guard now
   scans the file's full leading comment/blank-line run (stopping at the first non-comment,
   non-blank line) per Go's own stated convention, strips a trailing CRLF and leading BOM per
   line before matching. Five new regression cases added (license-header preamble, CRLF, BOM,
   and a negative case proving a marker appearing after the leading block does NOT suppress a
   real edit) — see Open Decision 1 above for the full before/after.
2. **SUGGESTION — stderr capture used an unnecessary `mktemp` file**, inconsistent with every
   other hook in the repo's simpler command-substitution idiom. Simplified to match.
3. **SUGGESTION — this PLAN's own Phase 1 Sanity Check claimed an existing repo script validates
   ecosystem yaml against `ecosystem.schema.json`; no such CI job or script exists.** Corrected the
   claim (see Phase 1's Sanity Check above) — the schema validation itself was and remains correct
   (verified manually via `check-jsonschema`), only the "reuse an existing script" framing was
   wrong. This is a pre-existing repo-wide CI-coverage gap, out of scope here.

## Blast radius

**MEDIUM.** New plugin + new ecosystem entry, but both are close pattern-replications of two
already-merged, already-reviewed precedents (typos-format PR #872, dotnet opt-in gate PR #890) in
this same epic. The two genuine judgment calls (goimports-unconditional, golangci-lint-opt-in) are
each backed by fresh primary-source research and a direct analogy to an already-accepted precedent
in this repo — not novel territory. No cross-module architectural change, no data-model change, no
multi-tenant concern. Several implementation-time facts (exact goimports flags, exact golangci-lint
install command, `go mod tidy` dry-run flag syntax) are flagged as **verify-live, don't assume** —
this is where a stress-test/implementation-time slip is most likely, not in the two locked design
decisions.

## Stress-test summary

Blast radius MEDIUM — no CRITICAL/HIGH triggers (no cross-module integration, no data-model change,
no multi-tenant posture) per `context/stress-test-triggers.md`'s criteria, but the two load-bearing
judgment calls (Open Decisions 1 and 2) warrant the mandatory Step 3 fresh-context plan-reviewer
pass before implementation, specifically pressure-testing: (a) is "goimports unconditional, no
opt-in" actually safe, or does goimports have a config-divergence axis this session's research
missed; (b) is the golangci-lint opt-in gate correctly scoped (does it match how `check-cmd`
composes with `fix-cmd` the same way python/dotnet's gates do, and is the ancestor-walk boundary
choice — repo-root-only, no `root = true`-equivalent — actually correct for golangci-lint's own
config discovery, which may differ from EditorConfig's semantics).

*(Dispatched separately as the mandatory Step 3 fresh-context plan-reviewer sub-agent — findings
folded in before implementation begins.)*

## Execution shape

Sequential — Phase 1 (ecosystem yaml) and Phase 2 (hook plugin) touch disjoint files and share no
data dependency (Phase 2 doesn't consume Phase 1's output), so they are parallel-safe by the
file-overlap test, but the combined scope is small enough (~14 files total) that the coordination
overhead of a two-agent split isn't worth it for a MEDIUM-blast-radius, largely-mechanical
replication lane. Single main-session sequential execution, Phase 1 then Phase 2, then Phase 3
cross-cutting verification gates both. Phase 3 is fully sequential-dependent on both.

## Open questions

None blocking — all flagged "verify live during implementation" items are execution-time fact
lookups (exact CLI flags/install commands), not design decisions requiring further user input.

## Handoff to implementation

### User-approval gates

None beyond initial plan approval — no `[FALLBACK]` tags, no scope-expansion proposals anticipated.
If live verification during Phase 1/2 surfaces that `goimports` or `golangci-lint` behave
materially differently than researched (e.g., goimports turns out to have a real config-divergence
axis), STOP and re-open Open Decision 1 rather than silently proceeding.

### Execution shape (`[EXEC-SHAPE]` tagged)

- `[EXEC-SHAPE]` Single PR bundling both deliverables (Open Decision 3).
- `[EXEC-SHAPE]` Sequential single-main-session execution (Execution shape section above).
- `[EXEC-SHAPE]` `go-format` hook plugin structural simplification (no ancestor config walk-up) —
  Open Decision 1's consequence.

### Mechanical work

Commit boundaries: one commit per phase is reasonable (Phase 1, Phase 2, then fixup commits for
review findings) but not mandated — squash-merge means the final PR history is one commit anyway.
Verification checkpoints: run the full local gate set after each phase, not just once at the end,
to catch cross-phase interactions (e.g., `plugin.json`/`CHANGELOG.md` version-bump conflicts
between the toolchain-plugin edit in Phase 1 and any repo-root catalog regen in Phase 2) early.
Sequential fallback: N/A (already sequential).
