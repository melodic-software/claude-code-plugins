# L1-derivability — `E-session-behavior`

145 files. `adhd`, `autonomy`, `discipline`, `playbooks`, `session-flow`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 136 |
| `out-of-scope: functional artifact` | 9 |

No deletions, no pointer conversions, no cache verdicts. The largest group in the corpus produced no
actionable verdict, so the basis is recorded rather than asserted.

Roll-up for the 136 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs and plugin READMEs. This group is where the derivability question is weakest by
construction: these documents are behavioral doctrine addressed to the model. There is no code
underneath them to re-derive from. `plugins/autonomy/reference/wiring-vs-advisor.md` is
representative at 850 bytes: it states a normative principle ("Anything that costs money is
advisory + explicit opt-in first, regardless of wireability") that no file in the repository
implements and
no exploration recovers. The `playbooks` fable-5 chapters are introspected doctrine whose whole
value is that a model does not reliably do it untold.

Nine files are functional artifacts and take no verdict:
`plugins/autonomy/skills/setup/scripts/fixtures/**` (including the 7-byte
`prerequisite-resolution/positive-verdict/repo/docs/README.md`),
`plugins/autonomy/skills/setup/templates/ack-reply.md`, and the `**/evals/fixtures/**` trees.

## Two files checked closely and kept

`plugins/session-flow/output-styles/brain-fried.md` (1316 bytes) is an output-style definition, an
instruction surface the harness loads. It owns its own behavioral contract. `keep-owns-facts`.

The five `context/gotchas.md` files in this group
(`plugins/autonomy/skills/setup/`, `plugins/session-flow/skills/handoff/`,
`plugins/session-flow/skills/orchestrate/`, and siblings) were checked for the unreachability
problem found in `implementation`. All are cited from their own skill bodies. `keep-owns-facts`, no
L2 route.
