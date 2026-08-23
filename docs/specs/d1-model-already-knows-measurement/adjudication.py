#!/usr/bin/env python3
"""Hand adjudication of the 185-sentence D1-flagged sample (#3121).

Every sample_id below was read in context and assigned one verdict:

  TP          genuine no-op — content the model already knows; deleting the
              whole sentence loses nothing.
  CONTESTED   reasonable people could disagree about whether the model does
              this by default. Scored BOTH ways, because the disagreement is
              itself the investigation's finding.
  FP-directive   load-bearing directive / hard boundary. Protected: "directives".
  FP-protected   motivating context, completion criteria, qualifier, quoted
                 string, worked example, threshold-in-words, stated limitation.
  FP-artifact    scanner defect: list lead-in, sentence fragment, table row, or
                 a descriptive statement that is not an instruction at all.
"""

import json
import re
import sys
from collections import Counter

CONTESTED = {9, 14, 25, 35, 46, 72, 86, 119, 129, 157, 164}

ARTIFACT = {18, 24, 29, 36, 41, 83, 87, 90, 96, 114, 115, 117, 132, 138, 145, 168, 171}

PROTECTED = {
    2,
    6,
    13,
    20,
    21,
    26,
    28,
    32,
    49,
    51,
    54,
    59,
    61,
    62,
    64,
    65,
    68,
    69,
    70,
    80,
    88,
    92,
    94,
    95,
    99,
    102,
    106,
    107,
    116,
    131,
    136,
    141,
    143,
    146,
    147,
    150,
    154,
    156,
    161,
    162,
    165,
    166,
    174,
    175,
    182,
    183,
    185,
}


def verdict(i):
    if i in CONTESTED:
        return "CONTESTED"
    if i in ARTIFACT:
        return "FP-artifact"
    if i in PROTECTED:
        return "FP-protected"
    return "FP-directive"


def main(sample_path, out_path, instructions_path):
    rows = [json.loads(ln) for ln in open(sample_path, encoding="utf-8")]
    rows.sort(key=lambda r: r["sample_id"])
    for r in rows:
        r["verdict"] = verdict(r["sample_id"])

    n = len(rows)
    c = Counter(r["verdict"] for r in rows)

    tp_strict = c["CONTESTED"]  # every contested call resolved FOR the proxy
    fp_strict = n - tp_strict
    tp_plain = 0  # every contested call resolved against it
    fp_plain = n - tp_plain

    with open(out_path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")

    print(f"sample size                : {n}")
    print()
    for k in ("CONTESTED", "FP-directive", "FP-protected", "FP-artifact"):
        print(f"  {k:16s} {c[k]:4d}  ({100.0 * c[k] / n:5.1f}%)")
    print()
    print("false-positive rate, two readings of the contested bucket")
    print(
        f"  most favourable to proxy (contested = true positive):"
        f" {fp_strict}/{n} = {100.0 * fp_strict / n:.1f}%"
    )
    print(
        f"  plain            (contested = false positive):"
        f" {fp_plain}/{n} = {100.0 * fp_plain / n:.1f}%"
    )

    # register analysis: how much of the flagged population is hard-boundary prose
    allrows = [json.loads(ln) for ln in open(instructions_path, encoding="utf-8")]
    flagged = [r for r in allrows if r["flagged"]]
    # Hard-boundary register. Bare "no " is deliberately NOT here: it fires on
    # ordinary prose ("no proper noun", "no path", "there is no reason to"),
    # which is not a boundary marker. Including it inflated this figure by 2.2
    # points over 134 sentences it alone matched.
    hard = re.compile(r"\b(never|must|do not|don't|cannot)\b", re.I)
    h = sum(1 for r in flagged if hard.search(r["sentence"]))
    print()
    print(f"flagged population         : {len(flagged)}")
    print(f"  in hard-boundary register: {h}  ({100.0 * h / len(flagged):.1f}%)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
