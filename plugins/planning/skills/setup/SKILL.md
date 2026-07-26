---
name: setup
description: "Verify and configure the planning plugin for this repository across its two concerns. check inspects read-only the topic-docs seam (.claude/topic-docs.yaml effective values, committed-tier conflict) and the standards index presence; apply resolves where topic documents land (persisting .claude/topic-docs.yaml) and bootstraps the standards index (docs/standards/ and, on relocation, .claude/standards.yaml). Use when: 'set up planning', 'is planning configured', 'configure the planning plugin', 'planning setup', 'where do planning artifacts land', 'set up standards', 'bootstrap the standards index', or a planning skill reports missing or thin config. Re-runnable — safe to invoke again to reconfigure or migrate."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and settle the topic-docs seam for the CONSUMING repo — where the planning pipeline's contract
documents (`PRD.md`, `PLAN.md`, `design/`) and working memory (checklists, baselines, scratch) land —
persisting it to the tracked concern file **`.claude/topic-docs.yaml`**, the consumer-side single
source of truth every consuming plugin resolves first. The file's shape is the convention's
`topic-docs.schema.json`; every key is optional and absent keys mean the documented defaults
(`contract_dir: docs/topics`, `memory_dir: .work`, `contract_tier: branch`, `vault_backend: docs`).
This plugin's binding — its tier table and vault-seam close-out pointer — lives in
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md);
the contract it cites owns the resolution order and runtime guards.

Both concern files are optional: with none, the pipeline uses the documented defaults, so their absence
is a reported INFO, never a FAIL. `check` inspects read-only; `apply` resolves and persists, then
re-runs `check`. No argument or `check` runs the check; `apply` runs the check first, then the
resolve-and-write flow. Idempotent: re-running reads the current state and offers an update rather than
overwriting blind.

## `check` (read-only)

Inspect both concerns and report a PASS/FAIL/INFO table with one remediation line per FAIL. Modify
nothing, and do NOT run a planning stage — those are the pipeline skills.

1. **topic-docs concern file** — read `.claude/topic-docs.yaml` if present and report its effective
   values (absent keys mean the documented defaults). Absent file → INFO: the documented defaults apply;
   `apply` persists a concern file when the repo diverges. A file that does not parse as the schema
   (e.g. a comment-only document YAML parses as null) is FAIL.
2. **Committed-tier conflict** — only when the effective `contract_tier` is `branch` (local mode has no
   committed tier to guard): `git check-ignore -v` on a representative file path inside the chosen
   contract root (e.g. `<contract_dir>/probe/PLAN.md` — a bare directory misses `**` patterns). A
   consumer ignore rule that matches is FAIL: a "committed" tier that git ignores is the failure the
   guard exists to catch; surface the exact rule and source line.
3. **vault_backend** — INFO when the effective `vault_backend` is `gitbook`: GitBook is deferred and
   non-writable; the effective writable promotion target remains `docs` until a later reviewed decision
   enables the backend.
4. **Standards index** — the index presence test at the resolved `<standards_dir>/README.md`
   (`.claude/standards.yaml` may relocate the root from the documented default). Absent → INFO: the
   standards concern is not bootstrapped; `apply` offers to scaffold it. A present index whose
   `standards-contract` frontmatter version is behind the plugin binding's is INFO with the DIRECTIONAL
   version-delta noted (migration runs under `apply`). A present `README.md` that is hand-authored (not
   a conforming index) is INFO, flagged for the `apply` confirmation gate.
5. **Interview-rendering toggle** — INFO: report the effective `use_ask_user_question` value,
   `${user_config.use_ask_user_question}` (unexpanded or empty means the default `false` — the pipeline
   skills' question rounds render as inline prose). This is a native `userConfig` toggle, not a
   consumer-project file; `apply` gives the reconfigure guidance below.

## `apply` (idempotent)

Run `check`, then resolve and persist both concerns. Proceed non-interactively where the invocation and
the repo make the values unambiguous; ask only where a choice genuinely needs the user. No silent
writes — every bootstrap write is user-accepted.

### First concern — topic-docs

1. **Read the current state first.** In order: an existing `.claude/topic-docs.yaml` (report its
   effective values as the baseline — the interview proposes changes against it); a working-docs
   convention declared in the consumer's `CLAUDE.md` / `.claude/rules` (an inference source —
   surface it as the recommended values and offer to persist it into the concern file).
2. **Infer before asking.** With no concern file and no declared convention, look for an existing
   conforming layout (a `docs/topics/`-shaped contract root, a self-ignoring `.work/`) and
   confirm it rather than guessing.
