# Design resolution — fresh-eyes-checkpoint-audit

outcome: light-design (Tier B) — resolved via prior-session interview (decision ledger in the
topic's memory slice) plus two user decisions, two research passes, and a fresh-context plan
review this session (2026-07-19). No full /design session warranted: one new contract surface, no
new types or package topology.

## The one design-significant element: the declared-pattern contract

Check 18 (skill-quality:check) is deterministic grep; it cannot understand prose. The doctrine
therefore defines two exact, greppable patterns — the contract every conformant skill (and all ten
wave-2 retrofits) adopts.

**Spec ownership (published-plugin constraint):** the mechanical pattern spec (grammar, classes,
semantics) ships INSIDE the skill-quality plugin (`reference/` page) so third-party authors hit by
a finding can read the contract being enforced; check-18 messages point there. This repo's
PLUGIN-PHILOSOPHY delegation-mechanics section carries the rationale and points at the plugin as
the spec owner (convention-registry style). No cross-plugin or cross-repo file reference at runtime.

### Delegation pattern — canonical visible prose

A same-context judgment step delegates by matching the POSIX ERE **`fresh[- ]context`** (both the
hyphenated and spaced forms are canonical — already-compliant skills use both), plus the
dispatch-ladder conventions the doctrine specifies: generic-fallback rung when a named agent is
preferred, artifact-not-story inputs, degrade-when-absent. *(Amended 2026-07-22, Phase-1 review:
the matching line must also name the worker or dispatch — `agent|worker|advisor|reviewer|`
`verif|dispatch|delegat` — because a bare "in a fresh context" phrase assigns the judgment to no one;
surfaced by external review on the Phase-1 PR.)* *(Amended 2026-07-23, Phase-1 review: worker
token `verif` narrowed to `verifier` — the stem matched bare "verification" prose that dispatches
no worker; surfaced by external review on the Phase-1 PR.)* *(Amended 2026-07-23, Phase-1 review
round 3: worker terms match as whole words with explicit inflections — substring stems let
"agentless" satisfy the worker requirement; surfaced by external review on the Phase-1 PR.)*
*(Amended 2026-07-25, Phase-1 review round 4: the `fresh[- ]context` half is bounded as a whole
word too — unbounded, it matched inside "Refresh context", so ordinary refresh prose next to any
worker term satisfied the gate; surfaced by external review on the Phase-1 PR.)* *(Amended
2026-07-26, Phase-1 review round 5: HTML comments are stripped before this detector, enforcing the
visible-prose requirement the form already states — a hidden `<!-- ... fresh-context agent -->` was
satisfying it, which is precisely the parallel marker this form exists to rule out.)*
Visible prose, not a marker: the wording IS the model's instruction, so it must be visible
regardless — a parallel marker would be a second source of truth that drifts.

### Exemption directive — namespaced HTML comment

```markdown
<!-- fresh-eyes-exempt: <class> -- <reason> -->
```

- Classes (closed set): `deterministic-gate` | `external-input` | `deferred` — mirrors the
  fresh-eyes doctrine's non-trigger list plus the Brief's "explicitly deferred with a trigger".
  A `deferred` reason cites its trigger (and tracking issue where one exists).
- `-- <reason>` is REQUIRED (user standard: justification recorded at the suppression site;
  ESLint's `-- description` syntax is the precedent for the shape).
- HTML comment channel follows the universal Markdown-linter precedent (markdownlint, Vale; local
  precedent: `<!-- markdown-discipline-ignore -->`, `<!-- spellchecker:off -->`). Comments are
  VERIFIED-VISIBLE to the model at skill load (empirical, this repo, 2026-07-19) — renderer
  invisibility is the benefit; model invisibility was a refuted assumption and is NOT a design input.

### Check-18 semantics (user-locked: fuzzy = WARN-only)

Rows evaluate top-down; first match wins per detection site.

| Condition | Result |
|---|---|
| Exemption directive with unknown class or malformed syntax | FAIL |
| Exemption directive missing `-- <reason>` | FAIL |
| Judgment-language heuristic hit with both delegation wording AND an exemption directive in window | pass (note: contradictory declaration — hand-verify) |
| Judgment-language heuristic hit with `fresh[- ]context` wording in proximity window | pass (note) |
| Judgment-language heuristic hit with valid exemption directive in proximity window | pass (note) |
| Judgment-language heuristic hit with neither | WARN |
| Exemption directive with no judgment-language hit in proximity window (stale directive) | WARN (advisory — the heuristic list, not the directive, may be the gap; verify before removing) |

Scan mechanics (all constraints normative for implementation):

- **Scan surface:** `SKILL.md` plus markdown under `context/`, `templates/`, `reference/`,
  `references/`, `actions/`, `lanes/`, `catalog/` — skill-internal only. **`vendor/` and `evals/`
  are excluded** — vendored content is byte-frozen (check 8) so a finding there is permanently
  unclearable, and evals fixtures intentionally contain arbitrary prose. Plugin-level shared
  spokes (e.g. a plugin-root `context/` referenced by many skills) are OUTSIDE the scan surface —
  the checker is generic and cannot assume a plugin layout. Consequence, normative for doctrine
  and retrofits: **the declaration (delegation wording or exemption directive) anchors in each
  skill's own scanned files**, even when the judgment mechanics live in a shared spoke.
- **Fence-aware, span-aware, CRLF-tolerant:** fenced code blocks AND inline code spans are ignored
  by both detectors (self-reference guard: the gate's own docs and the doctrine show literal
  directive examples — the markdownlint-escapes-its-own-docs problem). Literal directive examples
  in shipped docs MUST sit inside fenced blocks — never in tables or bare prose (a table cell
  cannot hold a fence; a placeholder `<class>` literal would otherwise FAIL as unknown-class).
  Directive parsing tolerates an optional trailing `\r` (third-party repos without `eol=lf`
  checkout normalization). *(Amended 2026-07-23, Phase-1 review round 3: a backtick fence opener
  carrying a backtick in its info string is prose, not a fence — CommonMark forbids such an info
  string, and treating it as an opener suppressed every following line until a closing run.)*
  *(Amended 2026-07-23, Phase-1 review round 3: an unclosed backtick run carries across the
  newline, because a span may cross a line boundary and its content was reaching the parser as a
  blocking malformed directive. The carry expires at the next blank line or fence — a CommonMark
  span cannot outlive its paragraph — so a stray backtick cannot blind the scanner past it. The
  carry is deliberately optimistic: masking risks missing a declaration, whereas scanning risks
  failing a skill on legitimate code-span text.)* *(Amended 2026-07-25, Phase-1 review round 4:
  blockquote and list-marker prefixes are stripped before fence matching — a container-nested fence
  never entered fence mode, so a quoted example failed the skill on its own documentation. The strip
  applies in-fence only when the OPENER carried a prefix — otherwise a quoted run inside an
  unprefixed fence's own example would close it and leak the block, reintroducing the same failure
  it fixes. A container-nested fence also ends with its container — a blockquote when the quote DEPTH
  drops below the opener's, a list item on a dedent — since the fence flag is global and an unclosed
  nested opener would otherwise swallow every following top-level line. *(Amended 2026-07-26,
  Phase-1 review round 5: depth, not mere marker presence — a fence opened at quote depth two lives
  in the inner quote, so a later depth-one line has left it.)* Backslash escapes and code spans resolve in ONE
  left-to-right pass because CommonMark couples them: outside a span an escape makes the next
  character literal (an escaped backtick was masking a malformed directive into a silent pass, and an
  escaped `\<!--` is text that was wrongly parsed as a directive), while inside a span nothing is
  escaped, so a literal backslash before the closing run does not stop it closing. Two independent
  passes cannot express that coupling — the escape-blind pass misreads an escaped backtick as a
  delimiter and the escape-first pass destroys a legitimate closer.)* **Accepted gap:** indented code blocks are NOT
  suppressed — telling one apart from indented list-item continuation needs a block parser this
  scanner does not have, and guessing would silently drop declarations inside nested lists, the
  worse direction. The contract tells authors to fence literal examples.
- **One classification per directive, not per line** (amended 2026-07-25, Phase-1 review round 4):
  each `<!-- fresh-eyes-exempt ... -->` occurrence is classified independently, bounded at its own
  terminator. Classifying the whole line let a well-formed directive lend its class and reason to a
  malformed neighbour, so an unknown-class suppression could hide beside a valid one.
- **Proximity is per-file and line-based** (tunable constant beside the script's existing caps).
  Known limitation, documented in the WARN message: a declaration living in a referenced spoke
  file cannot satisfy proximity — "declaration may live in a referenced spoke — hand-verify".
- **Heuristic list:** curated POSIX ERE regexes shipped in the script (no `grep -P` — BSD/macOS
  grep lacks it), seeded from the actual phrasing of the ten audited skills AND the exempted
  steps' phrasing (stale-directive asymmetry: unlike ESLint's `reportUnusedDisableDirectives`, the
  "rule" here is heuristic, so a valid exemption phrased outside the list reads stale).
  **Curation policy:** the skill-quality plugin owns the list; update trigger = a fleet
  WARN-clean regression, a new exemption directive reading stale, or a confirmed false hit.
  WARN-disposition ladder for any hit during triage: false hit → regex fix in the same PR;
  genuine hit → retrofit or exemption directive; declaration-in-spoke co-location gap →
  hand-verified note, no code change.

## Research base (all verified 2026-07-19, official sources)

- Linter directive/severity survey: ESLint rule severities + disable-directive description syntax +
  `reportUnusedDisableDirectives`; ShellCheck `disable=` directives; markdownlint inline HTML-comment
  directive family; Vale alert levels + in-document directives; Semgrep `nosemgrep` + confidence
  metadata.
- SKILL.md body processing: entire file loads raw (Claude Code skills doc; Agent Skills spec "no
  format restrictions", entire-file load); no comment stripping documented; HTML-comment visibility
  to the model proven empirically in-session. MD033 disabled in this repo — directive is lint-clean.
