// The shared publish gate: an explicit layer publishes an artifact, otherwise only a
// PUBLIC (or repository-free) source with nothing credential-shaped does. A hosted
// page always runs every check, explicit or not.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { tempDir } from "./test-tmp.mjs";

const GATE = join(dirname(fileURLToPath(import.meta.url)), "publish-gate.mjs");
const {
  DESTINATION,
  HIDDEN,
  MACHINE_PATTERNS,
  OPT_IN,
  SECRET_PATTERNS,
  UNJOINABLE,
  WARN_ONLY,
  findMachine,
  findSecret,
  firstHit,
  normalize,
  publishGate,
  scanLeak,
  trustedMedium,
} = await import(pathToFileURL(GATE).href);

const clean = "# Talk\n\nMerge queues stopped flaky main builds.\n";
const key = `${"gh"}p_${"a".repeat(36)}`;

// Samples are assembled at run time so this file holds no credential-shaped literal.
// Shapes: R2 keys are a 32-hex access key id and a 64-hex secret
// (developers.cloudflare.com/r2/api/tokens/); Cloudflare's scannable tokens are
// cfk_, cfut_ or cfat_, 40 alphanumerics and an 8-hex checksum
// (developers.cloudflare.com/fundamentals/api/get-started/token-formats); an Azure
// client secret carries Q~ after its fourth character. The stateless GitHub App
// installation token is ghs_ then a JWT of about 520 characters: three base64url
// segments joined by '.', each segment obviously fake, with and without an app-id-like prefix.
const b64url = (s) => Buffer.from(s).toString("base64url");
const rs256 = [b64url('{"alg":"RS256","typ":"JWT"}'), b64url('{"sub":"FAKE-not-a-real-token"}'), b64url("FAKE sig\xfb\xff".repeat(8))].join(".");
const hex = (n) => "0123456789abcdef".repeat(8).slice(0, n);
const stamp = `<!-- rv-gen:view-builder-interactive sha256:${hex(64)} -->`;
const credentials = [
  ["R2 key pair", `r2 ${hex(32)} ${hex(64)}`],
  ["R2 key pair", `"accessKeyId": "${hex(32)}"`],
  ["R2 key pair", `secretAccessKey=${hex(64)}`],
  ["Azure client secret", `secret abc8${"Q~"}${"a".repeat(34)}`],
  ["Cloudflare API token", `${"cfut"}_${"A1".repeat(20)}${hex(8)}`],
  ["Cloudflare API token", `${"cfat"}_${"b2".repeat(20)}${hex(8)}`],
  ["Cloudflare API token", `${"cfk"}_${"c3".repeat(20)}${hex(8)}`],
  ["upload token", `${"pgup"}_${"Zz9-".repeat(10)}`],
  ["GitHub token", `${"ghs"}_123456_${Array(3).fill("FAKE-not_a_token".repeat(10)).join(".")}`],
  ["GitHub token", `${"ghs"}_${Array(3).fill("FAKE-not_a_token".repeat(10)).join(".")}`],
  ["GitHub token", `${"ghs"}_${rs256}`],
  ["GitHub token", `${"ghs"}_123456_${rs256}`],
];
const machines = [
  ["home path", "/home/alice/src/app.js"],
  ["home path", "/Users/alice/Desktop/notes.md"],
  ["home path", "C:\\Users\\alice\\repo"],
  ["home path", "C:\\\\Users\\\\alice"],
  ["home path", "/mnt/c/Users/alice/repo"],
  ["home path", "cat /root/.bashrc"],
  ["WSL path", "\\\\wsl.localhost\\Ubuntu"],
  ["scratchpad slug", "projects/-home-alice-worktrees-app/x.jsonl"],
  ["fleet hostname", "ssh melo-desk-001"],
  ["fleet hostname", "on melo-lap-002 today"],
  ["private hostname", "build.local"],
  ["private hostname", "db.internal:5432"],
  ["private hostname", "nas.lan"],
];

