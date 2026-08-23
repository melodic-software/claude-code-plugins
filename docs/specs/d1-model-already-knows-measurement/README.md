# D1 measurement harness

The harness behind [`../d1-model-already-knows-measurement.md`](../d1-model-already-knows-measurement.md),
the #3121 investigation into whether cut class D1 — *content the model already knows* — is a
scanner shape.

It is committed so the reported **94.1% false-positive rate** can be re-derived rather than taken
on trust. #3124's acceptance criteria bind any future implementation to that number, and a bar
nobody can recompute is not a bar. The prose in the record states the method; these three files
are the method, including the fixed word lists and the sampling order that the prose can only
summarise.

## Pinned revision

The measurement was taken against **`dff0942917e56929f6146261117a0eceeac502c8`**
(`docs(work-items): de-slop instruction surfaces (0.39.13) (#3107)`). The corpus selectors are
relative to a working tree, so the counts move as the fleet grows — reproducing the published
numbers requires that revision, not `main`.

## Reproducing

```bash
git worktree add --detach /tmp/d1-repro dff0942917e56929f6146261117a0eceeac502c8
cd /tmp/d1-repro

{
  find plugins -name 'SKILL.md'
  find plugins -path '*/skills/*' -name '*.md' ! -name 'SKILL.md'
  find plugins -path '*/reference/*.md' ! -path '*/skills/*'
  find plugins -path '*/agents/*.md'
  echo CLAUDE.md
  echo AGENTS.md
  find plugins -path '*output-styles*' -name '*.md'
} | sort -u > corpus-files.txt

H=<path to this directory>
python3 "$H/d1_proxy.py"     corpus-files.txt  instructions.jsonl
python3 "$H/sample.py"       instructions.jsonl sample.md sample.jsonl
python3 "$H/adjudication.py" sample.jsonl adjudicated.jsonl instructions.jsonl
```

Expected, and verified reproducing exactly at the pinned revision:

| output | value |
|---|---:|
| corpus files | 895 |
| instruction sentences | 13,529 |
| flagged by the proxy | 6,107 (45.1%) |
| sampled | 185 |
| false-positive rate, contested scored for the proxy | 94.1% |
| false-positive rate, contested scored against it | 100% |
| flagged population in hard-boundary register | 57.0% |

## The three stages

| file | does |
|---|---|
| `d1_proxy.py` | segments markdown to sentences, classifies each as instruction or not, applies the proposed predicate, writes one JSONL row per instruction sentence |
| `sample.py` | draws the seeded (`random.Random(3121)`), stratified sample; allocation proportional to each stratum's flagged count with a floor of 5 |
| `adjudication.py` | carries the hand verdicts as explicit sample-id sets, computes both false-positive readings, and reports the hard-boundary-register share |

## What the hand step is, and is not

`adjudication.py` holds verdicts, it does not derive them. Each of the 185 sampled sentences was
read in its own file context and assigned one verdict; the sets in that file are the record of
those readings, not a rule that recomputes them. Re-running reproduces the arithmetic, not the
judgement — a reviewer who disagrees with a row should edit its set membership and see what the
rate does, which is the point of shipping it this way.

The **contested** bucket is deliberately scored twice. Those 11 sentences are model-relative:
whether `Return only what is necessary.` is a no-op is a claim about a model's default behaviour,
not something reading settles. Reporting one number would have hidden the disagreement that is
the investigation's actual finding.