3. **Interview — one decision.** The load-bearing choice is `contract_tier`: **`branch`
   (RECOMMENDED)** — contract documents commit on the task branch, travel to worktrees and cloud
   clones, and are pruned before merge — vs `local` — solo/offline mode; contract kinds join the
   memory tier and the PR-description paste is the only publication surface. Keep `contract_dir`,
   `memory_dir`, and `vault_backend` at their defaults unless the repo's own conventions say
   otherwise — but offer every schema key and preserve every key an existing file carries (a
   re-run never drops one); do not invent knobs beyond the schema. Whenever the effective
   `vault_backend` is (or becomes) `gitbook` — preserved from an existing file, inferred from the
   repo's own `CLAUDE.md` / `.claude/rules`, or chosen by the user during this interview — report
   that GitBook is deferred and non-writable: the effective writable promotion target remains
   `docs` until a later reviewed decision enables the backend. Do not configure or test a GitBook
   API, MCP, or Git Sync writer; offer to replace the key with `docs` only if the user chooses that
   change.
4. **Run the conflict check before writing** — only when the chosen tier is `branch` (local mode
   has no committed tier to guard). `git check-ignore -v` on a representative file path
   inside the chosen contract root (e.g. `<contract_dir>/probe/PLAN.md` — a bare directory misses
   `**` patterns): if a consumer ignore rule matches, STOP and surface the exact rule and
   source line — a "committed" tier that git ignores is the failure the guard exists to catch.
   Resolving the rule is the user's edit to make: **never modify the consumer's root
   `.gitignore`** (or any ignore file this setup did not itself create — the standards root's
   own bootstrap-shipped `.gitignore` below is the one setup-owned exception).
5. **Persist.** Write `.claude/topic-docs.yaml` (tracked, team-shared), recording only the keys
   the user chose — absent keys mean the documented defaults, so an all-defaults answer may
   yield a file with `contract_tier: branch` alone or the schema-valid empty mapping `{}`
   (optionally followed by comments), never a comment-only document, which YAML parses as null.
   Preserve every schema key an existing file carries.

### Second concern — standards bootstrap

Settle where the consumer's **standards** live — the adopted conventions and criteria the
planning skills ground plans in — by implementing the normative "Setup and migration" section of
the plugin's contract binding
[`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md).
The procedure (state reading via the index presence test, the conforming-index short-circuit, the
hand-authored-README confirmation gate, interview, skeleton write, row-path validation,
DIRECTIONAL version-delta detection with guided migration, idempotent re-run) lives there —
implement it by reference, do not restate it. Plugin-side notes only:

- **State reading order:** `.claude/standards.yaml` → index presence test at the resolved
  `<standards_dir>/README.md` → inference sources (existing docs directories, ecosystem configs,
  ambient `CLAUDE.md` content).
- **Bootstrap writes** (interactive, user-accepted — no silent writes): the skeleton index with
  its `standards-contract` frontmatter at the binding's version, and the setup-owned
  `<standards_dir>/.gitignore` containing `*.local.md` (the personal-overlay ignore). Write
  `.claude/standards.yaml` only when the user relocates the root from the documented default.
- **Optional offers, never demands:** pointer-rule generation for indexed ecosystem surfaces
  (interactive only), and reorganizing mixed or spread standards content toward the SRP + index
  shape.
- **Migration is this skill re-run** — no separate action; direction and messaging per the
  binding.

### Interview-rendering toggle

`use_ask_user_question` is a native `userConfig` boolean (default `false`) governing whether the
pipeline skills' question rounds render through `AskUserQuestion` or as inline prose — it is not a
consumer-project file this skill writes. To change it, direct the user to `/plugin configure planning`
(interactive, any time). Headless: `--config` only applies on a fresh install (ignored once installed),
so reconfigure via `claude plugin uninstall planning -s <scope>` then
`claude plugin install planning@<marketplace> -s <scope> --config use_ask_user_question=true`. Both
commands default to `-s user` — pass the scope `claude plugin list` reports for this plugin, and run
from that project's directory for a `project`/`local` scope. Defaulting instead uninstalls a separate
user-scope record while the effective install stays in place, so the reinstall lands at a scope that
does not load. This skill never writes Claude Code user settings or `pluginConfigs`.

### Verify after remediation

Re-run the `check` probes on what was written — the topic-docs conflict check on the persisted tier,
and the standards index presence/row-path validation — and report the actual results, never success on
the write alone.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

A written (or confirmed) `.claude/topic-docs.yaml`, plus — when the standards concern was
exercised — a written (or confirmed-healthy) standards index and its overlay `.gitignore`, a
one-line summary of the effective values, the conflict-check and row-validation results, and how
to re-run this setup to reconfigure or migrate.

## What this skill does NOT do

- Run a planning stage — that is the pipeline skills (`/planning:brainstorm`, `/planning:prd`,
  `/planning:interview`, `/planning:design`, `/planning:design-handoff`,
  `/planning:devils-advocate`, `/planning:plan`). `check` only inspects config.
- Edit the consumer's root `.gitignore` or any ignore file it did not itself create — the
  conflict check surfaces rules; the user resolves them. (The memory root's own self-ignoring
  `.gitignore` is created by the first memory-tier write, announced — not by setup. The single
  setup-owned ignore file is the standards root's bootstrap-shipped `<standards_dir>/.gitignore`.)
- Write anything into the plugin directory or the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}` is for caches and generated state only).
