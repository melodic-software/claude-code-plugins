# Convention engagement — upstream-drift, fired at sweep completion

Drafted at design time; EXECUTED only when the repo-wide sweep completes (the Brief's execution
contract names sweep completion, never spike results, as the firing event). One engagement, one
changelog entry in `docs/conventions/upstream-drift/CHANGELOG.md`. Placeholders in angle
brackets are filled from the sweep's actual record.

## What fires

The recorded decision "an adoption gate is deferred" (upstream-drift README, decided
2026-08-12, #2273) states its own recheck trigger: "a detector is demonstrated that separates
an upstream restatement from an in-repo one without a suppression list. Either event reopens
the shape question; neither is a date."

Sweep completion is that demonstration or it is not, and the engagement says which, from
evidence: the sweep's closure ledger (every file closed with a disposition or an explicit
neutral outcome), the golden set's measured case-level precision/recall at the stated minimum
n, and the carve-out record showing categorical exclusions only. If the sweep accumulated
per-instance suppressions, the "without a suppression list" bar is NOT cleared, the trigger has
not fired, and the engagement records exactly that with the count.

## The changelog entry (single, combined)

Three parts land as one entry:

1. **Recorded-decision re-derivation.** Re-derive the adoption-gate decision from the sweep
   evidence, per the convention's own firing procedure for named triggers guarding in-repo
   decisions. The open question is whether the zero-part shape (an unstamped upstream-fact
   carrier) now has a workable detector. The honest expected outcome, stated now so the
   engagement cannot overclaim later: the demonstrated detector is LLM-led with deterministic
   verification, so the enforceability row for that shape moves at most from reasoning-only to
   detect-then-judge, and a CI gate in the `*-gate` pattern (deterministic, suppression-free)
   remains unavailable. Whether even that reclassification holds depends on the measured
   precision at sweep scale: verdict `<adopt | defer-again with new trigger>`.
2. **Enforceability table update, version bump conditional.** Major bump ONLY if an
   enforceability verdict changes (the convention's own versioning rule); otherwise the
   re-derivation lands as a minor entry (additive guidance) with the as-of date refreshed and
   the outcome stated, drift or no drift.
3. **The trigger-less-stamp check lands.** The named-not-built candidate check ("flag any
   `Verified <date>` line or row whose surface states no trigger") carried the build trigger "a
   trigger-less stamp lands on main again". This engagement builds it as
   `<name>/audit/rule-trigger-less-stamp`, OFF by default behind the consuming repo's
   `trigger_less_stamp_check` config, because the live corpus carries stamp dates in at least
   four prose forms (validator A, ~115-file sample) and a portable-default gate over
   non-uniform forms converts signal to noise, the exact failure the recorded decision warns
   about. The convention's table row updates from "named but not built" to "built,
   off-by-default, repo-override enabled"; its build trigger is thereby answered, not
   re-armed.

## Also recorded at the same firing

- **Hash-store designed issue.** The convention defers per-source content hashing with its own
  trigger ("a fleet audit completes without re-fetching every stamped claim in its scope", or a
  stale-stamp defect a stored hash would have caught). The sweep's fetch telemetry (pages
  fetched, cache hits, re-fetch coverage) is the evidence to evaluate that trigger; if it
  fires, open the designed issue rather than adding an inline store.
- **Dead-pointer round-trip wiring.** The repo-side integration: the weekly link-check lane's
  findings over pointers this plugin wrote route to the demotion path
  (`reference/dispositions.md`: pointer demotes to stamped record or archived-snapshot
  citation). Recorded here because it is consuming-repo wiring, not plugin machinery.
- **Adopters table.** If the sweep leaves this repository conforming (no unstamped carriers in
  scope), the fleet's open-carriers issue (#2297) gets its closure evidence; rows are added
  only for surfaces that actually conform, per the table's own admission rule.

## What this engagement never does

- Never declares the migration playbook's plugin-eval deferral trigger fired (separate
  decision, explicitly out of scope in the Brief).
- Never rewrites history: prior changelog entries and dated records keep their wording.
- Never converts a judgment verdict into a deterministic claim: report-only tiers stay
  report-only whatever the sweep measured.
