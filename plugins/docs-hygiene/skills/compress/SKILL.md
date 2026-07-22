---
name: compress
description: "Compress (tighten, shorten, trim) markdown files by dropping flavor — filler, hedging, articles — while preserving all content (directives, qualifiers, thresholds, examples), with a mandatory semantic-diff subagent that reverts any SEMANTIC LOSS or AMBIGUITY. Use when: \"compress this doc\", \"tighten markdown\", \"cut prose\", \"shorten without losing meaning\", \"trim onboarding doc\", or verbose prose in docs/, READMEs, rule bodies, skill bodies, or third-party pasted text — actions: default (snapshot → backend → semantic-diff subagent → revert-pass → markdownlint) and audit (read-only dry-run classifying SKIP/COMPRESS/UNCERTAIN per file); flags: --force (bypass <3% revert rule), --keep-snapshot; not for: session compaction (/compact), markdown noise classification (/audit-noise), code-comment trimming, or content relocation/SSOT consolidation (/extract-ssot)."
argument-hint: "[audit] [target] [--force] [--keep-snapshot]"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files: !`git status --porcelain 2>/dev/null | grep '\.md$' | head -10 || echo "none"`

## Purpose

Markdown in `docs/`, README files, onboarding docs, third-party pasted prose, and drifted skill bodies accumulates FLAVOR — filler ("just", "really", "basically"), hedging ("perhaps", "might"), articles, pleasantries, redundant restatement. `context/flavor-vs-content-matrix.md` defines FLAVOR (safe to cut) vs CONTENT (never cut); this skill applies that taxonomy AT EDIT TIME to content where author-time discipline does NOT apply.

