# Changelog

## [0.4.2]

### Changed

- **Long reference files carry a `## Contents` index.** 1 reference file in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.4.1]

- **Every configured array stopped applying under the Windows build of jq
  (#3343).** `cfg_array` piped `jq -r` through `tr '\n' ' '`, which converts the
  line feed and leaves the carriage return of a CRLF attached to the element, so
  `excluded_paths`, `em_dash_allowed_paths` and `disabled_rules` arrived as
  `plugins/*/skills/*/vendor/**<CR>` and matched nothing. The exclusion was not
  reported as failing; it simply never fired, and the detector reported findings
  on files the consuming repo had deliberately placed out of scope. The CR
  originates in the detector's own jq invocation, so no caller could normalize
  it away from the config it supplies. Every config reader now strips it. Two
  more carried the same defect from the same source: `rule_allowed_paths`, the
  per-rule exemption added in 0.4.0, reads jq through `read`, which splits on
  the line feed, so the CR landed on the last glob of every entry and that key
  never applied on Windows either — this suite's own `rule_allowed_paths` cases
  already fail on a Windows workstation against the released 0.4.0, with no shim
  involved, and go green here; and `cfg_scalar`, which Git Bash masks —
  its command substitution strips one trailing CRLF pair — but which on a bash
  that strips only the line feed carries the CR into the emitted threshold text,
  in `--show-config` and in the density finding's label. CI cannot observe any
  of these conditions, because it runs on Linux, where jq emits LF, so the new
  cases force them with a shim ahead of jq on PATH that appends a CR to every
  output line, and a further assertion pins the shim itself so a runner that
  failed to select it fails loudly instead of reporting vacuous passes. The
  array and `rule_allowed_paths` cases reproduce on both platforms; the scalar
  case discriminates on Linux only, and says so where it sits.
  The strip is applied to `cfg_scalar`'s captured value rather than inside its
  command substitution, so jq's exit status still reaches the guard that reads
  it: a layer that parses to a value and then meets malformed trailing bytes
  emits that value while exiting nonzero, and a pipeline would have handed the
  guard `tr`'s unconditional success and let the half-read layer set the
  threshold.

## [0.4.0]

Shaped by the first full repo-wide `fix` dogfood (PR 3359: 82 findings, 45 files, ~40 closed
as markers), a plugin-quality audit of the skill, and three verified research runs against the
catalog's Wikipedia source, prior-art suppression design, and humanization craft.

### Added

- **Policy-level quotation exemption.** Every detector rule now carries a `wording` or
  `typography` class. Wording rules never scan blockquote lines or double-quoted spans (inline
  code was already exempt); typography rules (em dash, curly artifacts, emoji formatting,
  citation tokens, tracking parameters) still do, because byte residue is a defect wherever it
  sits. The design follows Wikipedia's MOS minimal-change split for quoted material. Quoted
  source text and mentions of a tell (style guides, forbidden-phrase lists, changelog entries
  citing a removed phrase) are now marker-free by construction; on the dogfood corpus the
  exemption replaced roughly thirty hand-written markers. Known limitation, recorded in the
  catalog: the quoted-span exemption is per-line.
- **`rule_allowed_paths` config key.** Per-rule path exemptions for every rule, generalizing
  `em_dash_allowed_paths` (which stays as an alias): the proportionate closure for a density
  verdict no line marker can quiet. Declines are counted per rule, never silent.
- **Knowledge-cutoff rule covers its whole source section.** The ERE previously matched
  roughly one of the six words-to-watch families and missed the source's own example "as of my
  last knowledge update"; it now covers both the cutoff half and the source-gap (RAG-era)
  half of the section's words-to-watch: the limited-details, not-widely-documented,
  provided-sources, and available-information phrase families.
- **Rewrite guide: non-evasion posture, legitimate-hit taxonomy, risky rewrite classes.** The
  guide now states the honesty boundary (the source's own descriptive-not-prescriptive warning
  plus the test "would this edit improve the prose if AI detection did not exist?"), names the
  five legitimate-hit classes a fix pass must not rewrite, and requires disambiguation before
  rewriting the three classes that produced or nearly produced semantic regressions in the
  dogfood PR: negative parallelism ("X alone insufficient" vs "X excluded"), triad collapse
  (survivors must entail deleted items), and quoted operative phrases (never edit inside).
- **Voice pass wired into the fix flow.** The guide's "Adding voice" section is now an explicit
  register-gated step of fix step 1, enriched with the researched craft constraints (Google's
  global-audience limits on sentence-length variation and terminology drift) and an explicit
  refusal of perplexity/burstiness as writing targets. The rationale for dropping Cursor's
  "Let some mess in" bullet is recorded so it is not re-added.
- **Catalog: source Caveats mined.** New false-positive-posture section (signs are descriptive;
  the source's 1-in-10 expert false-positive figure; combination over isolation), the em-dash
  spacing qualifier, and the recorded "in order to" divergence from the source's uncited
  human-counter-sign bullet.

### Changed

- **`rule-rule-of-three` demoted from script to judgment rubric**, per its own calibration
  clause: the dogfood pass ended with 18 of 18 residual findings on load-bearing enumerations,
  the ERE matched only single-word triads, and a verified survey of comparable prose linters
  (Vale, textlint, proselint, write-good, alex, markdownlint) found no tricolon implementation
  anywhere. The crosswalk row is now a no-row disposition; the script roster is 14.
- **`rule-elegant-variation` demoted to recorded-only**, following the live source page moving
  lexical diversity to its Historical indicators.
- The audit flow states that the rubric pass is independent of detector hits (a file with zero
  script findings still gets its rubric read when it is in the priority set), and the
  semantic-diff verifier's contract names QUOTE CORRUPTION and the risky classes for
  adversarial attention.

## [0.3.9]

- **Three directory-expansion defects survived 0.3.8.** A tracked file
  whose name held a non-ASCII byte was dropped with no trace, because
  `git ls-files` C-quotes those paths unless told otherwise; the listing
  now sets `core.quotePath=false` and stays newline-delimited. A
  filesystem walk still ran when git was missing or could not confirm a
  work tree, while the comment claimed that case was gone; the walk
  remains the fallback when tracked-files-only is not achievable, and
  that fallback is now reported on stderr (`git is not on PATH`, or
  `git could not confirm a work tree`). The new dir-target tests now
  assert the emitted `file=` path, not only the scan count, so rebuilding
  paths from `git rev-parse --show-toplevel` fails the suite; they also
  pin subtree restriction and a non-ASCII filename. Drive-root slash
  preservation from 0.3.8 is unchanged.

## [0.3.8]

- **Directory targets silently fell back to an untracked-inclusive filesystem
  walk when git and the shell spelled the same checkout differently.**
  `detect.sh` built its expansion prefix from `git rev-parse --show-toplevel`
  and its filter from `pwd`. On Git Bash those disagree (`D:/repo` vs
  `/d/repo`), so no prefixed candidate survived the filter, `grep` exited
  non-zero, and `|| find` ran in place of the tracked-files listing it was
  meant to back up. The walk returns untracked and ignored markdown, so a
  directory target audited files the checkout does not track and said
  nothing about it. Expansion now runs `git ls-files` with `-C <dir>`,
  which is already restricted to that directory's subtree and answers in
  paths relative to it. The caller's own spelling of the directory is the
  only anchor. The branch is chosen up front from `--is-inside-work-tree`
  rather than from an empty pipeline, so a filesystem walk is only ever
  the answer for a directory genuinely outside a checkout; inside one, a
  listing that fails reports on stderr instead of degrading into a
  different set of files. A Windows drive-root target such as `C:/` keeps
  its trailing slash: stripping it produced `C:`, which Windows treats as
  drive-relative (the cwd on that drive), so `git -C` / `find` can scan
  the wrong tree or nothing. Ordinary directory targets still lose one
  trailing slash.

## [0.3.7]

- **A branch name beginning with a YAML indicator silently dropped every finding it emitted.**
  `emit-findings.sh` interpolated the branch into its findings frontmatter as a bare plain scalar,
  and `git check-ref-format --branch` accepts `@foo`, `!foo`, `#foo` and `&foo`. Emitted bare,
  `#foo` and `&foo` parse to null and `@foo`/`!foo` are outright YAML parse errors, so the
  `branch:` value a consumer reads is not the branch name. The consumer admits a findings file
  only when that value matches the current branch exactly, so the whole file went unmatched — with
  no error, and nothing distinguishing it from "no findings". Frontmatter now goes through a
  `yaml_scalar()` helper that quotes only when the plain form would misparse, so an ordinary branch
  name stays a byte-identical unquoted scalar and the wire format for the common path does not
  move. The predicate is deliberately identical to the one `claude-config`'s and `testing`'s
  emitters use: three producers answer one frontmatter contract, and a consumer must not see three
  shapes. Implicit YAML types (`true`, `null`, `123`, `yes`, dates) are quoted the same way, because
  a bare scalar would type-coerce and the consumer's exact branch match would still drop the file.

## [0.3.6]

- **`emit-findings.sh` double-escaped a pipe the source already escaped, and left Location
  absolute when git and `pwd` spelled the same repo root differently.** Both defects were
  identified in #3180 and fixed for `docs-hygiene:audit-noise` in #3202; this copy was not
  reached. A naive `gsub(/\|/, "\\|")` turns `a \| b` into `a \\| b`, which GFM reads as a
  literal backslash followed by a live delimiter, so the row splits and the fix action
  misreads it. `esc()` now walks each backslash run and adds a delimiter escape only when
  the run length is even, so `a\\|b` (even) becomes a live-safe `a\\\|b` instead of
  restoring the original. Separately,
  `git rev-parse --show-toplevel` can answer Git's Windows-drive spelling while the caller is at `/tmp/…`
  (Git Bash). This producer failed OPEN: Location stayed absolute and nothing reported it,
  because an absolute path is still a well-formed cell. Root resolution now prefers the
  caller's own `pwd` (minus git's `--show-prefix`) and keeps git's two spellings as
  fallbacks. Shared code was considered and declined: plugins are portable and there is no
  existing cross-plugin emit-findings library; the three copies now agree on the same two
  helpers instead.

## [0.3.4]

- **The README now points back at the upstream ledger.** `docs/upstream/cursor-pstack.md` names
  this plugin's catalog and rewrite guide as where the Cursor `unslop` skill landed, but nothing
  under `plugins/ai-slop/` pointed the other way — the only derived plugin in the marketplace with
  no citation of that file, so a reader who arrived at the catalog through the README had no route
  to what the port took, deduplicated, or rejected, nor to the row that decides the next drift
  recheck. The README's existing sentence naming Cursor's skill now carries that link. The pointer
  belongs here rather than appended to the earlier entry that recorded the port, because a published
  changelog entry is history and is not edited. Documentation only.

## [0.3.3]

Three corrections found by re-reading what 0.3.1 and the 2.4.0 contract release actually shipped.
None changes what the detector finds or what the fix flow rewrites.

- **`emit-findings.sh` stamped a `date:` that is ISO-8601 in neither profile.** The format string
  was `%Y-%m-%dT%H-%M-%SZ` — an extended-form date joined to a hyphenated time — so every emitted
  file carried `date: 2026-08-21T13-24-36Z`. The consumer parses this field:
  `fix-pass-mode.md` "Step 1" reads a value only when it is a full ISO-8601 date-time with an
  explicit UTC designator or numeric offset, and classes anything else UNREADABLE. Nothing was
  dropped, because every clause on that path fails open — an unreadable `date:` keeps the candidate,
  at a bounded cost of one extra pass — but the staleness note Step 4's cleanup route asks for was
  degrading silently, since it judges age only from files that declare a readable one. Now
  `%Y-%m-%dT%H:%M:%SZ`.
- **The unit suite had pinned the malformed shape as the contract.** `detect.test.sh` asserted the
  hyphenated time under the name "colon-free UTC date", so the bug was guarded rather than caught.
  The colon-free rule is real but belongs to the FILE NAME, where it exists to keep the path
  Windows-safe (`persist-findings.md` "Where the file goes"); it never bound this frontmatter field,
  whose owner (`default-mode.md` "Findings-file shape") asks for `<ISO-8601 UTC>` plainly. The
  assertion now pins the extended form and says which document it answers to.
- **The Purpose section described the relay's cleanup route as `/simplify`-only.** Step 4 of
  `fix-pass-mode.md` reads "Invoke the `/simplify` skill when available in the session; otherwise
  apply the cleanup findings directly, one file at a time" — two branches, and the Purpose section
  named one. The paragraph's conclusion is unchanged and was never at risk: what makes routing these
  rows to `/ai-slop:audit fix` correct is that *neither* branch loads this skill's rewrite guide, so
  the omitted branch strengthens the argument rather than weakening it. This is a precision fix to
  rationale, not a behavior change; the audit flow's step 6 already carried the two-branch wording,
  and the Purpose section is now consistent with it.
- **Eval case 2 graded persistence without stating the premise persistence needs.** Its fourth
  expectation requires the findings file to be re-emitted after the last fixed file, but
  `SKILL.md` step 5 gates persistence on the audit having "examined tracked files" and the prompt
  asserted no such thing. 0.3.0 established the remedy for exactly this and applied it to cases 4
  and 5: a case cannot verify real repository state, so a case that grades the persistence step
  states the premise instead of constructing it. Case 2 is the third such case and was the one
  missed. Its prompt now carries the same sentence, and the expectation names the premise it rests
  on so a run that rewrites and re-runs but persists nothing no longer passes.

  **The fix flow's re-emit wording is left alone here, and the question stays open.** It states
  re-emission without repeating step 5's gate. `persist-findings.md` "Surfaces, and when the file is
  written at all" enumerates when a file is written and tracked-ness is not on that list, which is
  the reading under which the two never conflict — but that reading is not established, and this
  entry does not claim it is. Against it: step 1 scopes "the repo's tracked markdown" to the
  **empty-target** branch, while every eval case passes a path argument, so "examined tracked files"
  and "nothing scanned" are not obviously the same condition; and cases 4 and 5 word tracked-ness as
  gating ("since the audit examined a tracked file"), which an inert precondition would not need.
  `persist-findings.md`'s precedence clause also names the convention README rather than this
  `SKILL.md`, so its list is not authoritative over step 5.

  What is settled is the eval: case 2 grades persistence and lacked the premise its siblings carry,
  which is a gap under either reading. Whether tracked-ness is a substantive gate is a question about
  this skill's own wording, and if it is, the fix belongs in `context/persist-findings.md` rather
  than in the fix flow.

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
