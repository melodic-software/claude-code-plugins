# ai-slop unslop integration — follow-up

## Brief

### TLDR

The 0.2.0 integration's detection half shipped correct; its documentation, registration, and
dogfooding halves did not. This follow-up folds the corrections into the same unreviewed branch
rather than publishing a release whose changelog advertises an inert feature, and it makes the
plugin dogfoodable in this marketplace for the first time.

### Goal

Every claim the `ai-slop` plugin makes about itself is true of the shipped code, the plugin is
registered with the fleet conventions that track it, and its rule roster cannot drift from its
severity crosswalk without a test failing.

### Constraints

- **Same branch, version stays 0.2.0.** `claude/ai-slop-unslop-integration-l8gr0k` is one commit
  ahead of `main` with no PR open, so nothing has been reviewed or released. Correcting before
  first review beats publishing a known-false claim and issuing 0.2.1.
- **No convention work on this branch.** Narrowing a claim is in scope; extending the
  `detector-findings` contract so a producer can name its own remediation skill is a multi-adopter
  change that gets its own issue.
- **The upstream inspiration is a single link.** No licence text, no copyright notice, no
  commit-pinned drift record for it. The Wikipedia CC BY-SA attribution is unaffected and stays:
  it is a different licence with its own share-alike terms.
- **The shipped detector defaults stay neutral.** This repo's em-dash exemption is consuming-repo
  config, never a change to what the plugin ships.
- **Read-only conventions are edited additively.** Convention docs get a row and a CHANGELOG
  entry, never a rule change.

### Acceptance criteria

1. `detect.test.sh` passes, and its roster check fails if `detect.sh`'s registry stops matching the
   15 tabled rules. **Met: 84 cases pass, up from 65.**
2. Every one of the 15 rules' emitted tiers is asserted (was 2 of 15). **Met.**
3. The findings file carries no `tier:` frontmatter, matching both owner docs. **Met, with a
   regression assertion.**
4. `check-detector-findings-crosswalk.sh --check` exits 0. **Met.**
5. A repo-wide `detect.sh` run over this marketplace completes and returns an actionable finding
   count rather than a house-style flood. **Met: 173 findings across 1212 files, from ~34,900.**
6. No document in `plugins/ai-slop/` claims a rule, boundary, or relay behavior that the shipped
   code does not perform. **Met for the four known cases (R1, R2, R3, F1).**
7. `ai-slop` appears in the `config-cascade` Implementers table. **Met.**

Per-unit close-out for the collapsed repair batch: apply one file, re-run `detect.test.sh` and the
crosswalk gate, close. A unit is closed when both gates are green.

### Captured assumptions

- **"Inspired by" is the accurate characterization of the relationship.** The catalog's entries
  were written for this plugin's entry form and deduplicated against a pre-existing Wikipedia
  inventory; research confirmed the overlap map accounts for all 31 upstream patterns, so the
  additions are a small minority of a 66-entry catalog. Recorded as an assumption because it is a
  judgment about substantiality, made by the user, not a fact this session verified.
- **The em-dash exemption is permanent for this repo**, not a backlog. If that changes, the remedy
  is de-slopping the corpus, which is its own decision and much larger.
- **Nobody is currently relying on `--tier` in `emit-findings.sh`.** It had no caller in this repo
  and defaulted to a hardcoded value; a downstream consumer passing it would now get a usage error.

### Out-of-scope

- Extending `detector-findings` so a producer names its own remediation skill (the real fix for the
  relay gap). Separate issue.
- The full four-way roster-agreement script (catalog ≡ `detect.sh` ≡ crosswalk ≡ emitter mirror).
  Better suited to a fleet-wide pass than this branch; the narrow test assertion closes most of the
  risk.
- Promoting any `recorded-only` rule to a live layer. `rule-inline-header-lists` in particular asks
  for calibration its entry now says has not happened.
- De-slopping this marketplace's 173 findings. The audit is read-only by design; acting on it is a
  separate decision.

### Deferred questions

- **Q8 — Does any rule we ship appear under Wikipedia's "Ineffective indicators"?** That section
  lists signals the source page's own editors consider unreliable for detection, and our two most
  false-positive-prone rules (`rule-em-dash`, zero-tolerance; `rule-rule-of-three`, the catalog's
  own "highest false-positive risk") are the candidates. If either appears there, the catalog is
  shipping a rule its own cited source classifies as ineffective. **Blocked by environment network
  policy, not by permissions**: every Wikimedia host is denied at this environment's egress
  gateway, and routing through a third-party read-proxy was deliberately declined as circumventing
  the denial rather than researching around it. Needs one fetch from a session with Wikimedia
  egress, scoped to that section only. **Arbiter: USER-RESERVED** — the answer could add an
  out-of-scope entry or change a shipped rule's disposition, so it can move acceptance criteria.

## Plan

*(Empty — `/planning:plan` fills this. The Brief's acceptance criteria were met inline during the
interview session; anything remaining is the deferred question above.)*
