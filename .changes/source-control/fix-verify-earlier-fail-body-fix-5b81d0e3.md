---
bump: patch
---

### Fixed

- The pr-merge gate no longer holds a pull request at `verify:earlier-fail` after a verifier FAIL judged against its own title and body (`intent` `pull-request`), a trusted person fixed the body, and the verifier passed a head of the same change. Every pr-verify verdict now records the sha256 of the title and body it judged (`intent_sha256`, which only a pull-request intent recorded before). An earlier FAIL at a head of the same change clears when every counted FAIL there records `intent` `pull-request`, every such FAIL and every counted pass at the head record that digest, no pass's equals a FAIL's, and the body's last edit was made by a `kind: human` id on the trusted list after every such FAIL's run was created and before every pass's. A local agent session acting as that person counts as that person, so the `intent` limit is what makes the clear safe: a FAIL judged against an issue keeps the refusal whoever edits the body. An edit by the lanes App or any other account, no edit, an edit outside that window, equal or missing digests, and an edit or record that cannot be read keep the refusal. Every other refusal is unchanged.
