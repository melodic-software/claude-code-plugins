import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
	analyzeHarvestedRepos,
	filterGitHubUrls,
	sanitizePathSegment,
	shallowCloneGitHubRepo,
} from "./analyze-harvested-repos.js";

describe("filterGitHubUrls", () => {
	it("should keep unique GitHub URLs only", () => {
		const links = [
			{ url: "https://github.com/org/repo" },
			{ url: "https://example.com/spec" },
			{ url: "https://github.com/org/repo.git" },
		];
		expect(filterGitHubUrls(links)).toEqual([
			"https://github.com/org/repo",
			"https://github.com/org/repo.git",
		]);
	});
});

describe("sanitizePathSegment", () => {
	it("replaces Windows-reserved and path-breaking chars with underscores", () => {
		expect(sanitizePathSegment('a:b*c?d"e<f>g|h')).toBe("a_b_c_d_e_f_g_h");
	});

	it("preserves word chars, dots, and hyphens", () => {
		expect(sanitizePathSegment("Org-Name.v2")).toBe("Org-Name.v2");
	});
});

describe("shallowCloneGitHubRepo", () => {
	it("terminates git option parsing before repository and destination arguments", async () => {
		let capturedArgs;
		const spawnFn = (_command, args) => {
			capturedArgs = args;
			return {
				on(event, callback) {
					if (event === "close") callback(0);
				},
			};
		};

		await expect(
			shallowCloneGitHubRepo(
				"https://github.com/owner/repo",
				"-destination",
				spawnFn,
			),
		).resolves.toBe(true);
		expect(capturedArgs).toEqual([
			"clone",
			"--depth",
			"1",
			"--single-branch",
			"--",
			"https://github.com/owner/repo",
			"-destination",
		]);
	});
});

describe("analyzeHarvestedRepos clone target", () => {
	/** @type {string} */
	let sliceDir;

	beforeEach(() => {
		sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "harvested-repos-test-"));
		fs.mkdirSync(path.join(sliceDir, "source"), { recursive: true });
	});

	afterEach(() => {
		fs.rmSync(sliceDir, { recursive: true, force: true });
	});

	it("clones the canonical repo URL built from parsed parts, not the harvested deep link", async () => {
		fs.writeFileSync(
			path.join(sliceDir, "source", "harvested-links.json"),
			JSON.stringify([
				{
					url: "https://github.com/melodic-software/medley/blob/main/README.md",
				},
			]),
		);

		/** @type {string[]} */
		const clonedUrls = [];
		await analyzeHarvestedRepos(sliceDir, {
			clone: async (url) => {
				clonedUrls.push(url);
				return false; // skip structure detection; only the clone target matters here
			},
		});

		expect(clonedUrls).toEqual(["https://github.com/melodic-software/medley"]);
	});
});
