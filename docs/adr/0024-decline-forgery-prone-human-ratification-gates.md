# Decline forgery-prone human-ratification gates and name the shared-identity limit

- Status: accepted
- Date: 2026-07-23

## Decision

Recorded from the #1187 audit (triggered when the operator did not recall ratifying the
`consumer-config-layering` → `config-cascade` seam). All 12 `docs/conventions/*` seams are
**PR-introduced** across the repo's whole history (established from git history), so none was silently
accreted. In-doc issue/PR citation is the intended ratification signal but is **inconsistent** across
the surfaces today — some seams cite their ratifying issue in the README/CHANGELOG (`config-cascade`'s
exception class → #649), others (`hook-precision`, `seam-phrasing`) carry no in-doc reference, so an
operator auditing from the durable convention surface alone cannot always find it. Converging every
seam on an in-doc citation is a follow-up, not asserted here as already-true.

**The limitation, stated precisely — two provenance layers, only one collapses.** Distinguish:

- **Git commit metadata** (author, committer, `Co-authored-by` trailers) **does** carry a distinct
  identity — this very record's commit is authored by `Codex <codex@openai.com>`; other agents commit
  under their own identity (e.g. a `Co-authored-by: Claude …` trailer). So at the commit layer, agent
  work is often *visible*. But it is **soft, not proof**: an agent can set its git author to anything,
  so absence of an agent identity does not prove a human authored it.
- **GitHub gh-account actions** — PR author, PR review, merge, and the account a commit is *attributed
  to* — **all collapse to `kyle-sexton`** (the account `gh` is scoped to), whether the human or an
  agent-as-Kyle acted. At *this* layer no in-repo signal distinguishes human ratification from agent
  accretion.

So the gap is specifically at the **GitHub-account / review-and-merge layer**, which is exactly where
"ratification" is recorded — and it is a **repo-wide property**, not a defect of any one seam.

**Decision — decline forgery-prone gates; they are theater.** A `CODEOWNERS` rule or a `human-ratified`
label requiring a `kyle-sexton` review does **not** distinguish anything at the account layer: an agent
satisfies the same gate under the same identity. Commit signing already runs (`required_signatures`)
but under the shared key, so it does not separate either, and commit-author metadata is spoofable as
above. Standing up such a gate would manufacture *false* assurance — worse than naming the limitation.
So none is added.

**The only real distinguisher (flagged, not imposed).** Cryptographic separation requires an identity
agents do **not** hold — a distinct human-only GitHub account and/or a signing key kept off the agent
runners, with branch protection requiring that identity's review on `docs/conventions/**`. That is an
infrastructure change with real operator cost. **Recheck trigger:** the operator wants provable human
ratification, or a second human contributor joins (at which point identity separation exists naturally).

**Interim posture.** Ratification stays **trust-based and visible**: a convention-seam change **should
cite** a ratifying issue/PR in-doc (the norm going forward — converging existing seams on it is the
follow-up above), and the operator's explicit engagement on that thread (as in the #163434 session) is
the ratification signal. The audit trail — issue, review comments, commit-author metadata where it
carries an agent identity, and this record — is the durable account, in place of an account-layer
assurance the shared GitHub identity cannot provide.
