#!/usr/bin/env node
// Decide whether a rendered view may be published as a claude.ai Artifact or must
// stay on this machine. An explicit `medium: artifact` from a trusted layer
// publishes. Otherwise the view publishes only when its source repository is
// PUBLIC (or it has no repository source) and nothing in it is shaped like a
// credential. A miss proves nothing; a hit keeps the view local.
//
// A `hosted` page goes to a shared page host through `pages-publish`. It runs
// every check whatever the layers say: a credential refuses the host, and a
// repository that is not PUBLIC or a machine path or hostname sends it to the
// private host. The destination is only ever lowered from the one requested.
//
//   publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>]
//                    [--medium hosted [--visibility public|private]] < text
// Prints one JSON object. Exit 0 decided, 2 usage.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * The token shapes every scanner shares: this gate, the read runner's scan job (which loads this
 * file alone) and apply-patch's credential check (.github/scripts/apply-patch/apply-patch.mjs)
 * import them from here, each the broader of the shapes they once held apart.
 * Text shaped like a credential. Conservative: a hit keeps the page local, a miss proves nothing.
 * GitHub prefixes from
 * https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
 * and the ghs_ regex GitHub recommends for current and stateless installation tokens from
 * https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
 * (as of 2026-10-21; recheck when GitHub changes a token format or its recommended regex).
 */
