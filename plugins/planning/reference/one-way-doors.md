<!-- GENERATED from lib/one-way-doors.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# One-way and two-way doors

The shared definition of how hard a change or decision is to undo. Each skill that reads it owns
what it does with the call: design deliberates and records one-way doors, a merge-risk rating
rates them high.

- **One-way door**: undoing it takes more than a code-only change. Either others build on it, so
  undoing it needs a data migration, a coordinated release or a rewrite (a stored format, a public
  contract or API, a module boundary, a vendor commitment), or it has already acted outside the
  code (data rewritten or deleted, a migration applied, a message, email or webhook sent, a package
  published, a third-party call with a lasting effect, or something exposed outside the trust
  boundary, such as a deployed vulnerability, a leaked secret or personal data).
- **Two-way door**: undoing it is a code-only change, such as reverting the commit.

When the evidence cannot settle the call, treat it as a one-way door.

Source: Jeff Bezos, 2015 letter to shareowners,
[Amazon.com exhibit 99.1 to SEC Form 8-K](https://www.sec.gov/Archives/edgar/data/1018724/000119312516530910/d168744dex991.htm)
(filed 2016), the passage on Type 1 and Type 2 decisions.
