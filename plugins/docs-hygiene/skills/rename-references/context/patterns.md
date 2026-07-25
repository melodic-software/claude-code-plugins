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
(^|[^\w-])(plugins|packages|apps|libs|modules|extensions)/<old>([^\w-]|$)
```

- **Triage default:** Certain
- **Catches:** filesystem path references in markdown links, prose mentions, frontmatter `paths:` globs
- **Examples:** `[outcome](context/outcome.md)`, `Read /confirm`, `skills/confirm/research/performance.md`
- **False-positives:** rare — paths are inherently specific
- **Container-root segment — a path that ENDS in the container name.** The first four alternatives
  all require something AFTER `<old>`: a `.md` extension, a trailing slash, a known subdirectory.
  A catalog's `"source": "./plugins/<old>"` and a README link `[x](plugins/<old>)` have nothing
  after the token, so none of them reach it. Under container mode that leaves the reference as
  Form 2 residue, excluded from Certain — so apply mode can finish, and the re-sweep report zero
  actionable stragglers, while the marketplace still points at a directory that no longer exists
  and installation is broken. Verified on this repository's own tree: renaming `docs-hygiene`, the
  alternative matches `.claude-plugin/marketplace.json:193` (`"source": "./plugins/docs-hygiene"`),
  `README.md:108` (`[…](plugins/docs-hygiene)`), and a deep script path — three hits, all real
  references, no false positives.
- **Both ends exclude a hyphen, same reason as Forms 13 and 15.** Container directories are
  kebab-case, so a bare boundary would match inside a superstring. Verified:
  `plugins/docs-hygiene` matches; `plugins/docs-hygiene-extra`, `plugins/docs-hygienex`, and
  `x-plugins/docs-hygiene` do not. The trailing class permits `/`, so deep paths under the
  container directory match too.
- **Overlap with the earlier alternatives is expected, not a defect.** On
  `plugins/<old>/SKILL.md` this alternative and `<old>/SKILL\.md` both fire on the same token.
  Coequal-span dedup ("Phase 0") collapses them to one match — widest match span first — so the
  occurrence is reported and edited once.
- **Extend the container-root list** to whatever the consuming repository nests its containers
  under (`extensions/`, `services/`, `charts/`, …), the same way Form 15's appositive noun class
  is extended. A bare `<parent>/<old>` with an unconstrained parent is NOT safe: it would match
  ordinary prose like `input/output`, and this form is Certain.
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

## Container-position forms (13–15)

Forms 1–12 assume `<old>` is a skill/mode identifier. When the renamed thing is a
**container** — a plugin, a marketplace entry, anything a user names as an argument or
titles a document after — three positions carry it that none of the earlier forms reach.
Each is high-precision because the SURROUNDING SYNTAX proves the token is a proper name,
not a verb.

Why this matters more than coverage: when `<old>` is also an English verb *in the consuming
codebase*, Form 2 cannot separate the two senses at any triage setting. Measured on the
`re-anchor` → `discipline` rename, over the plugin's own tree: Form 2 matched **134** lines;
Forms 13–15 matched **9** — the 8 real defects plus one frozen CHANGELOG-history line the
existing "Frozen historical records" rule already excludes. See `triage.md`
"Verb-sense collision the blocklist cannot serve".

## Form 13: Command-argument position

```regex
(^|[^\w/-])/plugins?\s+(marketplace\s+)?(install|uninstall|configure|enable|disable|update|add|remove)\s+`?<old>([^\w-]|$)
(^|[^\w-])<old>@[\w]([\w-]*[\w])?([^\w.@-]|$)
```

- **Triage default:** **Certain for the management-verb alternative; Chain-context for the bare
  qualified-id alternative.** The two differ in what anchors them. The first has a management
  verb in front, which no email or prose can accidentally supply. The second is unanchored, and
  the dot-exclusion below is necessary but NOT sufficient: a dotless address is still a valid
  address, and this very tree contains `auth_email: "a@b"` and `git config user.email t@t`, both
  of which a container named `a` or `t` would match. Since Certain auto-applies, that would
  rewrite an address. Chain-context keeps the form's recall while routing it through
  confirmation — the honest rating when the shape cannot fully discriminate. Promote a specific
  occurrence to Certain only when a neighbor confirms it (a management verb on the line, or an
  `enabledPlugins` / `pluginConfigs` key context).
