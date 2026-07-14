const VTT_TIMESTAMP_RANGE =
	/(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})/;
const WHITESPACE_RUN = /\s+/g;
const SENTENCE_ENDING = /[.?!]$/;
const MIN_CUE_JOIN_OVERLAP_WORDS = 3;
const MAX_CUE_JOIN_OVERLAP_WORDS = 24;

/**
 * WebVTT segment parser and deduplicator for HLS subtitle streams.
 *
 * HLS subtitle tracks are delivered as chunked .webvtt files (~6s each).
 * Adjacent segments overlap — the same cue may appear in multiple segments
 * for smooth playback. This module:
 *
 *   1. Parses WebVTT cues from raw segment text
 *   2. Deduplicates across overlapping segments
 *   3. Formats as timestamped transcript text matching the [M:SS] format
 *
 * Provider-agnostic — usable by any adapter that receives HLS WebVTT segments.
 */

/**
 * @typedef {Object} VttCue
 * @property {number} startSec - start time in seconds
 * @property {number} endSec - end time in seconds
 * @property {string} text - cue text (may span multiple lines, joined with space)
 */

/**
 * Parse a WebVTT timestamp to total seconds.
 * Handles both HH:MM:SS.mmm and MM:SS.mmm formats.
 * @param {string} ts - "00:01:23.456" or "01:23.456"
 * @returns {number}
 */
export function vttTimestampToSeconds(ts) {
	const parts = ts.split(":");
	if (parts.length === 3) {
		return (
			Number.parseInt(parts[0], 10) * 3600 +
			Number.parseInt(parts[1], 10) * 60 +
			Number.parseFloat(parts[2])
		);
	}
	return Number.parseInt(parts[0], 10) * 60 + Number.parseFloat(parts[1]);
}

/**
 * Format seconds as M:SS timestamp.
 * @param {number} seconds
 * @returns {string}
 */
export function formatTimestamp(seconds) {
	const mins = Math.floor(seconds / 60);
	const secs = Math.floor(seconds % 60);
	return `${mins}:${String(secs).padStart(2, "0")}`;
}

/**
 * Remove WebVTT cue tags in one left-to-right pass.
 *
 * A state machine avoids both repeated regex rescans on unterminated tags and
 * the possibility that removing an inner fragment creates a new tag.
 * @param {string} text
 * @returns {string}
 */
export function stripVttInlineTags(text) {
	let result = "";
	let inTag = false;
	for (const character of text) {
		if (character === "<") {
			inTag = true;
		} else if (character === ">" && inTag) {
			inTag = false;
		} else if (!inTag) {
			result += character;
		}
	}
	return result;
}

/**
 * Parse a single WebVTT segment into an array of cues.
 * Skips the WEBVTT header, X-TIMESTAMP-MAP, and NOTE blocks.
 *
 * @param {string} vttText - raw WebVTT segment content
 * @returns {VttCue[]}
 */
export function parseVttSegment(vttText) {
	const cues = [];
	const lines = vttText.split("\n");
	let i = 0;

	while (i < lines.length) {
		const line = lines[i].trim();

		const match = line.match(VTT_TIMESTAMP_RANGE);
		if (match?.[1] && match[2]) {
			const startSec = vttTimestampToSeconds(match[1]);
			const endSec = vttTimestampToSeconds(match[2]);
			/** @type {string[]} */
			const textLines = [];
			i++;
			while (
				i < lines.length &&
				lines[i].trim() !== "" &&
				!lines[i].includes("-->")
			) {
				const cleaned = stripVttInlineTags(lines[i].trim());
				// Skip consecutive duplicate lines (Hotmart VTT repeats each line
				// for display carry-forward — joining both doubles the text)
				if (cleaned && cleaned !== textLines[textLines.length - 1]) {
					textLines.push(cleaned);
				}
				i++;
			}
			if (textLines.length > 0) {
				cues.push({ startSec, endSec, text: textLines.join(" ") });
			}
		} else {
			i++;
		}
	}
	return cues;
}

/**
 * Deduplicate cues from multiple overlapping HLS segments.
 *
 * HLS subtitle segments overlap by design — each ~6s segment includes
 * adjacent cues for smooth playback transitions. The same cue appears
 * in multiple segments with identical timestamps and text.
 *
 * Dedup strategy:
 *   - Key: rounded start time (to 0.1s) + normalized text
 *   - Normalized text: lowercased, whitespace-collapsed, trimmed
 *   - First occurrence wins (segments should be fed in order)
 *
 * @param {VttCue[]} cues - all cues from all segments (unsorted OK)
 * @returns {VttCue[]} deduplicated, sorted by start time
 */
