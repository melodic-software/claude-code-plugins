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

Both `fresh-context` and `fresh context` are canonical — and the same line must NAME the worker or
the dispatch (a token matching `agent|worker|advisor|reviewer|verifier|dispatch|delegat`): "dispatch
a fresh-context subagent" declares; a bare "think about it in a fresh context" assigns the
judgment to no one and does not. The wording is visible prose, not a marker — it IS the model's
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
- **Fence- and span-aware:** fenced code blocks and inline code spans are ignored by both
  detectors, so docs (like this page) can show literal examples. Fences follow CommonMark
  matching: a closer is a same-character run at least as long as its opener with only spaces
  after it — an info-string line inside a fence never closes it. Spans pair a backtick run with
  the next run of exactly the same length (multi-backtick spans included); an unpaired run is
  literal. Keep literal directive examples inside fences — a bare `<class>` placeholder in prose
  would FAIL as an unknown class.
- **Proximity is per-file and line-based** (`FRESH_EYES_PROXIMITY_LINES` in `check-skill.sh`). A
  declaration in a different file of the same skill does not satisfy proximity; the WARN message
  says so ("declaration may live in a referenced spoke — hand-verify").
- **Judgment-language heuristic:** a curated POSIX ERE list shipped in `check-skill.sh`. It is a
  heuristic, WARN-only by design. Curation policy: this plugin owns the list; update triggers are a
  confirmed false hit, a valid exemption directive reading stale, or a fleet regression.
  Disposition ladder for any WARN during triage: false hit → regex fix; genuine hit → delegate or
  add a directive; declaration-in-spoke gap → hand-verified note, no code change.
