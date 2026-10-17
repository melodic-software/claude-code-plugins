#!/usr/bin/env bash
# pr-bump-plugin-version.yml runs on pull_request, so its own checkout is the
# pull request's code. Every job that can write (any job whose permissions,
# its own or inherited from the workflow, are not all read or none) runs only
# what the allowlist below names: actions/checkout at a pinned SHA with one of
# the listed input sets, `bash` on a script in main's checkout at .base, and the
# inline steps whose sha256 is recorded. It sets no unlisted key or env var, and
# the workflow sets no defaults or env. The workflow is parsed with the yaml
# package (npm ci --prefix .github/standards/runner-policy). Mutants of the
# workflow prove each rule can fail.
# test-scope: .github/workflows/pr-bump-plugin-version.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

WORKFLOW="$ROOT/.github/workflows/pr-bump-plugin-version.yml"
POLICY_DIR="$ROOT/.github/standards/runner-policy"
CHECKOUT_SHA=3d3c42e5aac5ba805825da76410c181273ba90b1

# audit <workflow> prints one finding per line. `audit <workflow> --guard`
# prints the run line of the step that refuses a tracked .base.
read -r -d '' AUDIT_JS <<'EOF'
const { createRequire } = require("node:module");
const { createHash } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { isDeepStrictEqual } = require("node:util");
const yaml = createRequire(`${process.argv[1]}/package.json`)("yaml");