export function deduplicateCues(cues) {
	const seen = new Set();
	const unique = [];

	for (const cue of cues) {
		// Round to 0.1s to handle floating-point drift across segments
		const roundedStart = Math.round(cue.startSec * 10) / 10;
		const normalizedText = cue.text
			.toLowerCase()
			.replace(WHITESPACE_RUN, " ")
			.trim();
		const key = `${roundedStart}|${normalizedText}`;

		if (!seen.has(key)) {
			seen.add(key);
			unique.push(cue);
		}
	}

	return unique.sort((a, b) => a.startSec - b.startSec);
}

/**
 * Join adjacent cue text, stripping shared suffix/prefix word runs (rolling captions).
 *
 * @param {string} previous
 * @param {string} next
 * @returns {string}
 */
export function mergeAdjacentCueText(previous, next) {
	if (!previous) return next;
	if (!next) return previous;

	const prevWords = previous.split(WHITESPACE_RUN).filter(Boolean);
	const nextWords = next.split(WHITESPACE_RUN).filter(Boolean);
	const maxOverlap = Math.min(
		prevWords.length,
		nextWords.length,
		MAX_CUE_JOIN_OVERLAP_WORDS,
	);

	for (let len = maxOverlap; len >= MIN_CUE_JOIN_OVERLAP_WORDS; len--) {
		const suffix = prevWords.slice(-len).join(" ").toLowerCase();
		const prefix = nextWords.slice(0, len).join(" ").toLowerCase();
		if (suffix === prefix) {
			return [...prevWords, ...nextWords.slice(len)].join(" ");
		}
	}

	return `${previous} ${next}`;
}

/**
 * Format deduplicated cues into transcript paragraphs with timestamps.
 *
 * Groups cues into paragraphs based on natural sentence boundaries
 * (periods, question marks, exclamation marks) or time gaps (>30s).
 * Output format: "[M:SS] paragraph text"
 *
 * @param {VttCue[]} cues - deduplicated, sorted by start time
 * @returns {string} formatted transcript text (paragraphs separated by \n\n)
 */
export function formatTranscript(cues) {
	if (cues.length === 0) return "";

	const paragraphs = [];
	let currentParagraphText = "";
	let paragraphStart = cues[0].startSec;
	let cuesInParagraph = 0;

	for (const cue of cues) {
		if (currentParagraphText && cue.startSec - paragraphStart > 30) {
			paragraphs.push(
				`[${formatTimestamp(paragraphStart)}] ${currentParagraphText}`,
			);
			currentParagraphText = "";
			cuesInParagraph = 0;
			paragraphStart = cue.startSec;
		}

		if (!currentParagraphText) {
			paragraphStart = cue.startSec;
			currentParagraphText = cue.text;
			cuesInParagraph = 1;
		} else {
			currentParagraphText = mergeAdjacentCueText(
				currentParagraphText,
				cue.text,
			);
			cuesInParagraph++;
		}

		if (SENTENCE_ENDING.test(cue.text) && cuesInParagraph >= 2) {
			paragraphs.push(
				`[${formatTimestamp(paragraphStart)}] ${currentParagraphText}`,
			);
			currentParagraphText = "";
			cuesInParagraph = 0;
		}
	}

	if (currentParagraphText) {
		paragraphs.push(
			`[${formatTimestamp(paragraphStart)}] ${currentParagraphText}`,
		);
	}

	return paragraphs.join("\n\n");
}

/**
 * Parse an HLS subtitle manifest (.m3u8) to extract segment filenames.
 *
 * @param {string} manifestBody - raw m3u8 manifest content
 * @returns {string[]} segment filenames (including query params with auth tokens)
 */
export function parseSubtitleManifest(manifestBody) {
	return manifestBody
		.split("\n")
		.filter((line) => {
			const trimmed = line.trim();
			return trimmed && !trimmed.startsWith("#") && trimmed.includes(".webvtt");
		})
		.map((line) => line.trim());
}

/**
 * Full pipeline: parse segments, deduplicate, format.
 *
 * @param {string[]} segmentBodies - raw WebVTT text for each segment
 * @returns {{ transcript: string, cueCount: number, paragraphCount: number }}
 */
export function processSubtitleSegments(segmentBodies) {
	const allCues = segmentBodies.flatMap(parseVttSegment);
	const unique = deduplicateCues(allCues);
	const transcript = formatTranscript(unique);
	const paragraphCount = transcript ? transcript.split("\n\n").length : 0;

	return { transcript, cueCount: unique.length, paragraphCount };
}
