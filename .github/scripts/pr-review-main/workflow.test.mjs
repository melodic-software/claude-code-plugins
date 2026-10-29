// pr-review-main.yml's hardening, from its header and ADR 0049: it runs only
// from main on workflow_run, its token can only read, it checks out main and
// never the head, the model reads only its data directory, and each leg
// uploads the verdict once, after it is written, under the name the writer
// chose. Each lane runs one leg on the review lanes' credentials in their
// order, a later leg only for a lane the previous one handed on.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, symlinkSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const prompt = readFileSync(new URL("./prompt.md", import.meta.url), "utf8");
const KEY = "review";
const SUB = "review-subscription";
const FB = "review-fallback";
const LEGS = [KEY, SUB, FB];
const jobText = (id) => {
  const found = new RegExp(`\\n  ${id}:\\n([\\s\\S]*?)(?=\\n  [a-z-]+:\\n|$)`).exec(text);
  assert.ok(found, `a job ${id}`);
  return found[1];
};
// Each step starts at a `      - name:` line of its job.
const stepsOf = (id) =>
  jobText(id)
    .split(/\n(?=      - name: )/)
    .slice(1)
    // A step ends before the next step's or job's comment.
    .map((block) => ({ name: /^      - name: (.*)$/m.exec(block)[1], block: block.replace(/\n\n {2}(?: {4})?#[\s\S]*$/, "") }));
const STEPS = Object.fromEntries(LEGS.map((id) => [id, stepsOf(id)]));
const step = (name, job = KEY) => {
  const found = STEPS[job].find((s) => s.name === name);
  assert.ok(found, `a step named ${name} in ${job}`);
  return found.block;
};
const index = (name, job = KEY) => STEPS[job].findIndex((s) => s.name === name);
const writeDiff = readFileSync(new URL("./write-diff.py", import.meta.url), "utf8");
const WRITE_DIFF = new URL("./write-diff.py", import.meta.url).pathname;
const input = (block, key) => new RegExp(`^ {10}${key}: (.*)$`, "m").exec(block)?.[1];

test("it runs only from main on pr-require-checks' completion", () => {
  const on = /\non:\n([\s\S]*?)\n\S/.exec(text)[1];
  assert.match(on, /^ {2}workflow_run: # zizmor: ignore\[dangerous-triggers\]$/m);
  assert.match(on, /^ {4}workflows: \[pr-require-checks\]$/m);
  const keys = on.split("\n").filter((line) => !line.trim().startsWith("#")).map((line) => line.split(" #")[0]).join("\n");
  assert.doesNotMatch(keys, /pull_request|push|workflow_dispatch|issue|schedule/);
  assert.match(text, /github\.ref == 'refs\/heads\/main'/);
  assert.match(text, /github\.event\.workflow_run\.event == 'pull_request'/);
  assert.match(text, /github\.event\.workflow_run\.head_repository\.full_name == github\.repository/);
});

const grantsOf = (block) =>
  [...block.matchAll(/^ {6}([a-z-]+): (\w+)(?: #.*)?$/gm)].filter(([, scope]) =>
    ["contents", "pull-requests", "actions", "checks", "issues", "statuses", "id-token"].includes(scope),
  );

test("the model's jobs can only read, and the one writer runs no model", () => {
  assert.match(text, /^permissions: \{\}$/m);
  for (const job of LEGS) {
    const review = grantsOf(jobText(job));
    assert.ok(review.length > 0, job);
    for (const [line, , level] of review) assert.equal(level, "read", `${job}: ${line}`);
  }
  // The routes between legs hold no grant, no secret and no model.
  for (const job of ["review-handoffs", "subscription-handoffs"]) {
    const route = jobText(job);
    assert.match(route, /^ {4}permissions: \{\}$/m, job);
    assert.doesNotMatch(route, /run-claude-cli|secrets\.|actions\/checkout@|uses:/, job);
  }
  const record = jobText("record");
  assert.deepEqual(grantsOf(record).map(([, scope, level]) => `${scope}:${level}`), ["checks:write"]);
  assert.doesNotMatch(record, /run-claude-cli|secrets\.|actions\/checkout@/);
  // It posts counts only, read as numbers from this run's verdicts.
  assert.match(record, /critical =~ \^\[0-9\]\{1,6\}\$/);
  assert.match(record, /repos\/\$GITHUB_REPOSITORY\/check-runs/);
  assert.doesNotMatch(text, /write-all/);
});

test("the diff shows every file as text and refuses one a review cannot read whole", () => {
  const diff = step("Write the diff");
  assert.match(diff, /python3 -I \.base\/\.github\/scripts\/pr-review-main\/write-diff\.py "\$SRC" "\$BASE_SHA" "\$HEAD_SHA" "\$DATA\/diff\.patch" "\$MAX_DIFF_BYTES"$/m);
  assert.match(writeDiff, /^DIFF = \["diff", "--text", "--no-ext-diff", "--no-textconv", "--no-color"\]$/m);
  assert.match(diff, /\^\(Binary files \.\* differ\|GIT binary patch\)\$/);
  assert.match(diff, /-gt "\$MAX_DIFF_BYTES"/);
  assert.match(diff, /MAX_DIFF_BYTES: "\d+"/);
});

test("the diff is split into parts one read returns whole, and a longer line gets no verdict", () => {
  const diff = step("Write the diff");
  const awk = diff.match(/LC_ALL=C (awk -v dir=.*?' "\$DATA\/diff\.patch")/s)[1];
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-split-"));
  try {
    const run = (text) => {
      rmSync(path.join(dir, "diff"), { recursive: true, force: true });
      mkdirSync(path.join(dir, "diff"));
      writeFileSync(path.join(dir, "diff.patch"), text);
      return spawnSync("bash", ["-c", `LC_ALL=C ${awk}`], { env: { ...process.env, DATA: dir, PART_BYTES: "10", PART_LINES: "2" } });
    };
    // 5 lines of 4 bytes: 2 lines per part at most, so 3 parts, in order.
    assert.equal(run("aaa\nbbb\nccc\nddd\neee\n").status, 0);
    const parts = readdirSync(path.join(dir, "diff")).sort();
    assert.deepEqual(parts, ["part-001.patch", "part-002.patch", "part-003.patch"]);
    assert.equal(parts.map((p) => readFileSync(path.join(dir, "diff", p), "utf8")).join(""), "aaa\nbbb\nccc\nddd\neee\n");
    // A 13-byte line is longer than a 10-byte part.
    assert.notEqual(run("aaaaaaaaaaaa\n").status, 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a diff with a line past the review's cap gets no verdict", async () => {
  const diff = step("Write the diff");
  const { LONG_LINE_BYTES } = await import("./write-verdict.mjs");
  assert.match(diff, new RegExp(`LONG_LINE_BYTES: "${LONG_LINE_BYTES}"`));
  const awk = diff.match(/LC_ALL=C (awk -v max=.*?' "\$DATA\/diff\.patch")/s)[1];
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-long-"));
  try {
    const run = (line) => {
      writeFileSync(path.join(dir, "diff.patch"), `diff --git a/x b/x\n@@ -1 +1 @@\n${line}\n`);
      return spawnSync("bash", ["-c", `LC_ALL=C ${awk}`], { env: { ...process.env, DATA: dir, LONG_LINE_BYTES: String(LONG_LINE_BYTES) } }).status;
    };
    assert.equal(run(`+${"x".repeat(1000)}`), 0);
    assert.notEqual(run(`+${"x".repeat(2500)}`), 0);
    assert.notEqual(run(` ${"y".repeat(LONG_LINE_BYTES + 1)}`), 0);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// write-diff.py run on a fixture repository: each case is a commit on top of
// a base, and the patch it prints for base...head.
// A cap of 0 makes every patch over it, so moves may collapse.
function diffCase(build, maxBytes = 0) {
  const src = mkdtempSync(path.join(tmpdir(), "pr-review-main-rename-"));
  try {
    const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
    const git = (...args) => {
      if (args[0] === "mv") mkdirSync(path.dirname(path.join(src, args[2])), { recursive: true });
      const run = spawnSync("git", ["-C", src, ...args], { encoding: "utf8", env });
      assert.equal(run.status, 0, run.stderr);
      return run.stdout.trim();
    };
    const write = (file, body) => {
      mkdirSync(path.dirname(path.join(src, file)), { recursive: true });
      writeFileSync(path.join(src, file), body);
    };
    git("init", "-q");
    const symlink = (target, file) => {
      mkdirSync(path.dirname(path.join(src, file)), { recursive: true });
      symlinkSync(target, path.join(src, file));
    };
    const chmod = (file) => chmodSync(path.join(src, file), 0o755);
    build.base(write, symlink, chmod);
    git("add", "-A");
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base");
    const base = git("rev-parse", "HEAD");
    build.head(git, write, chmod);
    git("add", "-A");
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "head");
    const head = git("rev-parse", "HEAD");
    const out = path.join(src, "..", `${path.basename(src)}.patch`);
    const run = spawnSync("python3", ["-I", WRITE_DIFF, src, base, head, out, String(maxBytes)], { encoding: "utf8", env });
    assert.equal(run.status, 0, run.stderr);
    const patch = readFileSync(out, "utf8");
    rmSync(out);
    return patch;
  } finally {
    rmSync(src, { recursive: true, force: true });
  }
}
const lines = (prefix, n) => `${Array.from({ length: n }, (_, i) => `${prefix} ${i}`).join("\n")}\n`;

const fiveMoves = {
  base: (write) => {
    for (let i = 0; i < 5; i++) write(`docs/a${i}.md`, lines(`file ${i} line`, 400));
  },
  head: (git) => {
    for (let i = 0; i < 5; i++) git("mv", `docs/a${i}.md`, `guide/a${i}.md`);
  },
};

test("under the size cap every move prints whole, as --no-renames shows it", () => {
  // Five 400-line files, each about 7 KB as added and again as deleted.
  const patch = diffCase(fiveMoves, 300000);
  assert.doesNotMatch(patch, /^rename from/m);
  for (let i = 0; i < 5; i++) {
    assert.equal(patch.match(new RegExp(`^\\+file ${i} line \\d+$`, "gm")).length, 400);
    assert.equal(patch.match(new RegExp(`^-file ${i} line \\d+$`, "gm")).length, 400);
  }
});

test("over the size cap a file moved unchanged outside the lane sources prints as its rename lines alone", () => {
  const patch = diffCase(fiveMoves, 1000);
  // Five moves of 400 lines each: five headers, no content line.
  assert.equal(patch.match(/^rename from docs\/a\d\.md$/gm).length, 5);
  assert.equal(patch.match(/^rename to guide\/a\d\.md$/gm).length, 5);
  assert.doesNotMatch(patch, /^[+-]file /m);
  assert.ok(patch.length < 1000, `${patch.length} bytes`);
});

test("over the size cap a move an added line names prints whole, and so does one that move names", () => {
  const patch = diffCase({
    base: (write) => {
      write("tools/setup.sh", `source x/helper.sh\n${lines("hostile", 20)}`);
      write("lib/x/helper.sh", lines("helper", 20));
      write("lib/quiet.md", lines("quiet", 20));
      write("ci.yml", "steps: []\n");
    },
    head: (git, write) => {
      git("mv", "tools/setup.sh", "build/setup.sh");
      git("mv", "lib/x/helper.sh", "build/x/helper.sh");
      git("mv", "lib/quiet.md", "docs/quiet.md");
      // The edit names the first move by its whole path; that move, printed
      // whole, names the second by its last directory and name.
      write("ci.yml", "steps: []\nrun: bash build/setup.sh\n");
    },
  });
  for (const word of ["hostile", "helper"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 20, word);
  }
  assert.match(patch, /^\+source x\/helper\.sh$/m);
  // The move nothing names still collapses.
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
  assert.doesNotMatch(patch, /^rename to build\//m);
});

test("over the size cap a move a shown line names by its bare name, or its name without the extension, prints whole", () => {
  const patch = diffCase({
    base: (write) => {
      write("lib/helper.sh", lines("helper", 10));
      write("lib/payload.py", lines("payload", 10));
      write("lib/quiet.md", lines("quiet", 10));
      write("ci.sh", "true\n");
    },
    head: (git, write) => {
      git("mv", "lib/helper.sh", "tools/helper.sh");
      git("mv", "lib/payload.py", "tools/payload.py");
      git("mv", "lib/quiet.md", "docs/quiet.md");
      write("ci.sh", 'true\nsource "$(dirname "$0")/helper.sh"\nimport payload\n');
    },
  });
  for (const word of ["helper", "payload"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 10, word);
  }
  // An unrelated pure move still collapses.
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
});

test("over the size cap a move that may run or load prints whole", () => {
  const patch = diffCase({
    base: (write, _symlink) => {
      write("fixtures/evil/SKILL.md", lines("skill", 10));
      write("notes/run.md", lines("hook", 10));
      write("lib/x/conftest.py", lines("conftest", 10));
      write("lib/quiet.md", lines("quiet", 10));
    },
    head: (git) => {
      git("mv", "fixtures/evil/SKILL.md", "plugins/p/skills/evil/SKILL.md");
      git("mv", "notes/run.md", "plugins/p/hooks/run.md");
      git("mv", "lib/x/conftest.py", "tests/conftest.py");
      git("mv", "lib/quiet.md", "docs/quiet.md");
    },
  });
  for (const word of ["skill", "hook", "conftest"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 10, word);
  }
  assert.match(patch, /^rename to docs\/quiet\.md$/m);
  assert.doesNotMatch(patch, /^\+quiet /m);
});

test("over the size cap a moved executable prints whole", () => {
  const patch = diffCase({
    // Executable on both sides, so the mode does not change.
    base: (write, _symlink, chmod) => {
      write("tools/run", lines("exec", 10));
      chmod("tools/run");
    },
    head: (git) => git("mv", "tools/run", "bin/run"),
  });
  assert.doesNotMatch(patch, /^old mode/m);
  assert.equal(patch.match(/^\+exec \d+$/gm).length, 10);
});

test("over the size cap a moved symlink prints whole", () => {
  const patch = diffCase({
    base: (_write, symlink) => symlink("../../etc/hostile", "links/run"),
    head: (git) => git("mv", "links/run", "bin/run"),
  });
  // The link's target shows on both sides, as --no-renames prints it.
  assert.doesNotMatch(patch, /^rename from/m);
  assert.match(patch, /^new file mode 120000$/m);
  assert.match(patch, /^\+\.\.\/\.\.\/etc\/hostile$/m);
  assert.match(patch, /^-\.\.\/\.\.\/etc\/hostile$/m);
});

test("a move into or out of a lane source, or one that changes the mode, prints whole", () => {
  const patch = diffCase({
    base: (write) => {
      write("notes/hook.md", lines("into", 30));
      write(".github/workflows/old.yml", lines("out of", 30));
      write("tools/run.sh", lines("mode", 30));
    },
    head: (git, _write, chmod) => {
      git("mv", "notes/hook.md", ".claude/hook.md");
      git("mv", ".github/workflows/old.yml", "archive/old.yml");
      git("mv", "tools/run.sh", "tools/go.sh");
      chmod("tools/go.sh");
    },
  });
  assert.doesNotMatch(patch, /^rename from/m);
  // Each new file's every line is shown as added, each old one's as deleted.
  for (const word of ["into", "out of", "mode"]) {
    assert.equal(patch.match(new RegExp(`^\\+${word} \\d+$`, "gm")).length, 30, word);
    assert.equal(patch.match(new RegExp(`^-${word} \\d+$`, "gm")).length, 30, word);
  }
  assert.match(patch, /^new file mode 100755$/m);
});

test("an edited rename prints whole, as a delete and an add", () => {
  const patch = diffCase({
    base: (write) => write("notes.md", lines("line", 40)),
    head: (git, write) => {
      git("mv", "notes.md", "docs/notes.md");
      write("docs/notes.md", `${lines("line", 40)}run the payload\n`);
    },
  });
  assert.doesNotMatch(patch, /^rename from/m);
  assert.match(patch, /^\+line 0$/m);
  assert.match(patch, /^-line 0$/m);
  assert.match(patch, /^\+run the payload$/m);
});

test("each leg leaves a lane record", () => {
  for (const job of LEGS) {
    const report = step("Report the review's outcome", job);
    assert.match(report, /report-lane-outcome@[0-9a-f]{40}/);
    assert.match(report, /^ {10}lane: pr-review-main$/m);
    assert.match(report, /^ {10}lane-id: pr-review-main-\$\{\{ matrix\.lane \}\}$/m);
    assert.ok(index("Review the pull request", job) < index("Report the review's outcome", job));
    assert.match(step("Review the pull request", job), /^ {8}continue-on-error: true$/m);
  }
});

test("it checks out main only, and runs local actions from that checkout", () => {
  assert.equal(text.match(/uses: actions\/checkout@/g).length, LEGS.length);
  for (const job of LEGS) {
    const checkouts = STEPS[job].filter((s) => /uses: actions\/checkout@/.test(s.block));
    assert.equal(checkouts.length, 1, job);
    // workflow_run's github.sha is the default branch commit whose copy of
    // this file runs, so every leg checks out that same main.
    assert.match(checkouts[0].block, /^ {10}ref: \$\{\{ github\.sha \}\}$/m);
    assert.match(checkouts[0].block, /^ {10}persist-credentials: false$/m);
  }
  for (const [, local] of text.matchAll(/^\s+uses: (\.\/\S+)/gm)) {
    assert.ok(local.startsWith("./.base/.github/actions/"), local);
  }
  for (const [, remote] of text.matchAll(/^\s+uses: ([^.\s]\S*)/gm)) {
    assert.match(remote, /@[0-9a-f]{40}$/, remote);
  }
});

test("the model reads its data directory alone", () => {
  for (const job of LEGS) {
  const review = step("Review the pull request", job);
  assert.match(review, /^ {10}tools: Read$/m);
  assert.match(review, /^ {10}allowed-tools: Read\(\.\/pr-review-main-data\/\*\*\)$/m);
  assert.match(review, /^ {10}permission-mode: dontAsk$/m);
  for (const denied of ["Read(./.base/**)", "Bash", "Write", "Edit", "WebFetch", "Agent", "mcp__*"]) {
    assert.ok(review.includes(`            ${denied}\n`), denied);
  }
  }
  for (const placeholder of ["LANE_NAME", "CRITERIA_DIR", "STANDARDS_DIR", "DIFF_PARTS", "CONTEXT_FILE", "PR_FILE"]) {
    assert.ok(prompt.includes(placeholder), placeholder);
    assert.ok(step("Write the prompt and schema").includes(`prompt=\${prompt//${placeholder}/`), placeholder);
  }
});

test("the verdict uploads once, after it is written, under the writer's name", () => {
  assert.equal(text.match(/uses: actions\/upload-artifact@/g).length, LEGS.length);
  for (const job of LEGS) {
    const uploads = STEPS[job].filter((s) => /uses: actions\/upload-artifact@/.test(s.block));
    assert.equal(uploads.length, 1, job);
    assert.equal(uploads[0].name, "Upload the verdict");
    assert.ok(index("Write the verdict", job) < index("Upload the verdict", job));
    assert.match(uploads[0].block, /^ {8}if: steps\.verdict\.outcome == 'success'$/m);
    assert.match(uploads[0].block, /^ {10}name: \$\{\{ steps\.verdict\.outputs\.name \}\}$/m);
    // The tree is git's, the head and base the trigger gate's: never the model's.
    const write = step("Write the verdict", job);
    assert.match(write, /TREE_SHA: \$\{\{ steps\.diff\.outputs\.tree \}\}/);
    assert.match(write, /HEAD_SHA: \$\{\{ steps\.gate\.outputs\.head-sha \}\}/);
    // A handed-off leg writes no verdict.
    assert.match(write, /^ {8}if: steps\.review\.outcome == 'success' && steps\.review\.outputs\.handoff != 'true'$/m);
  }
  assert.match(step("Write the diff"), /rev-parse --verify "\$HEAD_SHA\^\{tree\}"/);
});

test("only a lane-source pull request is reviewed, by the gate's own predicate", () => {
  const select = step("Select a lane-source pull request");
  assert.match(select, /import babysit_review_evidence as ev/);
  assert.match(select, /ev\.lane_source\(p\)/);
  assert.match(step("Write the diff"), /^ {8}if: steps\.select\.outputs\.review == 'true'$/m);
});

// The review lanes' credential order, read from their callers' `secrets:`
// blocks, never from this workflow: each names the reusable's secret and the
// repository secret it passes.
const hostedChain = (file) => {
  const caller = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const block = /^ {4}secrets:\n((?: {6}.*\n)+)/m.exec(caller)[1];
  return [...block.matchAll(/^ {6}([A-Z_]+): \$\{\{ secrets\.([A-Z_]+) \}\}$/gm)].map(([, as, secret]) => [as, secret]);
};
// The run-claude-cli input each reusable secret reaches in ci-workflows
// pr-review-cli.yml: review-key passes CLAUDE_API_KEY as api-key,
// review-subscription CLAUDE_CODE_OAUTH_TOKEN as subscription-token,
// review-fallback FALLBACK_CLAUDE_CODE_OAUTH_TOKEN as fallback-token.
const LAUNCHER_INPUT = {
  CLAUDE_API_KEY: "api-key",
  CLAUDE_CODE_OAUTH_TOKEN: "subscription-token",
  FALLBACK_CLAUDE_CODE_OAUTH_TOKEN: "fallback-token",
};
const CREDENTIAL_INPUTS = Object.values(LAUNCHER_INPUT);
const needsOf = (job) => /^ {4}needs: (.*)$/m.exec(jobText(job))?.[1];

test("the legs run the review lanes' credentials in the review lanes' order", () => {
  const hosted = hostedChain("pr-review-hosted.yml");
  assert.deepEqual(hostedChain("pr-review-security-hosted.yml"), hosted);
  assert.equal(hosted.length, 3);
  // Walk this workflow's chain from the key leg through each route.
  const order = [KEY];
  for (let job = KEY; ; ) {
    const route = ["review-handoffs", "subscription-handoffs"].find((id) => needsOf(id) === job);
    if (!route) break;
    job = LEGS.find((id) => needsOf(id) === route);
    order.push(job);
  }
  assert.deepEqual(order, LEGS);
  const used = order.map((job) => {
    const review = step("Review the pull request", job);
    const set = CREDENTIAL_INPUTS.filter((name) => input(review, name) !== undefined);
    assert.equal(set.length, 1, `${job} passes one credential`);
    return [set[0], /^\$\{\{ secrets\.([A-Z_]+) \}\}$/.exec(input(review, set[0]))[1]];
  });
  assert.deepEqual(used, hosted.map(([as, secret]) => [LAUNCHER_INPUT[as], secret]));
  // Each leg checks its own credential; the key leg hands an empty key on,
  // and the subscription leg checks whether the fallback token is set.
  const later = {
    [KEY]: '"true"',
    [SUB]: "${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}",
    [FB]: '"false"',
  };
  order.forEach((job, i) => {
    const check = step("Check the credential", job);
    assert.equal(input(check, "PRESENT"), `\${{ secrets.${used[i][1]} != '' }}`, job);
    assert.equal(input(check, "SECRET_NAME"), used[i][1], job);
    assert.equal(input(check, "LATER_PRESENT"), later[job], job);
  });
  // Each secret's value reaches only its leg's launcher step; elsewhere a
  // job may ask only whether it is set.
  for (const job of LEGS) {
    for (const s of STEPS[job]) {
      const values = [...s.block.matchAll(/secrets\.([A-Z_]+)(?![A-Z_]| != '')/g)].map(([, name]) => name);
      if (s.name === "Review the pull request") assert.equal(values.length, 1, job);
      else assert.deepEqual(values, [], `${job}: ${s.name}`);
    }
  }
  assert.doesNotMatch(text, /secrets: inherit|toJSON\(secrets\)/);
});

// run-claude-cli's handoff-reason (its action.yml at the pinned SHA): a key
// leg hands off on credit-stop or auth, a subscription leg with fallback-ready
// on limit-stop, credit-stop or auth; an empty credential with a later leg's
// set hands off as no-key (report-lane-outcome's fallback-reason).
const ROUTES = {
  "review-handoffs": ["credit-stop", "auth", "no-key"],
  "subscription-handoffs": ["limit-stop", "credit-stop", "auth", "no-key"],
};
const routeRun = (job) => {
  const block = jobText(job);
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(block)[1].replace(/^ {10}/gm, "");
  return (env) => {
    const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-route-"));
    try {
      const out = path.join(dir, "out");
      writeFileSync(out, "");
      const reasons = /^ {10}REASONS: (.*)$/m.exec(block)[1];
      const result = spawnSync("bash", ["-e", "-c", run], { encoding: "utf8", env: { ...process.env, REASONS: reasons, GITHUB_OUTPUT: out, ...env } });
      const line = readFileSync(out, "utf8").trim();
      return { status: result.status, matrix: line ? JSON.parse(line.replace(/^matrix=/, "")) : undefined };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
};

test("a route hands the next leg fixed lane rows, only for a lane handed on with a closed reason", () => {
  const rows = {
    "claude-review": { lane: "claude-review", skill: "code-review", route: "review-code", switch: "CLAUDE_REVIEW_DISABLED" },
    "claude-security-review": { lane: "claude-security-review", skill: "security-review", route: "review-security", switch: "CLAUDE_SECURITY_REVIEW_DISABLED" },
  };
  // The rows are the key leg's own matrix.
  for (const row of Object.values(rows)) {
    assert.ok(jobText(KEY).includes(`          - lane: ${row.lane}\n            skill: ${row.skill}\n            route: ${row.route}\n            switch: ${row.switch}\n`), row.lane);
  }
  for (const [job, reasons] of Object.entries(ROUTES)) {
    assert.deepEqual(/^ {10}REASONS: (.*)$/m.exec(jobText(job))[1].split(" "), reasons, job);
    const route = routeRun(job);
    assert.deepEqual(route({ CODE: "credit-stop", SECURITY: "" }), { status: 0, matrix: { include: [{ ...rows["claude-review"], reason: "credit-stop" }] } });
    assert.deepEqual(route({ CODE: "auth", SECURITY: "no-key" }), {
      status: 0,
      matrix: { include: [{ ...rows["claude-review"], reason: "auth" }, { ...rows["claude-security-review"], reason: "no-key" }] },
    });
    for (const bad of ["other", "credit-stop ", "true"]) {
      const result = route({ CODE: "", SECURITY: bad });
      assert.notEqual(result.status, 0, `${job} ${JSON.stringify(bad)}`);
      assert.equal(result.matrix, undefined);
    }
  }
  // limit-stop comes only from a subscription leg.
  assert.notEqual(routeRun("review-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
  assert.equal(routeRun("subscription-handoffs")({ CODE: "limit-stop", SECURITY: "" }).status, 0);
});

test("a later leg runs only for the lanes the previous leg handed on", () => {
  for (const [route, from, to] of [["review-handoffs", KEY, SUB], ["subscription-handoffs", SUB, FB]]) {
    const routeJob = jobText(route);
    assert.equal(needsOf(route), from);
    assert.match(routeJob, new RegExp(`&& \\(needs\\.${from}\\.outputs\\.claude-review != '' \\|\\| needs\\.${from}\\.outputs\\.claude-security-review != ''\\)`));
    // !cancelled(): one lane's failed leg does not drop the other lane's
    // handoff; the route still passes on only closed-set reasons.
    assert.match(routeJob, /^ {4}if: >-\n {6}!cancelled\(\)\n {6}&& github\.ref == 'refs\/heads\/main'\n/m);
    assert.doesNotMatch(routeJob, /always\(\)/);
    const leg = jobText(to);
    assert.equal(needsOf(to), route);
    assert.match(leg, new RegExp(`^ {6}matrix: \\$\\{\\{ fromJSON\\(needs\\.${route}\\.outputs\\.matrix\\) \\}\\}$`, "m"));
    // !cancelled() with the route's own success: the implicit success() needs
    // every ancestor, so one lane's failed leg would skip the other's.
    assert.match(leg, new RegExp(`^ {4}if: >-\\n {6}!cancelled\\(\\)\\n {6}&& needs\\.${route}\\.result == 'success'\\n {6}&& github\\.ref == 'refs\\/heads\\/main'\\n`, "m"));
    assert.doesNotMatch(leg, /always\(\) \|\|/);
    // Each lane's reason is its own output, set only by the handoff step.
    for (const lane of ["claude-review", "claude-security-review"]) {
      assert.match(jobText(from), new RegExp(`^ {6}${lane}: \\$\\{\\{ steps\\.handoff\\.outputs\\.${lane} \\}\\}$`, "m"));
    }
  }
  // The fallback leg is the last: it hands nothing on.
  assert.equal(index("Hand the lane on", FB), -1);
  assert.doesNotMatch(jobText(FB), /^ {4}outputs:$/m);
  assert.doesNotMatch(step("Review the pull request", KEY), /fallback-ready/);
  assert.equal(input(step("Review the pull request", SUB), "fallback-ready"), "${{ steps.credential.outputs.fallback-ready }}");
  assert.doesNotMatch(step("Review the pull request", FB), /fallback-ready/);
  // The record job waits for every leg and runs when a later one skipped.
  assert.match(jobText("record"), /^ {4}needs: \[review, review-subscription, review-fallback\]$/m);
  assert.match(jobText("record"), /^ {4}if: \$\{\{ !cancelled\(\) && github\.ref == 'refs\/heads\/main' \}\}$/m);
});

test("the handoff step names its lane and a closed reason, and a handed-off leg stays green", () => {
  for (const job of [KEY, SUB]) {
    const handoff = step("Hand the lane on", job);
    assert.match(handoff, /^ {8}if: steps\.review\.outputs\.handoff == 'true' \|\| steps\.credential\.outputs\.present == 'false'$/m);
    assert.match(handoff, /^ {10}REASON: \$\{\{ steps\.credential\.outputs\.present == 'false' && 'no-key' \|\| steps\.review\.outputs\.handoff-reason \}\}$/m);
    assert.ok(index("Review the pull request", job) + 1 === index("Hand the lane on", job));
    assert.match(step("Report the review's outcome", job), /&& steps\.review\.outputs\.handoff != 'true'$/m);
    assert.match(step("Fail without a verdict", job), /&& steps\.handoff\.outcome != 'success'$/m);
  }
  const run = /^ {8}run: \|\n((?: {10}.*\n?)+)/m.exec(step("Hand the lane on"))[1].replace(/^ {10}/gm, "");
  const dir = mkdtempSync(path.join(tmpdir(), "pr-review-main-handoff-"));
  try {
    const out = path.join(dir, "out");
    const hand = (reason) => {
      writeFileSync(out, "");
      const status = spawnSync("bash", ["-e", "-c", run], { env: { ...process.env, LANE: "claude-security-review", REASON: reason, GITHUB_OUTPUT: out } }).status;
      return [status, readFileSync(out, "utf8")];
    };
    assert.deepEqual(hand("credit-stop"), [0, "claude-security-review=credit-stop\n"]);
    assert.deepEqual(hand("no-key"), [0, "claude-security-review=no-key\n"]);
    assert.notEqual(hand("")[0], 0);
    assert.equal(hand("x\nclaude-review=auth")[1], "");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("every later leg repeats the key leg's steps but for its credential and why it ran", () => {
  const normal = (block) =>
    block
      .replace(/secrets\.[A-Z_]+/g, "secrets.X")
      .replace(/^( {10}SECRET_NAME: ).*$/m, "$1X")
      .replace(new RegExp(`^( {10})(?:${CREDENTIAL_INPUTS.join("|")}): `, "m"), "$1credential: ")
      .replace(/^ {10}LATER_PRESENT: .*\n/m, "")
      .replace(/^ {10}fallback-ready: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}\n/m, "")
      .replace(/\n {10}# Why this leg ran, for the lane's one record\.\n {10}fallback-reason: [^\n]*/, "")
      .replace(/ && steps\.handoff\.outcome != 'success'|and handed nothing on\n {6}# fails here,|fails here,/g, "");
  const keyNames = STEPS[KEY].map((s) => s.name);
  assert.deepEqual(STEPS[SUB].map((s) => s.name), keyNames);
  assert.deepEqual(STEPS[FB].map((s) => s.name), keyNames.filter((name) => name !== "Hand the lane on"));
  for (const job of [SUB, FB]) {
    for (const s of STEPS[job]) assert.equal(normal(s.block), normal(step(s.name, KEY)), `${job}: ${s.name}`);
    // Its record names why it ran, from the route's closed reason.
    assert.equal(
      input(step("Report the review's outcome", job), "fallback-reason"),
      "${{ matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'limit-stop' && 'limit-stop' || matrix.reason == 'no-key' && 'no-key' || '' }}",
    );
    // Its gates are the key leg's.
    // Past the route checks, its gates are the key leg's.
    const gates = (id) => /^ {4}if: >-\n((?: {6}.*\n)+)/m.exec(jobText(id))[1].replace(/^ {6}!cancelled\(\)\n {6}&& needs\.[a-z-]+\.result == 'success'\n {6}&& /, "      ");
    assert.equal(gates(job), gates(KEY));
  }
  assert.equal(input(step("Report the review's outcome", KEY), "fallback-reason"), undefined);
});

test("one lane handed on beside one that reviewed routes only the handed-on lane", () => {
  for (const job of Object.keys(ROUTES)) {
    // The security lane reviewed (no output); the code lane handed on.
    const { status, matrix } = routeRun(job)({ CODE: "credit-stop", SECURITY: "" });
    assert.equal(status, 0, job);
    assert.deepEqual(matrix.include.map((row) => [row.lane, row.reason]), [["claude-review", "credit-stop"]], job);
  }
});

test("the prompt says a rename-only entry is unseen and a change that references a moved path is a finding", () => {
  const flat = prompt.replace(/\s+/g, " ");
  assert.ok(flat.includes("A file moved unchanged may show only as its `rename from` and `rename to` lines: its content is not in the diff, so you have not seen it."));
  assert.ok(flat.includes("When any change you can see runs, sources, includes or otherwise references a path such an entry moved (its old or new path), report it as a finding"));
  // It sits with the diff parts, before the placeholder they replace.
  assert.ok(prompt.indexOf("rename from") < prompt.indexOf("DIFF_PARTS"));
});
