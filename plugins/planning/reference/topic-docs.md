# Topic-docs resolution — where planning artifacts land

How every planning skill resolves the destination for its per-topic artifacts. All pipeline
skills read this one document; none bakes its own placement rules.

Implements the marketplace-wide topic-docs convention (tiers, resolution order, slug spec,
lifecycle):
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.

## The two tiers (planning's kinds)

Placement follows document nature: a document something downstream enforces against is a
**contract**; everything else is **working memory**.

| Tier | Location (default) | Git | Planning writes |
|---|---|---|---|
| Contract slice | `docs/topics/<topic-slug>/` | Committed on the task branch only; pruned before merge | `PRD.md`; `PLAN.md` (Brief + Plan); `design/` — ALL design artifacts, including the `design-threads.md` / `design-resolution.md` gate files and working design exploration docs (gate files must travel with the branch) |
| Memory slice | `.work/<topic-slug>/` | Never committed (the root is self-ignoring) | `interview-checklist.md`, `architect-checklist.md`, `baselines/` (machine-bound captures), opt-in `brainstorm.md`, resume notes, raw scratch |

`contract_tier: local` (solo/offline mode): contract kinds join the memory slice under
`.work/<topic-slug>/` with an identical layout, and the PR-description paste becomes the only
publication surface. The default is `branch` because sibling worktrees, PR-babysit checkouts,
and cloud clones see only committed content.

## Resolution order (six rungs, earlier wins)

1. `.claude/topic-docs.yaml` present → use it (the consumer-side SSOT; schema in the
   convention's `topic-docs.schema.json`).
2. A working-docs convention declared in the consumer's `CLAUDE.md` / `.claude/rules` → use
   it, and offer to persist it into the concern file.
3. A legacy `notes_dir` userConfig value → the deprecation grace path (below).
4. An existing conforming layout inferred from the repo → confirm with the user, persist to
   the concern file.
5. Ask once — one question, `branch` (RECOMMENDED) vs `local`; persist the answer to the
   concern file via `/planning:setup`.
6. The documented defaults: `docs/topics` + `.work`, `contract_tier: branch`.

**No project root** (no git toplevel or project marker): interactive → ask (current
directory or an explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/`
with the absolute path announced prominently and nothing persisted.

## Legacy grace — old pins until migrated

When old-convention content exists — `.claude/notes/<topic-slug>/` holds topic content, or
`notes_dir` is set (read the single
`pluginConfigs["planning@melodic-software"].options.notes_dir` key from the consumer's
settings, never a settings file wholesale; "set" means a value differing from its documented
`.claude/notes` default, or the configured directory already holds topic content) — operate
**wholly** on the old location,
reads AND writes, and emit a deprecation notice naming `/planning:setup` as the migration
path. New defaults apply to fresh repos and fresh topics only. Never dual-write; never split
one topic across roots. The `notes_dir` knob and this dual-read are removed at the plugin's
next major version.

## Slug spec

- Derivation precedence (one source wins): explicit argument → the Brief/PRD topic → the
  current branch name.
- Form: kebab-case `[a-z0-9-]`, ≤ 40 chars, truncated on a hyphen boundary; branch `/` maps
  to `-`; no leading or trailing hyphen or dot; Windows-reserved base names
  (`con prn aux nul com1-9 lpt1-9`) take an `-x` suffix.
- Same derived slug + existing contract dir on the branch = **resume**. A genuinely new task
  disambiguates with a scope qualifier or an ISO date suffix — never a bare ordinal.
- The same slug names the topic in both tiers; timestamps in filenames are ISO-basic UTC
  (`YYYYMMDDTHHMMSSZ`).

## Runtime guards

- **Committed-tier guard:** the first contract-slice write in a session runs
  `git check-ignore -v` on the target path. If a consumer ignore rule matches, stop and
  surface the exact rule — never silently produce an uncommittable "committed" tier.
- **Self-ignore guard:** every memory-slice write verifies the memory root contains a
  `.gitignore` with `*`, creating it (announced) when absent.
- No planning skill ever edits the consumer's root `.gitignore`.

## Lifecycle (contract slice)

Contracts commit on the task branch as they lock. At PR time the approved `PLAN.md` is pasted
into the PR description inside a `<details>` block. Before merge, durable outcomes graduate
through the knowledge-vault seam (default backend: history-preserving `git mv` into
`docs/adr/` / `docs/specs/`) and actionable follow-ups through the work-item tracker seam;
a final commit prunes `docs/topics/<topic-slug>/`, leaving context pointers.
`/planning:architect` describes the close-out. Committed evidence is distilled — no raw
command captures, machine-local absolute paths, usernames, or credentials; raw output stays
in `.work/<topic-slug>/`.
