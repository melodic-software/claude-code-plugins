#!/usr/bin/env python3
"""Draw a seeded, stratified sample of D1-flagged instruction sentences.

Allocation is proportional to each stratum's share of the flagged population,
with a floor of 5 per stratum so the small surfaces are still represented.
Seeded so the sample is reproducible and the adjudication auditable.
"""

import json
import random
import sys

SEED = 3121  # the issue number — arbitrary but fixed and disclosed
TARGET = 180


def main(src, dst_md, dst_jsonl):
    rows = [json.loads(ln) for ln in open(src, encoding="utf-8")]
    flagged = [r for r in rows if r["flagged"]]

    strata = {}
    for r in flagged:
        strata.setdefault(r["stratum"], []).append(r)

    total = len(flagged)
    alloc = {}
    for k, v in strata.items():
        alloc[k] = max(5, round(TARGET * len(v) / total))
        alloc[k] = min(alloc[k], len(v))

    rng = random.Random(SEED)
    picked = []
    for k in sorted(strata):
        pool = sorted(strata[k], key=lambda r: (r["file"], r["sentence"]))
        picked.extend(rng.sample(pool, alloc[k]))

    rng.shuffle(picked)
    for i, r in enumerate(picked, 1):
        r["sample_id"] = i

    with open(dst_jsonl, "w", encoding="utf-8") as fh:
        for r in picked:
            fh.write(json.dumps(r) + "\n")

    with open(dst_md, "w", encoding="utf-8") as fh:
        fh.write("# D1 proxy — stratified sample for hand adjudication\n\n")
        fh.write(
            f"seed={SEED} · target={TARGET} · drawn={len(picked)} "
            f"· flagged population={total}\n\n"
        )
        for k in sorted(alloc):
            fh.write(f"- {k}: {alloc[k]} of {len(strata[k])} flagged\n")
        fh.write("\n---\n\n")
        for r in picked:
            fh.write(f"## {r['sample_id']}. [{r['stratum']}]\n")
            fh.write(f"`{r['file']}`\n\n")
            fh.write(f"> {r['sentence']}\n\n")
            fh.write("verdict: \n\n")

    print(f"drawn {len(picked)} from {total} flagged")
    for k in sorted(alloc):
        print(f"  {k:24s} {alloc[k]:4d} of {len(strata[k])}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
