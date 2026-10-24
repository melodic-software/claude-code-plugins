---
bump: minor
---

### Added

- A resume-accuracy eval harness, `scripts/harness/resume_eval.py`, with seven synthetic `resume-eval` cases under `evals/re-*/`. It seeds a session, writes a handoff, a free-hand summary or a native `/compact`, then resumes it in a fresh Claude Code or Codex reader. It grades recall, artifact, continuation and decision probes and reports tokens on both sides in plugin eval's result schema, so `noise-report.py --baseline` compares any two arms. Directory-wide plugin-eval runs skip these cases.
- Handoff shape 3: `save_point.py new` writes a small hot file plus one immutable archive file per hop, `handoffs/archive/<chain-root-stem>/h<N>-<session8>.md`, holding every predecessor section the hot file does not carry, verbatim. The hot file has one fixed section order (`Original goal` first, `## Resume prompt` last), current rules with stable `[R<n>]` ids, a direction-change trail and the last three Prior-sessions rows. `validate` fails a hot file over its byte cap (provisional: 10,000 tokens' worth), a goal section that does not start with the predecessor's, a dropped, duplicated or unarchived changed rule, and a missing hop file on the chain path; it warns on a GitHub state claim. A shape-2 chain's next hop writes shape 3; shape-1 and shape-2 files validate and read unchanged, and `new --shape 2` still writes shape 2.

### Changed

- Update session-flow before resuming a shape-3 chain: an older `save_point.py` refuses to validate (exit 3) or build on a shape-3 file.
- `hop_chain.py --budget` is calibrated to the audited growth of 6.4 KB per hop, projects a shape-3 chain beside the shape-2 one, and fails when a projected hot file passes the cap by hop 20.
