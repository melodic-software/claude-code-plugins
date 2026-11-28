import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const BUILDER = join(PLUGIN, "skills/explain-change/scripts/build-digest.mjs");
const TEMPLATE = join(PLUGIN, "skills/explain-change/templates/digest.html");
const { validateView } = await import(pathToFileURL(join(PLUGIN, "lib/view-builder.mjs")).href);

const scratch = mkdtempSync(join(tmpdir(), "explain-change-branding-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

function cleanGitEnv(extra = {}) {
  const env = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1", ...extra };
  for (const key of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"]) delete env[key];
  return env;
}

describe("explain-change branding and --team-ref isolation", () => {
  test("digest template defines no literal palette color", () => {
    const raw = readFileSync(TEMPLATE, "utf8");
    const style = /<style>([\s\S]*?)<\/style>/i.exec(raw)?.[1] ?? "";
    assert.ok(!/#[0-9a-fA-F]{3,8}\b|rgb\(|hsl\(/i.test(style));
  });

  test("reads branding from --team-ref commit only, never the working tree, and preserves toggle, comment box and floor", () => {
    const repo = join(scratch, "repo");
    const home = join(scratch, "home");
    const outTmp = join(scratch, "tmp");
    mkdirSync(join(repo, "docs/conventions"), { recursive: true });
    mkdirSync(home, { recursive: true });
    mkdirSync(outTmp, { recursive: true });

    const git = (...args) => execFileSync("git", ["-C", repo, ...args], { env: cleanGitEnv(), encoding: "utf8" }).trim();
    git("init", "-q", "-b", "main");
    writeFileSync(
      join(repo, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      bg: "#F8F4EC"',
        '      muted: "#595954"',
        '      link: "#1A4D8F"',
        '      fg: "#CCCCCC"',
        "  type:",
        '    sans: "IBM Plex Sans, sans-serif"',
        "  logo:",
        '    svg: \'<svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="6" fill="#1A4D8F"/></svg>\'',
        '    label: "Trusted Team"',
      ].join("\n") + "\n",
    );
    git("add", "docs/conventions/rendered-views.yaml");
    git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "base branding");
    const trustedSha = git("rev-parse", "HEAD");

    writeFileSync(
      join(repo, "docs/conventions/rendered-views.yaml"),
      [
        "branding:",
        "  palette:",
        "    light:",
        '      bg: "#E0F0FF"',
        "  logo:",
        '    label: "Untrusted Working Tree"',
      ].join("\n") + "\n",
    );

    const env = cleanGitEnv({
      CLAUDE_PROJECT_DIR: repo,
      HOME: home,
      USERPROFILE: home,
      TMPDIR: outTmp,
      TEMP: outTmp,
      TMP: outTmp,
      CLAUDE_PLUGIN_OPTION_BRANDING: "",
    });
    const payload = JSON.stringify({ title: "Digest branding check", change: "#1", why: "w", before: "b", after: "a" });

    const noRef = spawnSync(process.execPath, [BUILDER], { input: payload, encoding: "utf8", env });
    assert.equal(noRef.status, 0, noRef.stderr);
    const noRefPage = readFileSync(noRef.stdout.trim(), "utf8");
    assert.deepEqual(validateView(noRefPage), { ok: true, failures: [] });
    assert.ok(noRefPage.includes("--ivory: #FAF9F5;"));
    assert.ok(!noRefPage.includes("--bg: #E0F0FF;"));
    assert.ok(!noRefPage.includes("Untrusted Working Tree"));
    assert.ok(!noRefPage.includes('class="rv-brand"'));
    assert.ok(noRefPage.includes('data-rv-theme="system" aria-pressed="true"'));
    assert.ok(noRefPage.includes('data-rv-note="note"'));
    assert.ok(noRefPage.includes("outline: 3px solid var(--focus)"));

    const atRef = spawnSync(process.execPath, [BUILDER, "--team-ref", trustedSha], { input: payload, encoding: "utf8", env });
    assert.equal(atRef.status, 0, atRef.stderr);
    assert.ok(atRef.stderr.includes("notice:") && atRef.stderr.includes("fg"), atRef.stderr);
    const atRefPage = readFileSync(atRef.stdout.trim(), "utf8");
    assert.deepEqual(validateView(atRefPage), { ok: true, failures: [] });
    const atRefStyle = /<style>([\s\S]*?)<\/style>/i.exec(atRefPage)?.[1] ?? "";
    assert.ok(!atRefStyle.includes("GENERATED") && !atRefStyle.includes("Provenance:"));
    assert.ok(atRefPage.includes("--bg: #F8F4EC;"));
    assert.ok(atRefPage.includes("--link: #1A4D8F;"));
    assert.ok(!atRefPage.includes("--fg: #CCCCCC;"));
    assert.ok(!atRefPage.includes("--bg: #E0F0FF;"));
    assert.ok(!atRefPage.includes("Untrusted Working Tree"));
    assert.ok(atRefPage.includes("--sans: IBM Plex Sans, sans-serif;"));
    assert.ok(atRefPage.includes('<div class="rv-bar"><div class="rv-brand"><svg viewBox="0 0 16 16"'));
    assert.ok(atRefPage.includes('<span class="rv-brand-label">Trusted Team</span>'));
    assert.ok(atRefPage.includes('data-rv-theme="dark"'));
    assert.ok(atRefPage.includes('data-rv-note="note"'));
    assert.ok(atRefPage.includes("outline: 3px solid var(--focus)"));

    const optRun = spawnSync(process.execPath, [BUILDER, "--branding-option", '{"logo":{"label":"CLI Digest"}}'], { input: payload, encoding: "utf8", env });
    assert.equal(optRun.status, 0, optRun.stderr);
    const optPage = readFileSync(optRun.stdout.trim(), "utf8");
    assert.deepEqual(validateView(optPage), { ok: true, failures: [] });
    assert.ok(optPage.includes('<span class="rv-brand-label">CLI Digest</span>'));
    assert.ok(!optPage.includes("Untrusted Working Tree"));

    const skill = readFileSync(join(PLUGIN, "skills/explain-change/SKILL.md"), "utf8");
    assert.ok(skill.includes("--team-ref") && skill.includes("--branding-option"));
  });
});