describe("publishGate", () => {
  test("an explicit layer publishes whatever the source", () => {
    const result = publishGate({ explicit: true, visibility: "PRIVATE", text: key });
    assert.equal(result.medium, "artifact");
    assert.equal(result.destination, DESTINATION);
  });
  for (const visibility of ["PRIVATE", "INTERNAL", "UNKNOWN", "", "bogus"]) {
    test(`a ${visibility || "missing"} visibility stays local and names the opt-in`, () => {
      const result = publishGate({ explicit: false, visibility, text: clean });
      assert.equal(result.medium, "file");
      assert.match(result.reason, /not PUBLIC/);
      assert.equal(result.opt_in, OPT_IN);
    });
  }
  for (const visibility of ["PUBLIC", "NONE"]) {
    test(`a ${visibility} source with clean text publishes and names the destination`, () => {
      const result = publishGate({ explicit: false, visibility, text: clean });
      assert.equal(result.medium, "artifact");
      assert.equal(result.destination, DESTINATION);
    });
    test(`a ${visibility} source with a credential stays local without echoing it`, () => {
      const result = publishGate({ explicit: false, visibility, text: `${clean}${key}\n`, subject: "deck" });
      assert.equal(result.medium, "file");
      assert.match(result.reason, /^deck line 4 looks like a GitHub token$/);
      assert.ok(!JSON.stringify(result).includes(key));
    });
  }
  test("a machine path does not keep an artifact local", () => {
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: "/home/alice/x" }).medium, "artifact");
  });
  test("findSecret reports a label and line, never the match", () => {
    assert.deepEqual(findSecret(`a\n${key}`), ["GitHub token", 2]);
    assert.equal(findSecret('password = "${PASSWORD}"'), null);
  });
});

describe("credential patterns", () => {
  for (const [label, line] of credentials) {
    test(`a ${label} sample is caught on its line`, () => {
      assert.deepEqual(findSecret(`clean\n${line}`), [label, 2]);
    });
  }
  test("a token placeholder and a commit sha are not credentials", () => {
    for (const text of ["ghs_job", "Bearer ghs_lane", "3e7fef0587433cfb07332dbeabf0d79fc0baadf3"]) {
      assert.equal(findSecret(text), null, text);
    }
  });
  test("a comment shaped like the stamp hides no token", () => {
    assert.notEqual(findSecret(`<!-- rv-gen:ghp_${"a".repeat(36)} sha256:${hex(64)} -->`), null);
    assert.notEqual(findSecret(`<!-- rv-gen:sk-ant-${"a".repeat(30)} sha256:${hex(64)} -->`), null);
    assert.equal(findSecret(`<!-- rv-gen:escape-helper-v1 sha256:${hex(64)} --> ${hex(32)}`), null);
  });
  test("the builder stamp's sha256 is not an R2 secret, even beside a 32-hex token", () => {
    assert.equal(findSecret(`${stamp}\n${hex(32)} ${stamp}`), null);
  });
  test("one 64-hex digest alone is not a key pair", () => {
    assert.equal(findSecret(`sha256 ${hex(64)}`), null);
  });
});

describe("machine patterns", () => {
  for (const [label, line] of machines) {
    test(`${JSON.stringify(line)} is a ${label}`, () => {
      assert.deepEqual(findMachine(`clean\n${line}`), [label, 2]);
    });
  }
  for (const line of ["/home/", "src/root/x.js", "https://example.com/Users", "localhost", "example.com", "melo-desk-1"]) {
    test(`${JSON.stringify(line)} is not a machine path or hostname`, () => {
      assert.equal(findMachine(line), null);
    });
  }
});

