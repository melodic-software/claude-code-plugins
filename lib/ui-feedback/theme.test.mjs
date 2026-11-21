import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const HOST = readFileSync(new URL("./host.html", import.meta.url), "utf8");
const FRAME = readFileSync(new URL("./proto-pin.js", import.meta.url), "utf8");
const SWITCHER = readFileSync(new URL("../../plugins/prototype/skills/explore-directions/assets/variant-switcher.html", import.meta.url), "utf8");

/** The `--uif-*` tokens a stylesheet declares, light (outside any media query) and dark (inside prefers-color-scheme: dark). */
function tokens(text) {
  const css = text.slice(text.indexOf("<style>"), text.indexOf("</style>"));
  const darkAt = css.indexOf("@media (prefers-color-scheme: dark)");
  assert.ok(darkAt > 0, "a dark block follows the light tokens");
  const read = (part) => Object.fromEntries([...part.matchAll(/(--uif-[a-z0-9-]+):\s*(#[0-9a-f]{6})/g)].map((m) => [m[1], m[2]]));
  const end = css.indexOf("}\n", css.indexOf("{", css.indexOf("{", darkAt) + 1));
  return { light: read(css.slice(0, darkAt)), dark: read(css.slice(darkAt, end)) };
}

// WCAG 2.2 relative luminance and contrast ratio (https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio).
const lin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const lum = (hex) => [1, 3, 5].map((i) => lin(parseInt(hex.slice(i, i + 2), 16) / 255)).reduce((s, c, i) => s + c * [0.2126, 0.7152, 0.0722][i], 0);
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

const TEXT = [["ink", "surface"], ["ink-2", "surface"], ["ink-2", "sunk"], ["ink", "sunk"], ["on-accent", "accent"],
  ["accent-text", "surface"], ["accent-text", "accent-soft"], ["draft", "surface"], ["ok", "surface"]];
const NON_TEXT = [["line-strong", "surface"], ["accent", "surface"], ["accent", "accent-soft"]];

const host = tokens(HOST);

for (const scheme of ["light", "dark"]) {
  test(`every text pair in the ${scheme} scheme meets WCAG 2.2 AA 4.5:1`, () => {
    for (const [fg, bg] of TEXT) {
      const r = ratio(host[scheme][`--uif-${fg}`], host[scheme][`--uif-${bg}`]);
      assert.ok(r >= 4.5, `${fg} on ${bg}: ${r.toFixed(2)}`);
    }
  });
  test(`every non-text pair in the ${scheme} scheme meets 3:1`, () => {
    for (const [fg, bg] of NON_TEXT) {
      const r = ratio(host[scheme][`--uif-${fg}`], host[scheme][`--uif-${bg}`]);
      assert.ok(r >= 3, `${fg} on ${bg}: ${r.toFixed(2)}`);
    }
  });
}

test("the host page declares the same tokens in both schemes", () => {
  assert.ok(Object.keys(host.light).length >= 12);
  assert.deepEqual(Object.keys(host.dark).sort(), Object.keys(host.light).sort());
});

test("the variant switcher takes each token it declares from the host page's set, in both schemes", () => {
  const own = tokens(SWITCHER);
  assert.ok(Object.keys(own.light).length > 0);
  for (const scheme of ["light", "dark"]) {
    for (const [k, v] of Object.entries(own[scheme])) assert.equal(v, host[scheme][k], `${scheme} ${k}`);
  }
});

test("the markers the frame helper draws use the host page's accent in both schemes", () => {
  for (const scheme of ["light", "dark"]) {
    for (const k of ["--uif-accent", "--uif-on-accent", "--uif-surface"]) assert.ok(FRAME.includes(`"${host[scheme][k]}"`), `${scheme} ${k}`);
  }
});
