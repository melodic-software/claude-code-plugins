# Authoring conventions — a new audit-style skill inside an existing plugin

Extracted from the repo as it stands. This is convention extraction only: every rule below is
observed in shipped code or enforced by a gate, with the file path that owns it. No design
decisions.

Primary exemplars (read these before writing anything):

- `plugins/code-tidying/skills/audit-comment-residue/` — the closest structural sibling
  (SKILL.md + `scripts/detect.sh` + `scripts/detect.test.sh` + `scripts/lib/comment-shapes.sh` +
  `evals/evals.json` + `evals/fixtures/`)
- `plugins/docs-hygiene/skills/audit-noise/` — same shape, one generation more evolved
  (`--offset/--limit` chunking, nameref hot path, two libs)
- `plugins/docs-hygiene/skills/audit-derivability/` — audit skill with no detector script
- `plugins/mutation-testing/skills/audit/`, `plugins/codebase-health/skills/audit/` — phased
  (non-classifier) audit shape; different body grammar, same frontmatter grammar

---

## 1. Directory layout

```text
plugins/<plugin>/skills/<skill-name>/
  SKILL.md                       # required
  scripts/detect.sh              # the detector entry point (mode 100755)
  scripts/detect.test.sh         # self-contained test suite (mode 100755)
  scripts/lib/<topic>-shapes.sh  # sourceable helper, NO shebang (mode 100644)
  evals/evals.json               # required in practice — see §7
  evals/fixtures/<fixture files> # every fixture must be consumed — see §7.3
  context/*.md | reference/*.md  # optional progressive-disclosure spokes
```

Observed modes (`git ls-files -s plugins/code-tidying/skills/audit-comment-residue/`):

```text
100644 SKILL.md
100644 evals/evals.json
100644 evals/fixtures/residue-snippet.py
100755 scripts/detect.sh
100755 scripts/detect.test.sh
100644 scripts/lib/comment-shapes.sh
```

