# Artifact Persistence and Template Override

Shared operational contract for every `/songwriting` craft skill: where generated files go, and how
a consuming project overrides a bundled template. Author-neutral layout; the template-override path
is namespaced by author (`pat-pattison`) so a future author's templates layer independently.

## Where generated work persists

Named per-song work (title given, multi-session) persists under the consuming project's root.
Default layout (relative to `${CLAUDE_PROJECT_DIR}`):

| Artifact kind | Default path |
|---|---|
| Per-song work | `songwriting/songs/<slug>/` |
| Pre-title work (brainstorm / idea / fragment) | the song's `ideation/` subfolder |
| Line / section brainstorm output | the song's `variations/` or `worksheets/` |
| Daily practice | `songwriting/practice/<YYYY>/<YYYY-MM-DD>.md` |
| Broader research not tied to one song | `songwriting/research/<topic>.md` |
| Reusable rhyme inventories / audit checklists | `songwriting/shared/` |

Per-song folder anatomy: `PLAN.md` / `BRIEF.md` / `LYRIC.md` / `ideation/` / `variations/` /
`worksheets/` / `research/` / `decisions/` / `journal/`. Slug = song title kebab-cased, lowercase,
no version qualifiers (`v1`, `final`, dates) — one canonical song per slug; rewrites overwrite
within the slug.

**Consumer override:** if the consuming project's `CLAUDE.md` or rules define their own songwriting
artifact layout, that layout wins — the table above is the default, not a mandate.

## Template override

When loading any `templates/<name>.md`, check
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` first — a project-level
override wins over the bundled skill default (first match), so writers layer custom versions without
forking the plugin.

## Output-to-file conventions

When the user asks for variations / multiple options, write each option to a `variations/<line>.md`
file as a labeled menu — don't dump options inline. When introducing a rhyme pair, run the
identity-vs-rhyme check (pre-vowel consonants MUST differ) via the song's
`worksheets/audit-checklist.md` Step 3 before declaring "this rhymes" — identity is NOT rhyme (per
[rhyme-fundamentals](rhyme-fundamentals.md)).
