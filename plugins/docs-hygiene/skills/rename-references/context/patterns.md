# Pattern library: syntactic forms

## Contents

- [How to read this file](#how-to-read-this-file)
- [Form 1: Slash-prefixed token (skill name)](#form-1-slash-prefixed-token-skill-name)
- [Form 2: Bare token with word boundary](#form-2-bare-token-with-word-boundary)
- [Form 3: Path references](#form-3-path-references)
- [Form 4: Chain prose forward](#form-4-chain-prose-forward)
- [Form 5: Chain prose backward](#form-5-chain-prose-backward)
- [Form 6: Numbered table row](#form-6-numbered-table-row)
- [Form 7: Frontmatter chain string](#form-7-frontmatter-chain-string)
- [Form 8: Frontmatter glob set](#form-8-frontmatter-glob-set)
- [Form 9: PascalCase comma-list (workflow verb sequence)](#form-9-pascalcase-comma-list-workflow-verb-sequence)
- [Form 10: Cross-skill mode reference](#form-10-cross-skill-mode-reference)
- [Form 11: Line-number-citation shapes](#form-11-line-number-citation-shapes)
- [Form 12: Dot-form sub-identifier](#form-12-dot-form-sub-identifier)
- [Container-position forms (13–15)](#container-position-forms-1315)
- [Form 13: Command-argument position](#form-13-command-argument-position)
- [Form 14: Document title / declared name](#form-14-document-title--declared-name)
- [Form 15: Possessive and appositive container reference](#form-15-possessive-and-appositive-container-reference)
- [Phase 0: pre-sweep blocklist load](#phase-0-pre-sweep-blocklist-load)
- [Phase 0b: container-rename mode](#phase-0b-container-rename-mode)
- [Phase 6: pattern library evolution](#phase-6-pattern-library-evolution)
- [Cross-platform note](#cross-platform-note)

Or jump by form: `grep -n '^## Form' context/patterns.md`.

The component `/docs-hygiene:rename-references` depends on. Each pattern catches references pure-token grep misses; a sweep reaches only the forms whose patterns it runs.

## How to read this file

Each pattern has:

- **Form name**: the syntactic shape it catches
- **Regex**: ripgrep-compatible (use Grep tool, not raw shell)
- **Triage default**: which bucket matches land in (per `triage.md`)
- **Example match**: what it catches
- **Known false-positives**: what to expect and how triage handles it

Substitute `<old>` with the actual old token. Anchor with word boundaries (`\b`) wherever possible; use `\B` only for slash-token form.

## Form 1: Slash-prefixed token (skill name)

```regex
\B/<old>([^\w-]|$)
```

- **Triage default:** Certain
- **Catches:** `/confirm`, `/test live`, `/<skill-name>` references in prose, tables, and frontmatter
- **Why `\B/`:** the slash must not be preceded by a word char, which excludes path contexts like `path/confirm`
- **Trailing boundary excludes a hyphen, and that matters on a Certain form.** A bare `\b`
  prevents `/confirm` matching in `/confirmation` but NOT in `/confirm-changes`, because `\b`
  treats a hyphen as a boundary. Names are kebab-case, so renaming `context` would match
  `/context-guard` and, Form 1 being on container mode's Certain allowlist, auto-apply a rewrite
  of another command's name. The consumed `([^\w-]|$)` terminator fixes both, the same shape
  Forms 13 and 15 use. Verified: `/context`, `/context:sub` (a namespaced invocation, `:` is a
  valid terminator) and `see /context.` match; `/context-guard`, `/contextual` and
  `path/context` do not.
- **The consumed terminator is not part of the reference.** Replace only the `/<old>` span and
  leave it in place; this form participates in the survey's cursor rule (`audit.md` Phase 2)
  like the other consume-the-delimiter forms.
- **False-positives:** none typical. Slash + identifier + a non-hyphen boundary is high-precision

## Form 2: Bare token with word boundary

```regex
\b<old>\b
```

- **Triage default:** Ambiguous if `<old>` is in English-verb blocklist (see `triage.md`); Certain otherwise
- **Catches:** mode names without leading slash (`live`, `e2e`, `outcome`), bare identifiers in prose
- **False-positives:** English-verb collision is the dominant failure mode. Always force ambiguous bucket when token is a common English word.
- **Use case:** the `/test live` rename. `live` appears in `context/live.md`, in mode dispatch tables, in prose; bare-token catches what slash-token misses.

## Form 3: Path references

```regex
context/<old>\.md
skills/<old>/
<old>/SKILL\.md
<old>/(?:context|reference|references|scripts|evals)/
(^|[^\w-])(plugins|packages|apps|libs|modules|extensions)/<old>([^\w-]|$)
```

- **Triage default:** Certain
- **Catches:** filesystem path references in markdown links, prose mentions, frontmatter `paths:` globs
- **Examples:** `[outcome](context/outcome.md)`, `Read /confirm`, `skills/confirm/research/performance.md`
- **False-positives:** rare. Paths are inherently specific
- **Container-root segment, a path that ENDS in the container name.** The first four alternatives
  all require something AFTER `<old>` (a `.md` extension, a trailing slash, a known
  subdirectory), so a catalog's `"source": "./plugins/<old>"` or a README link
  `[x](plugins/<old>)` reaches none of them. Under container mode that leaves the reference as
  excluded Form 2 residue: apply mode finishes and the re-sweep reports zero actionable
  stragglers while the marketplace points at a missing directory and installation is broken.
  Verified on this repository: renaming `docs-hygiene`, the alternative matches
  `.claude-plugin/marketplace.json:193` (`"source": "./plugins/docs-hygiene"`), `README.md:108`
  (`[…](plugins/docs-hygiene)`), and a deep script path: three real hits, no false positives.
- **Both ends exclude a hyphen, same reason as Forms 13 and 15.** Container directories are
  kebab-case. Verified: `plugins/docs-hygiene` matches; `plugins/docs-hygiene-extra`,
  `plugins/docs-hygienex`, and `x-plugins/docs-hygiene` do not. The trailing class permits `/`,
  so deep paths under the container directory match too.
- **Overlap with the earlier alternatives is expected.** On `plugins/<old>/SKILL.md` this
  alternative and `<old>/SKILL\.md` both fire; coequal-span dedup ("Phase 0") keeps one, widest
  match span first, so the occurrence is reported and edited once.
- **Extend the container-root list** to whatever the consuming repository nests containers under
  (`extensions/`, `services/`, `charts/`, …), as with Form 15's appositive noun class. A bare
  `<parent>/<old>` with an unconstrained parent is NOT safe: it matches prose like `input/output`,
  and this form is Certain.
- **Note:** if rename includes a path component (e.g., `/test live` → `/test e2e` renamed `context/live.md` → `context/e2e.md`), include path-form patterns even when args don't explicitly mention paths

## Form 4: Chain prose forward

```regex
(?:→|->|,| and | then )\s*<old>\b
```

- **Triage default:** Chain-context
- **Catches:** workflow chain prose like `→ confirm → retro`, `review, confirm`, `Test, Review, Confirm`, `test and confirm`, `review then confirm`
- **Why this matters:** workflow descriptions appear in frontmatter, READMEs, and architecture diagrams; token-only grep misses the rename context the `→`/`,` characters anchor.
- **False-positives:** when `<old>` is a common English word and the comma enumerates unrelated items (`apples, oranges, confirm`). Triage forces ambiguous when token is in blocklist.

## Form 5: Chain prose backward

```regex
\b<old>\s*(?:→|->|,| and | then )
```

- **Triage default:** Chain-context
- **Catches:** the other direction: `confirm → retro`, `confirm, retro`, `confirm and retro`
- **Pair with Form 4** in every sweep. They catch different positions in the chain

## Form 6: Numbered table row

```regex
\|\s*\d+\.\s*<old>\s*\|
\|\s*\d+\.\s*<old>\b
```

- **Triage default:** Chain-context
- **Catches:** workflow step tables like `| 7. Confirm |`, `| 7. Confirm | Yes/No/Partial |`, retrospective quick-mode tables, step lists
- **False-positives:** rare. Numbered prefix + pipe boundaries are highly specific
- **Variant:** without trailing pipe for tables that don't close columns visibly

## Form 7: Frontmatter chain string

```regex
description:\s*"[^"]*\b<old>\b[^"]*"
when_to_use:\s*"[^"]*\b<old>\b[^"]*"
description:\s*'[^']*\b<old>\b[^']*'
```

- **Triage default:** Certain (when token is enclosed in description chain like `→ <old> →`); Ambiguous otherwise
- **Catches:** SKILL.md frontmatter `description` and `when_to_use` fields containing chain references like `description: "...explore → research → architect → implement → test → review → confirm → retro process..."`
- **Use Grep with `multiline: true`.** Frontmatter strings can span lines
- **Why this matters:** frontmatter description is the SKILL discovery surface; a stale chain shows the AI outdated workflow vocabulary every time the skill loads

## Form 8: Frontmatter glob set

```regex
\{[^}]*\b<old>\b[^}]*\}
```

- **Triage default:** Certain
- **Catches:** glob patterns enumerating skill/file names like `Sources: '.claude/skills/{explore,research,architect,implement,test,review,confirm,retro}/'`, `paths: ['skills/{a,b,old}/SKILL.md']`
- **False-positives:** rare. Comma-separated brace expressions are uncommon outside glob contexts
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
- **Catches:** prose like `auto-triggers /test e2e`, `chains to /verify-changes outcome`, `invokes /test live`: references to a mode of *another* skill, which go stale when that skill renames its mode.
- **Why this matters:** skill renames (e.g. `/verify` → `/verify-changes`) and mode renames (e.g. `/test live` → `/test e2e`) leave chain prose stale; pure-token grep catches only some phrasings.

## Form 11: Line-number-citation shapes

```regex
\.md:[0-9]+
\.md\s+L[0-9]+
```

- **Triage default:** Certain
- **Catches:** `file.md:42` (colon shape) + `file.md L42` (space-L shape) literals in tracked prose. A forward-looking guard: line-number citations rot after ANY edit to the cited file.
- **Allow-listed contexts** (DO NOT flag): fenced code blocks (```); illustrative audit-output tables in skill docs (e.g. demo findings tables in audit-workflow documentation); work-notes paths excluded per `SKILL.md` "Auto-exclusions"
- **False-positives:** domain-specific `L<number>` notation is not caught unless it carries a `.md` prefix; exempt any path-scoped exceptions the consuming repository defines

## Form 12: Dot-form sub-identifier

```regex
\b<old>\.[\w-]+
```

- **Triage default:** Certain
- **Catches:** dotted identifiers built on the renamed token: action/mode IDs (`verify.runtime-affecting-paths`), dotted config keys, dotted mode/path references, in skill bodies, config files, and OTHER skills' dispatch tables. Forms 1 and 3 never reach them; Form 2 buries them in the ambiguous bucket whenever `<old>` is an English verb.
- **Why separate from Form 2:** the trailing `.<identifier>` rules out the verb sense, so `verify.runtime-affecting-paths` lands Certain even when `<old>` is in the blocklist. The `[\w-]+` class excludes `.` so a match cannot gobble across sentence boundaries.
- **False-positives:** rare; `<old>.` followed by a word char is specific. Sentence-end prose (`verify. Then…`) is excluded because `[\w-]+` requires a word char immediately after the dot.
- **Coupled-rename note:** when a skill renames, ALSO enumerate its internal mode names and content-file basenames that changed in lockstep (`quality` mode, `context/quality.md`) and sweep EACH as its own rename pair; they carry no primary token, so a sweep keyed only on `<old>` never reaches them. See SKILL.md "Gotchas" coupled-rename entry.

## Container-position forms (13–15)

Forms 1–12 assume `<old>` is a skill/mode identifier. When the renamed thing is a
**container** (a plugin, a marketplace entry, or anything a user names as an argument or titles
a document after), three positions carry it that the earlier forms miss. Each is high-precision
because the SURROUNDING SYNTAX proves the token is a proper name, not a verb.

When `<old>` is also an English verb *in the consuming codebase*, Form 2 cannot separate the two
senses at any triage setting. Measured on the `re-anchor` → `discipline` rename, over the
plugin's own tree: Form 2 matched **134** lines; Forms 13–15 matched **9**, the 8 real defects
plus one frozen CHANGELOG-history line the "Frozen historical records" rule already excludes.
See `triage.md` "Verb-sense collision the blocklist cannot serve".

## Form 13: Command-argument position

```regex
(^|[^\w/-])/plugins?\s+(marketplace\s+)?(install|uninstall|configure|enable|disable|update|add|remove)\s+`?<old>([^\w-]|$)
(^|[^\w-])<old>@[\w]([\w-]*[\w])?([^\w.@-]|$)
```

- **Triage default:** **Certain for the management-verb alternative; Chain-context for the bare
  qualified-id alternative.** The first is anchored by a management verb no email or prose
  supplies. The second is unanchored, and the dot-exclusion below is necessary but NOT
  sufficient: a dotless address is still valid, and this tree contains `auth_email: "a@b"` and
  `git config user.email t@t`, which a container named `a` or `t` would match. Certain
  auto-applies and would rewrite an address; Chain-context keeps recall while routing through
  confirmation.
- **Promotion must bind to the SAME occurrence, never to the line.**
  `/plugin install foo@acme; email t@t` carries a management command for a DIFFERENT plugin, and a line-level test would
  promote the unrelated `t@t` to Certain and rewrite the address. A verb that governs the
  occurrence is already matched by the management-verb alternative, so a line-level check adds no
  recall and only launders. The single promotion signal: the occurrence IS a key in a plugin-configuration map,
  `"<old>@<slug>"` immediately followed by `:`, under an `enabledPlugins` / `pluginConfigs`
  object. Nothing else promotes; when in doubt it stays Chain-context.
- **Catches:** `<old>` as the ARGUMENT to a management command, as in
  `/plugin install <old>@marketplace`, `/plugin configure <old>@<marketplace>` and
  `/plugin enable <old>`, plus the `<old>@<marketplace>` qualified-id form wherever it appears
  (settings examples, install snippets, `enabledPlugins` / `pluginConfigs` keys).
- **Why Form 1 misses it:** Form 1 anchors on `/<old>`. Here the slash belongs to `plugin`,
  and `<old>` sits one-to-several words downstream with no slash of its own.
- **Why the leading `[^\w/-]` alternation:** keeps `.../plugin install x` (a path) from
  matching while allowing a line start, a space, or a backtick before the slash.
- **Both ends exclude hyphens.** Container IDs are kebab-case, so a word boundary lets `<old>`
  match inside a hyphenated SUPERSTRING: renaming `guard` would match `context-guard@marketplace`,
  and renaming `context` would match `/plugin configure context-guard@acme-tools`, a silent
  auto-rewrite of an unrelated plugin's identifier, so both alternatives exclude an adjacent `-`
  on each side (`[^\w-]`). Verified against a marketplace with 32
  hyphenated plugin names: `/plugin configure context@acme-tools` matches while
  `/plugin configure context-guard@acme-tools` does not; `context@acme-tools` matches while
  `context-guard@acme-tools` does not.
- **Optional backtick before `<old>`:** these usually sit in inline code spans
  (`` `/plugin configure <old>@<marketplace>` ``); without `` `? `` the pattern misses the most
  common rendering.
- **`marketplace` subcommand shape included.** A marketplace's name sits after
  `/plugin marketplace add|update`, not directly after `/plugin`, so without the optional `marketplace\s+` group a marketplace
  rename matched no position-anchored form, container mode suppressed its Form 2 hits as residue,
  and the sweep could report zero actionable stragglers with install instructions stale.
  Verified: `/plugin marketplace add acme-tools` and `/plugin marketplace update acme-tools`
  match, `/plugin marketplace add acme-tools-extra` does not.
- **Email collision, and why the `@`-form excludes dots.** Without a verb in front,
  `<old>@[\w.-]+` matches an email address whenever the container name is a plausible local part
  (`info`, `admin`, `support`, `contact`, `dev`). A marketplace slug is kebab-case with **no
  dots**, while an email domain always carries a TLD dot, so the regex accepts `[\w-]` only and
  requires the slug to END: a following `.` disqualifies. Verified: `info@acme-tools`,
  `` `info@acme-tools` ``, and `"info@acme-tools": true` match; `info@acmetools.com` and
  `info@example.co.uk` do not.
- **No lookaround, deliberately.** A negative lookahead `(?![\w.-])` needs ripgrep's `-P/--pcre2`,
  and the "Cross-platform note" bans lookbehinds for the same reason. The trailing `([^\w.@-]|$)`
  **consumes** a terminator instead, as Forms 4 and 5 do. The consumed character is not part of
  the reference: replace only the matched `<old>@<slug>` span and leave it in place.
- **Consuming a delimiter has ONE cost, and the survey pays it, not the pattern.** The consumed
  character is often the LEADING delimiter of the next occurrence, so a rescan resuming after the
  whole match drops the second of two ADJACENT references. This affects every
  consume-the-delimiter form (3, 13, 15, and both delimiter-anchored Form 14 alternatives), so
  the remedy lives in one place: `audit.md` Phase 2 advances the rescan cursor to the end of the
  CAPTURED `<old>` span. Do not drop the consumed terminator; without it `<old>@slug` matches
  inside `<old>@slug.com` again.
- **False-positives:** otherwise rare; prose does not accidentally say "/plugin configure" before
  an English verb. If a consuming marketplace ever allows dots in a slug, demote the `@`-form to
  Chain-context rather than widening the regex back.
- **Severity note:** these are FUNCTIONAL breaks, not cosmetic. A reader following
  `/plugin install <old>@marketplace` gets `plugin-not-found`. Rank them above title hits
  when reporting.

## Form 14: Document title / declared name

```regex
(?i)^#{1,6}\s+`?<old>`?\s*(#+\s*)?$
(?i)^`?<old>`?\s*$\n^(=+|-+)\s*$
^\s*(name|title|id):\s*("<old>"|'<old>'|<old>)(\s+#.*)?\s*$
(^|[{,])\s*"(name|title|id)"\s*:\s*"<old>"\s*(,|}|$)
^\s*"?(name|title|id)"?\s*=\s*("<old>"|'<old>')\s*(#.*)?$
(^|[{,])\s*("<old>"|<old>)\s*:\s*[{\[]
```

- **Triage default:** Certain
- **Case on title shapes only:** the ATX and Setext alternatives carry `(?i)`, because a
  title-cased heading (`# Re-Anchor` for a container named `re-anchor`) is the same reference
  and keeps Form 14's scope rule. Declaration alternatives stay case-sensitive: registrations are
  exact identifiers.
- **Catches:** an ATX heading whose ENTIRE content is the renamed token (the README H1 that names
  the thing); a `name` / `title` / `id` declaration in YAML frontmatter, a JSON manifest or
  catalog, or a TOML manifest; and a catalog entry KEYED by the container.
- **Why the `$` anchor is required:** it makes this Certain rather than ambiguous. A heading that
  merely *contains* the token (`## How re-anchor works`) may be verb usage and belongs in Form 2's
  ambiguous bucket; a heading that IS the token can only be naming it.
- **Closed ATX headings still ARE the token.** In `# <old> #` the trailing hash run is
  decoration, so the optional `(#+\s*)?` lets it match; otherwise the title's only hit was Form 2,
  excluded as residue in container mode. Replace only the captured `<old>` span and leave the
  hashes in place.
- **Setext titles count.** A README may underline its title (`<old>` then a line of `=` or `-`);
  missing that shape left the title as excluded Form 2 residue and the rename could report
  completion with it stale. Requires `multiline: true`, like Form 7.
- **The JSON declaration is delimiter-anchored, not whole-line-anchored.** A minified manifest
  `{"name":"<old>","version":"1"}` still selects container mode, and a `^…$` anchor would leave
  its declaration suppressed as residue while apply mode reports completion. The alternative uses
  the same `(^|[{,])` opener as the key-position shape and a `(,|}|$)` terminator: a JSON member
  starts after a line start, `{`, or `,`, and ends at `,`, `}`, or end of line. Verified:
  `{"name":"<old>","version":"1"}`, `{"name":"<old>"}`, `{"version":"1","name":"<old>"}`, an
  indented `"name": "<old>",`, a spaced `"name" : "<old>",`, `"title": "<old>"` and
  `{"id":"<old>"}` match; `{"name":"<old>-extra",…}`, `{"description":"<old>"}` and a prose line
  quoting `"name": "<old>"` mid-sentence do not. Precision on this repository is unchanged:
  still exactly `.claude-plugin/marketplace.json:192` and
  `plugins/docs-hygiene/.claude-plugin/plugin.json:3`.
- **A declaration may carry an INLINE COMMENT, and the end anchor must let it through.** YAML and
  TOML allow `name: <old> # package name` and `name = "<old>"  # package name`; an end-anchored
  alternative rejected them, leaving the registration suppressed as residue.
  **The whitespace before `#` is not decoration in the YAML case.** YAML starts a comment only
  when `#` follows whitespace; `name: <old>#x` is the single scalar `<old>#x`. So the YAML
  alternative requires `(\s+#.*)?`, while TOML accepts `\s*(#.*)?` because its closing quote ends
  the string. Verified: `name: <old> # package name`, `name: "<old>" # c`, an indented
  `id: <old>` with a spaced trailing comment, `name = "<old>"  # package name` and
  `name = "<old>"#c` match; `name: <old>#x` and `name: <old>-extra # c` do not. JSON has no
  comment syntax.
- **The comment is INSIDE the match but OUTSIDE the reference region.** A comment often mentions
  what it documents: `name: <old> # <old> before publishing`. The survey enumerates every `<old>`
  span inside a match (`audit.md` Phase 2), and these alternatives are Certain and exempt from the
  common-word demotion inside a manifest, so blind enumeration would emit and rewrite the prose
  too. **Enumerate only within the declaration VALUE for these two alternatives**; the comment is
  documentation ABOUT the declaration, never a second declaration. `audit.md`
  carries the per-form reference-region table.
- **The YAML and TOML alternatives keep their `$` anchor deliberately.** Both grammars are
  line-oriented for the shapes manifests use (block mappings, top-level key/value pairs), so the
  anchor is a real discriminator; JSON has no line structure. For a YAML flow mapping
  (`{name: <old>}`) or a TOML inline table, resolve by hand like the YAML block-mapping catalog
  gap below; do not widen these two into every-nested-key patterns.
- **The declaration IS the container's REGISTERED name.** In JSON it is `"name": "<old>"`: quoted
  key, usually indented, usually a trailing comma. No other container-position form reaches it,
  so without this alternative container mode reduced the registered name to excluded Form 2
  residue. Verified on this repository: renaming `docs-hygiene` matches exactly
  `.claude-plugin/marketplace.json:192` and `plugins/docs-hygiene/.claude-plugin/plugin.json:3`,
  two real hits, none elsewhere.
- **TOML declarations too, where the delimiter is `=`, not `:`.** `pyproject.toml` and
  `Cargo.toml` declare `name = "<old>"`, which the colon-based alternatives miss. The mode ladder
  names `pyproject.toml` as container evidence, so without this alternative a Python or Rust
  package enters the mode that suppresses bare-token residue while its one declaration goes
  unmatched, and apply mode reports zero actionable stragglers. The key may be quoted or not and
  the value is a basic or literal string (`"…"` or `'…'`). Verified: `name = "<old>"`,
  `name="<old>"`, `"name" = "<old>"`, `name = '<old>'`, and `title = "<old>"` match;
  `name = "<old>-extra"` and `description = "<old>"` do not.
- **YAML declarations are not always at column zero.** A manifest or catalog that NESTS entries
  indents them (an indented `name: <old>` under a parent key), and the ladder counts that field as
  container evidence either way; the leading `\s*` makes the alternative indentation-agnostic,
  like the JSON and TOML ones.
- **A catalog can be KEYED by the container instead of declaring a `name` field.** Ladder rule 3
  names both shapes, "the `name`/`id` field of such a manifest, **or as a key in a
  marketplace/registry catalog**". The key-position alternative matches a key whose value OPENS
  an object or array (`plugins: { "<old>": { … } }`), which distinguishes a catalog entry from a
  scalar setting.
- **Anchor a catalog key on the JSON delimiter, not on the line start.** A `^\s*` anchor reaches
  only a key alone on its line, not the compact `plugins: { "<old>": { … } }` this form's own
  example uses. The anchor is `(^|[{,])`: a JSON key follows a line start, an opening brace, or a
  comma, and nothing else. Verified: `plugins: { "<old>": {` and an indented `"<old>": {` match,
  `{"a":1,"<old>":{}}` matches on the comma, and `"other": { "<old>": "scalar" }` does not,
  because the value must open an object or array.
- **The key-position alternative MUST have the manifest/catalog condition.** `"<key>": {` is the
  commonest JSON line shape (this repository carries 569); for an ordinary-word container name an
  unconditioned pattern would auto-rewrite unrelated configuration. Rate it Certain ONLY inside a
  file established as a manifest or registry catalog, the file class the declaration exemption
  names. **Anywhere else it is Ambiguous**, unconditionally; no common-word escape hatch is
  needed because the demotion does not depend on the token.
- **A YAML block-mapping catalog key is a KNOWN, deliberate gap.** The entry opens with just
  `<old>:` and an indented block, so `[{\[]` has nothing to bind to, and the only pattern that
  would reach it, `^\s*<old>\s*:\s*$`, matches EVERY YAML key with a nested value: a mass-rewrite
  vector on a Certain form. Verified: the alternative matches `"<old>": {` in JSON and not an
  indented `<old>:` in YAML. For a YAML-catalogued container, resolve the key by hand or with
  `--include-bare-token`, and read the residue aggregate rather than trusting the actionable
  count alone. Revisit if a flow-style (`{…}`) YAML catalog or a file-type-aware survey makes a
  bounded pattern possible.
- **`id` is a declaration key too.** Ladder rule 3 selects CONTAINER mode when `<old>` is
  "the `name`/`id` field of such a manifest", so matching only `name` and `title` left an `id`
  registration as excluded residue. All three KEYED declaration alternatives, YAML, JSON and
  TOML, accept `id`. The key-position alternative needs no key list: the container name IS the
  key.
- **The `=` shape, and `id`, are why the manifest/catalog qualifier below is required.**
  `name="<old>"` and `id="<old>"` are also shell and `.env` assignment syntax; this repository
  carries ~45 `id=` / `id:` string declarations, nearly all shell positional-argument binds in
  `.sh` files. They cannot collide unless the container's literal name is the assigned value.
  The exemption that makes a declaration Certain regardless of path applies only when
  the FILE is a manifest or catalog; in any other file the match is a title match and takes the
  scope rule and the common-word demotion. Without that condition every `id="$1"` in a shell
  script would be a Certain rename candidate.
- **Quote handling:** the YAML alternation accepts a bare, double-quoted, or single-quoted value
  and requires the quotes to PAIR (`"<old>"` and `'<old>'`, never `"<old>'`); a naive
  `["']?<old>["']?` would match the invalid mismatched form. The JSON alternative is
  double-quote-only on key and value.
- **False-positives are real, and they are the reason for the scope rule below.** "A heading that
  IS the token can only be naming it" FAILS for an ordinary-word name: renaming a `testing`
  plugin matches this repository's `README.md:86` (`### Testing`, a category heading), and
  renaming an `architecture` plugin matches `plugins/miro/README.md:39` (`## Architecture`, an
  unrelated section). Under precedence, a false Certain here is worse than a Form 2 hit, because
  it DISCARDS the safer classification.
- **Scope rule (required), for TITLE alternatives only.** Rate an ATX or Setext title match Certain
  only when the file is plausibly container-owned: the container's own README/SKILL/manifest, or
  a path under its directory. A heading match in a file the container does not own is
  **Ambiguous**, whatever the token looks like. When the token is a common English word, demote
  every title match to Ambiguous regardless of path.
- **Manifest and catalog DECLARATIONS are exempt from the scope rule, and from the common-word
  demotion.** A heading is weak evidence of naming; a `name` field in a container manifest
  (`plugin.json`, `package.json`, `pyproject.toml`, …) or a marketplace/registry catalog IS the
  registration, the key being the proof as Form 13's management verb is. Two consequences, both
  required:
  1. **Path is irrelevant.** A catalog lives at the REPOSITORY root, not under the container's
     directory: `.claude-plugin/marketplace.json`
     carries an entry FOR the container. Applying the scope rule would demote the container's own
     registration to Ambiguous and leave it stale.
  2. **A common-word name is still a registered name.** `"name": "review"` in a manifest cannot be
     verb usage, because the key admits only an identifier.

  This exemption covers all four declaration alternatives, the frontmatter `name:` shape, the
  JSON `"name":` shape and the TOML `name =` shape over all three keys (`name`, `title`, `id`),
  plus the key-position shape, **when the file is a manifest or catalog**, and only then. For the
  first three that condition governs the path exemption; for the key-position alternative it
  governs the rating itself, per its own bullet above. A `title:` in an ordinary document's
  frontmatter is a document title, not a registration: treat it as a title match and apply the
  scope rule and the common-word demotion.
- **Note:** a plugin/skill README H1 is the landing surface every consumer sees first and the
  most-missed reference in practice: the rename moves the directory, so path-form patterns pass,
  and nothing looks at line 1. The scope rule keeps the form from over-reaching to every document
  in the tree.

## Form 15: Possessive and appositive container reference

```regex
(^|[^\w-])`?<old>`?'s\b
\b[Tt]he `?<old>`? (plugin|skill|marketplace entry|package|module)\b
```

- **Triage default:** Certain
- **Catches:** prose where `<old>` stands in for the CONTAINER, as in "Report `<old>`'s effective
  configuration" or "the `<old>` plugin ships…".
- **`[Tt]he`, because sentence-initial is the common shape.** "The `<old>` plugin ships…" misses
  a lowercase-only `the`, leaving only a Form 2 hit that container mode suppresses as residue.
  Only the article is case-flexible; the token stays case-sensitive.
- **Hyphen boundary, same reason as Form 13.** Renaming `guard` would otherwise match
  `` `context-guard` ``'s; the leading `(^|[^\w-])` excludes an adjacent hyphen. The appositive
  alternative is already safe because the noun-class word must follow the token. Verified:
  `` `guard` ``'s and `guard's` match, `` `context-guard` ``'s does not.
- **Inline-code wrapping is the common case:** in markdown the token is usually a code span, so
  the text is `` `<old>` `` followed by `'s`, never the literal `<old>'s`. Without the optional
  backticks this form misses its own motivating example. Form 13 carries the same allowance.
- **Why it is Certain even when `<old>` is a blocklisted verb:** English verbs do not take the
  possessive clitic, and a noun-class appositive (`the X plugin`) forces the naming reading, so
  this is safe where Form 2 is not.
- **False-positives:** a token that is a noun in ordinary use ("the review plugin" vs a
  review) can still collide; when `<old>` is a common NOUN rather than a verb, demote this
  form to ambiguous.
- **Extend the appositive noun class** to whatever the consuming repository calls its
  containers.

## Phase 0: pre-sweep blocklist load

Before running any pattern, load the English-verb blocklist from `triage.md`. Any bare-token (Form 2) or chain-context match (Forms 4, 5, 6, 9) where the token is in the blocklist is forced into ambiguous bucket regardless of regex precision.

**Precedence: a container-position match wins its line outright.** Forms 13–15 are strictly
more specific than Form 2: every line they match, Form 2 also matches. Without precedence they
would only ADD hits, leaving the Form 2 flood intact.

**Deduplicate by OCCURRENCE SPAN, not by line.** `Use <old> via /plugin install <old>@marketplace`
carries a bare reference and a command-argument one. Collapsing the line would drop the bare
occurrence; since Phase 5 replaces one span at a time (`replace_all: false`), it would then be
reclassified as residue, excluded by container mode, and the re-sweep would declare completion
with a live stale reference. Key each match by `(file, line, start, end)` and suppress a weaker
match only when its span is **covered by** a more-specific match's span.

**Key every match by its CAPTURED `<old>` span, not by the whole match span.** Form 13's
management-verb alternative spans `/plugin install <old>@` while its qualified-id alternative
spans `<old>@acme-tools`; neither contains the other, so a whole-span test keeps both and
schedules two Edits on one token, the second failing. Compare the `(start, end)` of the captured
`<old>`; the rest of a match is context.

**With that keying, coverage collapses COEQUAL matches too.** When two matches share the same
`<old>` span, keep ONE: prefer the widest MATCH span (most reporting context), and on a tie the
earlier-numbered form. The test applies within a form as well as across forms.

Dedup runs AFTER the sweep and BEFORE triage:

1. An OCCURRENCE matched by any of Forms 13–15 is attributed to that form and enters **whatever
   bucket the OWNING FORM assigns to the matching alternative, after its scope rules are
   applied**. Certain is the default, not the outcome:

   | Owning form and alternative | Bucket |
   |---|---|
   | Form 13 management-verb (`/plugin install <old>`) | Certain |
   | Form 13 bare qualified-id (`<old>@slug`) | **Chain-context** |
   | Form 14 title, container-owned file, uncommon token | Certain |
   | Form 14 manifest/catalog declaration | Certain (scope rule does not apply) |
   | Form 14 title, other file, or common-word token | **Ambiguous** |
   | Form 15 possessive/appositive, common-NOUN token | **Ambiguous** |
   | Form 15 otherwise | Certain |

   Drop the Form 2 (and any chain-form) match for that same SPAN: it is the same reference
   through a weaker lens. A bare-token match elsewhere on the line is a DIFFERENT reference and
   survives.

   **Precedence changes WHICH form owns the line, never the safety of its rating.** Forcing a
   Form 14 line Certain would launder the demotion its scope rule exists for. Flattening Form 13's
   qualified-id alternative (demoted to the MIDDLE bucket) to Certain would auto-apply and rewrite
   a dotless address such as `t@t`. Read the bucket off the owning alternative; never off this
   rule.
2. Only lines Forms 13–15 did NOT match fall through to Form 2's blocklist rule above.

The Phase 0 rule therefore forces a blocklisted token's bare-token matches ambiguous, and
container-position matches never become bare-token matches. Report the deduplication in the
audit output as "N Form-2 hits superseded by container-position matches", so a reader sees the
suppression rather than inferring it from a smaller number.

**Precedence alone is NOT sufficient. It only resolves lines the container forms also
matched.** On the measured fixture that is 8 lines out of Form 2's 134. The other 126 are verb
uses no container form touches, so they fall through to Form 2 and, when the token is absent
from the static blocklist, take its **Certain** default.

## Phase 0b: container-rename mode

Declare the sweep's MODE at Phase 0, from what is being renamed.

**Selecting the mode is a concrete ladder, not a judgment call.** Identifier mode on a container
restores the Form 2 flood; container mode on an identifier suppresses actionable bare references.
**Only rule 1 short-circuits.** Rules 2–4 are evidence to COLLECT IN FULL and compare, per the
conflict rule below the list; stopping at the first that fires is the failure that rule prevents:

1. **Explicit override.** The invocation says which (`--container` / `--identifier`). Honor it.
2. **Filesystem evidence: a directory named `<old>` whose parent is a container root.** A
   `plugins/<old>/`, `packages/<old>/`, or the repo's own equivalent, containing a manifest
   (`plugin.json`, `package.json`, `pyproject.toml`, …) → **container**. If the move already
   happened, check the state BEFORE it: look for `<new>` in the same position, or read the
   pair out of `git log --diff-filter=R` / `git status`.
3. **Manifest evidence.** `<old>` appears as the `name`/`id` field of such a manifest, or as a
   key in a marketplace/registry catalog → **container**.
4. **Invocation-shape evidence.** The tree contains `/<old>:<something>` (a namespaced
   invocation) → `<old>` is the namespace, so **container**. `/<old>` with no colon suffix →
   **identifier**.
5. **Nothing fired → ASK.** One `AskUserQuestion`: "Is `<old>` a container (plugin, package,
   marketplace entry) or an identifier (skill, mode, action)?" with the evidence checked so far
   shown, so the answer is informed rather than guessed.

**Rules 2–4 are evidence, not precedence, so collect ALL of them before stopping.** Only rule 1 is
authoritative alone. Stopping at the first rule that fires is safe only while the rules cannot
disagree, and in a monorepo they routinely do: renaming the `/test` action
while an unrelated package manifest declares `name = "test"` fires rule 3 for **container**, and
stopping there never inspects the `/test` invocations that fire rule 4 for **identifier**.
Container mode then suppresses those bare references as residue and the rename falsely completes.

So evaluate rules 2, 3 and 4 in full and compare their verdicts:

- **All agree** → that is the mode. Record which rules fired.
- **They disagree** → do NOT take the earliest; a shared string does not show the manifest and
  the invocation name the SAME entity. Fall through to rule 5 and ASK, showing each rule's
  verdict and the file that produced it. Correlate first when the tree makes it cheap (a
  manifest whose directory also contains the `/<old>` definition is one entity and the conflict
  dissolves), but never infer the correlation from the name alone.

Do NOT infer mode from the token's shape: hyphenation, length, or word-likeness are uncorrelated
with what the thing IS. Never silently default; an unstated default is how one of the two
failure modes ships without anyone choosing it. Record the resolved mode and the rule that fired
in the audit report, so a reader can see which applied and override it.

The two modes:

- **Identifier rename** (a skill, a mode, a dotted ID): every form applies as before. Nothing
  below changes.
- **Container rename** (a plugin, a marketplace entry, a package): the thing being renamed is
  a proper name, so a bare-token occurrence is EVIDENCE OF NOTHING: it is as likely the ordinary
  word as the container. In this mode:
  1. Forms 13–15 (plus Forms 1 and 3, which are already position-anchored) are the forms that
     can produce the **Certain** bucket, but each match takes the bucket ITS OWN alternative
     assigns, per the table in "Phase 0". Container mode selects which forms are eligible for
     Certain; it never promotes an alternative its own form demoted. Form 13's bare qualified-id
     alternative stays **Chain-context** here, and a scope-demoted Form 14 title stays
     **Ambiguous**. Mode does not launder either.
  2. **Rule 1 is an ALLOWLIST, and it must be enforced against every form, not just Form 2.**
     Forms 1, 3 and 13–15 are the whole Certain-eligible set here; **every other form's
     matches are excluded from Certain**, whatever bucket that form carries in identifier mode.
     Filtering only Form 2's residue would leave Forms 8 and 12, Certain by default, on the
     auto-apply path, and they are as position-blind about a CONTAINER as Form 2:
     renaming a `context` plugin, Form 12 would rate the unrelated dotted key `context.timeout`
     Certain and apply mode rewrite it, and Form 8 the same for a `{a,context,b}` glob
     enumerating skills. Their syntax proves the token is an IDENTIFIER, which a container
     rename is not asking about.
  3. The excluded matches are reported two ways, by volume:
     - **Form 2's residue**, every bare-token occurrence not matched by a position-anchored
       form, is a single aggregate count ("126 bare-token occurrences not in container
       position, not proposed"), never per-match prompts. It is the flood the mode exists to
       suppress.
     - **Forms 4–12's matches** are demoted to **Ambiguous** and reported normally. They are few
       and carry real syntax, and a container name genuinely can appear in a glob set, so
       demoting rather than aggregating keeps them recoverable.
  4. Surface the bare-token residue only if the user explicitly asks to widen
     (`--include-bare-token`), and then as Ambiguous, never Certain.

Bare-token position carries no signal in a container rename, so prompting on it costs attention
and catches nothing. The static blocklist is irrelevant here: mode is a property of what is being
renamed, not of whether someone listed the token.

**With mode + precedence together**, the measured fixture resolves as: 8 Certain
container-position findings, 126 bare-token occurrences reported as an aggregate and not
proposed, and 0 confirmation prompts, against Form 2's unaided 134.

## Phase 6: pattern library evolution

When the skill's re-sweep finds a NEW syntactic form not covered above:

1. STOP. Do not silently mangle. Report the new form to user.
2. Document the pattern in this file with all 5 fields (form name, regex, triage default, example, false-positives)
3. Re-run sweep with extended pattern library

**A new rule is not landed until every site that states the old one is updated.** This skill's
contract is spread across `SKILL.md`, `context/patterns.md`, `context/triage.md`,
`context/audit.md`, `context/audit-modes.md`, `context/apply.md`, and `evals/evals.json`, and
several state the same fact by design, so a rule changed in one place leaves others asserting its
opposite (precedence saying Certain while Form 14's scope rule said Ambiguous; `SKILL.md` still
saying `count == 0` after `apply.md` learned the actionable-count rule; a flag documented in
`patterns.md` and registered nowhere).

After changing any rule here, grep the whole skill directory for the claim you changed (the old
bucket name, the old count semantics, the old flag list, the enumerated form list) and reconcile
every hit, evals included. An eval asserting superseded behavior fails against the corrected
skill and reads as a regression.

**Validate a new form on BOTH axes before adding it.** Recall alone is not evidence: Form 2 has
perfect recall on every form here and is still unusable when the token is a verb. Measure the
candidate against a real fixture: the commit that FIXED the missed references (its removed lines
are the defect set) for recall, and the whole pre-fix tree for precision, reporting its hit count
beside bare-token Form 2's on that tree. A form that does not beat Form 2 on precision is not
carrying its weight.

## Cross-platform note

All patterns are ripgrep-compatible (PCRE2 subset). Invoke via the Grep tool, NOT raw shell; it handles cross-platform path quoting and is faster than spawning `rg`. If a shell fallback is unavoidable, use `git grep -nE` scoped to tracked files or `rg` from the repo root with the Auto-exclusions applied, never `grep -P` (Perl regex doesn't exist on macOS BSD grep). Do not use lookbehinds. Form 1 uses `\B` instead.

**A raw `rg` fallback needs `--hidden`; the Grep tool and `git grep` do not.** Container manifests
routinely live in DOT-directories such as `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json`, which bare `rg` skips, so it returns zero for Form 14's
declaration alternative and Form 3's container-root alternative on exactly the files they exist
to reach. Verified on this tree: `rg '"name": "docs-hygiene"'` finds nothing, `rg --hidden` finds
both manifests, and the Grep tool and `git grep` find both without a flag. Prefer the Grep tool.
