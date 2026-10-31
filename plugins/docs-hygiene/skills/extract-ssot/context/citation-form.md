# Citation form

## Contents

- [Headline contract](#headline-contract)
- [1-line inline summary template](#1-line-inline-summary-template)
- [Line-wrap edge case](#line-wrap-edge-case)
- [Rename discipline](#rename-discipline)
- [Worked examples](#worked-examples)
- [Cross-references](#cross-references)

How markdown callers (rule files, skills, docs) cite an SSOT after extraction. Code and config callers use the idiomatic form instead, such as `import`, `using`, a YAML anchor, or JSON `$ref`.

## Headline contract

Cite by **exact H3 heading text** + **1-line inline summary** at every call site. Template:

```text
<short scope phrase> per `<rule-file>.md` "<exact heading text>".
```

Concrete shapes:

```text
<workflow step> per `<workflow-rule>.md` "<step heading>".
<naming convention> per `<style-guide>.md` "<rule heading>".
<API verb> per `<api-vocabulary>.md` "<verb heading>".
```

Three rules:

1. **Backticked filename**: `` `<file>.md` `` not `<file>.md`. Disambiguates filename from prose; lets grep find the citation deterministically
2. **Quoted heading text**: `"<heading>"` not `<heading>` or `'<heading>'`. Quote characters are stable; heading capitalization matches the SSOT exactly
3. **One level deep**: never chain `A.md` → `B.md` → `C.md`. If the SSOT references another SSOT for the same domain, fix that first (anti-pattern #2 over-indirection)

## 1-line inline summary template

For non-trivial citations, append a 1-line summary AFTER the citation so a reader skimming the caller understands the shape without clicking through:

```text
<scope phrase> per `<file>.md` "<heading>": <≤80 char shape description>.
```

Examples (substitute the actual rule file and heading):

- A workflow step citation might look like: `<step name> per <workflow>.md "<step heading>": short cadence/cycle description.`
- A naming citation might look like: `<naming concern> per <style-guide>.md "<rule heading>": short rule shape (kebab-case, 40-char cap, etc).`

Summary format: `: <≤80 char description>`. The colon is the separator, not an em dash: this repository's house style admits a colon where a definition or description follows and admits no em dash at all. Give the SHAPE of the cited rule, not its full content.

When to inline a summary:

| Caller context | Summary needed? |
|----------------|-----------------|
| Citation appears once in a body paragraph | YES, the reader hits cold context |
| Citation appears in a Cross-references section list | NO, section context already orients the reader |
| Citation is repeated within ~50 lines of the same caller | First citation YES, subsequent NO (reader has the context) |
| Citation is in a table cell | YES if the cell is the caller's only reference; NO if the cell is one of many short references |

## Line-wrap edge case

Heading text MUST stay on one line at the citation site, even past line width. The literal heading is the grep token; a line-wrapped citation is unrecoverable.

❌ Wrong (heading wraps across lines):

```text
<scope phrase> per `<file>.md` "<long heading text part 1
part 2)">.
```

✅ Right (heading on one line; rest wraps freely):

```text
<scope phrase> per `<file>.md`
"<full heading text on one line>": <summary>.
```

If the heading contains characters that confuse grep (parens, em-dashes, quote marks), the SSOT author should rename it to something greppable as-is.

## Rename discipline

Headings in an SSOT file are stable contracts. After ANY heading edit in an SSOT, invoke `/docs-hygiene:rename-references` via the Skill tool immediately. It sweeps all 10 syntactic forms including:

| Form | Example | Pure-token grep catches? |
|------|---------|--------------------------|
| Direct citation | `per X.md "Y"` | YES |
| Chain prose | `the Y rule (X.md "Y")` | NO, wrap form |
| Comma-list | `X.md headings "Y", "Z", "W"` | NO, needs context match |
| Numbered table row | `\| 3 \| Y \| ...` | NO, table-row form |
| Frontmatter chain | `extends: ../X.md#Y` | NO, frontmatter form |
| Frontmatter glob | `paths: [".claude/rules/X.md"]` | NO if heading-scoped |
| Cross-skill mode | `/<skill> mode Y` | NO, verb form |
| Mention-only | `the Y heading` | NO, context-dependent |
| Heading definition | `## Y` (the SSOT itself) | YES |
| Anchor URL | `X.md#y` | YES if exact-case |

`/docs-hygiene:rename-references` runs all 10. Pure-token grep alone misses 6+ forms.

## Worked examples

### Headline form across multiple call sites (good)

Call sites citing different verbs from the same vocabulary rule all use the same shape:

```text
<verb 1> per `<vocabulary-rule>.md` "<verb 1 heading>".
<verb 2> per `<vocabulary-rule>.md` "<verb 2 heading>".
<verb 3> per `<vocabulary-rule>.md` "<verb 3 heading>".
<verb 4> per `<vocabulary-rule>.md` "<verb 4 heading>".
```

Same shape across all: easy to grep, rename, and skim.

### With 1-line summary (good)

A skill orchestrating a multi-skill flow cites another skill's mode:

```text
<scope phrase> per `<other-skill>/SKILL.md` "<mode name>": <one-line description of what that mode does at a high level>.
```

### Refused (anti-pattern: chain prose)

❌ Don't write:

```text
The <pattern> pattern (covered in `<wrapper-rule>.md` "<pattern>",
which itself cites `<base-rule>.md` for the underlying shapes) ...
```

Chain prose hides the citation in narrative; pure-token grep finds the heading but the rename sweep needs context match. Rewrite as a direct citation to the canonical SSOT:

```text
<pattern> per `<base-rule>.md` "<pattern>".
```

## Cross-references

- `decision-framework.md`: 6-test extraction gate + 5-test keep-inline gate + output-type criteria
- `anti-patterns.md` #1 (citation rot), #4 (loss of locality), #5 (reference resolution failure): failure modes this contract guards against
- `/docs-hygiene:audit-encapsulation`: citation form for skill internals (cite the `/skill-name` invocation, not an internal file path)
- `/docs-hygiene:rename-references`: owns the full 10-pattern sweep specification
- Numbered references: write the full `docs/<family>/<number>-<slug>.md` path, not a bare number shorthand like "ADR-NNNN" (number-only shorthand collides)
