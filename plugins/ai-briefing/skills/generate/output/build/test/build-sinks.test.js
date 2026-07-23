import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import JSZip from "jszip";

import { buildSections } from "../build-sections.js";

const BUILD_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const theme = {
	bg: "0B1020", bgAccent: "141A2E", bgCard: "1C2440",
	brandIndigo: "3F3E87", brandRed: "E23B3B",
	accent: "80BEFF", accent2: "FFB901", accent3: "80FFC0",
	text: "FFFFFF", textMuted: "9AA3B2", divider: "2A3350",
	pptFontHead: "Arial", pptFontBody: "Arial",
	htmlFontHead: "Arial", htmlFontBody: "Arial",
};

test("HTML news sink drops a javascript: href and keeps a safe https href", () => {
	const newsSlide = {
		type: "news",
		provider: "openai",
		tier: "high",
		title: "OpenAI",
		bullets: [
			{
				title: "Launch",
				body: "detail",
				urls: ["https://safe.example/keep", "javascript:alert(1)"],
			},
		],
		section: "openai",
	};
	const { sectionsHtml } = buildSections({
		slides: [newsSlide],
		meta: { meetingNumber: 1, date: "2026-01-01" },
		logoWhiteData: "",
		providerLogoSvg: {},
	});

	assert.ok(
		sectionsHtml.includes('href="https://safe.example/keep"'),
		"safe https href must be rendered",
	);
	assert.ok(
		!sectionsHtml.includes("javascript:alert"),
		"javascript: href must be dropped",
	);
});

// Drives the real build-pptx.js entrypoint against a fixture slides-data.js so the
// buildNews/buildCondensed hyperlink sinks are exercised end-to-end, then reads the
// emitted deck's external hyperlink relationships to confirm the filtering.
test("PPTX news/condensed sinks drop file:// hyperlinks and keep safe ones", async () => {
	const safeNews = "https://safe.example/keep-news";
	const safeCondensed = "https://safe.example/keep-condensed";
	const evilNews = "file:///etc/passwd";
	const evilCondensed = "file:///etc/shadow";

	const stateRoot = fs.mkdtempSync(path.join(os.tmpdir(), "pptx-sink-"));
	try {
		const dataDir = path.join(stateRoot, "default", "output", "build");
		fs.mkdirSync(dataDir, { recursive: true });

		const slides = [
			{
				type: "news", provider: "openai", tier: "high", title: "News",
				subtitle: "s",
				bullets: [{ title: "N", body: "x", urls: [safeNews, evilNews] }],
				section: "openai",
			},
			{
				type: "condensed", provider: "openai", tier: "low", title: "Condensed",
				subtitle: "s",
				bullets: [{ title: "C", body: "y", urls: [safeCondensed, evilCondensed] }],
				section: "openai",
			},
		];
		const fixture =
			`export const meta = ${JSON.stringify({ meetingNumber: 99, org: "T", tagline: "t", date: "2026-01-01", window: "w", logoColor: "", logoWhite: "" })};\n` +
			`export const theme = ${JSON.stringify(theme)};\n` +
			`export const providerLogos = {};\n` +
			`export const slides = ${JSON.stringify(slides)};\n`;
		fs.writeFileSync(path.join(dataDir, "slides-data.js"), fixture);

		const r = spawnSync(process.execPath, [path.join(BUILD_DIR, "build-pptx.js")], {
			cwd: BUILD_DIR,
			env: { ...process.env, CLAUDE_PLUGIN_DATA: stateRoot },
			encoding: "utf8",
		});
		assert.equal(r.status, 0, `build-pptx.js failed: ${r.stderr || r.stdout}`);

		const pptxPath = path.join(stateRoot, "default", "output", "meetings", "ai-meeting-99.pptx");
		const zip = await JSZip.loadAsync(fs.readFileSync(pptxPath));
		const relNames = Object.keys(zip.files).filter((n) =>
			/ppt\/slides\/_rels\/slide\d+\.xml\.rels$/.test(n),
		);
		const targets = [];
		for (const n of relNames) {
			const xml = await zip.file(n).async("string");
			for (const m of xml.matchAll(/Target="([^"]+)"\s+TargetMode="External"/g)) {
				targets.push(m[1]);
			}
		}

		assert.ok(targets.includes(safeNews), "safe news hyperlink must survive");
		assert.ok(targets.includes(safeCondensed), "safe condensed hyperlink must survive");
		assert.ok(!targets.includes(evilNews), "file:// news hyperlink must be dropped");
		assert.ok(!targets.includes(evilCondensed), "file:// condensed hyperlink must be dropped");
	} finally {
		fs.rmSync(stateRoot, { recursive: true, force: true });
	}
});
