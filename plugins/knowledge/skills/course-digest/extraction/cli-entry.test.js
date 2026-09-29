import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { describe, expect, it } from "vitest";

const dir = path.dirname(new URL(import.meta.url).pathname);
const entrypoints = [
  "analyze-code-repo.js",
  "build-course-json.js",
  "discover-resources.js",
  "download-resources.js",
  "extract-course.js",
  "validate-extraction.js",
];

function run(script, args = []) {
  return spawnSync(process.execPath, [path.join(dir, script), ...args], {
    encoding: "utf8",
    timeout: 20000,
  });
}

function courseFixture(extra = {}) {
  const root = mkdtempSync(path.join(tmpdir(), "cli-course-"));
  writeFileSync(
    path.join(root, "course.json"),
    JSON.stringify({
      title: "CLI Course",
      instructor: "Ada",
      platform: "teachable",
      duration: "1h 0m",
      totalLessons: 0,
      status: "pending",
      modules: [],
      ...extra,
    }),
  );
  return root;
}

describe("CLI entrypoints do not run on import", () => {
  for (const file of entrypoints) {
    it(`imports ${file} with no output and no exit`, () => {
      const href = pathToFileURL(path.join(dir, file)).href;
      const result = spawnSync(
        process.execPath,
        ["--input-type=module", "-e", `await import(${JSON.stringify(href)})`],
        { encoding: "utf8", timeout: 20000 },
      );
      expect(result.status).toBe(0);
      expect(result.stdout).toBe("");
      expect(result.stderr).toBe("");
    });
  }
});

describe("build-course-json argv", () => {
  it("prints usage and exits 1 when an argument is missing", () => {
    const result = run("build-course-json.js");
    expect(result.status).toBe(1);
    expect(result.stderr).toContain(
      "Usage: node build-course-json.js --course-url <url> --output-dir <path>",
    );
  });

  it("exits 1 when only one of the two arguments is present", () => {
    const result = run("build-course-json.js", ["--course-url", "https://example.test/courses/enrolled/1"]);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("Usage:");
  });

  it("creates the output directory from argv before the browser step", () => {
    const out = mkdtempSync(path.join(tmpdir(), "cli-out-"));
    const dest = path.join(out, "course");
    const result = run("build-course-json.js", [
      "--course-url",
      "https://example.test/courses/enrolled/2518872",
      "--output-dir",
      dest,
    ]);
    expect(result.status).not.toBe(0);
    expect(existsSync(dest)).toBe(true);
    expect(existsSync(path.join(dest, "course.json"))).toBe(false);
  });
});

describe("course-dir CLIs", () => {
  for (const script of [
    "analyze-code-repo.js",
    "discover-resources.js",
    "download-resources.js",
    "extract-course.js",
    "validate-extraction.js",
  ]) {
    it(`${script} exits 1 when --course-dir is missing`, () => {
      const result = run(script);
      expect(result.status).toBe(1);
      expect(`${result.stdout}${result.stderr}`).toContain("--course-dir is required");
    });

    it(`${script} exits 1 when course.json is absent`, () => {
      const root = mkdtempSync(path.join(tmpdir(), "cli-empty-"));
      const result = run(script, ["--course-dir", root]);
      expect(result.status).toBe(1);
      expect(`${result.stdout}${result.stderr}`).toContain("course.json not found");
    });
  }

  it("runs main when the entrypoint path goes through a symlink", () => {
    const link = path.join(mkdtempSync(path.join(tmpdir(), "cli-link-")), "extraction");
    symlinkSync(dir, link, "junction");
    const result = spawnSync(process.execPath, [path.join(link, "validate-extraction.js")], {
      encoding: "utf8",
      timeout: 20000,
    });
    expect(result.status).toBe(1);
    expect(`${result.stdout}${result.stderr}`).toContain("--course-dir is required");
  });
});

describe("artifacts written through argv", () => {
  it("validate-extraction writes validation-report.json", () => {
    const root = courseFixture();
    const result = run("validate-extraction.js", ["--course-dir", root]);
    const report = JSON.parse(readFileSync(path.join(root, "validation-report.json"), "utf8"));
    expect(report.course).toBe("CLI Course");
    expect(result.status === 0 || result.status === 1).toBe(true);
  });

  it("analyze-code-repo --skip-clone writes analysis.json", () => {
    const root = courseFixture({
      resources: { githubUrl: "https://github.com/octocat/Hello-World" },
    });
    mkdirSync(path.join(root, "code"));
    writeFileSync(path.join(root, "code", "README.md"), "# hi\n");
    const result = run("analyze-code-repo.js", ["--course-dir", root, "--skip-clone"]);
    expect(result.status).toBe(0);
    const analysis = JSON.parse(readFileSync(path.join(root, "code", "analysis.json"), "utf8"));
    expect(analysis.repo).toBe("Hello-World");
    expect(readFileSync(path.join(root, "code", "README.md"), "utf8")).toContain("Course Code Repository");
  });

  it("download-resources writes article-links.json when there is nothing to fetch", () => {
    const root = courseFixture();
    mkdirSync(path.join(root, "modules"));
    const result = run("download-resources.js", ["--course-dir", root]);
    expect(result.status).toBe(0);
    expect(readFileSync(path.join(root, "article-links.json"), "utf8")).toBe("[]");
  });

  it("extract-course and discover-resources refuse a course with no platform before writing a report", () => {
    for (const script of ["extract-course.js", "discover-resources.js"]) {
      const root = courseFixture({ platform: "" });
      const result = run(script, ["--course-dir", root]);
      expect(result.status).toBe(1);
      expect(`${result.stdout}${result.stderr}`).toContain("missing required 'platform'");
      expect(() => readFileSync(path.join(root, "run-report.json"))).toThrow();
      expect(() => readFileSync(path.join(root, "resource-report.json"))).toThrow();
    }
  });
});
