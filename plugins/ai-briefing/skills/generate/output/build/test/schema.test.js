import assert from "node:assert/strict";
import test from "node:test";
import { validateDeck } from "../lib/schema.js";

const HEX = "112233";
const theme = {
	bg: HEX, bgAccent: HEX, bgCard: HEX,
	brandIndigo: HEX, brandRed: HEX,
	accent: HEX, accent2: HEX, accent3: HEX,
	text: HEX, textMuted: HEX, divider: HEX,
	pptFontHead: "Arial", pptFontBody: "Arial",
	htmlFontHead: "Arial", htmlFontBody: "Arial",
};

const meta = {
	meetingNumber: 1, org: "Org", tagline: "t",
	date: "2026-01-01", window: "w", logoColor: "", logoWhite: "",
};

const titleSlide = {
	type: "title", eyebrow: "e", title: "t", subtitle: "s", footer: "f",
};

// A valid 10-slide deck whose single news bullet carries `url`. The Url refine is
// the only thing under test, so everything else is held constant and valid.
function makeDeck(url) {
	const newsSlide = {
		type: "news",
		provider: null,
		title: "News",
		bullets: [{ title: "Item", body: "body", urls: [url] }],
	};
	return {
		meta,
		theme,
		providerLogos: {},
		slides: [newsSlide, ...Array.from({ length: 9 }, () => ({ ...titleSlide }))],
	};
}

test("validateDeck accepts benign source-URL schemes", () => {
	for (const url of [
		"https://example.com/a",
		"http://example.com/a",
		"mailto:person@example.com",
		"tel:+15551234567",
	]) {
		assert.doesNotThrow(() => validateDeck(makeDeck(url)), url);
	}
});

test("validateDeck rejects the whole deck on a dangerous or unlisted scheme", () => {
	for (const url of [
		"javascript:alert(1)",
		"data:text/html,<script>alert(1)</script>",
		"file:///etc/passwd",
		"ftp://example.com/x",
	]) {
		assert.throws(() => validateDeck(makeDeck(url)), /schema violation/, url);
	}
});
