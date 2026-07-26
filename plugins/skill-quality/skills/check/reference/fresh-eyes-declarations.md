# Fresh-eyes declaration contract (check 21)

The contract check 21 enforces. It is generic: it assumes nothing about your repo's doctrine —
only that a skill step whose output judges work produced in the same context either declares
delegation to a fresh-context worker or declares an exemption, in the skill's own files.

## Why

A context that produced work is a biased judge of that work. A skill step that self-reviews,
self-scores, or self-verifies its own session's output carries that bias unless the judgment is
delegated to a fresh context. Check 21 is a deterministic scanner: it cannot understand prose, so
conformance is declared in one of two exact, greppable forms.

## Form 1 — delegation wording (visible prose)

The step's own text says the judgment goes to a fresh-context worker, matching the POSIX ERE:

```text
fresh[- ]context
```

The wording must be **visible prose**: an HTML comment is stripped before this detector runs, so a
hidden `<!-- dispatch this to a fresh-context agent -->` declares nothing — it would be exactly the
parallel marker Form 1 exists to rule out.

Both `fresh-context` and `fresh context` are canonical — and the same line must NAME the worker or
the dispatch as a whole word (with inflections): `agent(s)`/`subagent(s)`, `worker(s)`,
`advisor(s)`, `reviewer(s)`, `verifier(s)`, `dispatch(es|ed|ing)`, `delegate(s|d)`/`delegating`/
`delegation`. "dispatch a fresh-context subagent" declares; a bare "think about it in a fresh
context" assigns the judgment to no one and does not. Both halves need whole-word matches, so an
embedded stem counts for neither: "agentless" names no worker, and "Refresh context" is not the
fresh-context wording. The wording is visible prose, not a marker — it IS the model's
instruction, so a parallel hidden marker would be a second source of truth that drifts.

## Form 2 — exemption directive (HTML comment)

```markdown
<!-- fresh-eyes-exempt: <class> -- <reason> -->
```