// The allowlist. Before adding or editing an entry, confirm it runs nothing
// from the pull request's checkout; a run block's sha256 is in the finding.
const CHECKOUT = "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1";
const ACTIONS = new Map([
  [CHECKOUT, [
    { ref: "${{ github.head_ref }}", "fetch-depth": 0, "persist-credentials": false },
    { ref: "refs/heads/main", path: ".base", "persist-credentials": false },
  ]],
]);
const GUARD = "test ! -e .base -a ! -L .base";
const RUN_LINES = [GUARD];
const RUN_BLOCKS = [
  "5cdcdce68851653289925f3b1e1c5d622084a6774045ddaf0af06a72f2b7b939", // Commit release metadata
];
const ENV = ["BASE_REF", "PR_NUMBER", "PR_TITLE", "GH_TOKEN", "HEAD_REF"];
const BASE_SCRIPT = /^bash \.base\/scripts\/[A-Za-z0-9_-]+\.sh( |$)/;
// Characters that chain, substitute or redirect a second command.
const CHAINING = /[;&|<>()`]/;
const TOP_KEYS = ["name", "on", "permissions", "concurrency", "jobs"];
const JOB_KEYS = ["if", "runs-on", "timeout-minutes", "permissions", "steps"];
const STEP_KEYS = ["name", "id", "uses", "with", "run", "env"];
const BUMP_JOB = "bump-plugin-version";
const ON = { pull_request: { types: ["opened", "synchronize", "reopened"], paths: ["plugins/**"] } };
const BUMP_IF = "github.event.pull_request.user.login == 'dependabot[bot]'";

const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const readOnly = (p) =>
  p === "read-all" || (isMap(p) && Object.values(p).every((v) => v === "read" || v === "none"));
const findings = [];
const flag = (s) => findings.push(s);

let wf;
try {
  wf = yaml.parse(readFileSync(process.argv[2], "utf8"));
} catch (e) {
  console.log(`the workflow does not parse: ${String(e.message).split("\n")[0]}`);
  process.exit(0);
}
const steps = (isMap(wf?.jobs) && Array.isArray(wf.jobs[BUMP_JOB]?.steps)) ? wf.jobs[BUMP_JOB].steps : [];

if (process.argv[3] === "--guard") {
  const step = steps.find((s) => s?.name === "Refuse a pull request that tracks .base");
  if (typeof step?.run !== "string") process.exit(1);
  console.log(step.run);
  process.exit(0);
}

function auditWriter(id, job) {
  for (const key of Object.keys(job)) if (!JOB_KEYS.includes(key)) flag(`${id}: sets ${key}`);
  if (!Array.isArray(job.steps)) return flag(`${id}: has no steps list`);
  job.steps.forEach((step, i) => {
    const at = `${id} step ${i + 1}`;
    if (!isMap(step)) return flag(`${at}: is not a mapping`);
    for (const key of Object.keys(step)) if (!STEP_KEYS.includes(key)) flag(`${at}: sets ${key}`);
    if ("env" in step) {
      if (!isMap(step.env)) flag(`${at}: env is not a mapping`);
      else for (const k of Object.keys(step.env)) if (!ENV.includes(k)) flag(`${at}: sets env ${k}, which is not listed`);
    }
    if (("uses" in step) === ("run" in step)) return flag(`${at}: needs exactly one of uses and run`);
    if ("uses" in step) {
      const inputs = ACTIONS.get(step.uses);
      if (!inputs) return flag(`${at}: uses '${step.uses}' is not an allowed action at an allowed SHA`);
      if (!inputs.some((w) => isDeepStrictEqual(step.with, w)))
        flag(`${at}: with ${JSON.stringify(step.with ?? null)} is not an input set listed for ${step.uses}`);
      return;
    }
    if ("with" in step) flag(`${at}: sets with on a run step`);
    const run = step.run;
    if (typeof run !== "string") return flag(`${at}: run is not a string`);
    if (!run.includes("\n")) {
      if (RUN_LINES.includes(run)) return;
      if (BASE_SCRIPT.test(run) && !run.includes("..") && !run.includes("${{") && !CHAINING.test(run)) return;
      return flag(`${at}: run '${run}' is neither bash on a .base script nor a listed line`);
    }
    const sum = createHash("sha256").update(run).digest("hex");
    if (!RUN_BLOCKS.includes(sum)) flag(`${at}: an inline run block is not on the allowlist (sha256 ${sum})`);
  });
  auditOrder(id, job.steps);
}

// One PR-head checkout, then the guard, then main's checkout at .base, after
// which no checkout runs; `bash .base/...` runs only after main's checkout.
function auditOrder(id, steps) {
  const at = (pred) => steps.flatMap((s, i) => (isMap(s) && pred(s) ? [i] : []));
  const prs = at((s) => s.uses === CHECKOUT && isMap(s.with) && !("path" in s.with));
  const bases = at((s) => s.uses === CHECKOUT && s.with?.path === ".base");
  const guards = at((s) => s.run === GUARD);
  const uses = at((s) => "uses" in s);
  if (prs.length !== 1) flag(`${id}: has ${prs.length} pull request checkouts, not exactly one`);
  const base = bases.length ? bases[0] : Infinity;
  if (uses.some((i) => i > base)) flag(`${id}: a checkout or action runs after main's checkout`);
  if (bases.length && !guards.some((g) => g > Math.max(...prs, -1) && g < base))
    flag(`${id}: main's checkout does not follow the last pull request checkout and the .base guard`);
  for (const i of at((s) => typeof s.run === "string" && BASE_SCRIPT.test(s.run)))
    if (!(i > base)) flag(`${id} step ${i + 1}: runs a .base script before main's checkout`);
}

// `<<` would merge keys in from elsewhere in the file under a YAML 1.1 reader.
function mergeKeys(node, path) {
  if (Array.isArray(node)) node.forEach((v, i) => mergeKeys(v, `${path}[${i}]`));
  else if (isMap(node))
    for (const [k, v] of Object.entries(node)) {
      if (k === "<<") flag(`${path}: uses a << merge key`);
      mergeKeys(v, `${path}.${k}`);
    }
}