Always-loaded instruction files (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`) bound empirically at 2-3% yield (baseline from the authoring repo: 3/3 attempts reverted, all flavor-only, 0 semantic loss). Likely 5-15% yield on author-time-undisciplined content.

Methodology: snapshot original → backend mechanical compression (the `caveman` plugin via `/caveman:compress`, OR in-session Edit fallback) → spawn semantic-diff subagent comparing original vs condensed (output: SEMANTIC LOSS / AMBIGUITY / FALSE POSITIVE per finding with verbatim citations) → revert every SEMANTIC LOSS + AMBIGUITY → run `markdownlint-cli2` → ship or revert.

## Backend selection

Default-action Step B picks the mechanical-compression backend: the `caveman` plugin (marketplace `caveman`, invoked as `/caveman:compress`) when present, otherwise the in-session Edit-based fallback. Caveman performs the mechanical flavor cuts (articles, fillers, hedging, verbose-verb collapses) as the compression backend — it is NOT the verification gate. Fallback policy is graceful: the in-session Edit-based path substitutes whenever caveman is absent or unwanted. Subsequent steps (semantic-diff dispatch, revert pass, markdownlint) wrap the output regardless of backend choice.

Note the distinction inside that plugin: `/caveman:compress` is a function-call skill (this skill's backend); `/caveman:caveman` is a session-wide response formatter — unrelated to this skill.

**Step A — detect caveman plugin:** `bash "${CLAUDE_SKILL_DIR}/scripts/detect-caveman.sh"`

**Step B — caveman backend (preferred):**

```bash
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT
cp "$target" "$tempdir/$(basename "$target")"
# Invoke caveman via Skill tool on tempdir copy:
#   Skill(caveman:compress, args="$tempdir/$(basename "$target")")
# Caveman writes compressed output to tempdir/basename and backup to tempdir/<basename>.original.md.
# Both stay inside tempdir; trap cleans on EXIT.
cp "$tempdir/$(basename "$target")" "$target"  # only on caveman success
```

Tempdir wrapper contains caveman's hardcoded `<file>.original.md` backup write. Real-path file replaced atomically on success. Consumers may add a defensive `**/*.original.md` entry to their `.gitignore` as belt-and-suspenders against tempdir cleanup races or future caveman backup-path-convention changes.

**Step B fallback — in-session Edit (caveman absent or disabled):**

Agent applies Edit ops directly on `$target` per the `context/flavor-vs-content-matrix.md` taxonomy. Same flavor-vs-content rules; no backend indirection.

**Step C+ unchanged:** semantic-diff dispatch (mandatory hard rule), revert pass for SEMANTIC LOSS / AMBIGUITY / UNCERTAIN findings, markdownlint-cli2, summary.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted `.md` from `git diff`; file path → single-file; dir path → batch | snapshot → backend → dispatch → revert-pass → markdownlint verify → summary |
| `audit [target]` | same target rules | read-only dry-run; compute expected-yield heuristic per `context/target-types.md`; classify SKIP/COMPRESS/UNCERTAIN |

Flags (apply to both actions):

- `--force` — proceed even when the default `<3% AND 0 semantic-loss → REVERT` rule would trip. User owns the sub-3% diff
- `--keep-snapshot` — persist the original to `${CLAUDE_PLUGIN_DATA}/snapshots/<ISO-basic>Z-<basename>.orig.md` (the plugin data directory survives plugin updates)

## Auto-detect default

1. Empty arg AND clean tree → friendly no-op exit 0 ("No uncommitted .md files. Pass file/dir target.")
2. Empty arg AND uncommitted `.md` files → batch default action over those files
3. Single file path → single-file default action
4. Directory path → batch default action (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit action on rest

## Hard rules

- **Semantic-diff dispatch is mandatory for default action.** Audit is read-only — no dispatch.
- **Post-edit `markdownlint-cli2` MUST pass** (using the consuming repository's markdownlint config when present). Non-zero exit blocks ship; revert and surface failures. `markdownlint-cli2` is **required for correctness** (it is the ship gate): if the binary is absent (neither on `PATH` nor as the repo's `node_modules/.bin/markdownlint-cli2`), STOP at the entry point before compressing anything and surface the remediation — install it explicitly (`npm install --save-dev markdownlint-cli2` or a global install); never treat absence as a lint failure and never ship unverified output.
- **Default `<3% AND 0 semantic-loss → REVERT`.** Proven safe in the authoring repo's empirical baseline (always-loaded instruction files: 3/3 attempts reverted). `--force` bypasses.
- **Summary output deterministic.** No timestamps; filenames sort lexically.
- **Snapshot default = ephemeral** (`mktemp -d`, deleted post-dispatch). `--keep-snapshot` persists to `${CLAUDE_PLUGIN_DATA}/snapshots/` instead.
- **Always-loaded instruction-file policy: SOFT-BLOCK.** Default reverts <3%/0SL on ANY file including `.claude/rules/**` / `AGENTS.md` / `CLAUDE.md` / `**/SKILL.md`. `--force` bypasses on ANY file — user owns the result. `audit` heuristic emits informational SKIP recommendation on always-loaded paths citing the 2-3% empirical baseline; not a structural gate.
- **Subagent dispatch follows `context/semantic-diff-prompt.md` template.** Findings must carry verifiable citations; training-recall citation tokens are forbidden — `[known]` / `[from memory]` / `[context]` / `[obvious]` / `[standard]` / `[usual]`.
- **Backend choice does NOT bypass semantic-diff dispatch.** When the caveman backend is absent or unwanted, `/compress` falls back to in-session Edit-based compression. Backend selection determines only the mechanical-compression path; semantic-diff + revert pass + markdownlint hard rules apply regardless. LLM-compression fabrication risk (caveman backend OR in-session Edit) caught structurally by the revert pass.

## Output schema (default action, per target)

```text
<basename>: <action_taken> (compression_pct=N.N%, semantic_loss=K, ambiguity=M, false_positive=P, markdownlint=PASS|FAIL)
```

`action_taken` ∈ {`compressed`, `reverted`, `skipped`}. Aggregate at end of batch.

Audit action output: table with `target`, `expected_yield_pct`, `classify` (SKIP/COMPRESS/UNCERTAIN), `reason`.

## Gotchas

Observed failure points — each traces to a real incident; grown iteratively.

- **Self-audit drifts toward EXPANSION.** The semantic-diff dispatch must run as a SEPARATE fresh-context audit, never a self-audit by the model that produced the edits — self-audit re-adds words just removed ("preserve clarity"). Prefer a cross-vendor advisor for that audit when one is installed — e.g. the OpenAI Codex plugin's `/codex:review` — with the fresh-context same-vendor subagent as the fallback, never a route to a command that may not resolve. Empirically observed in the authoring repo: 4/4 reverse-direction edits in one batch compression wave. Subagents cannot reliably spawn the verifier themselves (nested subagent support is version-dependent, and a fresh-context verifier beats self-critique regardless), so for batch fan-out follow `context/fan-out-orchestration.md`: the main session dispatches separate compress + audit subagents, reconciling per finding.
- **Sub-3% diffs auto-revert unless `--force`.** Default `<3% AND 0 semantic-loss → REVERT`; always-loaded instruction files bound at 2-3% yield (empirical baseline: 3/3 reverted, all flavor-only). Pass `--force` only when a targeted sub-3% diff is intentional — the user owns the result.
- **Caveman writes a `<file>.original.md` backup beside the target.** The caveman backend hardcodes this backup path; running it against the real file litters the repo. Backend Step B wraps caveman in a `mktemp -d` tempdir so the backup lands there and the `trap` cleans it; a gitignore entry for `**/*.original.md` in the consuming repo is optional belt-and-suspenders.

## When NOT to use

- Code files (`.cs`, `.py`, `.ts`, `.sh`, etc.) — methodology is markdown-specific. Code-comment compression is out of scope
- Binary files
- Author-time-disciplined instruction files (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`) — `audit` will SKIP-recommend; sub-3% revert default applies (Gotchas "Sub-3% diffs auto-revert unless `--force`")
- Conversation summarization or session compaction — that's the built-in `/compact`, different semantic
- **Subagent context invoking `/compress` for batch fan-out** — see Gotchas "Self-audit drifts toward EXPANSION"; follow `context/fan-out-orchestration.md`

## What this skill is NOT

- **Not an orchestrator surface.** `/compress` prints a human-readable summary; no structured/`--json` output
- **Not a lint front-end.** `markdownlint-cli2` is the post-edit verifier, not the primary purpose
- **Not a code-comment compressor.** Out of scope
- **Not a `/code-review` / `/simplify` shadow.** The built-in `/code-review` and `/simplify` review code changes; `/compress` rewrites markdown prose. Different concerns
- **Not `/audit-noise`.** `/compress` owns FLAVOR (filler, hedging, articles, redundant restatement). `/audit-noise` owns NOISE classification (historical citations, ghost refs, "Why this file exists" preambles, hard-coupled enumerated consumer lists) per its own taxonomy. Different concerns; both may apply to the same target iteratively
- **Not a content-relocation / cite-don't-recap tool.** When an inline passage recaps detail that already lives in a cited single source of truth (another doc or rule), condensing it is content RELOCATION, not flavor removal — the mandatory semantic-diff net sees the words gone from THIS file and reverts them as SEMANTIC LOSS, blind to the SSOT. Apply "reference, don't duplicate" as a MANUAL editorial pass (verify the cited SSOT actually holds the detail first — an unread pointer is an unverified claim); use `/extract-ssot` when the duplicated cluster spans 3+ files

## Cross-references

- `context/semantic-diff-prompt.md` — subagent dispatch template (Agent tool prompt + return-format contract)
- `context/flavor-vs-content-matrix.md` — canonical FLAVOR / CONTENT taxonomy + per-content-type variants
- `context/target-types.md` — per-action argument shapes + author-time-signal heuristic
- `context/fan-out-orchestration.md` — multi-phase batch fan-out recipe; read when compressing N files via parallel subagents (keeps the semantic-diff in a separate fresh-context auditor)
- `context/integration.md` — composition contract with sibling skills and consumer workflows
