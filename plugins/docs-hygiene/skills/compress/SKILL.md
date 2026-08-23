---
description: "Compress (tighten, shorten, trim) markdown files by dropping flavor — filler, hedging, articles — while preserving all content (directives, qualifiers, thresholds, examples), with a mandatory semantic-diff subagent that reverts any SEMANTIC LOSS or AMBIGUITY. Use when: 'compress this doc', 'tighten markdown', 'cut prose', 'shorten without losing meaning', 'trim onboarding doc', or verbose prose in docs/, READMEs, rule bodies, skill bodies, or third-party pasted text — actions: default (snapshot → backend → semantic-diff subagent → revert-pass → markdownlint) and audit (read-only dry-run classifying SKIP/COMPRESS/UNCERTAIN per file); empty target + clean tree in an interactive session offers a confirmation-gated repo-wide run (audit-first interview with prescribed defaults) instead of the no-op; flags: --force (bypass <3% revert rule), --keep-snapshot; not for: session compaction (/compact), markdown noise classification (/audit-noise), code-comment trimming, or content relocation/SSOT consolidation (/extract-ssot)."
argument-hint: "[audit] [target] [--force] [--keep-snapshot]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Tighten markdown by dropping flavor while preserving every directive
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files: !`{ git status --porcelain 2>/dev/null | grep '\.md$' || echo "none"; } | head -10`

## Purpose

