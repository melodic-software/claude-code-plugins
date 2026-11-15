# Line-emission hard gate

*(Plugin-authored, not Pat Pattison's.)* What must exist before any lyric line is emitted. Show the
artifacts, do not claim them.

A box is passed when its output is **visible in this response or on disk at a named path**. A box
named as passed with nothing to show is a failed box. For the source rows, what is shown is a
citation of what the file settled in THIS line; a filename is not an artifact, and neither is the
claim that the method is known. Every row applies before any line is emitted; the rhyme row
applies when the line sits in a rhyme position. The rows run in the order work happens: inputs,
then the rubric's recorded passes, then the skeptic's refutation from a fresh context.

| Required before emission | What "shown" means |
| --- | --- |
| Writer voiceprint loaded | the four dimensions visible in this response, or the path to the writer's voiceprint file. Built per [voiceprint](pat-pattison/research/voiceprint.md) |
| Craft sources read | `meter.md` and `phrasing.md` read this session, each cited by what it settled for this line, the stress count the line has to hit, the phrase shape it has to keep, not by filename |
| Metaphor source read, when a figure is asked for | `metaphor.md` read, and every figure emitted labeled with its type from Pat's three. Expressed Identity, Qualifying Metaphor, Verbal Metaphor. An unlabeled figure is a plain description until the label is shown |
| Sensory raw material exists | a path under the song's `ideation/`, or object-writing output in this response, from `/songwriting:object-writing generate` |
| Rhyme candidates generated | the labeled 8-15 candidate menu across ≥4 stability tiers, including ≥3 mosaic, visible, from `/songwriting:rhyme`, its search having walked the stressed vowel's coda field and not only the source word's own |
| Section mode named | stated in this response: does this section SHOW (verse) or TELL (chorus)? |
| Positional template or stress map marked | the marked line. Or, when a sung melody already exists, the numbered-and-bracketed positional template per [meter](pat-pattison/research/meter.md) "fitting a replacement line to an already-sung melody", never an assertion that it scans. From `/songwriting:meter-prosody` |
| Rubric cycled per candidate, pass 1 CLEAN | the pass-by-pass result visible in this response, or at the candidate's named path under the song's `variations/`, per [line-edit-rubric](pat-pattison/research/line-edit-rubric.md). Pass 1's artifact is the marked template above; on free-melody work the stress map stands in. Counts are run, not estimated: syllables per word from `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/scripts/datamuse.sh syllables <word>`, and pass 2's repeated words from a word-frequency count over the draft file (a `sort \| uniq -c` pipeline) |
| Skeptic refutation returned | the strongest case AGAINST each candidate, visible in this response or at a named path under the song's `variations/`, from a fresh subagent that READ [response-filter](pat-pattison/research/response-filter.md) §2, the marked map, and [line-edit-rubric](pat-pattison/research/line-edit-rubric.md) at those paths. A line survives when its refutation is stated and judged insufficient; a return holding nothing against anything has shown nothing |

**Every row except the rubric row may be skipped**, and a skip is **named, with its reason, in
the output**. A silent skip is the failure, and so is listing a box as passed while its artifact
does not exist. Those rows stay skippable because how much support a line gets is the writer's
craft call: "There are no rules, only tools." (*Writing Better Lyrics* (2009), Chapter 18, quoted
in [response-filter](pat-pattison/research/response-filter.md)). The skeptic row is
in that class deliberately: a refutation pass costs a subagent dispatch, and whether a batch is
worth one is a judgment, not a rule the writer laid down. Skip it by name and reason, and expect
to be asked why, because self-attestation is what failed. The verification level also governs it:
run the `read-verification.sh` command the invoking skill gives and copy its line into the output
([levels](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/verification-level/README.md)).
`standard` keeps the row as written; `strict` runs it on every batch, with no skip. Under `light`,
and `off`, which acts as `light` here, dispatch no skeptic and do not refute the batch yourself in
its place: the row's named skip is `verification: skipped (<level>)`.

**The rubric row is never skipped**: it is the writer's standing rule for every candidate, not a
craft box he may decline. Its record is not a verdict on the candidate: the countable passes run
as commands, and the skeptic row's fresh context tests the judgment passes. The rules behind it
are in [line-edit-rubric](pat-pattison/research/line-edit-rubric.md)
`## Standing operating rules`; in short, the cycle runs on every candidate every time with no
fatigue exception, and a FAILED pass kills the candidate rather than annotating it. Under load,
emit fewer candidates, not unchecked ones. Passes scoped out by their own headings (no fixed
melody, no rhyme position, no figure, no voiceprint on disk) are declared and stepped past: that is
the pass running, not a skip. The response filter's own §1-§8 boxes stay skippable-with-reason.

If a gate's input is missing, invoke the skill that produces it; do not proceed and note the
absence. Lines written without their inputs are LLM defaults wearing the method's vocabulary,
which is what the writer rejects. A source row's missing input is a file, so READ it: summarizing
what a craft file probably says, or working from a remembered version, is the same failure as an
unnamed skip.

## Refute, do not review

A self-graded pass is indistinguishable from a real one
when the same context produced both: a model running the response filter on its own output passes
itself. So dispatch the skeptic to build the case AGAINST each candidate, and give it nothing but
the candidate batch, the slot's positional template or marked scansion map, and the source paths
to read: not the reasoning that produced the candidates, not which one you prefer. This is a hard
boundary, not a default, the same blind-dispatch mechanic that makes
`/songwriting:object-writing generate`'s fleet work. Its kill rules rank singability and verbosity
ABOVE cleverness: a clever line that cannot be sung in the slot's length is refuted, not merely
ranked lower. The pass runs before the writer sees the batch and settles nothing; the writer's
sing-check is still the last word. Any general subagent honors this today; no agent in this plugin
is a skeptic, and a preloaded-skill skeptic agent is deliberately not shipped here.