if (!isMap(wf) || !isMap(wf.jobs)) {
  flag("the workflow has no jobs mapping");
} else {
  mergeKeys(wf, "(workflow)");
  for (const key of Object.keys(wf)) if (!TOP_KEYS.includes(key)) flag(`the workflow sets top-level ${key}`);
  if (!isDeepStrictEqual(wf.on, ON)) flag(`the workflow triggers on ${JSON.stringify(wf.on)}, not the pinned trigger`);
  if (wf.jobs[BUMP_JOB]?.if !== BUMP_IF) flag(`${BUMP_JOB} does not run only for Dependabot's pull requests`);
  if (wf.jobs[BUMP_JOB]?.permissions?.contents !== "write")
    flag(`${BUMP_JOB} does not hold contents: write; the bump cannot land`);
  for (const [id, job] of Object.entries(wf.jobs)) {
    if (!isMap(job)) { flag(`${id}: is not a mapping`); continue; }
    const perms = "permissions" in job ? job.permissions : wf.permissions;
    if (!readOnly(perms)) auditWriter(id, job);
  }
  const base = steps.findIndex((s) => s?.uses === CHECKOUT && s.with?.path === ".base");
  if (base < 0 || !steps.some((s, i) => i > base && /^bash \.base\/scripts\/dependabot-plugin-bump\.sh /.test(s?.run ?? "")))
    flag(`${BUMP_JOB}: no step after main's checkout runs .base/scripts/dependabot-plugin-bump.sh`);
}
if (findings.length) console.log(findings.join("\n"));
EOF

audit() { node -e "$AUDIT_JS" "$POLICY_DIR" "$@"; }

if ! findings="$(audit "$WORKFLOW")"; then
  fail "the audit did not run; is .github/standards/runner-policy installed?"
elif [[ -z "$findings" ]]; then
  ok "every job that can write runs only allowlisted steps"
else
  fail "the workflow breaks the allowlist:"$'\n'"$findings"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The guard step must fail when .base exists in any form after the pull
# request's checkout, a dangling symlink included, and pass when it is absent.
if guard="$(audit "$WORKFLOW" --guard)"; then
  for shape in absent directory file symlink dangling-symlink; do
    dir="$tmp/guard-$shape"
    mkdir -p "$dir"
    case "$shape" in
    directory) mkdir "$dir/.base" ;;
    file) : >"$dir/.base" ;;
    symlink) ln -s "$tmp" "$dir/.base" ;;
    dangling-symlink) ln -s "$dir/nowhere" "$dir/.base" ;;
    *) ;;
    esac
    (cd "$dir" && bash -c "$guard")
    rc=$?
    if [[ "$shape" == absent && $rc -eq 0 ]] || [[ "$shape" != absent && $rc -ne 0 ]]; then
      ok "the .base guard handles a .base that is $shape (rc=$rc)"
    else
      fail "the .base guard '$guard' gives rc=$rc for a .base that is $shape"
    fi
  done
else
  fail "the write job has no 'Refuse a pull request that tracks .base' run step"
fi

# mutate <out> <op>...: write the workflow with each op applied.
#   step:<text>         insert <text> as the first step of the write job
#   job:<text>          append <text> as a new job
#   sub:<line>=><text>  replace every line equal to <line>; empty <text> deletes it
mutate() {
  local out=$1 op from to
  shift
  cp "$WORKFLOW" "$out"
  for op in "$@"; do
    case "$op" in
    step:*) awk -v add="${op#step:}" '{ print } /^    steps:$/ { print add }' "$out" >"$out.next" ;;
    job:*) { cat "$out" && printf '%s\n' "${op#job:}"; } >"$out.next" ;;
    sub:*)
      from="${op#sub:}"
      to="${from#*=>}"
      from="${from%%=>*}"
      awk -v from="$from" -v to="$to" '$0 == from { if (to != "") print to; next } { print }' "$out" >"$out.next"
      ;;
    *) return 1 ;;
    esac
    mv "$out.next" "$out"
  done
}

# job <permissions line or empty>: a new job that runs the pull request's code.
job() {
  printf '  extra:\n    runs-on: ubuntu-24.04\n'
  [[ -n "$1" ]] && printf '    permissions:%s\n' "$1"
  printf '    steps:\n      - run: npm ci'
}

