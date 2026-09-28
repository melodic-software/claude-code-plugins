import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { parseGitHubUrl } from "./repo-analysis.js";

describe("parseGitHubUrl", () => {
  const accepted = [
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
  ];
  for (const [url, expected] of accepted) {
    it(`accepts an exact GitHub URL: ${url}`, () => {
      assert.deepEqual(parseGitHubUrl(url), expected);
    });
  }

  const rejected = [
    "https://github.com.example/owner/repo",
    "https://example.com/github.com/owner/repo",
    "https://user@github.com/owner/repo",
    "http://github.com/owner/repo",
    "--upload-pack=malicious",
    "git@github.com.evil:owner/repo",
  ];
  for (const url of rejected) {
    it(`rejects a host or option spoof: ${url}`, () => {
      assert.equal(parseGitHubUrl(url), null);
    });
  }
});