- **Catches:** `<old>` as the ARGUMENT to a management command rather than as the command
  itself — `/plugin install <old>@marketplace`, `/plugin configure <old>`,
  `/plugin enable <old>` — plus the `<old>@<marketplace>` qualified-id form wherever it
  appears (settings examples, install snippets, `enabledPlugins` / `pluginConfigs` keys).
- **Why Form 1 misses it:** Form 1 anchors on `/<old>`. Here the slash belongs to `plugin`,
  and `<old>` sits one-to-several words downstream with no slash of its own.
- **Why the leading `[^\w/-]` alternation:** keeps `.../plugin install x` (a path) from
  matching while still allowing a line start, a space, or a backtick before the slash.
- **Hyphens bound a word but NOT a container name — both ends exclude them.** Container IDs are
  kebab-case, so a plain word boundary lets `<old>` match inside a hyphenated SUPERSTRING:
  renaming `guard` would match `context-guard@marketplace`, and renaming `context` would match
  `/plugin configure context-guard`. On a Certain-rated form that silently auto-rewrites an
  unrelated plugin's identifier. Both alternatives therefore exclude an adjacent `-` on each
  side (`[^\w-]`) instead of relying on a word boundary. Verified against a marketplace where 32
  plugin names are hyphenated: `/plugin configure context` matches while
  `/plugin configure context-guard` does not; `context@acme-tools` matches while
  `context-guard@acme-tools` does not.
- **Optional backtick before `<old>`:** these appear inside inline code spans constantly
  (`` `/plugin configure <old>` ``); without `` `? `` the pattern misses the most common
  rendering.
- **`marketplace` subcommand shape included.** A marketplace's own name sits after
  `/plugin marketplace add|update`, not directly after `/plugin` — so without the optional
  `marketplace\s+` group, renaming a marketplace matched no position-anchored form, container
  mode then suppressed its Form 2 hits as residue, and the sweep could report zero actionable
  stragglers while executable install instructions stayed stale. Verified:
  `/plugin marketplace add acme-tools` and `/plugin marketplace update acme-tools` match,
  `/plugin marketplace add acme-tools-extra` does not.
- **Email collision, and why the `@`-form excludes dots.** The qualified-id alternative has no
  management verb in front of it, so on its own `<old>@[\w.-]+` matches an email address
  whenever the container name is a plausible local part — `info`, `admin`, `support`,
  `contact`, `dev`. On a Certain-rated form that is a silent auto-rewrite of contact addresses.
  The discriminator is structural: a marketplace slug is kebab-case with **no dots**, while an
  email domain always carries a TLD dot. The regex therefore accepts `[\w-]` only, then requires
  the slug to END — a following `.` disqualifies the match. Verified: `info@acme-tools`,
  `` `info@acme-tools` ``, and `"info@acme-tools": true` all match; `info@acmetools.com` and
  `info@example.co.uk` do not.
- **No lookaround — deliberately.** The natural way to write that boundary is a negative
  lookahead `(?![\w.-])`, but ripgrep's default engine rejects look-around entirely (it needs
  `-P/--pcre2`), and this file's own "Cross-platform note" already bans lookbehinds for the same
  class of reason. The trailing `([^\w.@-]|$)` **consumes** a terminator instead — same
  discrimination, no engine requirement. Forms 4 and 5 use the same consume-the-delimiter shape.
  A consumed trailing character is not part of the reference: replace only the matched
  `<old>@<slug>` span and leave it in place.
- **False-positives:** otherwise rare. For the first alternative, the enclosing management verb
  supplies the disambiguation bare-token position lacks — prose does not accidentally say
  "/plugin configure" before an English verb. If a consuming marketplace ever allows dots in a
  slug, demote the `@`-form to Chain-context rather than widening the regex back.
- **Severity note:** these are FUNCTIONAL breaks, not cosmetic. A reader following
  `/plugin install <old>@marketplace` gets `plugin-not-found`. Rank them above title hits
  when reporting.

## Form 14: Document title / declared name

```regex
^#{1,6}\s+`?<old>`?\s*$
^`?<old>`?\s*$\n^(=+|-+)\s*$
^(name|title):\s*("<old>"|'<old>'|<old>)\s*$
^\s*"(name|title)":\s*"<old>"\s*,?\s*$
```

- **Triage default:** Certain
- **Catches:** an ATX heading whose ENTIRE content is the renamed token — the README H1 that
  names the thing — and a `name:` / `title:` declaration in YAML frontmatter or a JSON manifest
  or catalog.
- **Why the `$` anchor is load-bearing:** it is what makes this Certain rather than
  ambiguous. A heading that merely *contains* the token (`## How re-anchor works`) may well
  be verb usage and belongs in Form 2's ambiguous bucket; a heading that IS the token can
  only be naming it.
