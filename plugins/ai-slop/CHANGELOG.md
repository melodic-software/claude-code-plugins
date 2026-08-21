# Changelog

## [0.3.2]

The catalog's cited source page lists an **Ineffective indicators** section — signals that
page's own editors consider unreliable for LLM detection. Until this release both that
section and **Comment-specific indicators** were a recorded fetch gap (the catalog-time
window ran out before those headings). That left a guardrail question unanswered: if a
rule we ship appeared there, we would be shipping a tell our own source classifies as
ineffective.

- **Negative finding, 2026-08-21.** Retrieved
  <https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing> (live revision
  [1370403579](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1370403579),
  `2026-08-20T23:13:41Z`) and re-read the catalog pin (revision
  [1369699198](https://en.wikipedia.org/w/index.php?title=Wikipedia:Signs_of_AI_writing&oldid=1369699198),
  2026-08-16, parse section 80). Both revisions list the same eight ineffective
  indicators: perfect grammar; mixed casual/formal registers; "bland"/"robotic" prose;
  undifferentiated "fancy"/"academic"/"formal" prose; transition words in isolation;
  unsourced content; bizarre wikitext; correct wikitext.
- **None of the 15 shipped script rules appear in that list**, including the two
  candidates the gap was filed to check (`rule-em-dash`, `rule-rule-of-three`). Those
  two remain valid *Style* / *Language and grammar* signs on the source page. The
  em-dash entry's "most useful […] in combination with other indicators, not by
  itself" sentence is a corroboration qualifier on a kept tell, not an Ineffective
  indicators listing; zero-tolerance stays the shipped house-style default.
- **Comment-specific indicators** retrieved in the same visit (pin section 62).
  Wikipedia talk-page scope. One of the seven tells already has a slug
  (`rule-canned-policy-assurance`). The other six land as `recorded-only` /
  `wikipedia-specific` entries so slug-based rechecks can track them:
  `rule-misquoted-policies`, `rule-maintenance-banner-transclusion`,
  `rule-sectioned-comments`, `rule-request-critic-input`,
  `rule-dismiss-origin-speculation`, `rule-redirect-to-content`. Inventory count
  59 → 65. No script-roster change.
- The inventory pin stays `1369699198`. Detector, emitter, evals, and rewrite guide are
  untouched: this is the fetch-gap close, not a roster change.

## [0.3.1]

The audit skill told operators to keep this plugin's findings away from the very relay route that
now remediates them. Both statements were true when 0.2.0 wrote them and neither survives `review`
0.26.0, which teaches the fix relay to honor a producer-declared remediation owner — but they fail
differently, and the entry says which is which: step 6's steer is now **flatly false**, while the
Purpose statement **draws a real distinction in the wrong place** rather than being false.

- **Step 6 of the audit flow no longer steers users off the route.** It said: "Recommend
  `review:fanout fix` only for `rule-utm-params` findings — it is the one rule the relay can apply
  meaning-preservingly; routing prose rewrites there retires the findings without fixing them."
  The second half is now flatly wrong. The crosswalk declares `/ai-slop:audit fix` as the
  remediation owner for the other fourteen rules, so the relay hands those rows to this skill
  instead of retiring them unfixed. This mattered more than an ordinary stale sentence because
  **the audit flow is the normal entry point that recommends remediation** — leaving it in place
  would have made the new route unreachable through the documented flow while the contract
  advertised it, and handed the model directly contradictory instructions.
- Step 6 now recommends `review:fanout fix` for the whole file when the operator is already
  running a fix pass, and this skill's own `fix` directly when they are not, and it names the one
  condition that changes the answer: the relay can only hand the rows over when `/ai-slop:audit`
  is available in that session, and surfaces them otherwise.
- **The Purpose section's detection-layer paragraph** drew the same line in the wrong place —
  "What the relay can actually apply is narrow… the findings file is how a consumer *sees* them,
  not how they get rewritten". The narrowness is real but it is about what the relay **applies**,
  not what it **routes**: `rule-utm-params` is still the only row the relay is *capable* of
  applying meaning-preservingly — it reaches the cleanup route, which prefers `/simplify` and
  applies rows itself only when `/simplify` is absent, so nothing promises it lands — and the
  other fourteen are now handed to this skill rather than left unrouted. The paragraph says
  that distinction explicitly, and keeps the true half — the cleanup route is a
  code-simplification skill that never loads this skill's rewrite guide, which is exactly why the
  declaration exists.

No behavior, script, or rule changed: this is the producer half of a claim the consumer now
honors. Detector, emitter, catalog, and evals are untouched.

## [0.3.0]

The audit eval cases described their input in prose. Nothing checked that the described input
produced the finding the case graded, and it drifted from the detector three times in one PR
(#3041) — each time a golden answer the scenario could not produce. Seven of the nine cases now
name a committed fixture instead.

- **Six eval fixtures ship under `skills/audit/evals/fixtures/`**, referenced from each case's
  `files` array: `report-only.md` (four rules on one file), `fix-guarded-rewrite.md` (two em dashes
  and two filler phrases), `rubric-boundary.md` (one script finding, promotional register the
  mechanical rules deliberately miss), `em-dash-substitution.md` (a single em dash),
  `triads.md` (rule-of-three at 3 hits in 69 words) and `knowledge-cutoff-prose.md` (the recorded
  false-positive class). Every case's `expected_output` now names the rules, lines and fired
  thresholds the detector actually emits, measured rather than asserted.
- **A case names its fixture through `files[]` and in prose, the way every sibling suite does** —
  `mcp-tools:audit` and `docs-hygiene:compress` both read "`evals/fixtures/<name>.md` relative to the
  skill directory", and none of the eighteen fixture-backed suites here builds a repository to audit
  in. These prompts are a *specification* of expected skill behavior, not a script: this repo has 200
  `evals.json` files and zero of the `case.yaml` / `prompt.md` + `graders/` layout `claude plugin
  eval` consumes, no manifest declares `experimental.evals`, and the only things that read
  `evals.json` are lint scripts. Nothing executes a prompt, so a prompt must be readable by a human
  or an agent working by hand, and environment control belongs nowhere in it. If this repo ever
  adopts the CLI's format, per-case setup has a first-class home there — a `scaffold_script` run
  under `--scaffold`.
- **Cases 2, 6 and 7 tell the reader to work on a copy.** They invoke `fix`, and the fix flow
  rewrites each flagged line in place, so running one by hand against the committed fixture
  remediates it and dirties the repo — and a later run then grades already-fixed input, where the
  declared findings no longer fire. One sentence in the prompt and one expectation per case, both
  about the outcome rather than the mechanism: the committed fixture is byte-identical after the run,
  and how the copy gets made is the reader's business. An instruction a case states but never checks
  is the same defect in miniature as the one this release removes.
- **Cases 4 and 5 state their premise instead of constructing it.** Both grade the persistence step,
  which `SKILL.md` gates on the audit having "examined tracked files", so each prompt says the
  audited file is tracked in the repo under audit and the expectations grade the skill's *decision*:
  that it treats persistence as applicable, fetches the producer contract first, and — case 4 —
  refuses to write when that fetch fails, rather than refusing because the target was out of tracked
  space. A case cannot verify real repository state, and pretending otherwise is what made case 4
  pass for the wrong reason. Case 5 also asserts the positive half — that the findings file is
  actually written — because `context/persist-findings.md` permits reporting without writing when the
  destination cannot be proven outside tracked space, so a negative-only case would be satisfied by a
  run that persists nothing at all.
- **This reverses 0.1.0's no-fixtures decision, which was recorded in `detect.test.sh`'s header.**
  That decision holds for the *unit* suite, whose fixtures are still built inline in a tmpdir. It
  does not survive contact with the eval suite: an eval case is graded against a deterministic
  detector run, so its scenario has to satisfy an ERE the eval author does not have in front of
  them. A committed fixture cannot disagree with the detector; prose describing one can, and did.
- Cases 3 and 9 keep `narration: true`. They grade repo-wide flow and consuming-repo config, not
  file content, so there is nothing for a fixture to pin.
- The fixtures carry real tells, so a repo auditing its own tree has to decline them. Prefer an
  `excluded_paths` glob over an in-file `ai-slop-ignore-file` marker: a file marker declines
  unconditionally, including under the empty `HOME` + `CLAUDE_PROJECT_DIR` isolation, so
  `detect.sh <fixture>` would print nothing and the eval author would be back to trusting prose.
  An `excluded_paths` entry is a config layer, and that isolation lifts it. This repo's own
  `.claude/ai-slop.json` carries the glob as the worked example.
- Consuming repos need no exclusion of their own: the audit scans `git ls-files '*.md'`, and an
  installed plugin's files are not tracked in the repo that installs it.

## [0.2.2]

The in-file suppression the fix flow and the catalog both tell operators to reach for now works in
the two forms they reach for first. Only `ai-slop-ignore-file` parsed the documented `: reason`;
the line and block forms did not, and each failed differently and without saying so.

- **Every marker form takes the optional `: reason`** — `<!-- ai-slop-ignore -->`,
  `-start`, `-end`, and `-file`. Previously a line marker carrying a reason did not match, so the
  finding was still reported and the operator's own reason text was quoted back inside its excerpt;
  an `ai-slop-ignore-start` carrying one never opened the block, so every line meant to be exempt
  was scanned instead. `-end` takes one for the failure in the dangerous direction: an unmatched
  `-end` left the block open and silently swallowed the rest of the file.
- The audit skill's fix flow closes a file with findings "explicitly suppressed (in-file marker
  with a reason)", and the catalog names the marker as the remedy for the recorded
  `rule-knowledge-cutoff-disclaimer` false-positive class. Both instructions were unfollowable for
  a single line or a block; they are now true of the code.
- The backtick guard that stops a document *describing* the markers from exempting itself
  generalized alongside them, so a backticked mention carrying a reason is still a mention. The
  guard **mirrors the line-marker pattern exactly** rather than matching any string starting with
  the marker prefix. Matching the prefix would let a backticked mention of `-start`, `-end`, or
  `-file` veto a genuine line marker sharing that line — reintroducing, in a new shape, the same
  failure this release removes: the suppression is rejected and the operator's own marker text is
  quoted back inside the excerpt.
- **Six new detector cases** (86 → 92) covering a reasoned line marker, a reasoned block, the
  `-end` close, the declined counts, and a line that mentions one marker form while using another
  — plus the marker-documentation fixture extended with a reasoned mention.
- Calibration record: the knowledge-cutoff false-positive class measured on the 1214-file dogfood
  corpus. All 8 findings fall in the recorded class, none was genuine assistant-frame residue.

## [0.2.1]

Eval coverage for the layer a shell test cannot reach. The deterministic side already had 86 cases
over all 15 script rules; the judgment side had none, which is the half that only a model performs.

- **Five new `audit` evals** (4 → 9, in line with sibling audit skills): the rubric layer reports
  but never enters the findings file; a `fix` never swaps an em dash for a parenthesis or en dash
  (the rewrite guide's substitution guardrail, and the tell most likely to be violated silently
  because the swap looks like a fix); triads collapse toward the strongest item rather than being
  repunctuated; the recorded knowledge-cutoff false-positive class routes to a marker or config
  rather than a rewrite, and never to weakening the rule; exemptions are named with their cause.
- **Two new `setup` evals** (3 → 5) covering the `_comment` rationale key added in 0.2.0: it is a
  documented annotation rather than unknown-key drift, and disabling a rule records why alongside
  the trade-off against `em_dash_allowed_paths`.
- Every eval case carries `narration: true`. The four original cases named a prose path that
  resolves nowhere, which the skill-quality Q4 check warns on unless the case declares itself
  narrative.
- Two eval scenarios corrected in review, both cases of a golden answer the scenario could not
  produce: the rubric-boundary case used promotional words that are themselves in the mechanical
  vocabulary list, so a second script finding fired and contradicted its own "one script finding"
  answer (measured: 3 hits, density 142.9/1000); and the triad case demanded a load-bearing triad
  be kept while supplying only rhetorical ones.
- The triad case needed a second correction, caught in review after the first: its load-bearing
  example used multi-word items ("project settings"), which `rule-rule-of-three`'s ERE
  (`[A-Za-z]+, [A-Za-z]+, and [A-Za-z]+`) requires to be single tokens, so the detector never
  surfaced it and the fix flow had nothing to judge. Each scenario is now verified by running the
  detector over it — the triad case measures 3 hits at 60.0/1000 words, with all three triads
  reaching the finding.

## [0.2.0]

- Added a set of catalog entries inspired by
  [Cursor's `unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md),
  deduplicated against the Wikipedia inventory in an overlap map.
- Three new detector rules, calibrated against this marketplace's corpus: `rule-chatbot-artifacts`
  (chat-turn residue and sycophancy phrases; IMPORTANT in the severity crosswalk),
  `rule-filler-phrases` (`in order to`, `due to the fact that`, deletable note-phrases), and
  `rule-stacked-hedging` (`could potentially` and kin) — both SUGGESTION.
- Four new rubric tells: false ranges, colon crutches, abstract metaphor jargon (kept out of the
  script layer by calibration: "substrate" alone had 114 legitimate uses on the calibration
  corpus), and mechanism-free claims.
- New `reference/rewrite-guide.md` owns fix-time guidance: plain-speech rewrites, substitution
  guardrails (an em dash never becomes a parenthesis or en dash), voice guidance bounded by
  meaning preservation, and a closing self-audit pass. The `fix` flow reads it first.
- AI-vocabulary default list gains the plain-word trio `utilize`, `leverage`, `facilitate`
  (density-gated; measured quiet on the calibration corpus).
- `rule-inline-header-lists` records a boundary refinement as **calibration pre-work** for a
  post-V1 script rule: a bold lead-in that ends in a period and is followed by new detail is
  reference-doc style, not a tell. The entry stays `recorded-only`, so nothing runs it yet.
- Overlap map says "catalogued by" rather than "covered by", and names the rows whose entries are
  dormant; Name-dropping is recorded as deliberately out of scope for general prose, and generic
  conclusions as detected only in their formulaic half.
- `rule-chatbot-artifacts` gains "Found the smoking gun"; `rule-abstract-metaphor-jargon` and the
  rewrite guide gain `evacuate` -> "move out". Two narrowings that were silent are now recorded:
  the promotional word core deliberately omits travel-copy words with no technical base rate, and
  the shipped AI-vocabulary list is a deliberate narrowing of the era-union rather than the union
  itself (`vocab_add` restores the rest).
- **Findings file no longer emits a `tier:` frontmatter field**, and `--tier` is retired from
  `emit-findings.sh`. Both owner docs already said this producer omits it, and the flag defaulted
  to a hardcoded value describing no property of the run.
- `rule-filler-phrases` and `rule-stacked-hedging` carry their own Action strings instead of the
  generic judgment fallback.
- **Roster-agreement guard**: the suite now asserts all 15 rules' emitted tiers (was 2) and fails
  when `detect.sh`'s registry no longer matches the tabled set, so a rule added without a
  crosswalk row can no longer emit SUGGESTION by silent fall-through.
- **Test config isolation**: the suite pins `HOME` and `CLAUDE_PROJECT_DIR` to empty directories
  so fixtures grade against shipped defaults. Found by dogfooding — a consuming repo disabling a
  rule for its own house style turned nine unrelated cases red.
- Relay expectations narrowed to what is true: `rule-utm-params` is the one relay-applicable rule;
  every other rule is `/ai-slop:audit fix` work.
- **Phrase rules match on whole words.** Without it, "These are great questions for the reviewer"
  fired `rule-chatbot-artifacts` at IMPORTANT tier on prose containing no chat residue, because
  the phrase merely prefixed a longer word. The registry carries a per-rule whole-word flag (POSIX
  `-w`, not GNU `\b`, so the cross-grep parity claim holds); it is off for the byte-class rules,
  the wildcard-bearing EREs, and the two whose match legitimately abuts a word character.

## [0.1.0]

- Initial release: `audit` skill (read-only default, explicit `fix` action), `setup` skill,
  deterministic detector with the mechanical rule roster, judgment rubric, and the
  Signs-of-AI-writing catalog (revision-pinned, CC BY-SA 4.0).
- Hardened by the first dogfood run (pre-release, folded in): ignore markers must be
  well-formed comment markers, not prose mentions — a document that documents the markers no
  longer exempts itself, and a mid-file `ai-slop-ignore-file` declines the whole file instead
  of silently truncating the scan; declined files are named in output (`Declined:` rows with
  cause), not just counted; `emit-findings.sh` composes the findings file deterministically
  from detector output (the model resolves the destination and the contract gate; the script
  owns row assembly at repo scale), writing coverage-only files on zero findings and refusing
  non-detector input.
- Fix guidance: `rule-of-three` rewrites collapse toward the single strongest item unless
  every element is load-bearing.