A file carrying a shebang **must** have the exec bit (CI step "Verify shebang files are
executable", `.github/workflows/ci.yml`). `lib/*.sh` carries no shebang — it opens with
`# shellcheck shell=bash` instead — so it stays 100644.

Naming: the leaf directory name IS the command name. Per `docs/PLUGIN-PHILOSOPHY.md` §Naming, a
skill name is an **imperative verb phrase**; `audit` means "read-only findings report; mutation
only behind an explicit user override, never on bare invocation". When a bare `audit` would
collide with or under-specify against a sibling in the same namespace, a **topic qualifier follows
the verb with a hyphen** (`audit-noise` beside `audit-encapsulation`, `audit-comment-residue`
beside `tidy`).

Cross-plugin leaf-name collisions are registered in `scripts/skill-leaf-name-registry.txt` and
gated by `scripts/check-skill-leaf-names.sh --check`. A qualified name like `audit-dead-code`
avoids the registry entirely; a bare `audit` in a new plugin would require adding that plugin to
the existing `audit` owner set:

```text
audit claude-config,claude-memory,codebase-health,github,machine-health,mcp-tools,mutation-testing,plugin-quality,repo-fleet-hygiene,testing
```

---

## 2. SKILL.md frontmatter

### 2.1 Fields actually used (fleet-wide counts over `plugins/*/skills/*/SKILL.md`)

| Key | Count | Notes |
|---|---|---|
| `description` | 207 | Required. Always a **double-quoted single-line scalar**. |
| `user-invocable` | 202 | Always `true` on audit skills. |
| `disable-model-invocation` | 190 | `false` on audit skills. (`true` is mandatory only for `setup` skills — enforced by `scripts/validate-plugin-contracts.mjs`.) |
| `argument-hint` | 181 | Quoted string. |
| `metadata` | 139 | Block with `workflow-stage` + `summary`. |
| `shell` | 71 | `shell: bash` — required when `!` injections use bash-only syntax (check 19). |
| `allowed-tools` | 18 | JSON array form on all script-backed audit skills. |
| `disallowed-tools` | 3 | Rare; e.g. `Edit, NotebookEdit`. |
| `hooks` | 2 | Not relevant here. |

**No `name:` key.** `docs/PLUGIN-PHILOSOPHY.md` §Naming: "A plugin skill declares no frontmatter
`name`." The directory name is the name. `skill-quality` check 1 FAILs a divergent `name` and
WARNs on a redundant one.

`metadata` sub-keys in use: `workflow-stage` (139), `summary` (139), `cadence` (13, required iff
`workflow-stage: operator`, forbidden otherwise), plus vendor-sync keys (`upstream-version`,
`synced`, `upstream-sha`) that do not apply here.

### 2.2 Verbatim exemplar frontmatter

`plugins/code-tidying/skills/audit-comment-residue/SKILL.md`:

```yaml
---
description: "Classify code comments for four residue shapes — history narration (\"used to… now…\"), plan/session references (\"Task 2 replaces the old…\", \"in this PR\"), conversational antecedents (\"per your request\", \"as you asked\"), and ticket/PR/branch back-references a future reader will never see — emitting Tier 1 (remove) and Tier 2 (review) findings with treatment guidance; read-only, no edits applied. Use when: 'comment residue', 'audit code comments', 'find stale/narrative comments', 'strip conversational comments', or before committing agent-written code — not for removing ALL comments, restating-the-code redundancy (that is /code-tidying:tidy's Beck tidyings), or markdown noise (use /audit-noise)."
argument-hint: "[audit] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Classify code comments for history narration and session-reference residue
---
```

`plugins/docs-hygiene/skills/audit-noise/SKILL.md` is byte-for-byte the same schema with
`workflow-stage: anytime`.

### 2.3 How `description` is worded (the house formula)

One double-quoted line, three clauses in this order:

1. **What it does + the finding vocabulary + the output tiers + the read-only contract.**
   `"Classify code comments for four residue shapes — <shape>, <shape>, <shape>, <shape> — emitting
   Tier 1 (remove) and Tier 2 (review) findings with treatment guidance; read-only, no edits
   applied."`
2. **`Use when:` followed by single-quoted trigger phrases, comma-separated**, ending with a
   natural-language trigger moment.
   `"Use when: 'comment residue', 'audit code comments', 'find stale/narrative comments', 'strip
   conversational comments', or before committing agent-written code"`
3. **A `— not for …` clause routing the adjacent concerns to their owning skills**, each named by
   its slash invocation.
   `"— not for removing ALL comments, restating-the-code redundancy (that is /code-tidying:tidy's
   Beck tidyings), or markdown noise (use /audit-noise)."`

Hard constraints on this field:

- Single-quoted trigger phrases are load-bearing: `skill-quality` check 3 tracks them across a diff
  and FAILs a rewrite that drops one (trigger-keyword preservation, `skill_frontmatter::extract_triggers`
  in `plugins/skill-quality/scripts/skill-frontmatter.sh`). Check 12 WARNs when the description
  carries no single-quoted `Use when` phrasing.
- `description` + `when_to_use` ≤ **1536 characters** (check 2, per-skill listing-entry cap).
- Prefer a single-line quoted scalar over a block scalar (the listing budget encourages it).
- Because plugin skills render as `(<plugin-name>) <description>` in the picker, the description's
  **first clause must name its object** (`docs/PLUGIN-PHILOSOPHY.md` §Naming, closing paragraph).

### 2.4 `argument-hint`

Bracketed action/arg grammar, quoted. Classifier siblings:

- `argument-hint: "[audit] [target]"` (audit-comment-residue, audit-noise)
- `argument-hint: "[audit] [target] | sweep <dir>"` (audit-derivability)
- `argument-hint: "[scope] [--full] [--paths <globs>] [--max <n>] [--no-suppress] [--persist-findings]"` (mutation-testing/audit)
- `argument-hint: "[detect|sweep|fix <file>:<line>|file-issues]"` (audit-encapsulation)

### 2.5 `allowed-tools` scoping

The rule the repo learned the hard way — `plugins/code-tidying/CHANGELOG.md` `## [0.10.0]`:

> `${CLAUDE_PLUGIN_ROOT}` is not substituted in `allowed-tools` — only `${CLAUDE_SKILL_DIR}` and
> `${CLAUDE_PROJECT_DIR}` are — so the rule stayed a literal string and never matched.

and:

> `Bash(bash *audit-comment-residue/scripts/detect.sh*)` matched because its leading and trailing
> wildcards absorbed both the `bash` wrapper and the quotes around the body's path. That is the
> wildcarded-interpreter shape auto mode drops outright… The change is **paired**: the bodies
> invoke their scripts directly and unquoted, and the rules name the same strings.

Therefore, for a new script-backed audit skill:

- Grant form: `"Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)"` — no `bash` wrapper, no leading
  wildcard, `${CLAUDE_SKILL_DIR}` (never `${CLAUDE_PLUGIN_ROOT}`).
- The SKILL.md body must invoke the script the **same way**: `${CLAUDE_SKILL_DIR}/scripts/detect.sh`,
  direct and unquoted. A grant and a body that disagree is a dead grant.
- Add only the narrow read helpers the body actually uses: `"Bash(grep:*)"`, `"Bash(head:*)"`,
  `"Bash(echo:*)"`.
- Governing convention: `docs/conventions/permission-rule-hygiene/README.md` (anti-patterns
  P1 interpreter-wildcard, P2 hardcoded machine path, P3 inert self-grant), enforced by
  `/claude-config:audit-permission-grants`.

### 2.6 `metadata` block

```yaml
metadata:
  workflow-stage: review        # or: anytime
  summary: Classify code comments for history narration and session-reference residue
```

- `workflow-stage` must be one of the slugs in `scripts/cheatsheet-config.mjs` `STAGES`:
  `contract, explore, research, plan, implement, test, review, verify, retro, pr, anytime,
  session, operator`. Audit-classifier siblings use `review` (code-tidying) or `anytime`
  (docs-hygiene). It is **required** unless the skill matches an exclusion entry —
  `scripts/generate-cheatsheet.mjs` fails on silent omission.
- `summary` must be a **plain YAML scalar ≤ 100 Unicode codepoints** (check 22 FAILs above that;
  `summaryError()` in `scripts/cheatsheet-config.mjs` also rejects a leading
  `[ ] { } > | * & ! % @ \` " ' # -`, tabs, and control characters). It is the generated cheat
  sheet's row text, so it reads as a terse imperative-less noun phrase describing the finding:
  `Classify markdown for stale citations, ghost refs, and meta-commentary`.
- `cadence` only with `workflow-stage: operator`.

---

## 3. SKILL.md body — section grammar

### 3.1 Headings across the exemplars

`plugins/code-tidying/skills/audit-comment-residue/SKILL.md`:

```text
## Pre-computed context
## Purpose
## Residue shapes and treatments
## Action router
## Auto-detect default
## Hard rules
## Output schema
## What this skill is NOT
## Sources
```

`plugins/docs-hygiene/skills/audit-noise/SKILL.md`:

```text
## Pre-computed context
## Purpose
## Existence pre-check (before in-page noise)     <- skill-specific
## Noise shapes and treatments
## Action router
## Auto-detect default
## Hard rules
## Output schema
## What this skill is NOT
## Sources
```

`plugins/docs-hygiene/skills/audit-derivability/SKILL.md`:

```text
## Pre-computed context
## Purpose
## The rubric — four factors, never derivability alone
## Verdict classes
## Audience-awareness
## Establishing derivability
## Action router
## Auto-detect default
### Repo-wide escalation — prescribed defaults
## Output schema
## Hard rules
## Gotchas
## What this skill is NOT
## Sources
## Recheck triggers
```

Phased (non-classifier) audit shape, `plugins/mutation-testing/skills/audit/SKILL.md`:

```text
## Pre-computed context
## Variables
## Argument parsing
## The contract this skill holds
## Phase 0 — Preflight … ## Phase 6 — Persist (opt-in)
## Remediation — delegated
## Gotchas
## What this skill does NOT do
```

`plugins/codebase-health/skills/audit/SKILL.md`: `## Pre-computed context`, `## Variables`,
`## Argument Parsing`, `## Read-only default`, `## Adapting to your environment (graceful degrade)`,
`## Audit dimensions & targets (tracked config seam)`, `## Emit checklist`, `## Phase 0: Prime
Context` … `## Phase 3: Categorize & Present`, `## Remediation (delegated to other plugins)`.

### 3.2 Universal vs skill-specific

**Universal to every audit skill** (present in all four exemplars):

- `## Pre-computed context` — always first, always immediately after frontmatter.
- `## Purpose` (phased variants substitute `## Variables` + `## Argument parsing` + a contract
  section, but every skill opens with a why).
- A read-only/remediation-delegation statement (`## Hard rules` in classifiers, `## Read-only
  default` / `## The contract this skill holds` in phased skills).
- An output-shape section (`## Output schema` / `## Output format` / `## Output shape (detect mode)`).
- A negative-space section: `## What this skill is NOT` (classifiers) or `## What this skill does
  NOT do` (phased). Both spellings are live; the classifier family uses **is NOT**.

**Universal to the classifier family specifically** (audit-comment-residue, audit-noise,
audit-derivability — the pattern a new detector-backed audit skill should copy):

`## Pre-computed context` → `## Purpose` → `## <Topic> shapes and treatments` (or `## The rubric` /
`## Verdict classes`) → `## Action router` → `## Auto-detect default` → `## Hard rules` →
`## Output schema` → `## What this skill is NOT` → `## Sources`.

**Skill-specific / optional:** `## Existence pre-check`, `## Gotchas` (WARN-level check 11 asks for
a gotchas surface — inline `## Gotchas` or `context/gotchas.md`; 11 of the audit-family skills ship
one), `## Recheck triggers`, `## Cross-references`, `## Sanity checks`, `## Anti-patterns guarded`.

### 3.3 `## Pre-computed context`

Verbatim, audit-comment-residue:

```markdown
## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted code files: !`git status --porcelain 2>/dev/null | awk '{print $NF}' | grep -Ei '\.(cs|ts|tsx|js|jsx|py|sh|ps1|go|rs|java|rb|lua|sql|c|h|cpp|hpp|yaml|yml|toml)$' | head -10 || echo "none"`
Residue findings (sample): !`${CLAUDE_SKILL_DIR}/scripts/detect.sh 2>/dev/null | grep -E '^(Summary total:|Finding shape:)' | head -20 || echo "none"`
```

Rules:

- `Label: !`command`` per line, one line per injection.
- **Every injection ends in `|| <fallback>`** with a known string (`"unknown"`, `"none"`,
  `"(unavailable)"`). Check 20 WARNs on an injection with no fallback.
- Redirect stderr: `2>/dev/null`.
- Declaring `shell: bash` is required when the injection uses bash-only syntax (check 19 FAILs
  bash-only syntax with no `shell:`; WARNs on portable-looking-but-undeclared).
- Known warn-only tension: `scripts/check-skill-precompute-compose.sh` reports
  `VIOLATION: … — 3 precompute lines with a git command (#1619 composition rule)` for **both**
  exemplars today. The gate is warn-only (`--strict` not yet enabled in CI: "Report precompute
  git+multi-line violations (warn-only)"). Copying the 3-line shape reproduces that warning; a
  2-line-or-fewer block with a git command, or a multi-line block with no git command, avoids it.

### 3.4 `## Action router`

A three-column table, `Action | Args | Behavior`, with the default (no-keyword) row first:

```markdown
| Action | Args | Behavior |
|---|---|---|
| `<target>` (default, no action keyword) | empty → uncommitted code files from git; file path → single-file; dir path → batch | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` on targets; map the emitted facts to the per-file tier table using the treatments above |
| `audit [target]` | same target rules | explicit form of the default; same behavior |
```

audit-noise adds a deferral note under the table: "Single action v1; `relocate` and `generalize`
actions are deferred until real demand surfaces".

### 3.5 `## Auto-detect default`

A numbered precedence list, always ending with the explicit-action-keyword rule:

```markdown
1. Empty arg AND no uncommitted code files → friendly no-op exit 0 ("No uncommitted code files. Pass a file/dir target.")
2. Empty arg AND uncommitted code files → batch audit over those files
3. Single file path → single-file audit
4. Directory path → batch audit (filenames sorted lexically for deterministic output)
5. First positional == `audit` → audit on rest (explicit form)
```

audit-noise substitutes rule 1 with an **offer** rather than a silent no-op, and cites the shared
shape at `../../context/clean-tree-fallback.md`.

### 3.6 Composition / shapes table

The heart of a classifier: `| Shape | What it looks like | Default tier | Treatment |`, one row per
finding shape, each `Shape` cell a backticked kebab-case token that is also the literal string the
detector emits. Followed by the consumer-override sentence:

> Consumers with their own comment conventions can refine these defaults in their repo's
> `CLAUDE.md` / rules; the classifier's shapes and tiers above are the skill's built-in baseline.

### 3.7 `## Hard rules`

Bulleted, each bullet opening with a **bold** rule name and a period:

```markdown
- **Read-only.** No `Edit`, no `Write`, no mutating `Bash` ops. The author owns every deletion.
- **Tier semantics.** Tier 1 = residue to remove; Tier 2 = review needed …
- **Code files only.** Markdown is `/docs-hygiene:audit-noise`'s territory and is skipped …
- **Comment-scoped detection.** Only the comment portion of a line is classified …
- **`TODO(#issue)` is sanctioned.** …
- **Opt-out markers respected.** `comment-residue-ignore` on a line (or the line before it) skips it.
- **Output deterministic.** Filenames sort lexically; findings sort by line number; no timestamps.
```

The **Read-only**, **Tier semantics**, **Opt-out markers respected**, and **Output deterministic**
bullets appear in every classifier. audit-noise adds: "a finding whose ruling includes an edit
('strip', 'relocate', 'replace') is Tier 2 or 1 by definition."

### 3.8 `## Output schema`

Two fenced ```text blocks — the per-file table, then the batch aggregate — followed by the shape
enumeration line:

````markdown
```text
<file>: N finding(s) — T1=<n>, T2=<n>

| Tier | Shape | Line | Excerpt | Treatment |
|------|-------|------|---------|-----------|
| 1    | history-narration | 42 | "// used to buffer; now flushes" | Delete — version control owns history |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited, <T1> Tier 1, <T2> Tier 2 findings.
```

`shape` values: `history-narration`, `plan-reference`, `conversational-antecedent`, `ticket-pr-residue`.
````

### 3.9 `## What this skill is NOT` and `## Sources`

- `is NOT`: 3–4 bullets, each **bold-led**, each naming the sibling that DOES own the excluded
  concern by slash invocation, plus a closing "Not an Edit operation" bullet.
- `## Sources`: markdown link list, `[Title](url) — why this source is cited`.

### 3.10 Length caps

- SKILL.md **< 500 lines** (check 4, FAIL).
- SKILL.md **≤ 200 lines** soft target (check 10, WARN — progressive disclosure; overflow goes to
  `context/` or `reference/` spokes). audit-comment-residue is 103 lines; audit-noise 140.
- Every backtick-cited skill-internal supporting file must resolve (check 5, FAIL).
- Companion spoke dirs must be referenced from SKILL.md (check 15, WARN — orphan spokes).

---

## 4. Shell script conventions

### 4.1 Detector entry script (`scripts/detect.sh`)

Header, verbatim from `plugins/code-tidying/skills/audit-comment-residue/scripts/detect.sh`:

```bash
#!/usr/bin/env bash
# Comment-residue findings for /audit-comment-residue. Read-only.
#
# Output: File, Finding tier/shape/line/excerpt; Summary lines.
# Exit: always 0 on audit paths — a read-only audit must never fail the caller,
# so -e is omitted; 2 on unknown arguments.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/comment-shapes.sh
source "$SCRIPT_DIR/lib/comment-shapes.sh"
```

- Shebang: `#!/usr/bin/env bash` (never `#!/bin/bash`).
- Strict mode: **`set -u` only** in a detector — `-e` is deliberately omitted and the reason is
  documented in the header ("a read-only audit must never fail the caller"). Test scripts and
  repo-level gates use `set -uo pipefail`; `set -euo pipefail` appears only in strict gates like
  `scripts/check-detector-findings-crosswalk.sh`.
- Self-locate with `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, then
  `source "$SCRIPT_DIR/lib/<lib>.sh"` preceded by a `# shellcheck source=lib/<lib>.sh` directive.
- Every script documents its own `Exit:` taxonomy in the header comment. Per
  `docs/conventions/shell-test-helpers/README.md`, exit-code taxonomies **diverge deliberately**
  per script; there is no shared enum. Detector taxonomy in this family: **0 = audit ran (findings
  or not), 2 = usage/unknown argument, and `--help` exits 0.**
- `usage()` is a `cat <<'EOF'` heredoc naming the script, its usage lines, its scope, and the exit
  codes. Reached by `-h | --help`.

### 4.2 Argument loop

Long-flag `while [[ $# -gt 0 ]]; do case "$1" in … esac; done` with these arms:
`--paths-file` (value-taking), `-h | --help`, `--` (everything after is a target), `-*` → unknown
arg to stderr + `exit 2`, `*` → positional target. audit-noise factors value-checking into a
helper and adds chunking flags:

```bash
require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "detect.sh: $opt requires a value" >&2
    exit 2
  fi
}
```

and `--offset N --limit N` — "chunk affordance over the sorted target list … Repo-wide
orchestration can invoke one detect.sh process per chunk without a per-file shell loop."

### 4.3 Path anchoring, cwd, CRLF

Both detectors `cd` to the repo root, so caller-relative paths must be anchored **before** the cd:

```bash
INVOCATION_CWD="$PWD"

cr_anchor_path() {
  case "$1" in
  /* | ?:[\\/]*) printf '%s' "$1" ;;          # POSIX or Windows drive-letter absolute
  *) printf '%s/%s' "$INVOCATION_CWD" "$1" ;;
  esac
}
```

`repo_root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"` — note the `tr -d '\r'`.
Every line read from a file or from `git status` is CRLF-scrubbed: `line="${line//$'\r'/}"`.

Determinism: `mapfile -t SORTED < <(printf '%s\n' "${TARGETS[@]}" | LC_ALL=C sort -u)`.

Empty-array safety uses the `${ARR[@]+"${ARR[@]}"}` idiom (required under `set -u` on bash 4).

### 4.4 Output format — the `Finding shape:` / `Summary total:` protocol

The detector emits **flat key-value records**, not tables; SKILL.md maps them into the table. One
record per finding, terminated by a `---` line:

```bash
printf 'File: %s\n' "$file"
printf 'Finding tier: %s\n' "$tier"
printf 'Finding shape: %s\n' "$shape"
printf 'Finding line: %s\n' "$line_num"
printf 'Finding excerpt: %s\n' "$excerpt"
printf '%s\n' '---'
```

Per-file footer and global footer:

```bash
printf 'Summary file: %s | T1=%s T2=%s T3=%s\n' "$file" "$t1" "$t2" "$t3"
printf 'Summary total: files=%s T1=%s T2=%s T3=%s\n' "$files_audited" "$total_t1" "$total_t2" "$total_t3"
```

Zero-target early exit prints the summary anyway plus a `Note:` line, then `exit 0`:

```bash
echo "Summary total: files=0 T1=0 T2=0 T3=0"
echo "Note: no code targets — pass code file paths or edit some tracked code files"
exit 0
```

`Summary total:` and `Finding shape:` are the two line prefixes the SKILL.md pre-compute greps for
(`grep -E '^(Summary total:|Finding shape:)'`), so their spelling is a contract.

Excerpts are trimmed to 120 chars with an ellipsis (`cr_trim_excerpt`), leading whitespace stripped.

### 4.5 `scripts/lib/` helper structure

`plugins/code-tidying/skills/audit-comment-residue/scripts/lib/comment-shapes.sh`:

```bash
# shellcheck shell=bash
# Shared comment-residue detectors for /audit-comment-residue (sourceable; not invoked directly).
# Shape definitions and treatments: the skill's SKILL.md "Residue shapes and treatments".
```

- **No shebang, no exec bit** — it is sourced, never run. First line is the `# shellcheck shell=bash`
  directive so standalone shellcheck knows the dialect.
- Header cites the SKILL.md section that owns the semantics ("Shape definitions and treatments: the
  skill's SKILL.md '<Shapes>' section"). The lib never redefines the taxonomy; SKILL.md owns it.
- Every function is prefixed with a short skill-scoped namespace: `cr_*` in comment-residue,
  `audit_noise_*` in audit-noise. Pick one and use it on every symbol.
- The canonical function set is:
  `<ns>_trim_excerpt`, `<ns>_is_<target>_file`, `<ns>_line_skipped` (opt-out markers),
  `<ns>_detect_shapes` (emits zero or more shape names, one per line on stdout),
  `<ns>_shape_tier` (maps shape → tier, `*)` default returns tier 3).
- Detection heuristics carry a comment stating the limit honestly, e.g.
  "Heuristic, not a full per-language lexer: … which is sufficient for a read-only audit."
- Performance idiom (audit-noise, later generation): nameref out-params to avoid a subshell per
  line — `audit_noise_detect_shapes_into shapes "$line"`, `local -n _out="$2"`. The comment marks
  it: "Hot path: nameref APIs only — no per-line command substitutions."
- Per `docs/conventions/shell-test-helpers/README.md`, these helpers are **deliberately not**
  shared across plugins. Do not reach into a sibling plugin's lib and do not add the new lib to
  `scripts/cross-plugin-source-registry.txt`.

### 4.6 Portability (`scripts/check-shell-portability.sh`)

The gate scans **changed `**/*.sh` files AND changed skill markdown under `plugins/*/skills/`**.
`scripts/shell-portability-skill-md-baseline.txt` grandfathers only *existing* debt and explicitly
says: "Do NOT add a path here to dodge the gate on NEW work." New files must be clean.

Banned constructs (the active ERE lines of `scripts/shell-portability-tokens.txt`), all because
macOS/BSD userland rejects or silently reinterprets them:

| Class | Banned |
|---|---|
| GNU regex escapes | `\b`, `\<`, `\>`, `\s`, `\S`, `\w`, `\W` (anywhere — including inside a quoted regex, and including in SKILL.md prose/commands) |
| grep | `grep -P` / `--perl-regexp` |
| echo | `echo -e` |
| sort | `sort -V` / `--version-sort` / `--sort=version` |
| sed | `sed -i` / `sed --in-place`; `&` as an unescaped replacement in `s///` (class `!subst-replacement-ampersand`) |
| readlink | `readlink -f` / `--canonicalize` |
| date | `date -d` / `--date` |
| stat | `stat -c` / `--format` / `--printf` |
| mktemp | `mktemp -p` / `--tmpdir` |

Use POSIX-portable equivalents instead: `[[:space:]]`, `[[:alnum:]_]` and explicit boundary
character classes, `printf` instead of `echo -e`, `LC_ALL=C sort`, a temp-file + `mv` instead of
`sed -i`, `mktemp -d` with no `-p`. The exemplar libs are the reference: they use
`[[:space:]]`/`[[:alpha:]]` bracket expressions throughout and never a GNU escape.

Three reviewer-visible escapes exist (script header, lines 70–86) and only for a genuine need:

1. an auto-recognized same-line BSD-counterpart guard (`realpath … || readlink -f …`);
2. a per-site `portability-ok: <reason>` marker on the hit line or in the contiguous comment block
   directly above it;
3. a whole-file `# portability-scope: <reason>` declaration — reserved for the gate's own fixture
   corpora, "not for excusing a real shipped script's real coupling."

Comment-only lines are skipped for construct matching, so documenting `date -d` in prose is fine;
a live command is not.

Separately, `scripts/check-skill-portability.sh` gates changed **skill** files against
`scripts/skill-portability-tokens.txt` — currently `origin/(main|master)` and `Clean Arch(itecture)?`.
Do not hardcode `origin/main`; resolve the default branch on the hit line, or annotate
`portability-ok: <reason>`.

Portability also means Bash 4+: `mapfile`, `${var,,}` case conversion, and namerefs are used
throughout, and `plugins/code-tidying/README.md` declares the Bash 4+ requirement with its Windows
(Git Bash) path.

---

## 5. Test script conventions (`scripts/detect.test.sh`)

### 5.1 Structure

```bash
#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib — ships with the
# plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
```

Assertion primitives, copied verbatim in both exemplars (the "skill-script shape" of
`docs/conventions/shell-test-helpers/README.md` — duplicate them, do not share them):

```bash
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: %s\n' "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1)); FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit()         { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains()     { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "contains: $3" "$2" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "absent: $3" "present" ;; *) pass "$1" ;; esac; }
```

Final report:

```bash
if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
```

### 5.2 Fixtures and sectioning

- Fixtures are **built inline in the tmpdir** with `cat >"$F" <<'EOF'` — the shipped
  `evals/fixtures/` files are for the eval grader, not for the unit tests.
- Cases are grouped under banner comments:
  `# --- 3b. String-aware extraction: leader inside a string is not a comment -------------`
- Each group carries a prose comment explaining the regression it guards.

### 5.3 The case set the exemplar covers (copy this coverage map)

1. `--help` exits 0; unknown flag exits 2.
2. Every shape detected, with its tier (`assert_contains "$out" "Finding shape: <shape>"`,
   `"Finding tier: 2"`, `"Summary file: $F"`).
3. Clean fixture: near-miss vocabulary and sanctioned exceptions **not** flagged
   (`assert_not_contains`).
4. Opt-out markers suppress wrapped content while a control finding still fires.
5. Out-of-scope target type yields `files=0`.
6. Directory target expands recursively.
7. `--paths-file` input; `--paths-file` with a missing value exits 2 under `timeout 10` (guards an
   infinite arg-loop spin).
8. Relative targets stay anchored to the caller cwd when invoked from a repo subdirectory
   (`git -C "$REPO8" init -q`, then `(cd "$SUBDIR" && bash "$DETECT" rel.py)`).

### 5.4 Discovery and CI

- `scripts/run-plugin-tests.sh` discovers `find plugins .claude/hooks -type f -name '*.test.sh' | sort`
  and runs `bash "$t"` on each. **A `*.test.sh` anywhere under `plugins/` runs in CI automatically —
  no registration.** CI step: "Run plugin contract tests".
- Skips are never silent: a test that needs an absent optional tool prints `SKIP: <reason>` (or
  `DISCRIMINATING SKIP:`) and exits 0; the runner counts and names them.
- `scripts/affected-tests.sh` selects suites by rule R2 (co-located `<stem>.test.sh`), so the
  `detect.sh` → `detect.test.sh` naming is what makes the new detector reachable from the
  affected-suite selector. A changed file mapping to no suite is a hard error.
- `skill-quality` check 7 also runs `scripts/*.test.sh` inside the skill under gate.

---

## 6. Lint / validation gates a new skill must pass

| Gate | Where | What it means for a new audit skill |
|---|---|---|
| markdownlint (`markdownlint-cli2`) | ci.yml "Lint markdown"; `.markdownlint-cli2.jsonc` | ATX headings, dash bullets, `*emphasis*` / `**strong**`, backtick fenced blocks, sibling-only duplicate headings. MD013 line-length, MD033 inline HTML, MD034 bare URLs, MD036 bold-as-heading, MD040 fence language, MD041 first-line-H1 are all **off**. |
| shellcheck | ci.yml "Lint shell scripts" (whole repo, unconditional) | Every `.sh` must be shellcheck-clean. Use `# shellcheck source=lib/x.sh` on the source line and `# shellcheck shell=bash` at the top of a sourceable lib. Inline `# shellcheck disable=SCxxxx` needs a trailing reason comment (existing style). |
| editorconfig-checker | ci.yml "Check editorconfig conformance"; `.editorconfig`, `.editorconfig-checker.json` | UTF-8, LF, final newline, **no trailing whitespace except in `*.md`**, `[*.{sh,bash}] indent_size = 2`, `[*.{json,...}] indent_size = 2`. IndentSize and MaxLineLength checks are disabled. |
| typos | ci.yml "Spell-check"; `_typos.toml` | New domain vocabulary (shape names, marker tokens) must either be real words or routed upstream to `melodic-software/standards`; per-line escape is `# spellchecker:disable-line`. |
| actionlint | ci.yml "Lint workflows" | Only if you touch `.github/workflows/` — a new skill normally does not. |
| check-jsonschema | ci.yml "Validate marketplace manifest" / "Validate plugin manifests" / "Validate every eval set against the bundled schema" | `evals/evals.json` is validated against `plugins/skill-quality/reference/evals.schema.json`; plugin.json against the Claude Code plugin-manifest schema. |
| `scripts/check-changed-skills.sh <base>` | ci.yml "Gate changed skills on the static skill-quality contract" | Runs `plugins/skill-quality/scripts/check-skill.sh` over every changed skill. **A new or modified `SKILL.md` is run with `--require-evals`, so a missing `evals/evals.json` FAILs.** |
| `check-evals-quality.sh` | ci.yml "Lint every eval set for quality" | Q1–Q4 FAIL, Q5–Q9 WARN. See §7.2. |
| `scripts/check-skill-portability.sh <base>` | ci.yml | No `origin/main` / `Clean Architecture` hardcoding in changed skill files. |
| `scripts/check-shell-portability.sh <base>` | ci.yml | §4.6 constructs banned in changed `.sh` **and** changed SKILL.md. |
| `scripts/check-orphaned-fixtures.sh --check` | ci.yml | Every file under `evals/fixtures/` must be consumed by the sibling `evals.json` (`files[]` entry or basename token) or by a `*.test.*` in the plugin. |
| `scripts/check-changelog-parity.sh` (`--check`, `--check-bump`, `--check-preserved`, `--check-order`) | ci.yml | §8.3. |
| `scripts/validate-plugins.sh` → `generate-catalog.mjs --check`, `generate-cheatsheet.mjs --check`, `validate-plugin-contracts.mjs`, `claude plugin validate` | ci.yml "Validate plugin and catalog manifests" | The generated blocks in `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` must be regenerated. |
| `scripts/validate-plugin-contracts.mjs` | via validate-plugins.sh | Skill markdown must not reference `@melodic-software`, `melodic-software/github-iac`, or a `MELODIC_*` env var ("reusable skill content must not require publisher-specific runtime identifiers"). |
| `scripts/check-skill-precompute-compose.sh --all` | ci.yml | Warn-only today (§3.3). |
| `scripts/check-lane-coverage.sh --check` | ci.yml | Only matters if you add a CI job. |
| exec-bit / machine-specific-paths / gitleaks / EOL-drift / comment-hygiene | ci.yml hygiene lane | Exec bit on shebanged files; no `/home/<user>` or `C:\Users\<name>` literals; no secrets. |

`skill-quality`'s twenty-two checks (`plugins/skill-quality/scripts/check-skill.sh` header) that a
new audit skill must clear: 1 frontmatter parses + description present + no divergent `name`;
2 listing-entry cap ≤ 1536 chars; 3 trigger-keyword preservation (skipped for a new skill);
4 SKILL.md < 500 lines; 5 backtick-cited internal files resolve; 6 markdownlint;
7 `scripts/*.test.sh` pass; 13 no committed cache/build artifacts; 14 evals presence (FAIL under
`--require-evals`); 19 `shell:` declared for bash-only injections; 22 `metadata.summary` ≤ 100
codepoints. WARN-level: 10 ≤ 200 lines, 11 gotchas surface, 12 quoted `Use when` phrasing,
15 orphan spokes, 18 precompute opportunity, 20 injection fallback, 21 fresh-eyes declaration.

Run locally before pushing:

```shell
bash plugins/skill-quality/scripts/check-skill.sh --require-evals <skill-name>   # via CHECK_SKILL_SKILLS_ROOT
bash plugins/<plugin>/skills/<skill>/scripts/detect.test.sh
bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/<plugin>/skills/<skill>/evals/evals.json
scripts/check-shell-portability.sh --paths plugins/<plugin>/skills/<skill>/SKILL.md plugins/<plugin>/skills/<skill>/scripts/detect.sh
scripts/check-orphaned-fixtures.sh --check
node scripts/generate-catalog.mjs && node scripts/generate-cheatsheet.mjs
scripts/check-changelog-parity.sh --check
```

---

## 7. `evals/evals.json`

### 7.1 Schema

Owned by `plugins/skill-quality/reference/evals.schema.json` (draft 2020-12,
`additionalProperties: false` at both levels).

Top level — required `skill_name` (string, minLength 1, "Skill directory name … Matches the slug
used by the slash invocation") and `evals` (array, minItems 1).

Each case — required `id` (integer or non-empty string) and `prompt` (non-empty string), **plus at
least one grading criterion**: a non-empty `expected_output`, a non-empty `expectations`, or a
non-empty `assertions`. Optional: `name` (kebab-case, `^[a-z0-9]+(-[a-z0-9]+)*$`), `files`
(array of non-empty strings), `narration` (boolean — opt out of the Q4 prose-path warning).

`expectations` is this repo's field name across rich-form skills; `assertions` is the upstream
skill-creator name. Pick one — carrying both WARNs (Q5).

Exemplar shape (`plugins/code-tidying/skills/audit-comment-residue/evals/evals.json`):

```json
{
  "skill_name": "audit-comment-residue",
  "evals": [
    {
      "id": 1,
      "name": "classify-residue-shapes-with-tiers",
      "prompt": "Audit code comments for residue: read evals/fixtures/residue-snippet.py relative to the skill directory and classify what you find.",
      "expected_output": "Emits a per-file tier table: the 'used to batch writes … now flushes' comment as history-narration (Tier 1), … each with delete/review treatment guidance. No edits are applied.",
      "files": ["evals/fixtures/residue-snippet.py"],
      "expectations": [
        "Output classifies findings by the skill's shape vocabulary (history-narration, plan-reference, conversational-antecedent, ticket-pr-residue)",
        "The 'used to … now flushes' comment is flagged as history-narration",
        "The 'see PR #45' comment is flagged as ticket-pr-residue at Tier 2",
        "The output is a classification report with tiers and treatments; no file is edited"
      ]
    }
  ]
}
```

Fixture reference form: **skill-relative** — `"files": ["evals/fixtures/residue-snippet.py"]` — and
the prompt says "relative to the skill directory". Cases with no fixture use `"files": []`.

### 7.2 Eval-quality lint (`plugins/skill-quality/scripts/check-evals-quality.sh`)

FAIL: Q1 duplicate `id`; Q2 duplicate `name`; Q3 non-gradeable criterion (empty/whitespace item);
Q4 a `files` entry that resolves to nothing under the skill dir or evals dir, or escapes them via
an absolute path or `..`.
WARN: Q5 both `expectations` and `assertions`; Q6 two cases with identical prompt+files;
Q7 vague criterion phrasing; Q8 a sole `expected_output` thinner than the minimum;
Q9 **set-level coverage — no case exhibiting refusal/guardrail or anti-pattern language**.

### 7.3 The six-case pattern both classifier exemplars ship

1. `classify-<topic>-shapes-with-tiers` — the happy path, with a real fixture in `files[]`.
2. `read-only-even-when-asked-to-fix` — the guardrail case: prompt explicitly asks for edits, the
   expectation is that no Edit/Write occurs. (This is what satisfies Q9's refusal requirement.)
3. A sanctioned-exception case (`sanctioned-todo-not-flagged`).
4. A false-positive case (`code-word-not-in-comment-not-flagged`).
5. A "not a blanket sweep" case (`not-delete-all-comments`).
6. A routing case handing an out-of-scope target to the sibling skill
   (`markdown-is-audit-noise-not-comment-residue`).

Fixtures: audit-comment-residue ships exactly one (`evals/fixtures/residue-snippet.py`, 15 lines)
containing one instance of every shape plus two clean controls. Every shipped fixture must be
referenced from `files[]` or a test, or `scripts/check-orphaned-fixtures.sh --check` fails.

---

## 8. Registration / wiring checklist

Adding a skill to an existing plugin touches **six** things beyond the skill directory itself.
There is no skill registry: `plugin.json` has **no** `skills` key (see
`plugins/code-tidying/.claude-plugin/plugin.json` — only `$schema`, `name`, `version`,
`description`, `author`, `license`, `keywords`), and skills are discovered from
`plugins/<plugin>/skills/*/SKILL.md`.

### 8.1 `plugins/<plugin>/.claude-plugin/plugin.json`

- **`description` — yes, update it.** The house convention is that the description enumerates every
  skill by slash invocation. Current code-tidying description names all three:
  "…`/code-tidying:tidy` proactively hunts …; `/code-tidying:batch-simplify` sweeps …;
  `/code-tidying:audit-comment-residue` is a read-only classifier that flags …". This string is the
  source `docs/CATALOG.md` is generated from, so a new skill that is not named there is invisible
  in the catalog.
- **`version` — bump.** See §8.3.
- `keywords` — extend if the new skill introduces a genuinely new keyword (code-tidying added
  `"comments"` for audit-comment-residue).

### 8.2 `plugins/<plugin>/README.md`

Update the skill roster. `plugins/code-tidying/README.md` opens with "Three skills, one capability:"
followed by one bold-led bullet per skill:

```markdown
- **`/code-tidying:tidy`** — proactively hunts a rotated, glob-scoped *lane* of
  the codebase for safe structural improvements …
```

The count word ("Three skills") is prose that must be updated with the roster.

### 8.3 `plugins/<plugin>/CHANGELOG.md`

Format (`plugins/code-tidying/CHANGELOG.md` header):

```markdown
# Changelog

All notable changes to the `code-tidying` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.10.3]

### Changed

- …
```

Rules enforced by `scripts/check-changelog-parity.sh`:

- `--check`: a plugin whose manifest carries a `version` must ship a sibling `CHANGELOG.md`, and
  its **newest heading must not exceed the manifest version**.
- `--check-bump <ref>`: a manifest version change must **ADD** a `## [<version>]` entry — present at
  head, absent at the base ref. Touching the file is not enough; reusing an existing heading is not
  enough. A heading written as `## <version>` without brackets is a FORMAT failure. The bump must be
  **strictly greater** than the base-ref version.
- `--check-preserved <ref>`: a touched changelog may not drop a `## [<v>]` heading it carried at the
  fork point.
- `--check-order`: newest-first, no duplicate versions.
- Headings are bare `## [x.y.z]` — the fleet has dropped dates from recent entries (older entries
  such as `## [0.8.2] — 2026-07-21` in docs-hygiene keep them).
- Section headings are Keep-a-Changelog verbs: `### Added`, `### Changed`, `### Fixed`.

**Semver bump for a new skill: minor.** Observed precedent — every `### Added` entry that introduces
new capability sits under a `0.x.0` heading (`docs-hygiene` `## [0.14.0] ### Added`,
`code-tidying` `## [0.4.0] ### Added`); patch releases carry only `### Changed`/`### Fixed`. A
skill rename is also minor and is marked **BREAKING** in the entry text
(`code-tidying` `## [0.6.0]`: "**BREAKING — the `comment-residue` skill renamed to
`audit-comment-residue`**"). Entry style: bold lead sentence naming the change, then the specifics,
with issue numbers in parentheses where one exists.

### 8.4 `.claude-plugin/marketplace.json` (repo root)

The plugin's entry is `{ "name", "source", "category", "tags" }` — **no skill list**. Only touch it
if the new skill justifies a new tag or a category change. It is validated by check-jsonschema, by
`scripts/check-manifest-duplicate-keys.py`, and by `claude plugin validate --strict .`, and it owns
category + ordering for the generated catalog.

### 8.5 Generated docs — regenerate, never hand-edit

- `docs/CATALOG.md` — block between `<!-- catalog:start -->` / `<!-- catalog:end -->`, generated by
  `node scripts/generate-catalog.mjs` from marketplace.json (category/order) + plugin.json
  (description). CI runs `--check`.
- `docs/SKILL-CHEAT-SHEET.md` — block between `<!-- cheatsheet:start -->` / `<!-- cheatsheet:end -->`,
  generated by `node scripts/generate-cheatsheet.mjs` from each SKILL.md's `metadata.workflow-stage`
  / `summary` / `cadence` plus `scripts/cheatsheet-config.mjs`. CI runs `--check`. A new skill with
  no `workflow-stage` and no exclusion entry **fails the generator**. The emitted row:

  ```markdown
  | [`/code-tidying:audit-comment-residue`](../plugins/code-tidying/skills/audit-comment-residue/SKILL.md) | `code-tidying` | Classify code comments for history narration and session-reference residue |
  ```

Both are covered by `scripts/validate-plugins.sh`; run `node scripts/generate-catalog.mjs && node
scripts/generate-cheatsheet.mjs` after editing plugin.json or the new frontmatter.

### 8.6 Registries that usually need nothing (verify, then leave alone)

- `scripts/skill-leaf-name-registry.txt` — only if the new leaf name collides with a leaf in another
  plugin (`scripts/check-skill-leaf-names.sh --check` fails on an unregistered collision).
- `scripts/orphaned-fixtures-baseline.txt` — never add a new fixture here; make it consumed.
- `scripts/shell-portability-skill-md-baseline.txt` — never add new work here.
- `scripts/cross-plugin-source-registry.txt` — the skill's `scripts/lib/` is per-plugin by design.
- `docs/conventions/detector-findings/README.md` + `scripts/check-detector-findings-crosswalk.sh`
  — only if the new skill persists a findings file for `/review:fanout`'s apply relay
  (`--persist-findings` shape, as in `plugins/mutation-testing/skills/audit`).
- `scripts/affected-tests-no-suite.txt` — not needed; the co-located `detect.test.sh` maps the new
  files automatically.

---

## 9. Sources (paths, for the implementation agent)

- `plugins/code-tidying/skills/audit-comment-residue/{SKILL.md,scripts/detect.sh,scripts/detect.test.sh,scripts/lib/comment-shapes.sh,evals/evals.json,evals/fixtures/residue-snippet.py}`
- `plugins/docs-hygiene/skills/audit-noise/{SKILL.md,scripts/detect.sh,scripts/detect.test.sh,scripts/lib/noise-shapes.sh,evals/evals.json}`
- `plugins/docs-hygiene/skills/audit-derivability/SKILL.md`, `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md`
- `plugins/mutation-testing/skills/audit/SKILL.md`, `plugins/codebase-health/skills/audit/SKILL.md`
- `plugins/code-tidying/{README.md,CHANGELOG.md,.claude-plugin/plugin.json}`
- `plugins/skill-quality/scripts/{check-skill.sh,check-evals-quality.sh,skill-frontmatter.sh}`,
  `plugins/skill-quality/reference/evals.schema.json`, `plugins/skill-quality/skills/check/SKILL.md`
- `scripts/{check-shell-portability.sh,shell-portability-tokens.txt,shell-portability-skill-md-baseline.txt}`
- `scripts/{check-skill-portability.sh,skill-portability-tokens.txt,check-changed-skills.sh,check-orphaned-fixtures.sh,check-changelog-parity.sh,check-skill-leaf-names.sh,skill-leaf-name-registry.txt,check-skill-precompute-compose.sh}`
- `scripts/{run-plugin-tests.sh,affected-tests.sh,validate-plugins.sh,validate-plugin-contracts.mjs,generate-catalog.mjs,generate-cheatsheet.mjs,cheatsheet-config.mjs}`
- `docs/PLUGIN-PHILOSOPHY.md` (§Naming, §Instruction economy), `docs/conventions/shell-test-helpers/README.md`,
  `docs/conventions/permission-rule-hygiene/README.md`, `docs/conventions/detector-findings/README.md`
- `.github/workflows/ci.yml`, `.markdownlint-cli2.jsonc`, `.editorconfig`, `.editorconfig-checker.json`, `_typos.toml`