describe("normalized copy", () => {
  const split = `${"gh"}p_<span>${"a".repeat(18)}</span><b class="x">${"a".repeat(18)}</b>`;
  const numeric = `${"gh"}&#x70;&#95;${"a".repeat(36)}`;
  // Entities stay off the assignment lines, so no source line forms the shape it tests.
  const [quot, eq, apos, QUOT, Quot] = ["&quot;", "&#61;", "&apos;", "&QUOT;", "&Quot;"];
  test("a credential split by highlighting tags is refused", () => {
    assert.deepEqual(findSecret(`clean\n${split}`), ["GitHub token", 2]);
  });
  test("a credential written with numeric entities is refused", () => {
    assert.deepEqual(findSecret(`clean\n${numeric}`), ["GitHub token", 2]);
  });
  test("a password assignment written with named entities is refused", () => {
    assert.deepEqual(findSecret(`password = ${quot}hunter2hunter2${quot}`), ["password or secret assignment", 1]);
    assert.deepEqual(findSecret(`password${eq}${apos}hunter2hunter2${apos}`), ["password or secret assignment", 1]);
  });
  test("entities are decoded case-insensitively", () => {
    assert.deepEqual(findSecret(`password = ${QUOT}hunter2hunter2${Quot}`), ["password or secret assignment", 1]);
  });
  test("a machine path split by tags or written with entities is caught", () => {
    assert.deepEqual(findMachine("clean\n/home/<b>alice</b>/src"), ["home path", 2]);
    assert.deepEqual(findMachine("clean\n&#x2F;home&#47;alice&#x2f;src"), ["home path", 2]);
    assert.deepEqual(findMachine("clean\nssh melo-&#100;esk-001"), ["fleet hostname", 2]);
  });
  test("a JSON-escaped machine path with doubled backslashes is caught", () => {
    assert.deepEqual(findMachine('clean\n"path": "\\\\\\\\wsl.localhost\\\\Ubuntu"'), ["WSL path", 2]);
    assert.deepEqual(findMachine('clean\n"path": "C:\\\\Users\\\\alice"'), ["home path", 2]);
  });
  test("a code point above U+10FFFF decodes to nothing, rejoining the split token", () => {
    assert.deepEqual(findSecret(`${"gh"}p_${"a".repeat(18)}&#x110000;${"a".repeat(18)}`), ["GitHub token", 1]);
  });
  test("oversized decimal and surrogate entities decode without throwing", () => {
    assert.deepEqual(findSecret(`${"gh"}p_${"a".repeat(18)}&#99999999999999999999;${"a".repeat(18)}`), ["GitHub token", 1]);
    assert.equal(findSecret("&#xD800; plain text"), null);
  });
  test("a double-encoded entity decodes to the fixpoint", () => {
    assert.deepEqual(findSecret(`${"gh"}&amp;#x70;_${"a".repeat(36)}`), ["GitHub token", 1]);
  });
  test("a tag nested in a tag, or written as entities, is removed to the fixpoint", () => {
    assert.deepEqual(findSecret(`${"gh"}p_${"a".repeat(18)}<<b>i>${"a".repeat(18)}`), ["GitHub token", 1]);
    assert.deepEqual(findSecret(`${"gh"}p_${"a".repeat(18)}&lt;i&gt;${"a".repeat(18)}`), ["GitHub token", 1]);
  });
  test("fullwidth lookalikes fold under NFKC", () => {
    const wide = (s) => [...s].map((c) => String.fromCodePoint(c.codePointAt(0) + 0xfee0)).join("");
    assert.deepEqual(findSecret(`${wide("ghp")}_${"a".repeat(36)}`), ["GitHub token", 1]);
  });
  test("zero-width characters and soft hyphens are stripped", () => {
    for (const code of [0x200b, 0x200c, 0x200d, 0x2060, 0xfeff, 0xad]) {
      const mark = String.fromCodePoint(code);
      assert.deepEqual(findSecret(`${"gh"}p_${"a".repeat(18)}${mark}${"a".repeat(18)}`), ["GitHub token", 1], code.toString(16));
    }
  });
  test("a JSON \\uXXXX escape is decoded", () => {
    assert.deepEqual(findSecret(`${"gh"}\\u0070_${"a".repeat(36)}`), ["GitHub token", 1]);
  });
  test("a single backslash before punctuation is folded, as markdown escapes it", () => {
    assert.deepEqual(findSecret(`${"gh"}p\\_${"a".repeat(36)}`), ["GitHub token", 1]);
    assert.deepEqual(findSecret(`${"sk"}\\-ant\\-${"a".repeat(20)}`), ["Anthropic key", 1]);
  });
  test("a backslash before a letter, a slash, a dot or a quote stays", () => {
    assert.equal(normalize("a\\nb \\/home\\/x \\.local \\\"q\\\" \\'q\\'"), "a\\nb \\/home\\/x \\.local \\\"q\\\" \\'q\\'");
  });
  test("a hit on a later line keeps its line number after a tag is stripped", () => {
    assert.deepEqual(findSecret(`a\n<p>b</p>\nc\n${split}`), ["GitHub token", 4]);
  });
  test("an entity that is not in the list stays as written", () => {
    assert.equal(findSecret(`${"gh"}p_&eacute;${"a".repeat(36)}`), null);
  });
  test("text clean both raw and normalized still passes", () => {
    const text = "<p>Merge queues &amp; flaky builds: a &lt;b&gt; tag, 1 &gt; 0.</p>\n<code>a \\\\ b</code>\n";
    assert.equal(findSecret(text), null);
    assert.equal(findMachine(text), null);
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text }).medium, "artifact");
  });
  test("a hosted page with an escaped credential is refused without echoing it", () => {
    const result = publishGate({ explicit: false, visibility: "PUBLIC", text: split, medium: "hosted" });
    assert.equal(result.medium, "file");
    assert.ok(!JSON.stringify(result).includes("aaaa"));
  });
});