- **Setext titles count.** A README may underline its title (`<old>` then a line of `=` or `-`)
  instead of using an ATX `#`. Both render as the document's primary heading, so missing the
  Setext shape meant a container's own title had only a Form 2 hit — which container mode
  excludes — and the rename could report completion with the landing-page title still stale.
  Requires `multiline: true`, like Form 7.
- **JSON declarations count, and they are the container's REGISTERED name.** When the manifest or
  catalog is JSON, the declaration is `"name": "<old>"` — the key is quoted, the line is indented
  rather than at column zero, and a trailing comma usually follows. The YAML alternative reaches
  none of that, and no other container-position form reaches it either, so container mode reduced
  the container's own registered name to excluded Form 2 residue and the sweep could report zero
  actionable stragglers with the registration stale. Verified on this repository: renaming
  `docs-hygiene` matches exactly `.claude-plugin/marketplace.json:192` and
  `plugins/docs-hygiene/.claude-plugin/plugin.json:3` — two hits, both real, none elsewhere in the
  tree.
- **Quote handling:** the YAML alternation accepts a bare, double-quoted, or single-quoted value
  and requires the quotes to PAIR — `"<old>"` and `'<old>'`, never `"<old>'`. A naive
  `["']?<old>["']?` would match the mismatched form, which is not valid YAML. The JSON alternative
  is double-quote-only on both key and value, because JSON admits no other quoting.
- **False-positives — real, and the reason for the scope rule below.** "A heading that IS the
  token can only be naming it" holds when the token is coined or hyphenated. It FAILS when the
  container has an ordinary-word name: renaming a `testing` plugin matches this repository's own
  `README.md:86` (`### Testing`, a marketplace category heading), and renaming an `architecture`
  plugin matches `plugins/miro/README.md:39` (`## Architecture`, an unrelated design section).
  Both were verified against the tree. Under precedence, a false Certain here is worse than a
  Form 2 hit, because it DISCARDS the safer classification.
- **Scope rule (required) — TITLE alternatives only.** Rate an ATX or Setext title match Certain
  only when the file is plausibly container-owned — the container's own README/SKILL/manifest, or
  a path under its directory. A heading match in a file the container does not own is
  **Ambiguous**, whatever the token looks like. When the token is a common English word, demote
  every title match to Ambiguous regardless of path.
- **Manifest and catalog DECLARATIONS are exempt from the scope rule, and from the common-word
  demotion.** The scope rule exists because a heading is only weak evidence of naming — `##
  Architecture` may be a section, not a container. A `name` field in a container manifest
  (`plugin.json`, `package.json`, `pyproject.toml`, …) or in a marketplace/registry catalog is not
  evidence of naming, it IS the registration; the key is the proof, the same way Form 13's
  management verb is. Two consequences, both load-bearing for the motivating case:
  1. **Path is irrelevant.** A catalog lives at the REPOSITORY root, not under the container's
     directory — `.claude-plugin/marketplace.json` is the marketplace's file carrying an entry
     FOR the container. Applying the scope rule to it would demote the container's own
     registration to Ambiguous and the sweep would leave it stale, which is the defect this
     alternative was added to close.
  2. **A common-word name is still a registered name.** `"name": "review"` in a manifest cannot be
     verb usage — the key admits only an identifier. Demoting it would suppress the one hit that
     is certain by construction.

  This exemption covers the declaration alternatives (`name:` / `title:` in frontmatter, and the
  JSON `"name":` / `"title":` shape) **when the file is a manifest or catalog**. A `title:` in an
  ordinary document's frontmatter is a document title, not a registration: treat it as a title
  match and apply the scope rule and the common-word demotion to it.
