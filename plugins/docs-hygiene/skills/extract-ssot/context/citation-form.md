# Citation form

Exact contract for how callers cite an SSOT after extraction. Applies to markdown citations between rule files / skills / docs. (Code and config callers use the language's idiomatic form — `import`, `using`, YAML anchor, JSON `$ref` — not this contract.)

SKILL.md cites the headline form; this file covers the full template, line-wrap edge case, and rename discipline.

## Headline contract

Cite by **exact H3 heading text** + **1-line inline summary** at every call site. Template:

```text
<short scope phrase> per `<rule-file>.md` "<exact heading text>".
```

Concrete shapes the template produces:

```text
<workflow step> per `<workflow-rule>.md` "<step heading>".
<naming convention> per `<style-guide>.md` "<rule heading>".
<API verb> per `<api-vocabulary>.md` "<verb heading>".
```

Three rules baked in:

1. **Backticked filename** — `` `<file>.md` `` not `<file>.md`. Disambiguates filename from prose; lets grep find the citation deterministically
2. **Quoted heading text** — `"<heading>"` not `<heading>` or `'<heading>'`. Quote characters are stable; heading capitalization matches the SSOT exactly
3. **One level deep** — never chain `A.md` → `B.md` → `C.md`. If the SSOT references another SSOT for the same domain, fix that first (anti-pattern #2 over-indirection)

## 1-line inline summary template

For non-trivial citations, append a 1-line summary AFTER the citation so the reader can skim the caller and understand the shape without clicking through:

```text
<scope phrase> per `<file>.md` "<heading>" — <≤80 char shape description>.
```

Examples of the shape pattern (substitute the actual rule file and heading at the call site):

- A workflow step citation might look like: `<step name> per <workflow>.md "<step heading>" — short cadence/cycle description.`
- A naming citation might look like: `<naming concern> per <style-guide>.md "<rule heading>" — short rule shape (kebab-case, 40-char cap, etc).`

Summary format: `— <≤80 char description>`. Em-dash separator preferred over colon (visual scan). Aim for the SHAPE of the cited rule, not its full content.

When to inline a summary:

| Caller context | Summary needed? |
|----------------|-----------------|
| Citation appears once in a body paragraph | YES — reader hits cold context |
| Citation appears in a Cross-references section list | NO — section context already orients the reader |
| Citation is repeated within ~50 lines of the same caller | First citation YES, subsequent NO (reader has the context) |
| Citation is in a table cell | YES if the cell is the caller's only reference; NO if the cell is one of many short references |

## Line-wrap edge case

Heading text MUST stay on one line at the citation site, even if it pushes the surrounding sentence past line width. The literal heading is the grep token; line-wrapped citations are unrecoverable.

❌ Wrong (heading wraps across lines):

```text
<scope phrase> per `<file>.md` "<long heading text part 1
part 2)">.
```

✅ Right (heading on one line; rest wraps freely):

```text
<scope phrase> per `<file>.md`
"<full heading text on one line>" — <summary>.
```

If the heading itself contains characters that confuse grep (parens, em-dashes, quote marks), the SSOT author should rename the heading to something simpler. Heading text should be greppable as-is.

## Rename discipline

Headings in an SSOT file are stable contracts. After ANY heading edit in an SSOT, run `/rename-references` immediately — it sweeps all 10 syntactic forms including:

| Form | Example | Pure-token grep catches? |
|------|---------|--------------------------|
| Direct citation | `per X.md "Y"` | YES |
| Chain prose | `the Y rule (X.md "Y")` | NO — wrap form |
| Comma-list | `X.md headings "Y", "Z", "W"` | NO — needs context match |
| Numbered table row | `\| 3 \| Y \| ...` | NO — table-row form |
| Frontmatter chain | `extends: ../X.md#Y` | NO — frontmatter form |
| Frontmatter glob | `paths: [".claude/rules/X.md"]` | NO if heading-scoped |
| Cross-skill mode | `/<skill> mode Y` | NO — verb form |
| Mention-only | `the Y heading` | NO — context-dependent |
| Heading definition | `## Y` (the SSOT itself) | YES |
| Anchor URL | `X.md#y` | YES if exact-case |

`/rename-references` runs all 10. Pure-token grep alone misses 6+ forms.

## Worked examples

### Headline form across multiple call sites (good)

When several call sites cite different verbs from the same vocabulary rule, every citation uses the same shape:

```text
<verb 1> per `<vocabulary-rule>.md` "<verb 1 heading>".
<verb 2> per `<vocabulary-rule>.md` "<verb 2 heading>".
<verb 3> per `<vocabulary-rule>.md` "<verb 3 heading>".
<verb 4> per `<vocabulary-rule>.md` "<verb 4 heading>".
```

Same shape across all — easy to grep, easy to rename, easy to skim.

### With 1-line summary (good)

When a skill orchestrates a multi-skill flow and cites another skill's mode:

```text
<scope phrase> per `<other-skill>/SKILL.md` "<mode name>" — <one-line description of what that mode does at a high level>.
```

Reader skims, sees the scope phrase, understands what the cited mode will do without clicking.

### Refused (anti-pattern: chain prose)

❌ Don't write:

```text
The <pattern> pattern (covered in `<wrapper-rule>.md` "<pattern>",
which itself cites `<base-rule>.md` for the underlying shapes) ...
```

The chain prose form hides the citation in narrative; pure-token grep can find the heading but the rename sweep needs context match. Rewrite as a direct citation to the canonical SSOT:

```text
<pattern> per `<base-rule>.md` "<pattern>".
```

## Cross-references

- `decision-framework.md` — 6-test extraction gate + 5-test keep-inline gate + output-type criteria
- `anti-patterns.md` #1 (citation rot), #4 (loss of locality), #5 (reference resolution failure) — failure modes this contract guards against
- `/audit-encapsulation` — citation form for skill internals (cite the `/skill-name` invocation, not an internal file path)
- `/rename-references` — owns the full 10-pattern sweep specification
- Numbered references — write the full `docs/<family>/<number>-<slug>.md` path, not a bare number shorthand like "ADR-NNNN" (number-only shorthand collides)