describe("split lines", () => {
  const broken = `${"gh"}p_${"a".repeat(18)}\n${"a".repeat(18)}`;
  test("a credential with a line break inside it is caught on its first line", () => {
    assert.deepEqual(findSecret(broken), ["GitHub token", 1]);
    assert.deepEqual(findSecret(`clean\n${broken.replace("\n", "\r\n")}\nclean`), ["GitHub token", 2]);
    assert.deepEqual(findSecret(`${"cfut"}_${"A1".repeat(10)}\n${"A1".repeat(10)}${hex(8)}`), ["Cloudflare API token", 1]);
  });
  test("a credential split by a line break and a tag is caught", () => {
    assert.deepEqual(findSecret(`${"gh"}p_<b>${"a".repeat(18)}\n${"a".repeat(18)}</b>`), ["GitHub token", 1]);
  });
  test("a split credential keeps the view local and refuses the host", () => {
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: broken }).medium, "file");
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: broken, medium: "hosted" }).medium, "file");
  });
  test("the leak scan blocks a split credential", () => {
    assert.deepEqual(scanLeak(Buffer.from(broken)), { block: "GitHub token", credential: true });
  });
  test("a 32-hex value on one line and a 64-hex value on the next are not a key pair", () => {
    // Each pair would form the key pair on one line, so these fail if the R2 pattern were joined.
    assert.equal(findSecret(`"md5": "${hex(32)}",\n"sha256": "${hex(64)}"`), null);
    assert.equal(findSecret(`${hex(32)}\n ${hex(64)}`), null);
  });
  test("an sk- word ending a line and a word starting the next are not a key", () => {
    assert.equal(findSecret(`see the ${"sk"}-\nprefixed-keys-documentation page`), null);
  });
  // Assembled at run time, so no source line forms an assignment.
  const splitAssignment = `"${"pass"}word":\n"${"hunter2".repeat(2)}"`;
  test("an assignment split across two lines keeps the view local and refuses the host", () => {
    // Fails if the gate's pair pass leaves the assignment out.
    assert.deepEqual(findSecret(splitAssignment), [WARN_ONLY, 1]);
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: splitAssignment }).medium, "file");
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: splitAssignment, medium: "hosted" }).medium, "file");
  });
  test("the leak scan neither blocks nor warns on an assignment split across two lines", () => {
    // Fails if the leak scan's split-line pass joins the assignment, which it only warns on alone.
    assert.deepEqual(scanLeak(Buffer.from(splitAssignment)), {});
    assert.deepEqual(scanLeak(Buffer.from(`+${splitAssignment.replace("\n", "\n+")}`), { diff: true }), {});
  });
  test("only the OpenAI key and the R2 key pair are left out of the gate's pair pass, by labels that exist", () => {
    assert.deepEqual([...UNJOINABLE], ["OpenAI key", "R2 key pair"]);
    const labels = SECRET_PATTERNS.map(([label]) => label);
    for (const label of [WARN_ONLY, ...UNJOINABLE]) assert.ok(labels.includes(label), label);
  });
  test("plain prose with line breaks and a home path split across lines raises nothing", () => {
    const prose = "Merge queues stopped\nflaky builds in /home/\nalice/src today, and /ho\nme/alice/x too.\n";
    assert.equal(findSecret(prose), null);
    assert.equal(findMachine(prose), null);
    assert.equal(publishGate({ explicit: false, visibility: "PUBLIC", text: prose, medium: "hosted" }).destination, "public");
  });
});