- **Note:** a plugin/skill README H1 is the landing surface every consumer sees first, and
  it is the single most-missed reference in practice — the rename moves the directory, so
  the path-form patterns all pass, and nothing looks at line 1. That is why the form exists;
  the scope rule is what keeps it from over-reaching to every document in the tree.

## Form 15: Possessive and appositive container reference

```regex
(^|[^\w-])`?<old>`?'s\b
\b[Tt]he `?<old>`? (plugin|skill|marketplace entry|package|module)\b
```

- **Triage default:** Certain
- **Catches:** prose where `<old>` stands in for the CONTAINER — "Report `<old>`'s effective
  configuration", "the `<old>` plugin ships…".
- **`[Tt]he` — sentence-initial is the common shape.** Container prose routinely opens a sentence
  with "The `<old>` plugin ships…", which a lowercase-only `the` misses; the token's only hit is
  then Form 2, which container mode suppresses as residue, so apply mode finishes with the stale
  reference in place. Only the article is case-flexible — the token itself stays case-sensitive
  (see `#1394`).
- **Hyphen boundary, same reason as Form 13.** A word boundary counts a hyphen as a boundary, so
  the possessive would fire inside a kebab-case superstring — renaming `guard` would match
  `` `context-guard` ``'s. The leading `(^|[^\w-])` excludes an adjacent hyphen. The appositive
  alternative is already safe: the noun-class word must follow the token. Verified:
  `` `guard` ``'s and `guard's` match, `` `context-guard` ``'s does not.
- **Inline-code wrapping is the common case, not the exception:** in markdown the token is
  usually a code span, so the literal `<old>'s` sequence never appears — it is
  `` `<old>` `` followed by `'s`. The optional backticks are what make this form fire on
  real documentation; without them it silently misses its own motivating example. Form 13
  carries the same allowance for the same reason.
- **Why it is Certain even when `<old>` is a blocklisted verb:** English verbs do not take
  the possessive clitic, and a noun-class appositive (`the X plugin`) forces the naming
  reading. Both shapes are grammatically incompatible with the verb sense, so this is safe
  where Form 2 is not.
- **False-positives:** a token that is a noun in ordinary use ("the review plugin" vs a
  review) can still collide; when `<old>` is a common NOUN rather than a verb, demote this
  form to ambiguous.
- **Extend the appositive noun class** to whatever the consuming repository calls its
  containers.

## Phase 0 — pre-sweep blocklist load

Before running any pattern, load the English-verb blocklist from `triage.md`. Any bare-token (Form 2) or chain-context match (Forms 4, 5, 6, 9) where the token is in the blocklist is forced into ambiguous bucket regardless of regex precision.

**Precedence: a container-position match wins its line outright.** Forms 13–15 are strictly
more specific than Form 2 — every line they match, Form 2 also matches. Without precedence the
new forms would only ADD hits, leaving the Form 2 flood they exist to avoid fully intact.

**Deduplicate by OCCURRENCE SPAN, not by line.** A single line can carry two independent
references — `Use <old> via /plugin install <old>@marketplace` has a bare one and a
command-argument one. Collapsing the line would drop the bare occurrence, and since Phase 5
replaces one span at a time (`replace_all: false`), the surviving reference would then be
reclassified as residue, excluded by container mode, and the re-sweep would declare completion
with a live stale reference still in the file. Key each match by `(file, line, start, end)` and
suppress a weaker match only when its span is **covered by** a more-specific match's span.

**Key every match by its CAPTURED `<old>` span, not by the whole match span.** A regex match
usually spans more than the token: Form 13's management-verb alternative spans
`/plugin install <old>@` while its qualified-id alternative spans `<old>@acme-tools`. Those two
overlap without either containing the other, so a whole-span coverage test keeps both and
schedules two Edits on one token — the second failing because the first already rewrote it.
Compare the `(start, end)` of the captured `<old>` itself; everything else in a match is context,
not the thing being replaced.

**With that keying, coverage collapses COEQUAL matches too, not only weaker ones.** When two
matches share the same `<old>` span, keep ONE: prefer the widest MATCH span (it carries the most
context for reporting), and on a tie the earlier-numbered form. Same test, applied within a form
as well as across forms.

With that keying, dedup runs AFTER the sweep and BEFORE triage:

