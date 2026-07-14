import { describe, expect, it } from "vitest";

import { parseGitHubUrl } from "./repo-analysis.js";

describe("parseGitHubUrl", () => {
	it.each([
		[
			"https://github.com/melodic-software/medley",
			{ owner: "melodic-software", repo: "medley" },
		],
		[
			"https://github.com/melodic-software/medley.git",
			{ owner: "melodic-software", repo: "medley" },
		],
		[
			"https://github.com/melodic-software/medley/blob/main/README.md",
			{ owner: "melodic-software", repo: "medley" },
		],
		[
			"git@github.com:melodic-software/medley.git",
			{ owner: "melodic-software", repo: "medley" },
		],
	])("accepts an exact GitHub URL: %s", (url, expected) => {
		expect(parseGitHubUrl(url)).toEqual(expected);
	});

	it.each([
		"https://github.com.example/owner/repo",
		"https://example.com/github.com/owner/repo",
		"https://user@github.com/owner/repo",
		"http://github.com/owner/repo",
		"--upload-pack=malicious",
		"git@github.com.evil:owner/repo",
	])("rejects a host or option spoof: %s", (url) => {
		expect(parseGitHubUrl(url)).toBeNull();
	});
});