describe("leak scan", () => {
  // Assembled at run time, like the samples above, so no source line forms an assignment.
  const value = `"${"hunter2".repeat(2)}"`;
  const plain = `${"sec"}ret = ${value}`;
  test("a plain assignment alone only warns", () => {
    assert.deepEqual(scanLeak(Buffer.from(`${plain} // see [1]`)), { warn: true });
  });
  test("a plain assignment beside an escape normalize() folds blocks, since blanking cannot be trusted there", () => {
    assert.deepEqual(scanLeak(Buffer.from(`${plain} // see \\[1\\]`)), { block: HIDDEN, credential: false });
    assert.deepEqual(scanLeak(Buffer.from(`${plain} // see \\(1\\)`)), { block: HIDDEN, credential: false });
  });
  test("an assignment only the backslash fold shows blocks", () => {
    assert.deepEqual(scanLeak(Buffer.from(`${"pass"}word \\= ${value}`)), { block: HIDDEN, credential: false });
  });
});

describe("leak scan on UTF-8 bytes", () => {
  const token = `ghp_${"a".repeat(36)}`;
  const wide = (s) => [...s].map((c) => String.fromCodePoint(c.codePointAt(0) + 0xfee0)).join("");
  const scan = (text) => scanLeak(Buffer.from(text, "utf8"));

  test("a zero-width space inside a credential blocks", () => {
    const hidden = `${token.slice(0, 4)}${String.fromCodePoint(0x200b)}${token.slice(4)}`;
    assert.deepEqual(scan(hidden), { block: "GitHub token", credential: true });
  });

  test("a soft hyphen inside a credential blocks", () => {
    const hidden = `${token.slice(0, 4)}${String.fromCodePoint(0xad)}${token.slice(4)}`;
    assert.deepEqual(scan(hidden), { block: "GitHub token", credential: true });
  });

  test("a fullwidth look-alike credential blocks", () => {
    assert.deepEqual(scan(wide(token)), { block: "GitHub token", credential: true });
  });

  test("a plain assignment earlier in the text does not hide a credential after it", () => {
    const hidden = `${wide("ghp")}_${"a".repeat(36)}`;
    assert.deepEqual(scan(`${"pass"}word = "plaintext"\n${hidden}`), { block: "GitHub token", credential: true });
  });

  test("non-ASCII text beside a plain assignment still only warns", () => {
    const text = `${"pass"}word = "plaintext" # ${String.fromCodePoint(0xe9)} ${String.fromCodePoint(0xff08)}note${String.fromCodePoint(0xff09)} ${String.fromCodePoint(0x200b)}`;
    assert.deepEqual(scan(text), { warn: true });
  });

  test("plain non-ASCII text passes", () => {
    assert.deepEqual(scan(`${String.fromCodePoint(0xe9)} ${wide("note")} ${String.fromCodePoint(0x200b)} ${String.fromCodePoint(0x4e2d, 0x6587)}`), {});
  });

  test("byte patterns still read latin1 where the bytes are not valid UTF-8", () => {
    assert.deepEqual(scanLeak(Buffer.concat([Buffer.from([0xff]), Buffer.from(token), Buffer.from([0xfe])])), { block: "GitHub token", credential: true });
  });
});