export const CREDENTIAL_SHAPES = Object.freeze([
  ["GitHub token", /\b(?:ghs_[A-Za-z0-9._-]{36,}|gh[pousr]_[0-9A-Za-z]{36,}|github_pat_[0-9A-Za-z_]{22,})/],
  ["Anthropic key", /sk-ant-[A-Za-z0-9_-]{20,}/],
]);
export const SECRET_PATTERNS = Object.freeze([
  ["private key", /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ["AWS access key", /\b(?:AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}\b/],
  ...CREDENTIAL_SHAPES,
  ["OpenAI key", /\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{20,}/],
  ["Slack token", /\bxox[abposr]-[0-9A-Za-z-]{10,}/],
  ["Stripe key", /\b[sr]k_(?:test|live|prod)_[0-9A-Za-z]{10,}/],
  ["password or secret assignment", /\b(?:password|passwd|pwd|secret|client_secret|api_?key|token)["']?\s*[:=]\s*["'][^"'\s$<>{}]{8,}["']/i],
  // A 32-hex and a 64-hex word on one line, in either order. The lookaheads run once per line
  // start (m: after the terminators `.` stops at), so time grows linearly; a `hex.*hex` form
  // rescans the line from every hex word, quadratic on one-line JSON full of digests.
  [
    "R2 key pair",
    /^(?=.*\b[0-9a-f]{32}\b)(?=.*\b[0-9a-f]{64}\b)|\b(?:access_?key_?id|secret_?access_?key)["']?\s*[:=]\s*["']?[0-9A-Za-z/+]{16,}/im,
  ],
  ["Azure client secret", /(?:^|[^\w~.-])[\w~.]{3}\dQ~[\w~.-]{31,34}(?![\w~.-])/],
  ["Cloudflare API token", /\bcf(?:k|ut|at)_[A-Za-z0-9]{40,}/],
  ["upload token", /\bpgup_[A-Za-z0-9_-]{20,}/],
  ["npm token", /\bnpm_[A-Za-z0-9]{36}/],
  ["Google API key", /\bAIza[0-9A-Za-z_-]{35}/],
  ["JSON Web Token", /\beyJ[A-Za-z0-9_-]{7,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}/],
  ["Docker registry auth", /"auth"\s*:\s*"[A-Za-z0-9+/=]{16,}"/],
  // Split literals, so this source line never matches its own pattern.
  ["Azure storage account key", new RegExp("Account" + "Key=[A-Za-z0-9+/]{40,}={0,2}")],
  ["Pulumi access token", /\bpul-[0-9a-f]{40}/],
  ["base64-encoded PEM block", new RegExp("LS0tLS1CRUdJ" + "Ti[A-Za-z0-9+/]{20,}")],
  ["netrc password", /\b(?:machine\s+\S+|default)\s+login\s+\S+\s+password\s+[^\s"'\\]{8,}/],
  ["netrc password", /^\s*password\s+[^\s"'\\]{8,}\s*$/],
]);

/**
 * Credentials in a URL's userinfo: a password of 6 or more characters that is not a
 * placeholder (user:password@, <password>, ${PASSWORD}, ***). Not in SECRET_PATTERNS:
 * redaction tests across the tracked tree carry realistic fake connection strings,
 * which this shape cannot tell from real ones, and every scanner importing those
 * patterns would block a change touching them. Callers whose text has no such
 * fixtures (the lane telemetry upserts) check it alongside scanLeak.
 */
export const URL_CREDENTIALS = Object.freeze([
  "URL credentials",
  /:\/\/[^/\s:@]+:(?!password@|<[^>]*>@|\$\{[^}]*\}@|\*+@)[^/\s@]{6,}@/i,
]);

// The secret patterns read on each pair of adjacent lines joined, so a credential a line break
// splits still matches. Left out of every pair pass: the OpenAI key (any sk- and 20 token
// characters), since an sk- word ending a line joins the next line's first word; and the R2 key
// pair (a 32-hex and a 64-hex token), since adjacent md5 and sha256 lines pair. The gate's pair
// pass (findSecret) keeps the assignment, since any label from it keeps a view local or refuses
// the host; the leak scan's split-line pass (straddles) leaves it out too, since it only warns
// on it. publish-gate.test.mjs checks the labels against SECRET_PATTERNS, so a renamed one fails
// loudly there. Loading never throws on a missing label: the leak scan runs a gate whose list
// lacks the assignment (callers.test.mjs).
export const WARN_ONLY = "password or secret assignment";
export const UNJOINABLE = Object.freeze(["OpenAI key", "R2 key pair"]);
const GATE_JOINABLE = SECRET_PATTERNS.filter(([label]) => !UNJOINABLE.includes(label));
const JOINABLE = GATE_JOINABLE.filter(([label]) => label !== WARN_ONLY);

/** Machine paths and hostnames: a hit sends a hosted page to the private host. Only these shapes are caught. */
export const MACHINE_PATTERNS = Object.freeze([
  ["home path", /\/home\/[a-z_][\w.-]*\/|\/Users\/[^/\s"'<>]+\/|\b[A-Za-z]:\\+Users\\+|\/mnt\/[a-z]\/Users\/|(?<![\w.~-])\/root\//i],
  ["WSL path", /\\\\wsl(?:\$|\.localhost)/i],
  ["scratchpad slug", /(?<![\w-])-home-[a-z_][\w.]*-/i],
  ["fleet hostname", /\bmelo-(?:desk|lap|phone)-\d{3}\b/i],
  ["private hostname", /\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:local|internal|lan)\b(?![.-])/i],
]);

// The builders' page stamps carry a 64-hex digest, which would otherwise pair with any 32-hex token.
// Only their own names match, since what this removes no pattern reads.
const STAMP = /<!-- rv-gen:(?:escape-helper-v\d+|view-builder-interactive) sha256:[0-9a-f]{64} -->/g;

const ENTITIES = Object.freeze({ amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " });
const codePoint = (n) => (Number.isFinite(n) && n <= 0x10ffff ? String.fromCodePoint(n) : "");

// Zero-width space, non-joiner and joiner, word joiner, zero-width no-break space, soft hyphen.
const INVISIBLE = /[\u{200B}-\u{200D}\u{2060}\u{FEFF}\u{AD}]/gu;

const unescapeOnce = (text) =>
  text
    .normalize("NFKC")
    .replace(INVISIBLE, "")
    .replace(/\\u([0-9a-f]{4})/gi, (_, hex) => String.fromCharCode(Number.parseInt(hex, 16)))
    .replace(/<[^<>]*>/g, "")
    .replace(/&(?:#x([0-9a-f]+)|#(\d+)|(amp|lt|gt|quot|apos|nbsp));/gi, (_, hex, dec, name) =>
      name ? ENTITIES[name.toLowerCase()] : codePoint(hex ? Number.parseInt(hex, 16) : Number.parseInt(dec, 10)),
    );

// The pages host scans a normalized copy beside the raw bytes. The copy here goes further, so a
// split, look-alike, HTML-escaped or JSON-escaped credential or path is caught before upload:
// NFKC, invisible characters stripped, \uXXXX decoded, tags removed and entities decoded until a
// pass changes nothing, then a backslash before punctuation dropped. A backslash before / . " or '
// stays: folding those turns tracked regex sources and escaped JSON into paths, hostnames and
// assignments, which the tracked-tree test in publish-gate.test.mjs refuses.
export const normalize = (text) => {
  let previous;
  let folded = text;
  while (folded !== previous) {
    previous = folded;
    folded = unescapeOnce(folded);
  }
  return folded.replace(/\\([^\sA-Za-z0-9/."'])/g, "$1");
};

const linesOf = (text) => String(text ?? "").split(/\r?\n/).map((line) => line.replace(STAMP, ""));
const firstIn = (patterns, lines, normalized) => {
  for (let i = 0; i < lines.length; i += 1) {
    for (const [label, re] of patterns) if (re.test(lines[i]) || (normalized[i] !== lines[i] && re.test(normalized[i]))) return [label, i + 1];
  }
  return null;
};
const pairs = (lines) => lines.slice(1).map((line, i) => lines[i] + line);

/** The first of `patterns` in `text` or its folded copy, as [label, 1-based line], or null. `fold` stands in for normalize. */
export const firstHit = (patterns, text, fold = normalize) => {
  const lines = linesOf(text);
  return firstIn(patterns, lines, lines.map(fold));
};

/**
 * The first credential-shaped pattern in `text`, as [label, 1-based line], or null. Never the match itself.
 * When no line matches alone, the GATE_JOINABLE patterns read each pair of adjacent lines joined, raw
 * and normalized, and a hit names the pair's first line.
 */
export const findSecret = (text) => {
  const lines = linesOf(text);
  const normalized = lines.map(normalize);
  return firstIn(SECRET_PATTERNS, lines, normalized) ?? firstIn(GATE_JOINABLE, pairs(lines), pairs(normalized));
};

/** The first machine path or hostname in `text`, as [label, 1-based line], or null. Never the match itself. */
export const findMachine = (text) => firstHit(MACHINE_PATTERNS, text);

// ------------------------------------------------------------ leak scan

// The lanes' leak scan: the read runner's scan job runs it on what a run
// leaves, and work-resolve-issue.yml's run-checks job on a reused branch.
// A credential format blocks and asks for rotation. The one broad label, an
// assignment that may be a test fixture (WARN_ONLY, above), only warns, and only on a plain line.
export const HIDDEN = "assignment hidden by markup or escapes";
const BLOCKING = SECRET_PATTERNS.filter(([label]) => label !== WARN_ONLY);
const WARN_PATTERN = SECRET_PATTERNS.find(([label]) => label === WARN_ONLY)?.[1];
const WARN_ONE = WARN_PATTERN && new RegExp(WARN_PATTERN.source, WARN_PATTERN.flags.replace("g", ""));
const WARN_ALL = WARN_PATTERN && new RegExp(WARN_PATTERN.source, `${WARN_PATTERN.flags.replace("g", "")}g`);
// Markup and escapes only. classify reads latin1, so each byte of a UTF-8 character is its own
// code point: findSecret's NFKC and invisible-character passes still run on that text, but on
// code points such as 0xAD, 0xA0 and 0xBD that ordinary UTF-8 continuation bytes produce, so
// counting them here would block a plain assignment on any line of non-ASCII text. A real UTF-8
// look-alike reaches those passes as latin1 code points they leave alone; scanLeak's UTF-8 pass
// is what folds it.
const folds = (line) => /<[^<>]*>|&#?\w+;|\\u[0-9a-f]{4}|\\[^\sA-Za-z0-9/."']/i.test(line);
const credential = (label) => ({ block: label, credential: true });
const blockingIn = (line) => BLOCKING.find(([, re]) => re.test(line))?.[0];

// Each line is judged on its own: every blocking pattern on the raw line,
// then findSecret (which adds the normalized copy). When findSecret names the
// assignment, its matches are blanked and the line read again, and each match
// is read again with its = and : blanked. A line whose assignment sits beside
// markup or escapes normalize() folds, or whose assignment only the folded
// copy shows, blocks under HIDDEN: blanking cannot be trusted there.
const classifyLine = (line) => {
  const raw = blockingIn(line);
  if (raw) return credential(raw);
  const first = findSecret(line);
  if (!first) return {};
  if (first[0] !== WARN_ONLY || !WARN_PATTERN) return credential(first[0]);
  const again = findSecret(line.replace(WARN_ALL, (match) => " ".repeat(match.length)));
  if (again && again[0] !== WARN_ONLY) return credential(again[0]);
  for (const [match] of line.matchAll(WARN_ALL)) {
    const inside = findSecret(match.replace(/[:=]/g, " "));
    if (inside && inside[0] !== WARN_ONLY) return credential(inside[0]);
  }
  if (again || folds(line) || !WARN_ONE.test(line)) return { block: HIDDEN, credential: false };
  return { warn: true };
};

// The secret patterns run line by line on the whole text too, and any credential label from them
// blocks. Lines are not joined here: deeperLeak joins them, raw only, with a diff's hunk prefixes
// removed first.
const classify = (text) => {
  let warn = false;
  for (const line of text.split(/\r?\n/)) {
    const result = classifyLine(line);
    if (result.block) return result;
    warn ||= Boolean(result.warn);
  }
  const whole = firstHit(SECRET_PATTERNS, text);
  if (whole && whole[0] !== WARN_ONLY) return credential(whole[0]);
  return { warn };
};

// Two more passes, on credential formats only (owner ruling Q37):
// - UTF-16LE: the text with its NUL bytes removed, so a token written two
//   bytes a character reads as one; a space in place of each NUL would split it.
// - Split lines: each pair of adjacent lines joined with no separator, counting
//   only a match that straddles the join of a JOINABLE pattern neither line
//   matches alone. In a diff the pair is hunk lines with their +,
//   - or space prefix removed and the file headers dropped, or a token split
//   inside an added hunk would join as "...ab+cd..." and never match.
const JOINABLE_ALL = JOINABLE.map(([label, re]) => [label, re, new RegExp(re.source, `${re.flags.replace("g", "")}g`)]);
const straddles = (left, right) => {
  const joined = left + right;
  for (const [label, re, all] of JOINABLE_ALL) {
    if (re.test(left) || re.test(right)) continue;
    for (const match of joined.matchAll(all)) {
      if (match.index < left.length && match.index + match[0].length > left.length) return label;
    }
  }
  return null;
};
const credentialIn = (text) => {
  for (const line of text.split(/\r?\n/)) {
    const raw = blockingIn(line);
    if (raw) return raw;
  }
  const found = firstHit(SECRET_PATTERNS, text);
  return found && found[0] !== WARN_ONLY ? found[0] : null;
};
const HUNK_HEADER = /^(?:\+\+\+|---) /;
const isHunkLine = (line) => /^[-+ ]/.test(line) && !HUNK_HEADER.test(line);

// JSON writes a line break or tab as \n, \r or \t, which leaves a letter where the break was, so a
// \b-anchored credential right after one has no word boundary. normalize() keeps a backslash
// before a letter (see its comment), so scanLeak reads a copy with these escapes decoded, for the
// credential formats alone.
const BREAK_ESCAPES = Object.freeze({ "\\": "\\", n: "\n", r: "\r", t: "\t" });
const unescapeBreaks = (text) => text.replace(/\\([\\nrt])/g, (_, c) => BREAK_ESCAPES[c]);

/** The UTF-16LE and split-line passes over `text`, a diff when `diff`: a credential label, or null. */
export function deeperLeak(text, diff = false) {
  const plain = text.replace(/\0/g, "");
  if (plain !== text) {
    const label = credentialIn(plain);
    if (label) return label;
  }
  let lines = plain.split(/\r?\n/);
  if (diff) lines = lines.filter(isHunkLine).map((line) => line.slice(1));
  for (let i = 0; i + 1 < lines.length; i += 1) {
    const label = straddles(lines[i], lines[i + 1]);
    if (label) return label;
  }
  return null;
}

// A base64 or base64url run, decoded and read for CREDENTIAL_SHAPES, as gitleaks decodes before
// matching. 36 characters is the shortest run that can hold the shortest shape, the Anthropic key
// (sk-ant- and 20 characters, 27 bytes: 4 * ceil(27 / 3) = 36). Node's base64 decoder reads the
// base64url alphabet too (https://nodejs.org/api/buffer.html#buffers-and-character-encodings).
// Each run decodes at all four offsets, so a stray alphabet character before it (a diff's +, a
// path's /) does not shift every group. Only a decoding at least 90% printable is read or decoded
// again, to ENCODED_DEPTH layers, so image and gzip runs pass. Well-formed UTF-8 (a character cut
// at the end left pending) counts by character, C0 and C1 controls but tab, LF and CR not
// printable, so emoji, accented or CJK text counts; random and compressed bytes are almost never
// well-formed, and those count by byte, printable ASCII only. The first ENCODED_PROBE
// characters (66 bytes) decide that before the rest is decoded, so a binary run costs 66 bytes
// an offset whatever its length. ENCODED_CAP bounds the decoded bytes per call across runs,
// offsets and layers: at most 3 decoded bytes per input character (four offsets of 3/4 each), so
// the 4 MiB cap reads at least 1.4M characters of printable base64 text in full. Past the cap
// nothing is decoded.
// The runs are found by a character loop: a regex over a run of millions of characters overflows
// V8's stack. Padding is left off; the decoder does not need it.
const ENCODED_MIN = 36;
const ENCODED_PROBE = 88;
export const ENCODED_DEPTH = 2;
export const ENCODED_CAP = 1 << 22;
const ALPHABET = new Uint8Array(128);
for (const c of "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_") ALPHABET[c.charCodeAt(0)] = 1;
function* encodedRuns(text) {
  let start = 0;
  for (let i = 0; i <= text.length; i += 1) {
    if (i < text.length && ALPHABET[text.charCodeAt(i)]) continue;
    if (i - start >= ENCODED_MIN) yield text.slice(start, i);
    start = i + 1;
  }
}
const textual = (code) => (code >= 0x20 && code < 0x7f) || code > 0x9f || code === 9 || code === 10 || code === 13;
const printable = (bytes) => {
  let text;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes, { stream: true });
  } catch {
    text = null;
  }
  let count = 0;
  let total = 0;
  if (text) {
    for (const c of text) {
      total += 1;
      if (textual(c.codePointAt(0))) count += 1;
    }
  } else {
    total = bytes.length;
    for (const byte of bytes) if (byte < 0x80 && textual(byte)) count += 1;
  }
  return count >= total * 0.9;
};

/** The first CREDENTIAL_SHAPES label inside a base64 run of `text`, decoded up to `depth` layers within `cap` decoded bytes, or null. */
export function encodedLeak(text, { depth = ENCODED_DEPTH, cap = ENCODED_CAP } = {}) {
  let budget = cap;
  const read = (layer, level) => {
    for (const run of encodedRuns(layer)) {
      for (let offset = 0; offset < 4; offset += 1) {
        if (budget < 3) return null;
        const body = run.slice(offset, offset + Math.floor(budget / 3) * 4);
        if (body.length < ENCODED_MIN) continue;
        let bytes = Buffer.from(body.slice(0, ENCODED_PROBE), "base64");
        if (printable(bytes) && body.length > ENCODED_PROBE) bytes = Buffer.from(body, "base64");
        budget -= bytes.length;
        if (!printable(bytes)) continue;
        const decoded = bytes.toString("latin1");
        const shape = CREDENTIAL_SHAPES.find(([, re]) => re.test(decoded));
        if (shape) return shape[0];
        const deeper = level < depth ? read(decoded, level + 1) : null;
        if (deeper) return deeper;
      }
    }
    return null;
  };
  return read(String(text), 1);
}

/**
 * Every pass over `bytes`: `{block, credential}` naming the first blocking
 * label (credential true when it asks for rotation), `{warn: true}` for a
 * plain assignment alone, else `{}`. Never the match. Latin1 keeps every byte
 * for the byte patterns. A UTF-8 reading then gives NFKC and the invisible
 * strip real characters, for credential formats only, so a look-alike blocks
 * and non-ASCII text beside a plain assignment still only warns. Then that
 * reading with JSON's \n, \r and \t escapes decoded, credential formats only,
 * so a token after an escaped line break or tab blocks. Last, base64 runs
 * decoded (encodedLeak), GitHub and Anthropic shapes only.
 */
export function scanLeak(bytes, { diff = false } = {}) {
  const buffer = Buffer.from(bytes);
  const text = buffer.toString("latin1");
  const { block, credential: format, warn } = classify(text);
  if (block) return { block, credential: format };
  const deep = deeperLeak(text, diff);
  if (deep) return credential(deep);
  const decoded = buffer.toString("utf8");
  const hidden = decoded !== text && firstHit(BLOCKING, decoded);
  if (hidden) return credential(hidden[0]);
  const unbroken = unescapeBreaks(decoded);
  const escaped = unbroken !== decoded && firstHit(BLOCKING, unbroken);
  if (escaped) return credential(escaped[0]);
  const encoded = encodedLeak(text);
  if (encoded) return credential(encoded);
  return warn ? { warn: true } : {};
}

// A blocked hit's fingerprint, for a job summary anyone who reads the repository can read: the
// label, the file and the line, never any character of the match.

/**
 * The 1-based line where scanLeak's `block` label sits in `bytes`, read in
 * scanLeak's order, as `{line}`; line 0 when no pass places it.
 */
export function locateHit(bytes, block, { diff = false } = {}) {
  const patterns = SECRET_PATTERNS.filter(([label]) => label === block).map(([, re]) => re);
  const hits = (...candidates) => candidates.some((candidate) => patterns.some((re) => re.test(candidate)));
  const buffer = Buffer.from(bytes);
  const text = buffer.toString("latin1");
  const at = text.split(/\r?\n/).findIndex((line) => classifyLine(line).block === block);
  if (at >= 0) return { line: at + 1 };
  const plain = text.replace(/\0/g, "");
  const decoded = buffer.toString("utf8");
  for (const view of [text, plain, decoded]) {
    const index = linesOf(view).findIndex((line) => hits(line, normalize(line)));
    if (index >= 0) return { line: index + 1 };
  }
  // Escaped breaks decode within one physical line, so each line is decoded on its own and the
  // hit keeps the line number of the file it was scanned in.
  const escaped = linesOf(decoded).findIndex((line) => linesOf(unescapeBreaks(line)).some((part) => hits(part, normalize(part))));
  if (escaped >= 0) return { line: escaped + 1 };
  let numbered = plain.split(/\r?\n/).map((line, index) => [line, index]);
  if (diff) numbered = numbered.filter(([line]) => isHunkLine(line)).map(([line, index]) => [line.slice(1), index]);
  for (let i = 0; i + 1 < numbered.length; i += 1) {
    if (hits(numbered[i][0] + numbered[i + 1][0])) return { line: numbered[i][1] + 1 };
  }
  const encoded = linesOf(text).findIndex((line) => encodedLeak(line) === block);
  return { line: encoded + 1 };
}

// Model-chosen text as markdown data: every UTF-16 unit outside printable ASCII (controls, C1,
// bidi, line separators, zero-width), and each backtick, pipe, markup character and backslash,
// becomes a \u escape, so a value cannot close its code span, reorder the line or start a command.
const MARKUP = new Set([..."`|<>&\\"]);
const summaryText = (value) =>
  String(value)
    .split("")
    .map((c) => {
      const code = c.charCodeAt(0);
      return code < 0x20 || code > 0x7e || MARKUP.has(c) ? `\\u${code.toString(16).padStart(4, "0")}` : c;
    })
    .join("");

/**
 * One markdown line for a job summary on a block: the rule (scanLeak's
 * label), the path and the line (locateHit), never any of the match. A path
 * that scanLeak blocks or warns on itself is written as `unshown`.
 */
export function hitFingerprint(bytes, block, path, { diff = false, unshown = "a file name" } = {}) {
  const { line } = locateHit(bytes, block, { diff });
  const { block: pathBlock, warn } = scanLeak(Buffer.from(String(path), "utf8"));
  const parts = [`rule \`${summaryText(block)}\``, `path \`${summaryText(pathBlock || warn ? unshown : path)}\``];
  if (line) parts.push(`line ${line}`);
  return `- ${parts.join(", ")}\n`;
}

/**
 * Each file `to` changes from `from`, both tree-ish: its name, then its bytes
 * when it is a regular file or a link (a link's are its target). `git` runs
 * git plumbing in the caller's repository and returns stdout as a Buffer.
 */
export function* changedBytes(git, from, to) {
  const fields = git(["diff-tree", "-r", "-z", "--no-renames", from, to]).toString("latin1").split("\0");
  for (let i = 0; i + 1 < fields.length; i += 2) {
    const [, mode, , sha] = fields[i].replace(/^:/, "").split(" ");
    yield Buffer.from(fields[i + 1], "latin1");
    if (/^(100644|100755|120000)$/.test(mode)) yield git(["cat-file", "blob", sha]);
  }
}

// "private" is who sees a new artifact before anyone shares it:
// https://code.claude.com/docs/en/artifacts#share-an-artifact (as of 2026-10-11;
// recheck when that section makes a new artifact visible to anyone but its author).
export const DESTINATION = "a private Artifact on claude.ai";
export const OPT_IN = "set medium: artifact in the plugin's medium option to publish anyway";
export const VISIBILITIES = Object.freeze(["PUBLIC", "PRIVATE", "INTERNAL", "UNKNOWN", "NONE"]);

/**
 * Where an `artifact` view actually goes. `visibility` is the source repository's
 * (`gh repo view --json visibility`), `NONE` when the view draws on no repository,
 * and anything unrecognized is treated as not PUBLIC.
 * A `hosted` medium returns `{medium: "hosted", destination: "public"|"private", reason}`,
 * or `medium: "file"` when a credential refuses the host; `explicit` skips nothing there.
 * @param {{explicit: boolean, visibility: string, text: string, subject?: string, medium?: string, requested?: string}} input
 */
export function publishGate({ explicit, visibility, text, subject = "content", medium = "artifact", requested = "public" }) {
  if (medium === "hosted") return hostedGate({ visibility, text, subject, requested });
  if (explicit) return { medium: "artifact", destination: DESTINATION, reason: "a layer sets medium: artifact" };
  const closed = notPublic(visibility);
  if (closed) return { medium: "file", reason: closed, opt_in: OPT_IN };
  const secret = findSecret(text);
  if (secret) return { medium: "file", reason: `${subject} line ${secret[1]} looks like a ${secret[0]}`, opt_in: OPT_IN };
  return { medium: "artifact", destination: DESTINATION, reason: `${sourceOf(visibility)} and nothing credential-shaped in the ${subject}` };
}

const notPublic = (visibility) =>
  visibility === "PUBLIC" || visibility === "NONE" ? null : `repository visibility is ${visibility || "unknown"}, not PUBLIC`;
const sourceOf = (visibility) => (visibility === "NONE" ? "no repository source" : "public repository");

function hostedGate({ visibility, text, subject, requested }) {
  const secret = findSecret(text);
  if (secret) return { medium: "file", reason: `${subject} line ${secret[1]} looks like a ${secret[0]}; a hosted page is refused` };
  const to = (destination, reason) => ({ medium: "hosted", destination, reason });
  if (requested !== "public") return to("private", "the private host was requested");
  const closed = notPublic(visibility);
  if (closed) return to("private", closed);
  const machine = findMachine(text);
  if (machine) return to("private", `${subject} line ${machine[1]} names a ${machine[0]}`);
  return to("public", `${sourceOf(visibility)} and nothing credential-, path- or host-shaped in the ${subject}`);
}

/** CLI: the argument vector after the script path; returns the exit code. */
export function main(argv, input = () => readFileSync(0, "utf8")) {
  const [visibility, ...rest] = argv;
  if (!visibility || visibility.startsWith("--")) return usage();
  const opts = { explicit: false, subject: "content", medium: "artifact", requested: "public" };
  let requested = false;
  for (let i = 0; i < rest.length; i += 1) {
    const next = rest[i + 1] ?? "";
    if (rest[i] === "--explicit") opts.explicit = true;
    else if (rest[i] === "--subject" && /^[a-z]{1,20}$/.test(next)) opts.subject = rest[++i];
    else if (rest[i] === "--medium" && next === "hosted") opts.medium = rest[++i];
    else if (rest[i] === "--visibility" && ["public", "private"].includes(next)) [opts.requested, requested] = [rest[++i], true];
    else return usage();
  }
  if (requested && opts.medium !== "hosted") return usage();
  const result = publishGate({ ...opts, visibility: visibility.toUpperCase(), text: input() });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return 0;
}

function usage() {
  process.stderr.write(
    "usage: publish-gate.mjs <PUBLIC|PRIVATE|INTERNAL|UNKNOWN|NONE> [--explicit] [--subject <word>] [--medium hosted [--visibility public|private]] < text\n",
  );
  return 2;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