- **Classes (closed set):** `deterministic-gate` (the pass/fail verdict is a script's, not the
  model's), `external-input` (the judgment is over input the context did not produce), `deferred`
  (a recorded decision to retrofit later — the reason cites the trigger, and a tracking issue where
  one exists).
- **`-- <reason>` is required.** Justification lives at the suppression site (the ESLint
  `-- description` syntax is the precedent). A directive without a reason FAILs.
- The HTML comment is renderer-invisible but model-visible; it follows the inline-directive
  precedent of markdownlint and Vale. A trailing `\r` is tolerated (CRLF checkouts).

## Check semantics

Rows evaluate top-down; the first match wins per detection site.

| Condition | Result |
|---|---|
| Exemption directive with unknown class or malformed syntax | FAIL |
| Exemption directive missing the `-- <reason>` | FAIL |
| Judgment-language hit with BOTH delegation wording AND a directive in window | pass (INFO: contradictory declaration — hand-verify) |
| Judgment-language hit with delegation wording in the proximity window | pass (INFO) |
| Judgment-language hit with a valid exemption directive in the proximity window | pass (INFO) |
| Judgment-language hit with neither | WARN |
| Exemption directive with no judgment-language hit in its window (stale directive) | WARN (advisory — the heuristic list, not your directive, may be the gap; verify before removing) |

## Scan mechanics

- **Surface:** `SKILL.md` plus markdown under the skill's own `context/`, `templates/`,
  `reference/`, `references/`, `actions/`, `lanes/`, and `catalog/` directories. `vendor/` and
  `evals/` are excluded (vendored content is byte-frozen; evals fixtures contain arbitrary prose).
  Plugin-level shared files outside the skill directory are NOT scanned — anchor your declaration
  in the skill's own files even when the judgment mechanics live in a shared spoke.
- **Markdown structure:** see the parsing contract below. Keep literal directive examples inside
  fences — a bare `<class>` placeholder in live prose would FAIL as an unknown class.
- **Every directive on a line is classified on its own**, bounded at its own `-->`, so a malformed
  directive cannot borrow a valid neighbour's class or reason to escape the FAIL.
- **Proximity is per-file and line-based** (`FRESH_EYES_PROXIMITY_LINES` in `check-skill.sh`). A
  declaration in a different file of the same skill does not satisfy proximity; the WARN message
  says so ("declaration may live in a referenced spoke — hand-verify").
- **Judgment-language heuristic:** a curated POSIX ERE list shipped in `check-skill.sh`. It is a
  heuristic, WARN-only by design. Curation policy: this plugin owns the list; update triggers are a
  confirmed false hit, a valid exemption directive reading stale, or a fleet regression.
  Disposition ladder for any WARN during triage: false hit → regex fix; genuine hit → delegate or
  add a directive; declaration-in-spoke gap → hand-verified note, no code change.

## Parsing contract

Check 21 runs on a contributor's machine with nothing but a POSIX shell and `awk`, so its markdown
handling is a hand-written structure pass, not a CommonMark implementation. This section is the
scanner's **bounded claim**: what it models, what it does not attempt, and what it does when it
cannot tell. A finding against this check is measured against this list, not against full CommonMark.

### Modeled

- **Fenced code blocks**, backtick and tilde. A closer is a same-character run at least as long as
  the opener with only whitespace after it; opener and closer indentation cap at three spaces.
- **Info strings.** An info-string line inside a fence is content, never a closer. A backtick opener
  whose info string contains a backtick is prose, not a fence (CommonMark forbids it).
- **Container-nested fences.** Blockquote and list-marker prefixes are stripped before fence
  matching, so `> ~~~markdown` and `- ```markdown` open fences. Only a fence whose own opener carried
  a prefix strips prefixes inside the fence, so a quoted run cannot close an unprefixed fence.
- **Container termination.** A nested fence ends with its container: a blockquote when the quote
  depth drops below the opener's, a list item on a dedent below the opener's content column.
- **Inline code spans**, pairing a backtick run with the next run of exactly equal length, including
  multi-backtick spans and spans that cross a newline (the carry expires at the next blank line or
  fence, since a span cannot outlive its paragraph).
- **Backslash escapes**, resolved in the same pass as spans because CommonMark couples them: outside
  a span an escape makes the next character literal, so `` \` `` opens no span and `\<!-- ... -->` is
  text rather than a directive; inside a span nothing is escaped, so a literal backslash before the
  closing run does not stop it closing.
- **Multiple directives on one line**, each classified independently and bounded at its own `-->`.
  The name must be followed by `:`, whitespace, or `-->`, so an ordinary comment about a longer
  identifier such as `fresh-eyes-exemption` is not read as a directive.
- **YAML frontmatter is skipped**, not parsed as markdown: nothing in it is a fence, a span, or a
  directive, and every structural carry resets at its closing `---`.
- **Whole-word wording boundaries** on both halves of Form 1, so `agentless` names no worker and
  `Refresh context` is not the fresh-context wording.
- **Single-line HTML comments**, stripped before the Form 1 detector so hidden wording cannot declare.

### Not attempted

Each of these is a real construct the scanner does not model. All are recorded here rather than
patched, because the list of constructs CommonMark permits is unbounded and chasing it is what this
contract exists to stop:

- **Indented code blocks.** A four-space-indented line is either indented code or a list item's
  continuation; separating them needs a block parser. Such a line is treated as ambiguous — see
  *Ambiguity* below.
- **Mixed container stacks.** Only blockquote depth and a single list-marker column are tracked, so a
  fence opened at `> - ~~~markdown` is not released when the inner list ends while the quote
  continues.
- **Paragraph-interrupting block constructs.** A pending cross-line span carry expires at a blank
  line or a fence, but not at an ATX heading, thematic break, or table that also interrupts the
  paragraph in CommonMark.
- **Multi-line HTML comments.** Comment state is not carried across lines: an unterminated `<!--`
  discards the rest of its own line only, so a comment body on a later line is read as prose.
- **Reference definitions, HTML blocks, setext headings, and link/image syntax** are not interpreted
  at all; they are scanned as ordinary prose.

### Ambiguity — the scanner declines rather than guesses

The two verdict families are asymmetric, and the whole posture follows from that:

- `DIRECTIVE_MALFORMED` and `DIRECTIVE_NOREASON` are hard **FAIL**s. A false positive here blocks a
  legitimate skill author on a parser artifact.
- `HIT_WORDING` / `HIT_NONE` / `HIT_DIRECTIVE` and the stale-directive notice are **WARN**s or notes.
  A miss there costs one nudge.

So where the structure pass reaches a configuration it cannot resolve, it **withholds the hard
verdicts** for directives on that line. It also withholds the stale WARN, and refuses to let such a
directive satisfy a nearby judgment step — the same lack of confidence cuts both ways, so a literal
exemption inside an indented example cannot silence the warning that step deserves. The judgment
detector itself continues to run. Today this fires on the
indented-code case above; the mechanism could extend to a resolved cross-line span carry and to an
unterminated comment, and deliberately does not, because both occur throughout ordinary prose and
suppressing them would widen the blind spot far past anything observed.

Where an unmodeled construct instead causes content to be **skipped** — an unclosed fence or span
carry swallowing lines — no verdict forms at all. That is already the safe direction, and it is worth
being exact: suppression prevents wrong FAILs; it is not what makes a skipped line harmless.

**This posture is specific to check 21**, whose verdicts are authoring nudges. Do not carry it into a
gate whose verdict is a security decision, where a miss is a bypass and fail-closed is correct.
