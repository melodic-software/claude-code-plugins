# Pattern Library — Syntactic Forms

The load-bearing component of `/rename-references`. Each pattern catches references that pure-token grep misses. Empirically derived from a real skill-rename incident where 11 stale references survived 3 sweep passes; each pass found a new form.

## How to read this file

Each pattern has:

- **Form name** — the syntactic shape it catches
- **Regex** — ripgrep-compatible (use Grep tool, not raw shell)
- **Triage default** — which bucket matches land in (per `triage.md`)
- **Example match** — what it catches
- **Known false-positives** — what to expect and how triage handles it

Substitute `<old>` with the actual old token. Anchor patterns with word boundaries (`\b`) wherever possible; use `\B` only for slash-token form.

## Form 1: Slash-prefixed token (skill name)

```regex
\B/<old>\b
```

- **Triage default:** Certain
- **Catches:** `/confirm`, `/test live`, `/<skill-name>` references in prose, tables, and frontmatter
- **Why `\B/`:** word-boundary after slash would match `path/confirm` where slash is a path separator; non-word-boundary before slash means "the slash is not preceded by a word char," which excludes path contexts
- **Why `\b` after:** prevents `/confirm` matching in `/confirmation`
- **False-positives:** none typical — slash + identifier + word-boundary is high-precision

## Form 2: Bare token with word boundary

```regex
\b<old>\b
```

- **Triage default:** Ambiguous if `<old>` is in English-verb blocklist (see `triage.md`); Certain otherwise
- **Catches:** mode names without leading slash (`live`, `e2e`, `outcome`), bare identifiers in prose
- **False-positives:** English-verb collision is the dominant failure mode. Always force ambiguous bucket when token is a common English word.
- **Use case:** `/test live` rename — `live` appears in `context/live.md`, in mode dispatch tables, in prose. Bare-token catches what slash-token misses.

## Form 3: Path references

```regex
context/<old>\.md
skills/<old>/
<old>/SKILL\.md
<old>/(?:context|reference|references|scripts|evals)/
```

- **Triage default:** Certain
- **Catches:** filesystem path references in markdown links, prose mentions, frontmatter `paths:` globs
- **Examples:** `[outcome](context/outcome.md)`, `Read /confirm`, `skills/confirm/research/performance.md`
- **False-positives:** rare — paths are inherently specific
- **Note:** if rename includes a path component (e.g., `/test live` → `/test e2e` renamed `context/live.md` → `context/e2e.md`), include path-form patterns even when args don't explicitly mention paths

## Form 4: Chain prose forward

```regex
(?:→|->|,| and | then )\s*<old>\b
```

- **Triage default:** Chain-context
- **Catches:** workflow chain prose like `→ confirm → retro`, `review, confirm`, `Test, Review, Confirm`, `test and confirm`, `review then confirm`
- **Why this matters:** workflow descriptions appear in frontmatter, README files, and architecture diagrams. Token-only grep misses them because the surrounding `→`/`,` characters anchor the rename context.
- **False-positives:** when `<old>` is a common English word and the comma is enumeration of unrelated items (`apples, oranges, confirm`). Triage forces ambiguous when token is in blocklist.

## Form 5: Chain prose backward

```regex
\b<old>\s*(?:→|->|,| and | then )
```

- **Triage default:** Chain-context
- **Catches:** the other direction — `confirm → retro`, `confirm, retro`, `confirm and retro`
- **Pair with Form 4** in every sweep — they catch different positions in the chain

## Form 6: Numbered table row

```regex
\|\s*\d+\.\s*<old>\s*\|
\|\s*\d+\.\s*<old>\b
```

- **Triage default:** Chain-context
- **Catches:** workflow step tables like `| 7. Confirm |`, `| 7. Confirm | Yes/No/Partial |`, retrospective quick-mode tables, step lists
- **False-positives:** rare — numbered prefix + pipe boundaries are highly specific
- **Variant:** without trailing pipe for tables that don't close columns visibly

## Form 7: Frontmatter chain string

```regex
description:\s*"[^"]*\b<old>\b[^"]*"
when_to_use:\s*"[^"]*\b<old>\b[^"]*"
description:\s*'[^']*\b<old>\b[^']*'
```

- **Triage default:** Certain (when token is enclosed in description chain like `→ <old> →`); Ambiguous otherwise
- **Catches:** SKILL.md frontmatter `description` and `when_to_use` fields containing chain references like `description: "...explore → research → architect → implement → test → review → confirm → retro process..."`
- **Use Grep with `multiline: true`** — frontmatter strings can span lines
- **Why this matters:** frontmatter description is the SKILL discovery surface; stale chain references mean the AI sees outdated workflow vocabulary every time the skill loads

## Form 8: Frontmatter glob set

```regex
\{[^}]*\b<old>\b[^}]*\}
```