1. An OCCURRENCE matched by any of Forms 13–15 is attributed to that form and enters **whatever
   bucket the OWNING FORM assigns to the matching alternative, after its scope rules are
   applied**. Certain is the default, not the outcome — the owning form may assign any of the
   three buckets, and precedence carries that assignment through unchanged:

   | Owning form and alternative | Bucket |
   |---|---|
   | Form 13 management-verb (`/plugin install <old>`) | Certain |
   | Form 13 bare qualified-id (`<old>@slug`) | **Chain-context** |
   | Form 14 title, container-owned file, uncommon token | Certain |
   | Form 14 manifest/catalog declaration | Certain (scope rule does not apply) |
   | Form 14 title, other file, or common-word token | **Ambiguous** |
   | Form 15 possessive/appositive, common-NOUN token | **Ambiguous** |
   | Form 15 otherwise | Certain |

   Drop the Form 2 (and any chain-form) match for that same SPAN — it is the same reference seen
   through a weaker lens, not a second finding. A bare-token match elsewhere on the line is a
   DIFFERENT reference and survives.

   **Precedence changes WHICH form owns the line, never the safety of its rating.** Attributing
   a line to Form 14 and then forcing it Certain would use precedence to launder a
   demotion — the exact false positive Form 14's scope rule exists to prevent, and worse than
   the Form 2 hit it replaced. Enumerating only Certain-and-Ambiguous would do the same to
   Form 13's qualified-id alternative, whose demotion target is the MIDDLE bucket: flattened to
   Certain it auto-applies, and apply mode rewrites a dotless address such as `t@t`. Read the
   bucket off the owning alternative; never off this rule.
2. Only lines Forms 13–15 did NOT match fall through to Form 2's blocklist rule above.

The Phase 0 rule is therefore scoped to what actually reaches Form 2: it forces a
blocklisted token's bare-token matches ambiguous, and container-position matches never
become bare-token matches. Report the deduplication in the audit output — "N Form-2 hits
superseded by container-position matches" — so a reader can see the suppression happened
rather than inferring it from a smaller number.

**Precedence alone is NOT sufficient — it only resolves lines the container forms also
matched.** On the measured fixture that is 8 lines out of Form 2's 134. The other 126 are
ordinary verb uses that no container form touches, so they fall through to Form 2 and, when
the token is absent from the static blocklist, take its **Certain** default. Deduplicating
overlaps does nothing for them.

## Phase 0b — container-rename mode

Declare the sweep's MODE at Phase 0, from what is being renamed.

**Selecting the mode — a concrete ladder, not a judgment call.** Getting this wrong is costly in
both directions: identifier mode on a container restores the Form 2 flood, container mode on an
identifier suppresses bare references that were genuinely actionable. Resolve in this order and
stop at the first rule that fires:

1. **Explicit override.** The invocation says which (`--container` / `--identifier`). Honor it.
2. **Filesystem evidence — a directory named `<old>` whose parent is a container root.** A
   `plugins/<old>/`, `packages/<old>/`, or the repo's own equivalent, containing a manifest
   (`plugin.json`, `package.json`, `pyproject.toml`, …) → **container**. Check the state BEFORE
   the rename when the move already happened: look for `<new>` in the same position, or read the
   pair out of `git log --diff-filter=R` / `git status`.
3. **Manifest evidence.** `<old>` appears as the `name`/`id` field of such a manifest, or as a
   key in a marketplace/registry catalog → **container**.
4. **Invocation-shape evidence.** The tree contains `/<old>:<something>` (a namespaced
   invocation) → `<old>` is the namespace, so **container**. `/<old>` with no colon suffix →
   **identifier**.
5. **Nothing fired → ASK.** One `AskUserQuestion`: "Is `<old>` a container (plugin, package,
   marketplace entry) or an identifier (skill, mode, action)?" with the evidence checked so far
   shown, so the answer is informed rather than guessed.

Do NOT infer mode from the token's shape — hyphenation, length, or whether it looks like a word
are all uncorrelated with what the thing IS. Never silently default; an unstated default is how
one of these two failure modes ships without anyone choosing it. Record the resolved mode and
the rule that fired in the audit report, so a reader can see which one applied and override it.

The two modes:

- **Identifier rename** (a skill, a mode, a dotted ID) — every form applies as before. Nothing
  below changes.
