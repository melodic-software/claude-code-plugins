import { describe, expect, it } from "vitest";

import { filterGitHubUrls } from "./analyze-harvested-repos.js";

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
