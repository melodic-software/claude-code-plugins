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
(^|[^\w/])/plugins?\s+(install|uninstall|configure|enable|disable|update|add|remove)\s+`?<old>\b
\b<old>@[\w]([\w-]*[\w])?([^\w.@-]|$)
```

- **Triage default:** Certain
- **Catches:** `<old>` as the ARGUMENT to a management command rather than as the command
  itself — `/plugin install <old>@marketplace`, `/plugin configure <old>`,
  `/plugin enable <old>` — plus the `<old>@<marketplace>` qualified-id form wherever it
  appears (settings examples, install snippets, `enabledPlugins` / `pluginConfigs` keys).
- **Why Form 1 misses it:** Form 1 anchors on `/<old>`. Here the slash belongs to `plugin`,
  and `<old>` sits one-to-several words downstream with no slash of its own.
- **Why the leading `[^\w/]` alternation:** keeps `.../plugin install x` (a path) from
  matching while still allowing a line start, a space, or a backtick before the slash.
- **Optional backtick before `<old>`:** these appear inside inline code spans constantly
  (`` `/plugin configure <old>` ``); without `` `? `` the pattern misses the most common
  rendering.
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
^(name|title):\s*("<old>"|'<old>'|<old>)\s*$
```

- **Triage default:** Certain
- **Catches:** an ATX heading whose ENTIRE content is the renamed token — the README H1 that
  names the thing — and frontmatter `name:` / `title:` declaring it.
- **Why the `$` anchor is load-bearing:** it is what makes this Certain rather than
  ambiguous. A heading that merely *contains* the token (`## How re-anchor works`) may well
  be verb usage and belongs in Form 2's ambiguous bucket; a heading that IS the token can
  only be naming it.
- **Quote handling:** the alternation accepts a bare, double-quoted, or single-quoted value
  and requires the quotes to PAIR — `"<old>"` and `'<old>'`, never `"<old>'`. A naive
  `["']?<old>["']?` would match the mismatched form, which is not valid YAML.
- **False-positives — real, and the reason for the scope rule below.** "A heading that IS the
  token can only be naming it" holds when the token is coined or hyphenated. It FAILS when the
  container has an ordinary-word name: renaming a `testing` plugin matches this repository's own
  `README.md:86` (`### Testing`, a marketplace category heading), and renaming an `architecture`
  plugin matches `plugins/miro/README.md:39` (`## Architecture`, an unrelated design section).
  Both were verified against the tree. Under precedence, a false Certain here is worse than a
  Form 2 hit, because it DISCARDS the safer classification.
- **Scope rule (required):** rate a title match Certain only when the file is plausibly
  container-owned — the container's own README/SKILL/manifest, or a path under its directory.
  A heading match in a file the container does not own is **Ambiguous**, whatever the token
  looks like. When the token is a common English word, demote every title match to Ambiguous
  regardless of path.
- **Note:** a plugin/skill README H1 is the landing surface every consumer sees first, and
  it is the single most-missed reference in practice — the rename moves the directory, so
  the path-form patterns all pass, and nothing looks at line 1. That is why the form exists;
  the scope rule is what keeps it from over-reaching to every document in the tree.

## Form 15: Possessive and appositive container reference

```regex
`?\b<old>\b`?'s\b
\bthe `?<old>`? (plugin|skill|marketplace entry|package|module)\b
```

- **Triage default:** Certain
- **Catches:** prose where `<old>` stands in for the CONTAINER — "Report `<old>`'s effective
  configuration", "the `<old>` plugin ships…".
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

With that keying, dedup runs AFTER the sweep and BEFORE triage:

1. An OCCURRENCE matched by any of Forms 13–15 is attributed to that form and enters **that
   form's own triage bucket after its scope rules are applied** — which is Certain by default,
   but **Ambiguous** whenever the matching form demotes it (Form 14 outside container-owned
   files, or with a common-word token). Drop the Form 2 (and any chain-form) match for that
   same SPAN — it is the same reference seen through a weaker lens, not a second finding. A
   bare-token match elsewhere on the line is a DIFFERENT reference and survives.

   **Precedence changes WHICH form owns the line, never the safety of its rating.** Attributing
   a line to Form 14 and then forcing it Certain would use precedence to launder a
   demotion — the exact false positive Form 14's scope rule exists to prevent, and worse than
   the Form 2 hit it replaced. If the owning form demotes, the deduplicated line is Ambiguous.
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

Declare the sweep's MODE at Phase 0, from what is being renamed:

- **Identifier rename** (a skill, a mode, a dotted ID) — every form applies as before. Nothing
  below changes.
- **Container rename** (a plugin, a marketplace entry, a package) — the thing being renamed is
  a proper name, so a bare-token occurrence is EVIDENCE OF NOTHING: it is as likely to be the
  word used ordinarily as the container referenced. In this mode:
  1. Forms 13–15 (plus Forms 1 and 3, which are already position-anchored) produce the
     **Certain** bucket.
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

**Validate a new form on BOTH axes before adding it.** Recall alone is not evidence — Form 2
already has perfect recall on every form here and is still unusable when the token is a verb.
Measure the candidate against a real fixture: the reference commit that FIXED the missed
references (its removed lines are the defect set) for recall, and the whole pre-fix tree for
precision, reporting the new form's hit count beside bare-token Form 2's on that same tree.
A form that does not beat Form 2 on precision is not carrying its weight.

## Cross-platform note

All patterns are ripgrep-compatible (PCRE2 subset). Invoke via the Grep tool, NOT raw shell — Grep handles cross-platform path quoting and is faster than spawning `rg`. If a shell fallback is unavoidable, use `git grep -nE` scoped to tracked files or `rg` from the repo root with the Auto-exclusions applied — never `grep -P` (Perl regex doesn't exist on macOS BSD grep). Do not use lookbehinds — Form 1 uses `\B` instead.