- **Container rename** (a plugin, a marketplace entry, a package) — the thing being renamed is
  a proper name, so a bare-token occurrence is EVIDENCE OF NOTHING: it is as likely to be the
  word used ordinarily as the container referenced. In this mode:
  1. Forms 13–15 (plus Forms 1 and 3, which are already position-anchored) are the forms that
     can produce the **Certain** bucket — but each match takes the bucket ITS OWN alternative
     assigns, per the table in "Phase 0". Container mode selects which forms are eligible for
     Certain; it never promotes an alternative its own form demoted. Form 13's bare qualified-id
     alternative stays **Chain-context** here, and a scope-demoted Form 14 title stays
     **Ambiguous** — mode does not launder either.
  2. Form 2's residue — every bare-token line NOT matched by a position-anchored form — is
     **excluded from Certain entirely**, regardless of blocklist membership. Report it as a
     single aggregate count ("126 bare-token occurrences not in container position, not
     proposed"), never as per-match prompts.
  3. Surface the residue only if the user explicitly asks to widen (`--include-bare-token`),
     and then as Ambiguous, never Certain.

Container renames are exactly the case where bare-token position carries no signal, so
spending the user's attention on it is a cost with no corresponding catch. The static
blocklist is irrelevant here — mode is a property of what is being renamed, not of whether
someone remembered to list the token.

**With mode + precedence together**, the measured fixture resolves as: 8 Certain
container-position findings, 126 bare-token occurrences reported as an aggregate and not
proposed, and 0 confirmation prompts — against Form 2's unaided 134.

## Phase 6 — pattern library evolution

When the skill's re-sweep finds a NEW syntactic form not covered above:

1. STOP — do not silently mangle. Report the new form to user.
2. Document the pattern in this file with all 5 fields (form name, regex, triage default, example, false-positives)
3. Re-run sweep with extended pattern library

**A new rule is not landed until every site that states the old one is updated.** This skill's
contract is spread across `SKILL.md`, `context/patterns.md`, `context/triage.md`,
`context/audit.md`, `context/audit-modes.md`, `context/apply.md`, and `evals/evals.json` — the
same fact is stated in several of them by design, so a rule changed in one place leaves the
others asserting its opposite. Three review rounds on the change that added Forms 13–15 were
consumed almost entirely by that class: precedence said Certain while Form 14's scope rule said
Ambiguous; `apply.md` learned the actionable-count rule while `SKILL.md` still said `count == 0`
twice and an eval still asserted the raw count; a flag was documented in `patterns.md` and
registered nowhere.

After changing any rule here, grep the whole skill directory for the claim you just changed —
the old bucket name, the old count semantics, the old flag list, the enumerated form list — and
reconcile every hit, evals included. An eval asserting superseded behavior is worse than a stale
sentence: it will fail against the corrected skill and read as a regression.

**Validate a new form on BOTH axes before adding it.** Recall alone is not evidence — Form 2
already has perfect recall on every form here and is still unusable when the token is a verb.
Measure the candidate against a real fixture: the reference commit that FIXED the missed
references (its removed lines are the defect set) for recall, and the whole pre-fix tree for
precision, reporting the new form's hit count beside bare-token Form 2's on that same tree.
A form that does not beat Form 2 on precision is not carrying its weight.

## Cross-platform note

All patterns are ripgrep-compatible (PCRE2 subset). Invoke via the Grep tool, NOT raw shell — Grep handles cross-platform path quoting and is faster than spawning `rg`. If a shell fallback is unavoidable, use `git grep -nE` scoped to tracked files or `rg` from the repo root with the Auto-exclusions applied — never `grep -P` (Perl regex doesn't exist on macOS BSD grep). Do not use lookbehinds — Form 1 uses `\B` instead.

**A raw `rg` fallback needs `--hidden`; the Grep tool and `git grep` do not.** Container manifests
routinely live in DOT-directories — `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
— and bare `rg` skips hidden paths by default, so it returns zero for Form 14's declaration
alternative and Form 3's container-root alternative on exactly the files those alternatives exist
to reach. Verified on this tree: `rg '"name": "docs-hygiene"'` finds nothing, `rg --hidden` finds
both manifests, and the Grep tool and `git grep` find both without a flag. Prefer the Grep tool.