Markdown in `docs/`, README files, onboarding docs, third-party pasted prose, and drifted skill bodies accumulates FLAVOR — filler ("just", "really", "basically"), hedging ("perhaps", "might"), articles, pleasantries. `context/flavor-vs-content-matrix.md` defines FLAVOR (safe to cut) vs CONTENT (never cut). The **batch fan-out path** (Phase A LATITUDE) is a word-level trimmer: mechanical drops + passive→active + nominalization only — no sentence-level restatement deletion. The **single-file in-session Edit fallback** may apply the full matrix taxonomy (including redundant restatement of bold rule names) behind the same semantic-diff net. Always-loaded instruction files (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`) bound empirically at 2-3% yield (see ## Sources). Likely 5-15% yield on author-time-undisciplined content when the Edit fallback's broader latitude applies; batch fan-out yields are correspondingly smaller.

Methodology: snapshot original → backend mechanical compression (the `caveman` plugin via `/caveman:compress`, OR in-session Edit fallback) → spawn semantic-diff subagent comparing original vs condensed (output: SEMANTIC LOSS / AMBIGUITY / FALSE POSITIVE per finding with verbatim citations) → revert every SEMANTIC LOSS + AMBIGUITY → run `markdownlint-cli2` → ship or revert.

## Backend selection

Default-action Step B picks the mechanical-compression backend: the `caveman` plugin (marketplace `caveman`, invoked as `/caveman:compress` via the Skill tool) when present, otherwise the in-session Edit-based fallback. Caveman performs the mechanical flavor cuts (articles, fillers, hedging, verbose-verb collapses) as the compression backend — it is NOT the verification gate. Fallback policy is graceful: the in-session Edit-based path substitutes whenever caveman is absent or unwanted. Subsequent steps (semantic-diff dispatch, revert pass, markdownlint) wrap the output regardless of backend choice.

 `disable-model-invocation: false` is deliberate: compress is model-invocable with interview confirmation gates and permission-governed Edit/Bash; not an oversight relative to D1 guidance that mutating skills often set the flag true.

Note the distinction inside that plugin: `/caveman:compress` is a function-call skill (this skill's backend); `/caveman:caveman` is a session-wide response formatter — unrelated to this skill.

**Step A — detect caveman plugin:** `bash "${CLAUDE_SKILL_DIR}/scripts/detect-caveman.sh"`
Tri-state: `available` → prefer caveman; `absent` OR `unknown` → treat as absent and use the Edit fallback (`unknown` means `claude`/`jq` missing from PATH — fail open to Edit, not a hard error).

**Step B — caveman backend (preferred when available):** cross-tool-call steps (Bash state does not persist across tool calls — no `trap … EXIT`, no relying on `$tempdir` in a later call):

1. **Bash call 1** — create a temp copy and echo its absolute path (no EXIT trap):

   ```bash
   tempdir=$(mktemp -d)
   cp "$target" "$tempdir/$(basename "$target")"
   printf '%s\n' "$tempdir/$(basename "$target")"
   ```

2. **Skill call** — `Skill(caveman:compress, args="<absolute-path-from-step-1>")` on that temp copy. Caveman may write `<file>.original.md` beside the copy inside the tempdir.
3. **Bash call 2** — on caveman success, copy the compressed file back and remove the tempdir explicitly:

   ```bash
   cp "<absolute-path-from-step-1>" "$target"
   rm -rf "$(dirname "<absolute-path-from-step-1>")"
   ```

   On caveman failure, skip the `cp` and still `rm -rf` the tempdir so the real target is untouched.

Tempdir wrapper contains caveman's hardcoded `<file>.original.md` backup write. Real-path file replaced only on success. Consumers may add a defensive `**/*.original.md` entry to their `.gitignore` as belt-and-suspenders against cleanup races or future caveman backup-path-convention changes.

**Step B fallback — in-session Edit (caveman absent, unknown, or unwanted):**

Agent applies Edit ops directly on `$target` per the `context/flavor-vs-content-matrix.md` taxonomy (full matrix, including restatement deletion). Same flavor-vs-content rules; no backend indirection.

**Step C+ unchanged:** semantic-diff dispatch (mandatory hard rule), revert pass for SEMANTIC LOSS / AMBIGUITY / UNCERTAIN findings, markdownlint-cli2, summary.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` from `git status`; file path → single-file; dir path → batch | snapshot → backend → dispatch → revert-pass → markdownlint verify → summary |
| `audit [target]` | same target rules | read-only dry-run; run `scripts/audit-scan.sh` (six-signal heuristic in `context/target-types.md`); classify SKIP/COMPRESS/UNCERTAIN |

Flags (apply to both actions):

- `--force` — proceed even when the default `<3% AND 0 semantic-loss → REVERT` rule would trip. User owns the sub-3% diff
- `--keep-snapshot` — persist the original to `${CLAUDE_PLUGIN_DATA}/snapshots/<ISO-basic>Z-<basename>.orig.md` (the plugin data directory survives plugin updates)

## Auto-detect default

Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md).

1. Empty arg AND clean tree → interactive session: repo-wide interview fallback (next section); non-interactive context (subagent, headless/CI): friendly no-op exit 0 ("No uncommitted .md files. Pass file/dir target.")
2. Empty arg AND uncommitted `.md` files → batch default action over those files
3. Single file path → single-file default action
4. Directory path → batch default action (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit action on rest (same clean-tree offer as rule 1 when the rest is empty — report-only corpus audit, no Edit)

## Repo-wide interview fallback (empty arg, clean tree, interactive)

Instead of dead-ending, offer a repo-wide run — confirmation-gated at every step; declining at any step exits with the friendly no-op message. Bare `/docs-hygiene:compress audit` on a clean tree uses steps 1–2 only (free audit + report; no compression interview).

1. **Offer** (AskUserQuestion): run against all tracked eligible `.md` files? Decline → no-op exit.
2. **Audit first** (free — mechanical scan, no subagents): run the audit action over every tracked eligible `.md`. Present INLINE only aggregate counts per class, a dispatch-cost estimate (2 subagent requests per compressed file), and a top-20 excerpt of COMPRESS rows selected deterministically: expected-yield band descending, then word count descending, then lexical path (band strings tie; the two tie-breaks keep the excerpt stable run-to-run). Write the full per-file table to a file — destination `${CLAUDE_PLUGIN_DATA}/audit/<branch-or-scope>-audit.md` when that dir is writable, otherwise a temp path echoed to the user — lexically sorted per the "Summary output deterministic" hard rule — and point at it. Never render every row inline — on a large repo the full table can run to hundreds of KB and truncate the confirmation prompt it feeds. **Stop here when the invocation was the audit action** (report-only).
3. **Interview with prescribed defaults** (AskUserQuestion, recommended option listed first) — default (mutating) action only:
   - **Scope** — default: **top-10** COMPRESS-classified files, highest expected yield first (report-only / decline remains available); alternates: top-N (user picks N), all COMPRESS, include UNCERTAIN, stop after audit (report only). Downgraded from "all COMPRESS" after the 2026-08-15 calibration run (87 consecutive auto-reverts) — see `context/fan-out-orchestration.md` circuit breaker.
   - **Concurrency** — default: 2 concurrent subagents per wave (rate-limit-conservative); alternates: 1 (sequential), 3-5 (`context/fan-out-orchestration.md` default).
   - **Always-loaded files** — default: excluded (SKIP per the 2-3% empirical baseline); including them requires the same explicit opt-in as `--force`.
4. **Confirm and run**: batch default action over the confirmed set, waves per `context/fan-out-orchestration.md`. Every per-file hard rule — semantic-diff dispatch, revert pass, markdownlint, `<3% AND 0 semantic-loss → REVERT` — applies unchanged.

Non-interactive contexts never interview; they take the no-op branch. The fallback adds an entry path only — it changes no compression, verification, or revert semantics.

## Hard rules

- **Semantic-diff dispatch is mandatory for default action.** Audit is read-only — no dispatch.
- **Post-edit `markdownlint-cli2` MUST pass** (using the consuming repository's markdownlint config when present). Non-zero exit blocks ship; revert and surface failures. `markdownlint-cli2` is **required for correctness** (it is the ship gate): if the binary is absent (neither on `PATH` nor as the repo's `node_modules/.bin/markdownlint-cli2`), STOP at the entry point before compressing anything and surface the remediation — install it explicitly (`npm install --save-dev markdownlint-cli2` or a global install); never treat absence as a lint failure and never ship unverified output.
- **Default `<3% AND 0 semantic-loss → REVERT`.** Proven safe in the authoring repo's empirical baseline (always-loaded instruction files: 3/3 attempts reverted). `--force` bypasses.
- **Summary output deterministic.** No timestamps; filenames sort lexically.
- **Snapshot default = ephemeral** (`mktemp -d`, deleted post-dispatch). `--keep-snapshot` persists to `${CLAUDE_PLUGIN_DATA}/snapshots/` instead.
- **Always-loaded instruction-file policy: SOFT-BLOCK.** Default reverts <3%/0SL on ANY file including `.claude/rules/**` / `AGENTS.md` / `CLAUDE.md` / `**/SKILL.md`. `--force` bypasses on ANY file — user owns the result. `audit` heuristic emits informational SKIP recommendation on always-loaded paths citing the 2-3% empirical baseline; not a structural gate.
- **Subagent dispatch follows `context/semantic-diff-prompt.md` template.** Findings must carry verifiable citations; training-recall citation tokens are forbidden — `[known]` / `[from memory]` / `[context]` / `[obvious]` / `[standard]` / `[usual]`.
- **Backend choice does NOT bypass semantic-diff dispatch.** When the caveman backend is absent or unwanted, `/docs-hygiene:compress` falls back to in-session Edit-based compression. Backend selection determines only the mechanical-compression path; semantic-diff + revert pass + markdownlint hard rules apply regardless. LLM-compression fabrication risk (caveman backend OR in-session Edit) caught structurally by the revert pass.

## Output schema (default action, per target)

```text
<basename>: <action_taken> (compression_pct=N.N%, semantic_loss=K, ambiguity=M, false_positive=P, markdownlint=PASS|FAIL)
```

`action_taken` ∈ {`compressed`, `reverted`, `skipped`}. Aggregate at end of batch.

Audit action output: table with `target`, `expected_yield_pct`, `classify` (SKIP/COMPRESS/UNCERTAIN), `reason`.

## Gotchas

Observed failure points — each traces to a real incident; grown iteratively.

- **Self-audit drifts toward EXPANSION.** The semantic-diff dispatch must run as a SEPARATE fresh-context audit, never a self-audit by the model that produced the edits — self-audit re-adds words just removed ("preserve clarity"; an observed failure — see ## Sources). Prefer a cross-vendor advisor for that audit **when one is installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the stated fallback, never a route to a command that may not resolve (per `docs/PLUGIN-PHILOSOPHY.md` "Fresh-eyes checkpoints" in the marketplace repository). Subagents cannot reliably spawn the verifier themselves (nested subagent support is version-dependent, and a fresh-context verifier beats self-critique regardless), so for batch fan-out follow `context/fan-out-orchestration.md`: the main session dispatches separate compress + audit subagents, reconciling per finding.
- **Sub-3% diffs auto-revert unless `--force`.** Default `<3% AND 0 semantic-loss → REVERT`; always-loaded instruction files bound at 2-3% yield (see ## Sources). Pass `--force` only when a targeted sub-3% diff is intentional — the user owns the result.
- **Caveman writes a `<file>.original.md` backup beside the target.** The caveman backend hardcodes this backup path; running it against the real file litters the repo. Backend Step B wraps caveman in a `mktemp -d` tempdir so the backup lands there and the `trap` cleans it; a gitignore entry for `**/*.original.md` in the consuming repo is optional belt-and-suspenders.

## When NOT to use

- Code files (`.cs`, `.py`, `.ts`, `.sh`, etc.) — methodology is markdown-specific. Code-comment compression is out of scope
- Binary files
- Author-time-disciplined instruction files (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`) — `audit` will SKIP-recommend; sub-3% revert default applies (Gotchas "Sub-3% diffs auto-revert unless `--force`")
- Conversation summarization or session compaction — that's the built-in `/compact`, different semantic
- **Subagent context invoking `/docs-hygiene:compress` for batch fan-out** — see Gotchas "Self-audit drifts toward EXPANSION"; follow `context/fan-out-orchestration.md`

## What this skill is NOT

- **Not an orchestrator surface.** `/docs-hygiene:compress` prints a human-readable summary; no structured/`--json` output
- **Not a lint front-end.** `markdownlint-cli2` is the post-edit verifier, not the primary purpose
- **Not a code-comment compressor.** Out of scope
- **Not a `/code-review` / `/simplify` shadow.** The bundled `/code-review` and `/simplify` skills review code changes; `/docs-hygiene:compress` rewrites markdown prose. Different concerns
- **Not `/docs-hygiene:audit-noise`.** `/docs-hygiene:compress` owns FLAVOR (filler, hedging, articles, redundant restatement). `/docs-hygiene:audit-noise` owns NOISE classification (historical citations, ghost refs, "Why this file exists" preambles, hard-coupled enumerated consumer lists) per its own taxonomy. Different concerns; both may apply to the same target iteratively
- **Not a content-relocation / cite-don't-recap tool.** When an inline passage recaps detail that already lives in a cited single source of truth (another doc or rule), condensing it is content RELOCATION, not flavor removal — the mandatory semantic-diff net sees the words gone from THIS file and reverts them as SEMANTIC LOSS, blind to the SSOT. Apply "reference, don't duplicate" as a MANUAL editorial pass (verify the cited SSOT actually holds the detail first — an unread pointer is an unverified claim); use `/docs-hygiene:extract-ssot` when the duplicated cluster spans 3+ files

## Sources

- Always-loaded instruction-file yield bound (2-3%): authoring-repo baseline, 3/3 compression attempts reverted, all flavor-only, 0 semantic loss
- Self-audit expansion drift: authoring-repo batch compression wave, 2026-05-23 — 4/4 reverse-direction edits from self-audit (`context/fan-out-orchestration.md` ## History)

## Cross-references

- `context/semantic-diff-prompt.md` — subagent dispatch template (Agent tool prompt + return-format contract)
- `context/flavor-vs-content-matrix.md` — canonical FLAVOR / CONTENT taxonomy + per-content-type variants
- `context/target-types.md` — per-action argument shapes + author-time-signal heuristic
- `context/fan-out-orchestration.md` — multi-phase batch fan-out recipe; read when compressing N files via parallel subagents (keeps the semantic-diff in a separate fresh-context auditor)
- `context/integration.md` — composition contract with sibling skills and consumer workflows
