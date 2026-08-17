#!/usr/bin/env bash
# Contract test for the lever catalogue (reference/levers.json).
#
# The catalogue's honesty rule made mechanical: every lever carries a category
# from the declared vocabulary, at least one official citation, a posture, a
# verified date, and a recheck trigger; net-negative levers are never
# recommendable; and no row smuggles in a token figure (the engine measures,
# the catalogue never asserts values).
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOGUE="$SCRIPT_DIR/../reference/levers.json"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required to validate the catalogue" >&2
  exit 1
fi

out="$(node -e '
const fs = require("fs");
const cat = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const problems = [];
if (cat.schema !== "context-budget.levers/1") problems.push("bad schema tag: " + cat.schema);
const vocab = Object.keys(cat.meta?.categories ?? {});
if (vocab.length < 5) problems.push("category vocabulary incomplete");
const ids = new Set();
for (const l of cat.levers ?? []) {
  const where = "lever " + (l.id ?? "<no id>");
  if (!l.id) problems.push(where + ": missing id");
  else if (ids.has(l.id)) problems.push(where + ": duplicate id");
  else ids.add(l.id);
  if (!vocab.includes(l.category)) problems.push(where + ": category not in vocabulary: " + l.category);
  if (!l.categoryBasis) problems.push(where + ": missing categoryBasis");
  if (!Array.isArray(l.citations) || l.citations.length === 0) problems.push(where + ": no citations");
  else for (const c of l.citations) if (!/^https:\/\//.test(c)) problems.push(where + ": non-URL citation: " + c);
  if (!l.posture) problems.push(where + ": missing posture");
  if (!l.detection) problems.push(where + ": missing detection");
  if (!l.measurement) problems.push(where + ": missing measurement");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(l.verified ?? "")) problems.push(where + ": missing/invalid verified date");
  if (!l.recheckTrigger) problems.push(where + ": missing recheckTrigger");
  if (l.category === "net-negative" && l.posture === "recommendable-on-fit") problems.push(where + ": net-negative lever marked recommendable");
  if (l.category === "unverified-undocumented" && l.posture === "recommendable-on-fit") problems.push(where + ": unverified lever marked recommendable");
  // Token figures do not belong in catalogue rows: the engine measures them.
  // Two shapes are scanned: k-suffixed figures (no legitimate Nk string exists
  // in a row — versions are dotted, counts are words) and plain integers
  // adjacent to the word token in either order.
  const text = JSON.stringify({ ...l, citations: [], emittedConfig: "" });
  const kFigure = text.match(/\b\d+(\.\d+)?k\b/i);
  // portability-ok: \s lives in an embedded node -e JavaScript regex, not a shell tool pattern
  const plainFigure = text.match(/\b\d{2,}\s*tokens?\b/i) || text.match(/tokens?\s*[:=]?\s*\d{2,}\b/i);
  if (kFigure || plainFigure) {
    problems.push(where + ": looks like a shipped token figure: " + (kFigure || plainFigure)[0].slice(0, 60));
  }
}
if ((cat.levers ?? []).length < 10) problems.push("suspiciously few levers: " + (cat.levers ?? []).length);
console.log(problems.length ? problems.join("\n") : "CLEAN");
' "$CATALOGUE")"

if [[ "$out" == "CLEAN" ]]; then
  ok "catalogue: every lever categorized, cited, postured, dated, with a recheck trigger; no shipped token figures"
else
  while IFS= read -r line; do fail "$line"; done <<<"$out"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
