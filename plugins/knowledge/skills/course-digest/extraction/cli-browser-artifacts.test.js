import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { afterEach, describe, expect, it } from "vitest";

const tempDirs = [];
const tempDir = (prefix) => {
  const d = mkdtempSync(path.join(tmpdir(), prefix));
  tempDirs.push(d);
  return d;
};
afterEach(() => {
  for (const d of tempDirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

const dir = path.dirname(new URL(import.meta.url).pathname);
const registerStub = pathToFileURL(path.join(dir, "test-support", "register-playwright-stub.mjs")).href;

const platformConfig = {
  videoPlayerSelector: ".hotmart_video_player",
  loginUrl: "https://sso.example.test/login",
  authEnvPrefix: "TEACHABLE",
  baseUrl: "https://courses.example.test",
  courseSlug: "stub-course",
};

const lesson = (position, title, lectureId, duration = "5m 0s") => ({
  position,
  title,
  slug: lectureId,
  lectureId,
  duration,
  status: "pending",
});

/** Run a CLI in a child whose `playwright` import is the scripted stub. */
function runBrowserCli(script, args, evaluateRules) {
  const scratch = tempDir("cli-browser-");
  const fixture = path.join(scratch, "stub-fixture.json");
  writeFileSync(fixture, JSON.stringify({ evaluate: evaluateRules }));
  const result = spawnSync(
    process.execPath,
    ["--import", registerStub, path.join(dir, script), ...args],
    {
      encoding: "utf8",
      timeout: 20000,
      env: { ...process.env, CLAUDE_PLUGIN_DATA: scratch, PLAYWRIGHT_STUB_FIXTURE: fixture },
    },
  );
  return { result, output: `${result.stdout}${result.stderr}` };
}

function courseDirWith(course) {
  const root = tempDir("cli-browser-course-");
  writeFileSync(path.join(root, "course.json"), JSON.stringify(course));
  return root;
}

const readJson = (file) => JSON.parse(readFileSync(file, "utf8"));

describe("browser-driven CLIs write their artifact through a stubbed playwright", () => {
  it("build-course-json writes course.json from the scraped curriculum", () => {
    const out = path.join(tempDir("cli-browser-out-"), "course");
    const curriculum = {
      title: "Stub Curriculum",
      modules: [
        {
          position: 1,
          title: "Intro",
          slug: "01-intro",
          lessons: [lesson(1, "Welcome", "111", "1m 30s"), lesson(2, "Setup", "222", "2m 0s")],
        },
        { position: 2, title: "Deep Dive", slug: "02-deep-dive", lessons: [lesson(1, "Core", "333", "3m 0s")] },
      ],
    };
    const { result, output } = runBrowserCli(
      "build-course-json.js",
      ["--course-url", "https://courses.example.test/courses/enrolled/2518872", "--output-dir", out],
      [{ when: "instructorFragment", value: curriculum }],
    );
    expect(output).toContain("course.json written to");
    expect(result.status).toBe(0);
    const course = readJson(path.join(out, "course.json"));
    expect(course.title).toBe("Stub Curriculum");
    expect(course.platform).toBe("teachable");
    expect(course.courseId).toBe("2518872");
    expect(course.totalLessons).toBe(3);
    expect(course.duration).toBe("0h 6m");
    expect(course.modules.map((m) => m.slug)).toEqual(["01-intro", "02-deep-dive"]);
  });

  it("discover-resources writes discovery-report.json from per-lesson page payloads", () => {
    const root = courseDirWith({
      title: "Discovery Course",
      platform: "teachable",
      platformConfig,
      url: "https://courses.example.test/courses/enrolled/1",
      modules: [
        {
          position: 1,
          title: "Intro",
          lessons: [lesson(1, "Welcome", "111"), lesson(2, "Rate this course", "999", "")],
        },
        { position: 2, title: "Deep Dive", lessons: [lesson(1, "Core", "333")] },
      ],
    });
    const resources = {
      hasVideo: true,
      hasTranscript: false,
      hasDownload: true,
      hasLessonNotes: false,
      hasReadThisLesson: false,
      attachmentTypes: ["video", "file"],
    };
    const { result, output } = runBrowserCli("discover-resources.js", ["--course-dir", root], [
      { when: "attachmentTypeSource", value: resources },
      { when: "querySelector(sel)", value: true },
    ]);
    expect(output).toContain("Authenticated");
    expect(result.status).toBe(0);
    const report = readJson(path.join(root, "discovery-report.json"));
    expect(report.course).toBe("Discovery Course");
    expect(report.mode).toBe("full");
    expect(report.summary).toEqual({
      totalLessons: 3,
      checked: 2,
      withVideo: 2,
      withDownload: 2,
      withNotes: 0,
      withReadThisLesson: 0,
    });
    expect(report.lessons.map((l) => [l.module, l.lesson, l.type ?? "video"])).toEqual([
      [1, 1, "video"],
      [1, 2, "non-video"],
      [2, 1, "video"],
    ]);
    expect(report.lessons[0].attachmentTypes).toEqual(["video", "file"]);
  });

  it("extract-course --metadata-only adds the landing-page metadata to course.json", () => {
    const root = courseDirWith({
      title: "Metadata Course",
      platform: "teachable",
      platformConfig,
      url: "https://courses.example.test/courses/enrolled/1",
      totalLessons: 1,
      modules: [{ position: 1, title: "Intro", lessons: [lesson(1, "Welcome", "111")] }],
    });
    const { result, output } = runBrowserCli("extract-course.js", ["--course-dir", root, "--metadata-only"], [
      { when: "lectureContent", value: { hotmart: true, lectureContent: true, attachments: 0 } },
      { when: 'querySelectorAll("meta")', value: { "og:title": "Stub OG Title", "og:description": "Stub blurb" } },
      { when: "?? null", value: "Ada Instructor" },
      { when: "querySelector(sel)", value: true },
    ]);
    expect(output).toContain("Done (metadata only)");
    expect(result.status).toBe(0);
    const course = readJson(path.join(root, "course.json"));
    expect(course.metadata).toMatchObject({
      title: "Stub OG Title",
      description: "Stub blurb",
      instructor: "Ada Instructor",
      ogTags: { "og:title": "Stub OG Title" },
    });
    expect(() => readFileSync(path.join(root, "run-report.json"))).toThrow();
  });
});