describe("tracked tree", () => {
  // normalize() before NFKC, invisible characters, \uXXXX, the fixpoint and single backslashes.
  const NAMED = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
  const legacy = (text) =>
    text
      .replace(/<[^<>]*>/g, "")
      .replace(/&(?:#x([0-9a-f]+)|#(\d+)|(amp|lt|gt|quot|apos|nbsp));/gi, (_, hex, dec, name) => {
        if (name) return NAMED[name.toLowerCase()];
        const n = hex ? Number.parseInt(hex, 16) : Number.parseInt(dec, 10);
        return Number.isFinite(n) && n <= 0x10ffff ? String.fromCodePoint(n) : "";
      })
      .replace(/\\\\/g, "\\");
  const FIXTURES = /(?:^|\/)(?:tests?|fixtures|samples)\/|\.test\.[^/]+$|(?:^|\/)test_[^/]+$|_test\.[^/]+$|\.fixture$/;
  const root = join(dirname(GATE), "..");
  test("every tracked file outside the test fixtures that the earlier fold passes still passes", () => {
    const listed = spawnSync("git", ["-C", root, "ls-files", "-z"], { encoding: "utf8", maxBuffer: 1 << 28 });
    assert.equal(listed.status, 0, listed.stderr);
    const added = [];
    for (const path of listed.stdout.split("\0")) {
      if (!path || FIXTURES.test(path)) continue;
      let text;
      try {
        text = readFileSync(join(root, path), "utf8");
      } catch {
        continue;
      }
      if (text.includes("\0") || text.split(/\r?\n/).every((line) => normalize(line) === legacy(line))) continue;
      for (const [name, patterns] of [["findSecret", SECRET_PATTERNS], ["findMachine", MACHINE_PATTERNS]]) {
        const hit = firstHit(patterns, text);
        if (hit && !firstHit(patterns, text, legacy)) added.push(`${path}:${hit[1]} ${name} ${hit[0]}`);
      }
    }
    assert.deepEqual(added, []);
  });
  test("every tracked file outside the test fixtures that passes line by line still passes with lines joined", () => {
    const listed = spawnSync("git", ["-C", root, "ls-files", "-z"], { encoding: "utf8", maxBuffer: 1 << 28 });
    assert.equal(listed.status, 0, listed.stderr);
    const added = [];
    for (const path of listed.stdout.split("\0")) {
      if (!path || FIXTURES.test(path)) continue;
      let text;
      try {
        text = readFileSync(join(root, path), "utf8");
      } catch {
        continue;
      }
      if (text.includes("\0")) continue;
      const hit = findSecret(text);
      if (hit && !firstHit(SECRET_PATTERNS, text)) added.push(`${path}:${hit[1]} findSecret ${hit[0]}`);
    }
    assert.deepEqual(added, []);
  });
});