- **Triage default:** Certain
- **Catches:** glob patterns enumerating skill/file names like `Sources: '.claude/skills/{explore,research,architect,implement,test,review,confirm,retro}/'`, `paths: ['skills/{a,b,old}/SKILL.md']`
- **False-positives:** rare — comma-separated brace expressions are uncommon outside glob contexts
- **Note:** brace expansion is shell-specific; this catches it in any text context

## Form 9: PascalCase comma-list (workflow verb sequence)

```regex
\b[A-Z][a-z]+(?:\s*,\s*\b[A-Z][a-z]+){2,}
```

- **Triage default:** Chain-context (filter further for known workflow verbs)
- **Catches:** comma-separated sequences of capitalized workflow verbs like `Test, Review, Confirm, Retrospective`, `Explore, Research, Architect, Implement`
- **Why separate from Form 4:** prose chains use lowercase + arrows; PascalCase comma-lists are formal lists in step-name tables, ADR Sources fields, and workflow-pattern documentation
- **Triage refinement:** only flag matches where at least 2 of the comma-separated tokens are known workflow verb names (the rest of the list provides contextual evidence)

## Form 10: Cross-skill mode reference

```regex
auto-triggers?\s+`?/<other-skill>\s+<old>\b
chains?\s+(?:back\s+)?to\s+`?/<other-skill>\s+<old>\b
invokes?\s+`?/<other-skill>\s+<old>\b
```

- **Triage default:** Chain-context
- **Catches:** prose like `auto-triggers /test e2e`, `chains to /verify-changes outcome`, `invokes /test live` — references to a mode of *another* skill. When that other skill renames its mode, the references in the inviting skill go stale.
- **Why this matters:** skill renames (e.g. `/verify` → `/verify-changes`) and mode renames (e.g. `/test live` → `/test e2e`) leave chain prose stale; pure-token grep catches some but not all phrasings.

## Form 11: Line-number-citation shapes

```regex
\.md:[0-9]+
\.md\s+L[0-9]+
```

- **Triage default:** Certain
- **Catches:** `file.md:42` (colon shape) + `file.md L42` (space-L shape) literals in tracked prose. Forward-looking guard — line-number citations rot after ANY edit to the cited file, so they defend against drift after skill renames or doc edits.
- **Allow-listed contexts** (DO NOT flag): fenced code blocks (```); illustrative audit-output tables in skill docs (e.g. demo findings tables in audit-workflow documentation); work-notes paths excluded per `SKILL.md` "Auto-exclusions"
- **False-positives:** domain-specific `L<number>` notation is not caught by the pattern shape unless it carries a `.md` prefix; exempt any path-scoped exceptions the consuming repository defines

## Form 12: Dot-form sub-identifier

```regex
\b<old>\.[\w-]+
```

- **Triage default:** Certain
- **Catches:** dotted identifiers built on the renamed token — action/mode IDs (`verify.runtime-affecting-paths`), dotted config keys, dotted mode/path references. These live in skill bodies, config files, and OTHER skills' dispatch tables. Slash-anchored (Form 1) and path-anchored (Form 3) patterns never reach them; bare-token (Form 2) would bury them in the ambiguous bucket whenever `<old>` is an English verb.
- **Why separate from Form 2:** the trailing `.<identifier>` disambiguates from the English-verb sense — `verify.runtime-affecting-paths` is unambiguously the identifier, so it lands Certain even when `<old>` is in the blocklist. The `[\w-]+` char class excludes `.` so a match cannot gobble across sentence boundaries.
- **False-positives:** rare — `<old>.` followed by a word char is specific. Sentence-end prose (`verify. Then…`) is excluded because `[\w-]+` requires a word char immediately after the dot (the space after the dot breaks it).
- **Coupled-rename note:** dot-form is one face of coupled-sibling renames. When a skill renames, ALSO enumerate its internal mode names and content-file basenames that changed in lockstep (`quality` mode, `context/quality.md`) and sweep EACH as its own rename pair — they carry no primary token, so a sweep keyed only on `<old>` never reaches them. See SKILL.md "Gotchas" coupled-rename entry.

## Phase 0 — pre-sweep blocklist load

Before running any pattern, load the English-verb blocklist from `triage.md`. Any bare-token (Form 2) or chain-context match (Forms 4, 5, 6, 9) where the token is in the blocklist is forced into ambiguous bucket regardless of regex precision.

## Phase 6 — pattern library evolution

When the skill's re-sweep finds a NEW syntactic form not covered above:

1. STOP — do not silently mangle. Report the new form to user.
2. Document the pattern in this file with all 5 fields (form name, regex, triage default, example, false-positives)
3. Re-run sweep with extended pattern library

## Cross-platform note

All patterns are ripgrep-compatible (PCRE2 subset). Invoke via the Grep tool, NOT raw shell — Grep handles cross-platform path quoting and is faster than spawning `rg`. If a shell fallback is unavoidable, use `git grep -nE` scoped to tracked files or `rg` from the repo root with the Auto-exclusions applied — never `grep -P` (Perl regex doesn't exist on macOS BSD grep). Do not use lookbehinds — Form 1 uses `\B` instead.
