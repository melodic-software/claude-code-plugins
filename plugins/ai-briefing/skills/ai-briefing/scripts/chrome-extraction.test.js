// Test chrome extractor schema + parseAbbreviated helper + slimForPrompt (S3 view).
//
// Run: node scripts/chrome-extraction.test.js
//
// Covers:
//   - parseAbbreviated edge cases (abbreviations, commas, aria-label form, garbage, null)
//   - TweetSchema accepts the full shape (all optional fields populated)
//   - Partial shapes (only metrics, only card, etc.) validate
//   - CHUNK_SIZE locked at 2 for current byte budget
//   - slimForPrompt drops bloat fields, keeps essentials

import { strict as assert } from "node:assert";

import { CHUNK_SIZE, parseAbbreviated, validateExtractorOutput } from "./lib/chrome-extract.js";
import { slimForPrompt } from "./lib/synthesize-agent.js";
import { writelnStdout } from "./lib/terminal.js";

let passed = 0;
let failed = 0;
const test = (name, fn) => {
  try {
    fn();
    writelnStdout(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    writelnStdout(`  ✗ ${name}\n    ${e.message}`);
    failed++;
  }
};

writelnStdout("parseAbbreviated:");
test('"1.2K" → 1200', () => assert.equal(parseAbbreviated("1.2K"), 1200));
test('"12.4K" → 12400', () => assert.equal(parseAbbreviated("12.4K"), 12400));
test('"1.2M" → 1200000', () => assert.equal(parseAbbreviated("1.2M"), 1200000));
test('"1.5B" → 1500000000', () => assert.equal(parseAbbreviated("1.5B"), 1500000000));
test('"1,234" → 1234', () => assert.equal(parseAbbreviated("1,234"), 1234));
test('"0" → 0', () => assert.equal(parseAbbreviated("0"), 0));
test('"" → null', () => assert.equal(parseAbbreviated(""), null));
test("null → null", () => assert.equal(parseAbbreviated(null), null));
test("undefined → null", () => assert.equal(parseAbbreviated(undefined), null));
test('"1,234 likes" → 1234 (aria-label form)', () =>
  assert.equal(parseAbbreviated("1,234 likes"), 1234));
test('"abc" → null (garbage)', () => assert.equal(parseAbbreviated("abc"), null));
test('lowercase "1.2k" → 1200 (case-insensitive)', () =>
  assert.equal(parseAbbreviated("1.2k"), 1200));

writelnStdout("\nTweetSchema:");
test("full tweet shape validates", () => {
  const out = validateExtractorOutput({
    a: "@AnthropicAI",
    n: 1,
    tw: [
      {
        t: "shipping new feature",
        u: "https://x.com/a/status/1",
        d: "2026-05-08T00:00:00Z",
        external_links: [{ href: "https://anthropic.com/news", text: "anthropic.com/news…" }],
        card: {
          url: "https://anthropic.com/news",
          title: "New feature",
          domain: "anthropic.com",
          image: "https://example.com/img.png",
        },
        quoted_tweet: {
          handle: "@b",
          text: "original announcement",
          url: "https://x.com/b/status/2",
        },
        metrics: { likes: 1234, reposts: 56, replies: 12 },
      },
    ],
  });
  assert.equal(out.tw[0].metrics.likes, 1234);
  assert.equal(out.tw[0].external_links[0].href, "https://anthropic.com/news");
  assert.equal(out.tw[0].card.domain, "anthropic.com");
  assert.equal(out.tw[0].quoted_tweet.handle, "@b");
});

test("tweet with only metrics validates", () => {
  validateExtractorOutput({
    a: "@x",
    n: 1,
    tw: [
      {
        t: "a",
        u: "b",
        d: "c",
        metrics: { likes: 5, reposts: null, replies: null },
      },
    ],
  });
});

test("tweet with only card validates", () => {
  validateExtractorOutput({
    a: "@x",
    n: 1,
    tw: [
      {
        t: "a",
        u: "b",
        d: "c",
        card: { url: "https://example.com" },
      },
    ],
  });
});

writelnStdout("\nCHUNK_SIZE:");
test("CHUNK_SIZE === 2", () => assert.equal(CHUNK_SIZE, 2));

writelnStdout("\nslimForPrompt (S3 view):");
test("minimal tweet round-trips unchanged", () => {
  const out = slimForPrompt({ t: "hi", u: "u", d: "d" });
  assert.deepEqual(out, { t: "hi", u: "u", d: "d" });
});

test("external_links → top 1 href only", () => {
  const out = slimForPrompt({
    t: "hi",
    u: "u",
    d: "d",
    external_links: [
      { href: "https://a.com", text: "a.com…" },
      { href: "https://b.com", text: "b.com…" },
    ],
  });
  assert.deepEqual(out.links, ["https://a.com"]);
});

test("card → {url, title trunc 60} only", () => {
  const longTitle = "x".repeat(80);
  const out = slimForPrompt({
    t: "hi",
    u: "u",
    d: "d",
    card: {
      url: "https://example.com",
      title: longTitle,
      domain: "example.com",
      image: "https://example.com/img.png",
    },
  });
  assert.equal(out.card.url, "https://example.com");
  assert.equal(out.card.title.length, 60);
  // domain + image dropped
  assert.equal(out.card.domain, undefined);
  assert.equal(out.card.image, undefined);
});

test('metrics → packed "L/R/Re" string', () => {
  const out = slimForPrompt({
    t: "hi",
    u: "u",
    d: "d",
    metrics: { likes: 1234, reposts: 56, replies: 12 },
  });
  assert.equal(out.m, "1234/56/12");
});

test('metrics with nulls → "1234/-/12"', () => {
  const out = slimForPrompt({
    t: "hi",
    u: "u",
    d: "d",
    metrics: { likes: 1234, reposts: null, replies: 12 },
  });
  assert.equal(out.m, "1234/-/12");
});

test("quoted_tweet INTENTIONALLY OMITTED from S3 view (budget)", () => {
  const out = slimForPrompt({
    t: "hi",
    u: "u",
    d: "d",
    quoted_tweet: { handle: "@x", text: "quoted", url: "https://x.com/x/status/1" },
  });
  assert.equal(out.quoted_tweet, undefined);
});

writelnStdout(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