describe("hosted", () => {
  const hosted = (over) =>
    publishGate({ explicit: false, visibility: "PUBLIC", text: `${stamp}\n${clean}`, medium: "hosted", ...over });
  test("a public, clean, stamped page goes to the public host", () => {
    assert.deepEqual(hosted({}), {
      medium: "hosted",
      destination: "public",
      reason: "public repository and nothing credential-, path- or host-shaped in the content",
    });
    assert.equal(hosted({ visibility: "NONE" }).destination, "public");
  });
  for (const explicit of [false, true]) {
    for (const visibility of ["PRIVATE", "INTERNAL", "UNKNOWN", "", "bogus"]) {
      test(`explicit=${explicit} and a ${visibility || "missing"} repository go private`, () => {
        const result = hosted({ explicit, visibility });
        assert.equal(result.medium, "hosted");
        assert.equal(result.destination, "private");
        assert.match(result.reason, /not PUBLIC/);
      });
    }
    test(`explicit=${explicit} and a credential refuse the host, naming only label and line`, () => {
      const result = hosted({ explicit, text: `${clean}${key}\n`, subject: "page" });
      assert.deepEqual(result, { medium: "file", reason: "page line 4 looks like a GitHub token; a hosted page is refused" });
    });
    test(`explicit=${explicit} and a machine path go private`, () => {
      const result = hosted({ explicit, text: `${clean}/home/alice/x\n` });
      assert.deepEqual(result, { medium: "hosted", destination: "private", reason: "content line 4 names a home path" });
    });
  }
  test("a private request stays private and nothing raises it", () => {
    assert.equal(hosted({ requested: "private" }).destination, "private");
    assert.equal(hosted({ requested: "bogus" }).destination, "private");
  });
  test("a credential refuses even a private request", () => {
    assert.equal(hosted({ requested: "private", text: key }).medium, "file");
  });
});

describe("trustedMedium", () => {
  const home = tempDir("gate-home-");
  after(() => rmSync(home, { recursive: true, force: true }));
  test("hosted counts from the argument, the option and the user file, like artifact", () => {
    assert.equal(trustedMedium({ argument: "hosted", home, project: null }).medium, "hosted");
    assert.equal(trustedMedium({ option: "hosted", home, project: null }).medium, "hosted");
    mkdirSync(join(home, ".claude"), { recursive: true });
    writeFileSync(join(home, ".claude", "rendered-views.md"), "medium: hosted\n");
    assert.equal(trustedMedium({ home, project: null }).medium, "hosted");
  });
});

describe("CLI", () => {
  const run = (args, input = clean) => spawnSync(process.execPath, [GATE, ...args], { input, encoding: "utf8" });
  test("reads the text on stdin and upper-cases the visibility", () => {
    assert.equal(JSON.parse(run(["public"]).stdout).medium, "artifact");
    assert.equal(JSON.parse(run(["none"]).stdout).medium, "artifact");
    assert.equal(JSON.parse(run(["private"]).stdout).medium, "file");
    assert.equal(JSON.parse(run(["private", "--explicit"]).stdout).medium, "artifact");
    assert.match(JSON.parse(run(["public", "--subject", "deck"], key).stdout).reason, /^deck line 1/);
  });
  test("--medium hosted runs the hosted checks, explicit or not", () => {
    assert.equal(JSON.parse(run(["public", "--medium", "hosted"]).stdout).destination, "public");
    assert.equal(JSON.parse(run(["private", "--explicit", "--medium", "hosted"]).stdout).destination, "private");
    assert.equal(JSON.parse(run(["public", "--medium", "hosted", "--visibility", "private"]).stdout).destination, "private");
    assert.equal(JSON.parse(run(["public", "--explicit", "--medium", "hosted"], key).stdout).medium, "file");
  });
  test("refuses a missing visibility or an unknown flag", () => {
    assert.equal(run([]).status, 2);
    assert.equal(run(["--explicit"]).status, 2);
    assert.equal(run(["PUBLIC", "--force"]).status, 2);
    assert.equal(run(["PUBLIC", "--subject"]).status, 2);
    assert.equal(run(["PUBLIC", "--medium", "file"]).status, 2);
    assert.equal(run(["PUBLIC", "--visibility", "public"]).status, 2);
    assert.equal(run(["PUBLIC", "--medium", "hosted", "--visibility", "open"]).status, 2);
  });
});
