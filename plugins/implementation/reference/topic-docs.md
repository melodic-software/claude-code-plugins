# Topic-docs placement — where this plugin's artifacts land

How `/implementation:implement`, `/implementation:implement-dispatch`, `/implementation:verify-changes`,
and `/implementation:verify-improvement` resolve where generated documents land in a consuming repo.
These skills read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and prune-with-pointer lifecycle;
this document binds this plugin's artifacts to it.

## What this plugin writes, per tier

| Artifact | Tier | Location |
|---|---|---|
| `PLAN.md` Plan section + progress marks (phase tags, step boxes) | Contract | `docs/topics/<slug>/PLAN.md`, committed on the task branch |
| `DEVIATIONS.md` (autonomous-run deviation log, reviewed at PR time) | Contract | beside `PLAN.md` in the topic's contract slice |
| Verification manifest (distilled, `verified_at_sha`-keyed) | Contract | `docs/topics/<slug>/verification/` |
| Baselines (machine-bound measurements) | Memory | `.work/<slug>/baselines/` — never committed |
| Raw verification captures | Memory | `.work/<slug>/scratch/` |
| Status summary | Memory | `.work/<slug>/` |
| Timestamped handoff notes | Memory | `.work/handoffs/` — `/session-flow:handoff` owns that surface; the fallback note (plugin absent) lands in the same home |

`contract_tier: local` in the concern file (solo/offline mode) moves the contract rows into
`.work/<slug>/` with an identical layout; the PR-description paste becomes the only publication
surface. Roots are configurable via the concern file's `contract_dir` / `memory_dir` keys.

**Redaction bar (contract tier):** committed evidence is distilled — no raw command captures, no
machine-local absolute paths, no usernames or credentials. Raw output stays in `.work/<slug>/`.

## Resolution ladder (six rungs, earlier wins)

1. `.claude/topic-docs.yaml` present → use it.
2. A working-docs convention declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it, and
   offer to persist it into the concern file.
3. A legacy `notes_dir` userConfig value, or existing `.claude/notes/<slug>/` content → **old pins
   until migrated**: operate wholly on the old location (reads AND writes) and emit the deprecation
   notice with a guarded migration command. Never dual-write; never split one topic across roots.
4. An existing conforming layout inferred from the repo → confirm with the user, persist to the
   concern file.
5. Ask once (one question, recommended option first: `branch`); persist the answer via
   `/implementation:setup`.
6. The documented defaults: `docs/topics` + `.work`, `contract_tier: branch`.

## Runtime guards

- **Committed-tier guard:** the first contract-slice write in a session runs `git check-ignore -v`
  on the target path. If a consumer ignore rule matches, STOP and surface the exact rule — never
  silently produce an uncommittable "committed" tier.
- **Self-ignore guard:** every memory-tier write verifies the tier root contains a `.gitignore` with
  `*`, creating it (announced) when absent — fresh clones heal on first write.
- No skill in this plugin ever edits the consumer's root `.gitignore`.

## No project root

No git toplevel or project marker: interactive → ask (create under the current directory, or an
explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/` with the absolute path
announced prominently and nothing persisted.

## Slug

Derivation and form per the contract: explicit argument → Brief/PRD topic → current branch name;
kebab-case `[a-z0-9-]`, ≤ 40 chars. The same slug names the topic in both tiers — that is the
traceability bridge between a plan's contract slice and its working memory.
