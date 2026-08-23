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
  const kFigure = text.match(/\b\d+(\.\d+)?k\b/i); // portability-ok: embedded node -e JavaScript regex, not a shell tool pattern
  const plainFigure = text.match(/\b\d{2,}\s*tokens?\b/i) || text.match(/tokens?\s*[:=]?\s*\d{2,}\b/i); // portability-ok: embedded node -e JavaScript regex, not a shell tool pattern
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

# Keys that left the settings overview page for settings-reference (#3198).
citeout="$(node -e '
const cat = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const problems = [];
const moved = {
  "disable-workflows": "settings-reference#disableworkflows",
  "disable-artifact": "settings-reference#disableartifact",
  "include-git-instructions": "settings-reference#includegitinstructions",
  "skill-overrides": "settings-reference#skilloverrides",
  "disable-bundled-skills": "settings-reference#disablebundledskills",
  "skill-listing-budget": "settings-reference#skilllistingbudgetfraction",
  "mcp-project-servers": "settings-reference#disabledmcpjsonservers",
};
for (const [id, needle] of Object.entries(moved)) {
  const lever = (cat.levers ?? []).find((l) => l.id === id);
  if (!lever) { problems.push("missing lever " + id); continue; }
  if (!(lever.citations ?? []).some((c) => c.includes(needle))) {
    problems.push(id + " does not cite " + needle);
  }
  if ((lever.citations ?? []).some((c) => /docs\/en\/settings(?:$|#)/.test(c))) {
    problems.push(id + " still cites the settings overview page");
  }
}
const artifact = (cat.levers ?? []).find((l) => l.id === "disable-artifact");
if (artifact) {
  if (!String(artifact.emittedConfig || "").includes("enableArtifact")) {
    problems.push("disable-artifact emittedConfig is not the user-scope enableArtifact form");
  }
  if (!/user scope/i.test([artifact.scope, ...(artifact.caveats ?? [])].join("\n"))) {
    problems.push("disable-artifact does not say user scope");
  }
}
if (cat.meta?.verifiedAgainst?.cliVersion !== "2.1.241") {
  problems.push("verifiedAgainst.cliVersion is not 2.1.241");
}
console.log(problems.length ? problems.join("\n") : "CLEAN");
' "$CATALOGUE")"

if [[ "$citeout" == "CLEAN" ]]; then
  ok "moved settings keys cite settings-reference anchors; disableArtifact is user-scope"
else
  while IFS= read -r line; do fail "$line"; done <<<"$citeout"
fi

# #3200 — env measurement route + resolvable simple-system-prompt condition.
routeout="$(node -e '
const cat = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const problems = [];
const git = (cat.levers ?? []).find((l) => l.id === "include-git-instructions");
if (!git) problems.push("missing include-git-instructions");
else {
  const blob = [git.title, git.mechanism, git.scope, git.detection, git.measurement, ...(git.caveats ?? [])].join("\n");
  if (!blob.includes("CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS")) {
    problems.push("include-git-instructions does not name CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS");
  }
  if (!/unverified-undocumented/i.test(blob)) {
    problems.push("include-git-instructions does not mark the env form unverified-undocumented");
  }
  if (!String(git.emittedConfig || "").includes("includeGitInstructions")) {
    problems.push("include-git-instructions dropped the settings key as emitted config");
  }
}
const lean = (cat.levers ?? []).find((l) => l.id === "simple-system-prompt");
if (!lean) problems.push("missing simple-system-prompt");
else {
  const cond = String(lean.conditions || "");
  if (!/opus-5/i.test(cond)) problems.push("simple-system-prompt conditions do not name opus-5");
  if (!/already-default|already defaults lean/i.test(cond)) {
    problems.push("simple-system-prompt conditions do not explain a zero as already-default");
  }
  if (!/legacy list|claude-opus-4-0/i.test(cond)) {
    problems.push("simple-system-prompt conditions do not cite the binary legacy-list check");
  }
}
console.log(problems.length ? problems.join("\n") : "CLEAN");
' "$CATALOGUE")"

if [[ "$routeout" == "CLEAN" ]]; then
  ok "include-git-instructions names the env route; simple-system-prompt resolves opus-5 lean default"
else
  while IFS= read -r line; do fail "$line"; done <<<"$routeout"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
