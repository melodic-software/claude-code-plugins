# Rejected-concept ledger (consumer convention)

Optional per consuming repository. This marketplace keeps one copy at the repo root so
`work-items:triage` and `work-items:track add` can match incoming requests against settled
rejections without re-litigating them.

One file per concept under this directory. Each file records the decision, rationale, revisit
trigger, and a "Prior requests" log (append-only).

This repository is single-operator today; entries here are publisher-side decisions that also
apply to marketplace consumers who adopt the ledger shape.
