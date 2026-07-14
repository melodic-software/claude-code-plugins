# Topic-docs placement — where discovery artifacts land

How `/discovery:explore`, `/discovery:explore-deep`, `/discovery:research`, and
`/discovery:research-deep` resolve where generated documents land in a consuming repo. These skills
read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, concern-file schema, slug spec, and lifecycle; this document binds
this plugin's artifacts to it.

## What this plugin writes

Discovery writes **memory tier only** — working documents nothing downstream enforces against:

| Artifact | Location |
|---|---|
| `EXPLORE.md` (+ `EXPLORE-<scope>.md` sidecars and overflow) | `.work/<slug>/` — never committed |
| `RESEARCH.md` (+ `RESEARCH-<topic>.md` sidecars and overflow) | `.work/<slug>/` — never committed |

The memory root is configurable via the concern file's `memory_dir` key. Discovery never writes the
contract tier (`docs/topics/<slug>/`); the `contract_tier` setting does not change where its
artifacts land.

## Resolution ladder (six rungs, earlier wins)

1. `.claude/topic-docs.yaml` present → use it (the consumer-side SSOT; schema in the convention's
   `topic-docs.schema.json`).
2. A working-docs convention declared in the consumer's `CLAUDE.md` / `.claude/rules` → use it, and
   offer to persist it into the concern file.
3. A legacy `notes_dir` userConfig value (`${user_config.notes_dir}`) → the deprecation grace path
   (below).
4. An existing conforming layout inferred from the repo → confirm with the user, persist to the
   concern file.
5. Ask once — one question, recommended option first; persist the answer to the concern file via
   `/discovery:setup`.
6. The documented default: `.work`.

**No project root** (no git toplevel or project marker): interactive → ask (current directory or an
explicit path); non-interactive → `${CLAUDE_PLUGIN_DATA}/topic-docs/<slug>/` with the absolute path
announced prominently and nothing persisted.

**Forked variants** (`/discovery:explore-deep`, a Tier-2 research subagent) cannot ask the user or
persist the concern file: when resolution would reach an ask-or-persist rung, use the resolved (or
default) value and flag the assumption in the return summary.

## Legacy grace — old pins until migrated

When `.claude/notes/<slug>` holds topic content or `notes_dir` is set, operate **wholly** on the old
location — reads AND writes — and emit a deprecation notice naming `/discovery:setup` as the guarded
migration path. New defaults apply to fresh repos and fresh topics only. Never dual-write; never
split one topic across roots. The `notes_dir` knob and this dual-read are removed at the plugin's
next major version.

## Slug spec

- Derivation precedence (one source wins): explicit argument → the Brief/PRD topic (or the
  exploration/research scope) → the current branch name.
- Form: kebab-case `[a-z0-9-]`, ≤ 40 chars truncated on a hyphen boundary; branch `/` maps to `-`;
  no leading or trailing hyphen or dot; Windows-reserved base names (`con prn aux nul com1-9
  lpt1-9`) take an `-x` suffix.
- Same derived slug + existing directory = **resume** that topic. A genuinely new task
  disambiguates with a scope qualifier or an ISO date suffix — never a bare ordinal.
- Reserved first-level names under the memory root: `handoffs`, `reviews` (a colliding topic slug
  takes the `-x` suffix). The same slug names the topic in both tiers — the traceability bridge.

## Runtime guards

- **Self-ignore guard:** every memory-tier write verifies the memory root contains a `.gitignore`
  with `*`, creating it (announced) when absent — fresh clones heal on first write.
- No discovery skill ever edits the consumer's root `.gitignore`.