# Each mutant gives the audit a finding the unmutated workflow does not have.
# Ops within one mutant are separated by \x1e.
S=$'\x1e'
NL=$'\n'
checkout="      - uses: actions/checkout@$CHECKOUT_SHA"
pr_with="        with:$NL          ref: \${{ github.head_ref }}$NL          fetch-depth: 0"
mutants=(
  "step:      - uses: './.github/actions/download-full-history'"
  "step:      - run: ./scripts/x.sh"
  "step:      - run: npm ci"
  "step:      - run: bash \"\$GITHUB_WORKSPACE/scripts/x.sh\""
  "step:      - working-directory: plugins/x$NL        run: bash build.sh"
  "step:      - run: bash .base/scripts/x.sh; npm ci"
  "step:      - run: bash .base/scripts/x.sh \$(npm ci)"
  "step:      - env:$NL          BASH_ENV: scripts/x.sh$NL        run: bash .base/scripts/x.sh"
  "step:      - run: |$NL          bash scripts/x.sh"
  "step:      - {run: npm ci}"
  "step:      - \"run\": npm ci"
  "step:      - uses: someone/action@0123456789abcdef0123456789abcdef01234567"
  "step:$checkout"
  "step:$checkout$NL$pr_with$NL          persist-credentials: true"
  "step:$checkout$NL$pr_with$NL          persist-credentials: false$NL          repository: someone/fork"
  "sub:          ref: refs/heads/main=>          # ref: refs/heads/main"
  "sub:        run: test ! -e .base -a ! -L .base=>        run: test ! -e .base"
  "job:$(job ' write-all')"
  "job:$(job ' { contents: write }')"
  "job:$(job "$NL      actions: write")"
  "job:$(job "$NL      pull-requests: write")"
  "job:$(job "$NL      id-token: write")"
  "sub:  contents: read=>  contents: write${S}job:$(job '')"
  "sub:permissions:=>${S}sub:  contents: read=>${S}job:$(job '')"
  # A: a writer that runs a .base script with no main checkout behind it.
  "job:  extra:$NL    runs-on: ubuntu-24.04$NL    permissions:$NL      contents: write$NL    steps:$NL$checkout$NL$pr_with$NL          persist-credentials: false$NL      - run: bash .base/scripts/x.sh"
  # B: a .base script between the pull request checkout and the guard.
  "sub:      - name: Refuse a pull request that tracks .base=>      - run: bash .base/scripts/x.sh$NL      - name: Refuse a pull request that tracks .base"
  # C: a second pull request checkout after main's.
  "sub:      - name: Bump legacy plugin manifests and changelogs=>$checkout$NL$pr_with$NL          persist-credentials: false$NL      - name: Bump legacy plugin manifests and changelogs"
  # D: an expression interpolated into an allowed run line.
  "sub:      - name: Commit release metadata=>      - run: bash .base/scripts/x.sh \${{ github.event.pull_request.title }}$NL      - name: Commit release metadata"
  # E: a merge key.
  "sub:  cancel-in-progress: true=>  cancel-in-progress: true$NL  <<: {group: x}"
  # F: pull_request_target, with the Dependabot-only condition dropped.
  "sub:  pull_request:=>  pull_request_target:${S}sub:    if: github.event.pull_request.user.login == 'dependabot[bot]'=>"
)
for mutant in "${mutants[@]}"; do
  mapfile -d "$S" -t ops < <(printf '%s' "$mutant")
  label="${mutant//$NL/ / }"
  label="${label//$S/ + }"
  if ! mutate "$tmp/mutant.yml" "${ops[@]}"; then
    fail "the mutant could not be applied: $label"
  elif [[ -n "$(comm -13 <(sort <<<"$findings") <(audit "$tmp/mutant.yml" | sort))" ]]; then
    ok "the audit flags: $label"
  else
    fail "the audit passes a mutant that could run pull request code: $label"
  fi
done

test_harness::report
