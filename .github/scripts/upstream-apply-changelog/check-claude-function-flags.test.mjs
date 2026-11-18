import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { flagProblems } from "./check-claude-function-flags.mjs";

const SCRIPT = fileURLToPath(new URL("./check-claude-function-flags.mjs", import.meta.url));

const help = (...rows) =>
  [
    "Usage: claude [options] [command] [prompt]",
    "",
    "Options:",
    "  --add-dir <directories...>            More directories Claude can access",
    ...rows,
    "  -h, --help                            Display help for command",
    "",
    "Commands:",
    "  doctor                                Check the health of your install",
  ].join("\n");

const RESUME = "  -r, --resume [value]                  Resume a conversation by session ID";
const SETTINGS = "  --settings <file-or-json>             Settings file or JSON string to load";

test("a help text with -r, --resume and --settings and no --profile has no problem", () => {
  assert.deepEqual(flagProblems(help(RESUME, SETTINGS)), []);
});

test("an upstream --profile flag is a problem, in any flag-column form", () => {
  for (const row of [
    "  --profile <name>                      Start in a named profile",
    "  -P, --profile <name>                  Start in a named profile",
    "  --profile=<name>                      Start in a named profile",
    "  --profiles, --profile <name>          Start in a named profile",
  ]) {
    const problems = flagProblems(help(RESUME, SETTINGS, row));
    assert.equal(problems.length, 1, row);
    assert.match(problems[0], /lists --profile/);
  }
});

test("a missing -r, --resume or --settings is a problem each", () => {
  assert.match(flagProblems(help(SETTINGS)).join("\n"), /no longer lists -r, --resume/);
  assert.match(flagProblems(help("  --resume [value]                      Resume", SETTINGS)).join("\n"), /no longer lists -r, --resume/);
  assert.match(flagProblems(help(RESUME)).join("\n"), /no longer lists --settings/);
  assert.equal(flagProblems(help()).length, 2);
});

test("near misses are not the flags: longer names, mentions in a description, continuation lines", () => {
  const rows = [
    RESUME,
    SETTINGS,
    "  --profile-dir <path>                  A directory of profiles",
    "  --setting-sources <sources>           Comma-separated list of setting sources",
    "  --bare                                Minimal mode. Explicitly provide context via",
    "                                        --profile and --settings.",
    "      --profile is not a flag here either",
  ];
  assert.deepEqual(flagProblems(help(...rows)), []);
  assert.match(
    flagProblems(help(RESUME, "  --setting-sources <sources>           Comma-separated list")).join("\n"),
    /no longer lists --settings/,
  );
});

test("each problem names the dotfiles claude function, both fixes and this issue", () => {
  for (const problem of flagProblems(help("  --profile <name>                      Start in a profile"))) {
    assert.match(problem, /dotfiles `claude` shell function/);
    assert.match(problem, /rename the function's flag/);
    assert.match(problem, /follow the upstream change/);
    assert.match(problem, /claude-code-plugins#17030/);
  }
});

test("the command runs the named binary's --help and exits 1 with one error line per problem", () => {
  const dir = mkdtempSync(join(tmpdir(), "ccf-"));
  try {
    const fake = (name, text) => {
      const file = join(dir, name);
      writeFileSync(file, `#!/bin/sh\n[ "$1" = --help ] || exit 9\ncat <<'EOF'\n${text}\nEOF\n`);
      chmodSync(file, 0o755);
      return file;
    };
    const ok = spawnSync(process.execPath, [SCRIPT, fake("ok", help(RESUME, SETTINGS))], { encoding: "utf8" });
    assert.equal(ok.status, 0, ok.stderr);
    assert.match(ok.stdout, /lists -r, --resume and --settings and no --profile/);
    const bad = spawnSync(process.execPath, [SCRIPT, fake("bad", help(SETTINGS, "  --profile <name>                      x"))], { encoding: "utf8" });
    assert.equal(bad.status, 1);
    assert.equal(bad.stdout.split("\n").filter((l) => l.startsWith("::error::")).length, 2);
    const broken = spawnSync(process.execPath, [SCRIPT, join(dir, "missing")], { encoding: "utf8" });
    assert.equal(broken.status, 1);
    assert.match(broken.stdout, /::error::.*did not print its help/);
    const usage = spawnSync(process.execPath, [SCRIPT], { encoding: "utf8" });
    assert.equal(usage.status, 2);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
