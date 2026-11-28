import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "./test-tmp.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "view-settings.mjs");
const { resolveBranding, contrastRatio, validateSvgLogo } = await import("./view-settings.mjs");
const { BRANDING_USER_CONFIG_OPTION, PALETTE_ROLES, SHIPPED_TOKENS, TYPE_STACKS } = await import("./view-registry.mjs");
const { styleRefused } = await import("./html-escape.mjs");
const { buildView, validateView } = await import("./view-builder.mjs");

const TEAM = "docs/conventions/rendered-views.yaml";
const PERSONAL = "docs/conventions/rendered-views.local.yaml";

function repo(files = {}, ignore = []) {
  const dir = tempDir("view-settings-branding-repo-");
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  git("init", "-q", "-b", "main");
  if (ignore.length) writeFileSync(join(dir, ".gitignore"), `${ignore.join("\n")}\n`);
  for (const [path, [text, tracked]] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
    if (tracked) git("add", "-f", "--", path);
  }
  const commit = () => git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "x");
  return { dir, git, commit };
}
const userHome = (files = {}) => {
  const dir = tempDir("view-settings-branding-home-");
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
};
const EMPTY_HOME = userHome();

const PNG_BYTES = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52]);
const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const WOFF2_BYTES = Buffer.from([0x77, 0x4f, 0x46, 0x32, 0x00, 0x01, 0x00, 0x00]);
const WOFF_BYTES = Buffer.from([0x77, 0x4f, 0x46, 0x46, 0x00, 0x01, 0x00, 0x00]);
const TTF_BYTES = Buffer.from([0x00, 0x01, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x80]);
const TTF_TRUE_BYTES = Buffer.from([0x74, 0x72, 0x75, 0x65, 0x00, 0x0c, 0x00, 0x80]);
const OTF_BYTES = Buffer.from([0x4f, 0x54, 0x54, 0x4f, 0x00, 0x0c, 0x00, 0x80]);
const VALID_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="Acme"><defs><linearGradient id="g"><stop offset="0" stop-color="#111111"/></linearGradient></defs><path d="M2 2L22 22" fill="url(#g)"/><text x="4" y="12">Acme</text></svg>';

const brand = (request = {}, options = {}) => resolveBranding(request, { userHome: EMPTY_HOME, ...options });

describe("branding defaults, tokens parity and userConfig option shape", () => {
  test("SHIPPED_TOKENS matches lib/html-tokens.css verbatim", () => {
    const css = readFileSync(join(HERE, "html-tokens.css"), "utf8").replace(/\r\n?/g, "\n");
    const lightBlock = /^:root \{([^}]*)\}/m.exec(css)[1];
    const darkBlock = /^:root\[data-theme=dark\] \{([^}]*)\}/m.exec(css)[1];
    const readVar = (body, name) => new RegExp(`(?:^|\\n)[ \\t]*--${name}:[ \\t]*([^;]+);`).exec(body)?.[1];
    const resolveHex = (body, name) => {
      let v = readVar(body, name);
      for (let i = 0; v?.startsWith("var(--") && i < 5; i += 1) v = readVar(lightBlock, v.slice(6, -1));
      return v?.toUpperCase();
    };
    for (const role of PALETTE_ROLES) {
      assert.equal(SHIPPED_TOKENS.palette.light[role], resolveHex(lightBlock, role), `light.${role}`);
      assert.equal(SHIPPED_TOKENS.palette.dark[role], resolveHex(darkBlock, role), `dark.${role}`);
    }
    for (const stack of TYPE_STACKS) {
      assert.equal(SHIPPED_TOKENS.type[stack], readVar(lightBlock, stack), `type.${stack}`);
    }
  });

  test("BRANDING_USER_CONFIG_OPTION conforms to docs/contracts/plugin-option-naming", () => {
    const { key, type, title, description, default: def } = BRANDING_USER_CONFIG_OPTION;
    assert.match(key, /^[a-z][a-z0-9_]*$/);
    assert.equal(type, "string");
    assert.equal(def, "");
    assert.ok([...title].length <= 40, `title length ${title.length}`);
    assert.match(title, /^[A-Z0-9]/);
    const words = title.split(/[\s-]+/).map((w) => w.replace(/^[^A-Za-z0-9]+|[^A-Za-z0-9]+$/g, ""));
    assert.equal(words.some((w) => /^[A-Z]{6,}$/.test(w)), false);
    assert.equal(words.slice(1).some((w) => /^[A-Z][a-z]+$/.test(w)), false);
    assert.ok([...description].length <= 300, `description length ${description.length}`);
    assert.equal(description.includes("`"), false);
    assert.equal(description.includes("*"), false);
    assert.equal(/\[[^\]]*\]\([^)]*\)/.test(description), false);
    assert.equal(description.includes("\u2014"), false);
  });

  test("with no layer configured, shipped defaults apply with empty CSS and default attribution", () => {
    const res = brand();
    assert.deepEqual(res.palette, SHIPPED_TOKENS.palette);
    assert.deepEqual(res.type, { ...SHIPPED_TOKENS.type, fonts: [] });
    assert.deepEqual(res.logo, { kind: null, svg: null, dataUrl: null, mediaType: null, label: null });
    assert.equal(res.css, "");
    assert.deepEqual(res.notices, []);
    assert.equal(Object.values(res.sources).every((s) => s === "default"), true);
  });
});

describe("branding resolution order (plain ADR 0075: personal override > team > userConfig > default)", () => {
  test("personal override beats team, team beats userConfig, and unmentioned keys merge per key", () => {
    const { dir } = repo(
      {
        [TEAM]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#1D4ED8"',
            '      link: "#1E40AF"',
            "  type:",
            '    sans: "Inter, system-ui, sans-serif"',
            "  logo:",
            '    label: "Team Brand"',
            "",
          ].join("\n"),
          true,
        ],
        [PERSONAL]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#0F766E"',
            "  logo:",
            '    label: "Personal Label"',
            "",
          ].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const userCfg = JSON.stringify({
      palette: { light: { accent: "#B91C1C", focus: "#1D4ED8" }, dark: { accent: "#60A5FA" } },
      type: { mono: "JetBrains Mono, ui-monospace, monospace", sans: "Roboto, sans-serif" },
      logo: { label: "User Label" },
    });
    const res = brand({ userConfig: userCfg, projectRoot: dir });
    assert.deepEqual(res.notices, []);
    assert.equal(res.palette.light.accent, "#0F766E");
    assert.equal(res.sources["palette.light.accent"], "personal override");
    assert.equal(res.palette.light.link, "#1E40AF");
    assert.equal(res.sources["palette.light.link"], "team");
    assert.equal(res.palette.light.focus, "#1D4ED8");
    assert.equal(res.sources["palette.light.focus"], "userConfig");
    assert.equal(res.palette.dark.accent, "#60A5FA");
    assert.equal(res.sources["palette.dark.accent"], "userConfig");
    assert.equal(res.palette.light.bg, SHIPPED_TOKENS.palette.light.bg);
    assert.equal(res.sources["palette.light.bg"], "default");
    assert.equal(res.type.sans, "Inter, system-ui, sans-serif");
    assert.equal(res.sources["type.sans"], "team");
    assert.equal(res.type.mono, "JetBrains Mono, ui-monospace, monospace");
    assert.equal(res.sources["type.mono"], "userConfig");
    assert.equal(res.logo.label, "Personal Label");
    assert.equal(res.sources["logo.label"], "personal override");
    assert.equal(styleRefused(res.css), false, res.css);
  });

  test("unsubstituted userConfig placeholder and empty string act as unset", () => {
    for (const userConfig of ["", "${user_config.branding}", null, undefined]) {
      const res = brand({ userConfig });
      assert.deepEqual(res.notices, []);
      assert.equal(res.css, "");
    }
  });

  test("a tracked team branding value applies without the publish trust walk", () => {
    const { dir } = repo({
      [TEAM]: [["medium: artifact", "branding:", "  palette:", "    light:", '      accent: "#2563EB"', ""].join("\n"), true],
    });
    const res = brand({ projectRoot: dir });
    assert.equal(res.palette.light.accent, "#2563EB");
    assert.equal(res.sources["palette.light.accent"], "team");
    assert.deepEqual(res.notices, []);
  });
});

describe("branding validation refusals keep other layers and valid siblings", () => {
  test("refuses non-six-digit hex colors while preserving lower layer and valid siblings", () => {
    const { dir } = repo(
      {
        [TEAM]: [["branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', '      link: "#1E40AF"', ""].join("\n"), true],
        [PERSONAL]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#fff"',
            '      link: "red"',
            '      focus: "#11223344"',
            "    dark:",
            '      accent: "rgb(1, 2, 3)"',
            '      link: "#93C5FD; color: red"',
            "",
          ].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.palette.light.accent, "#1D4ED8");
    assert.equal(res.sources["palette.light.accent"], "team");
    assert.equal(res.palette.light.link, "#1E40AF");
    assert.equal(res.sources["palette.light.link"], "team");
    assert.equal(res.palette.light.focus, SHIPPED_TOKENS.palette.light.focus);
    assert.equal(res.notices.filter((n) => n.kind === "invalid").length, 5);
  });

  test("refuses font families outside the closed character set while preserving valid stacks", () => {
    const badStacks = [
      "Inter; background: url(https://evil.example/x)",
      "Inter</style><script>alert(1)</script>",
      "Inter\\003b color:red",
      'Inter, "Quoted Double"',
      "Inter'unclosed",
      ", sans-serif",
      "",
      "A".repeat(260),
    ];
    for (const sans of badStacks) {
      const res = brand({ userConfig: JSON.stringify({ type: { sans, serif: "Georgia, serif" } }) });
      assert.equal(res.type.sans, SHIPPED_TOKENS.type.sans, sans);
      assert.equal(res.type.serif, "Georgia, serif", sans);
      assert.ok(res.notices.some((n) => n.kind === "invalid" && n.text.includes("branding.type.sans")), sans);
    }
    const quoted = brand({ userConfig: JSON.stringify({ type: { mono: "ui-monospace, 'SF Mono', Menlo, monospace" } }) });
    assert.deepEqual(quoted.notices, []);
    assert.equal(quoted.type.mono, "ui-monospace, 'SF Mono', Menlo, monospace");
  });

  test("SVG allowlist accepts safe SVG matching builder rules and refuses every dangerous construct", () => {
    assert.equal(validateSvgLogo(VALID_SVG).ok, true);
    const res = brand({ userConfig: JSON.stringify({ logo: { svg: VALID_SVG, label: "Acme" } }) });
    assert.deepEqual(res.notices, []);
    assert.equal(res.logo.kind, "svg");
    assert.equal(res.logo.svg, VALID_SVG);
    const page = buildView({
      profile: "interactive",
      template: `<!doctype html><html><head><meta charset="utf-8"><title>T</title><style>body{margin:0}</style></head><body><div class="rv-bar">${res.logo.svg}</div></body></html>`,
      data: {},
    });
    assert.equal(validateView(page).ok, true);

    const hostileSvgs = [
      "<svg><script>alert(1)</script></svg>",
      "<svg><style>body{background:url(https://evil.example)}</style></svg>",
      '<svg><image href="https://evil.example/a.png"/></svg>',
      '<svg><use href="https://evil.example/a.svg#x"/></svg>',
      "<svg><foreignObject><div>hi</div></foreignObject></svg>",
      '<svg><a href="https://evil.example"><rect width="10" height="10"/></a></svg>',
      '<svg><animate attributeName="href" to="javascript:alert(1)"/></svg>',
      '<svg><set attributeName="x" to="1"/></svg>',
      '<svg><rect onload="alert(1)" width="10" height="10"/></svg>',
      '<svg><rect style="fill:red" width="10" height="10"/></svg>',
      '<svg xml:base="https://evil.example/"><rect width="10" height="10"/></svg>',
      '<svg><path href="https://evil.example/x" d="M0 0"/></svg>',
      '<svg><path xlink:href="javascript:alert(1)" d="M0 0"/></svg>',
      '<svg><rect fill="url(https://evil.example/a)" width="10" height="10"/></svg>',
      '<svg xmlns="http://www.w3.org/1999/xhtml"><rect width="10" height="10"/></svg>',
      "<!-- comment --><svg><rect width=\"10\" height=\"10\"/></svg>",
      '<?xml version="1.0"?><svg><rect width="10" height="10"/></svg>',
      '<!DOCTYPE svg><svg><rect width="10" height="10"/></svg>',
      "<svg><rect width=\"10\" height=\"10\"></svg>",
      "<div>not svg</div>",
      "<svg><text>A & B</text></svg>",
    ];
    for (const svg of hostileSvgs) {
      const check = validateSvgLogo(svg);
      assert.equal(check.ok, false, `expected refusal for ${svg}`);
      const out = brand({ userConfig: JSON.stringify({ logo: { svg } }) });
      assert.equal(out.logo.kind, null, svg);
      assert.ok(out.notices.some((n) => n.kind === "invalid" && n.text.includes("SVG allowlist")), svg);
    }
  });

  test("embeds PNG, JPEG and SVG logo files via magic bytes and refuses spoofed extensions, traversal and symlinks", () => {
    const { dir } = repo({
      [TEAM]: [["branding:", "  logo:", '    file: "docs/brand/logo.bin"', '    label: "Acme"', ""].join("\n"), true],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/logo.bin"), PNG_BYTES);
    const pngRes = brand({ projectRoot: dir });
    assert.deepEqual(pngRes.notices, []);
    assert.equal(pngRes.logo.kind, "image");
    assert.equal(pngRes.logo.mediaType, "image/png");
    assert.equal(pngRes.logo.dataUrl, `data:image/png;base64,${PNG_BYTES.toString("base64")}`);
    assert.match(pngRes.css, /^\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
    assert.equal(styleRefused(pngRes.css), false, pngRes.css);

    writeFileSync(join(dir, "docs/brand/logo.bin"), JPEG_BYTES);
    const jpgRes = brand({ projectRoot: dir });
    assert.deepEqual(jpgRes.notices, []);
    assert.equal(jpgRes.logo.mediaType, "image/jpeg");
    assert.equal(styleRefused(jpgRes.css), false);

    writeFileSync(join(dir, "docs/brand/logo.bin"), VALID_SVG);
    const svgFileRes = brand({ projectRoot: dir });
    assert.deepEqual(svgFileRes.notices, []);
    assert.equal(svgFileRes.logo.kind, "svg");
    assert.equal(svgFileRes.logo.svg, VALID_SVG);

    writeFileSync(join(dir, "docs/brand/fake.png"), Buffer.from("GIF89a\x01\x00\x01\x00"));
    writeFileSync(join(dir, TEAM), ["branding:", "  logo:", "    file: \"docs/brand/fake.png\"", ""].join("\n"));
    const spoofed = brand({ projectRoot: dir });
    assert.equal(spoofed.logo.kind, null);
    assert.ok(spoofed.notices.some((n) => n.kind === "invalid" && /magic bytes/.test(n.text)));

    for (const badPath of ["../escape.png", "/etc/passwd", "~/logo.png"]) {
      writeFileSync(join(dir, TEAM), ["branding:", "  logo:", `    file: ${JSON.stringify(badPath)}`, ""].join("\n"));
      const escaped = brand({ projectRoot: dir });
      assert.equal(escaped.logo.kind, null, badPath);
      assert.ok(escaped.notices.some((n) => n.kind === "invalid"), badPath);
    }

    if (process.platform !== "win32") {
      const outside = tempDir("view-settings-outside-");
      writeFileSync(join(outside, "ext.png"), PNG_BYTES);
      execFileSync("ln", ["-s", join(outside, "ext.png"), join(dir, "docs/brand/link.png")]);
      writeFileSync(join(dir, TEAM), ["branding:", "  logo:", "    file: \"docs/brand/link.png\"", ""].join("\n"));
      const linked = brand({ projectRoot: dir });
      assert.equal(linked.logo.kind, null);
      assert.ok(linked.notices.some((n) => n.kind === "invalid" && /symlink/.test(n.text)));
    }
  });

  test("refuses both logo.svg and logo.file in one layer without dropping a lower layer's logo", () => {
    const { dir } = repo(
      {
        [TEAM]: [["branding:", "  logo:", `    svg: ${JSON.stringify(VALID_SVG)}`, ""].join("\n"), true],
        [PERSONAL]: [
          ["branding:", "  logo:", `    svg: ${JSON.stringify(VALID_SVG)}`, '    file: "docs/brand/logo.png"', '    label: "Keep Label"', ""].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.logo.kind, "svg");
    assert.equal(res.sources["logo.graphic"], "team");
    assert.equal(res.logo.label, "Keep Label");
    assert.equal(res.sources["logo.label"], "personal override");
    assert.ok(res.notices.some((n) => n.kind === "invalid" && /both svg and file/.test(n.text)));
  });

  test("embeds WOFF2, WOFF, TTF and OTF font files via magic bytes and refuses spoofed fonts", () => {
    const cases = [
      ["a.woff2", WOFF2_BYTES, "font/woff2", "woff2"],
      ["b.woff", WOFF_BYTES, "font/woff", "woff"],
      ["c.ttf", TTF_BYTES, "font/ttf", "truetype"],
      ["d.ttf", TTF_TRUE_BYTES, "font/ttf", "truetype"],
      ["e.otf", OTF_BYTES, "font/otf", "opentype"],
    ];
    const { dir } = repo();
    mkdirSync(join(dir, "docs/fonts"), { recursive: true });
    for (const [name, bytes] of cases) writeFileSync(join(dir, "docs/fonts", name), bytes);
    writeFileSync(join(dir, "docs/fonts/spoof.woff2"), PNG_BYTES);
    mkdirSync(join(dir, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(dir, TEAM),
      [
        "branding:",
        "  type:",
        "    fonts:",
        ...cases.flatMap(([name], i) => [`      - family: "Brand ${i}"`, `        file: "docs/fonts/${name}"`, "        weight: 600", "        style: italic"]),
        '      - family: "Spoof"',
        '        file: "docs/fonts/spoof.woff2"',
        "",
      ].join("\n"),
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.type.fonts.length, cases.length);
    cases.forEach(([, bytes, mediaType, format], i) => {
      assert.equal(res.type.fonts[i].family, `Brand ${i}`);
      assert.equal(res.type.fonts[i].mediaType, mediaType);
      assert.equal(res.type.fonts[i].format, format);
      assert.equal(res.type.fonts[i].weight, "600");
      assert.equal(res.type.fonts[i].style, "italic");
      assert.equal(res.type.fonts[i].dataUrl, `data:${mediaType};base64,${bytes.toString("base64")}`);
    });
    assert.equal(res.notices.length, 1);
    assert.match(res.notices[0].text, /magic bytes/);
    assert.equal(styleRefused(res.css), false, res.css);
  });

  test("userConfig handles invalid JSON, non-object JSON, unknown keys, reserved keys and home-relative files", () => {
    const home = userHome();
    mkdirSync(join(home, "brand"), { recursive: true });
    writeFileSync(join(home, "brand/logo.png"), PNG_BYTES);
    const ok = brand({ userConfig: JSON.stringify({ logo: { file: "~/brand/logo.png", label: "Home" } }) }, { userHome: home });
    assert.deepEqual(ok.notices, []);
    assert.equal(ok.logo.mediaType, "image/png");

    const badJson = brand({ userConfig: "{not json" });
    assert.ok(badJson.notices.some((n) => n.kind === "invalid" && /invalid JSON/.test(n.text)));
    const nonObj = brand({ userConfig: "[]" });
    assert.ok(nonObj.notices.some((n) => n.kind === "invalid" && /expected a JSON object/.test(n.text)));
    const reserved = brand({ userConfig: '{"__proto__":{"x":1},"unknown":1,"palette":{"light":{"accent":"#2563EB"}}}' });
    assert.equal(reserved.palette.light.accent, "#2563EB");
    assert.equal(reserved.notices.filter((n) => n.kind === "invalid").length, 2);
    const badLabel = brand({ userConfig: JSON.stringify({ logo: { label: "Bad\u202eBidi" } }) });
    assert.equal(badLabel.logo.label, null);
    assert.ok(badLabel.notices.some((n) => n.kind === "invalid" && /branding\.logo\.label/.test(n.text)));

    const longLabel = brand({ userConfig: JSON.stringify({ logo: { label: "A".repeat(81) } }) });
    assert.equal(longLabel.logo.label, null);
    assert.ok(longLabel.notices.some((n) => n.kind === "invalid" && /branding\.logo\.label/.test(n.text)));

    const relUser = brand({ userConfig: JSON.stringify({ logo: { file: "docs/brand/logo.png" } }) }, { userHome: home });
    assert.equal(relUser.logo.kind, null);
    assert.ok(relUser.notices.some((n) => n.kind === "invalid" && /must be absolute or start with ~\//.test(n.text)));
  });

  test("preserves valid font entries beside schema-invalid siblings and honors an explicitly empty fonts list", () => {
    const { dir } = repo(
      {
        [TEAM]: [
          [
            "branding:",
            "  type:",
            "    fonts:",
            '      - family: "Good Font"',
            '        file: "docs/fonts/good.woff2"',
            '      - family: "Bad Style"',
            '        file: "docs/fonts/good.woff2"',
            '        style: "oblique"',
            '      - family: "Extra Key"',
            '        file: "docs/fonts/good.woff2"',
            '        display: "swap"',
            "",
          ].join("\n"),
          true,
        ],
      },
      ["*.local.yaml"],
    );
    mkdirSync(join(dir, "docs/fonts"), { recursive: true });
    writeFileSync(join(dir, "docs/fonts/good.woff2"), WOFF2_BYTES);
    const partial = brand({ projectRoot: dir });
    assert.equal(partial.type.fonts.length, 1);
    assert.equal(partial.type.fonts[0].family, "Good Font");
    assert.equal(partial.sources["type.fonts"], "team");
    assert.equal(partial.notices.filter((n) => n.kind === "invalid").length, 2);

    writeFileSync(join(dir, PERSONAL), ["branding:", "  type:", "    fonts: []", ""].join("\n"));
    const cleared = brand({ projectRoot: dir });
    assert.deepEqual(cleared.type.fonts, []);
    assert.equal(cleared.sources["type.fonts"], "personal override");
    assert.equal(cleared.css, "");

    writeFileSync(join(dir, PERSONAL), ["branding:", "  type:", "    fonts:", '      - family: "Broken"', '        file: "docs/fonts/missing.woff2"', ""].join("\n"));
    const allBad = brand({ projectRoot: dir });
    assert.equal(allBad.type.fonts.length, 1);
    assert.equal(allBad.type.fonts[0].family, "Good Font");
    assert.equal(allBad.sources["type.fonts"], "team");
  });

  test("gates personal override external paths and ignores tracked personal overrides (including under --team-ref)", () => {
    const home = userHome();
    mkdirSync(join(home, "brand"), { recursive: true });
    const extLogo = join(home, "brand/logo.png");
    writeFileSync(extLogo, PNG_BYTES);

    const tracked = repo(
      {
        [TEAM]: [["branding:", "  logo:", '    label: "Team"', ""].join("\n"), true],
        [PERSONAL]: [["branding:", "  logo:", '    file: "~/brand/logo.png"', '    label: "Spoof"', ""].join("\n"), true],
      },
      ["*.local.yaml"],
    );
    tracked.commit();
    const sha = tracked.git("rev-parse", "HEAD").trim();
    for (const req of [{ projectRoot: tracked.dir }, { projectRoot: tracked.dir, teamRef: sha }]) {
      const res = brand(req, { userHome: home });
      assert.equal(res.logo.label, "Team");
      assert.equal(res.logo.kind, null);
      assert.ok(res.notices.some((n) => n.kind === "ignored" && /tracked in git/.test(n.text)));
    }

    const unignored = repo({ [PERSONAL]: [["branding:", "  logo:", `    file: ${JSON.stringify(extLogo)}`, ""].join("\n"), false] });
    const refused = brand({ projectRoot: unignored.dir }, { userHome: home });
    assert.equal(refused.logo.kind, null);
    assert.ok(refused.notices.some((n) => n.kind === "invalid" && /external asset path requires an untracked, gitignored personal override/.test(n.text)));

    const ignored = repo({ [PERSONAL]: [["branding:", "  logo:", '    file: "~/brand/logo.png"', ""].join("\n"), false] }, ["*.local.yaml"]);
    const accepted = brand({ projectRoot: ignored.dir }, { userHome: home });
    assert.deepEqual(accepted.notices, []);
    assert.equal(accepted.logo.kind, "image");
    assert.equal(accepted.sources["logo.graphic"], "personal override");
  });

  test("enforces size caps for disk assets, git blobs and inline SVG", () => {
    const hugePng = Buffer.alloc(5 * 1024 * 1024 + 16);
    PNG_BYTES.copy(hugePng);
    const { dir, git, commit } = repo({ [TEAM]: [["branding:", "  logo:", '    file: "docs/brand/huge.png"', ""].join("\n"), true] });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/huge.png"), hugePng);
    const diskOver = brand({ projectRoot: dir });
    assert.equal(diskOver.logo.kind, null);
    assert.ok(diskOver.notices.some((n) => n.kind === "invalid" && /exceeds/.test(n.text)));

    git("add", "-f", "--", "docs/brand/huge.png");
    commit();
    const blobOver = brand({ projectRoot: dir, teamRef: git("rev-parse", "HEAD").trim() });
    assert.equal(blobOver.logo.kind, null);
    assert.ok(blobOver.notices.some((n) => n.kind === "invalid" && /exceeds/.test(n.text)));

    const hugeSvg = `<svg xmlns="http://www.w3.org/2000/svg"><desc>${"a".repeat(256 * 1024 + 64)}</desc></svg>`;
    const svgOver = brand({ userConfig: JSON.stringify({ logo: { svg: hugeSvg } }) });
    assert.equal(svgOver.logo.kind, null);
    assert.ok(svgOver.notices.some((n) => n.kind === "invalid" && /exceeds/.test(n.text)));
  });
});

describe("branding --team-ref reads config and team assets from the named commit", () => {
  test("reads branding values and logo/font blobs from the commit, ignoring working-tree edits", () => {
    const { dir, git, commit } = repo({
      [TEAM]: [
        [
          "branding:",
          "  palette:",
          "    light:",
          '      accent: "#1D4ED8"',
          "  type:",
          "    fonts:",
          '      - family: "Committed Font"',
          '        file: "docs/brand/font.woff2"',
          "  logo:",
          '    file: "docs/brand/logo.png"',
          '    label: "Committed"',
          "",
        ].join("\n"),
        true,
      ],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/logo.png"), PNG_BYTES);
    writeFileSync(join(dir, "docs/brand/font.woff2"), WOFF2_BYTES);
    git("add", "-f", "--", "docs/brand/logo.png", "docs/brand/font.woff2");
    commit();
    const base = git("rev-parse", "HEAD").trim();

    writeFileSync(join(dir, TEAM), ["branding:", "  palette:", "    light:", "      accent: \"#DC2626\"", "  logo:", "    label: \"Dirty\"", ""].join("\n"));
    writeFileSync(join(dir, "docs/brand/logo.png"), JPEG_BYTES);

    const atRef = brand({ projectRoot: dir, teamRef: base });
    assert.deepEqual(atRef.notices, []);
    assert.equal(atRef.palette.light.accent, "#1D4ED8");
    assert.equal(atRef.logo.mediaType, "image/png");
    assert.equal(atRef.logo.label, "Committed");
    assert.equal(atRef.type.fonts[0].mediaType, "font/woff2");

    const atWork = brand({ projectRoot: dir });
    assert.equal(atWork.palette.light.accent, "#DC2626");
    assert.equal(atWork.logo.label, "Dirty");

    const badRef = brand({ projectRoot: dir, teamRef: "no-such-ref" });
    assert.equal(badRef.palette.light.accent, SHIPPED_TOKENS.palette.light.accent);
    assert.ok(badRef.notices.some((n) => n.kind === "team-ref"));
  });

  test("refuses a symlinked asset committed at --team-ref", { skip: process.platform === "win32" && "symlinks need a privilege on Windows" }, () => {
    const { dir, git, commit } = repo({
      [TEAM]: [["branding:", "  logo:", '    file: "docs/brand/sym.png"', ""].join("\n"), true],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/real.png"), PNG_BYTES);
    execFileSync("ln", ["-s", "real.png", join(dir, "docs/brand/sym.png")]);
    git("add", "-f", "--", "docs/brand/real.png", "docs/brand/sym.png");
    commit();
    const base = git("rev-parse", "HEAD").trim();
    const res = brand({ projectRoot: dir, teamRef: base });
    assert.equal(res.logo.kind, null);
    assert.ok(res.notices.some((n) => n.kind === "invalid" && /symlink/.test(n.text)));
  });
});

describe("branding WCAG 2.1 contrast floor in both schemes", () => {
  test("contrastRatio computes exact WCAG 2.1 ratios", () => {
    assert.equal(Number(contrastRatio("#000000", "#FFFFFF").toFixed(2)), 21);
    assert.equal(Number(contrastRatio("#A0512E", "#FAF9F5").toFixed(2)), 5.37);
    assert.equal(Number(contrastRatio("#E89B7E", "#3D3D3A").toFixed(2)), 4.89);
  });

  test("drops low-contrast fg, muted, link (< 4.5:1) and focus (< 3:1) in both schemes, naming role, scheme, pair and ratio", () => {
    const lightFail = brand({
      userConfig: JSON.stringify({
        palette: {
          light: { fg: "#CCCCCC", muted: "#AAAAAA", link: "#D97757", focus: "#E3DACC", accent: "#0066CC" },
          dark: { fg: "#222222", muted: "#444444", link: "#555555", focus: "#4A4A47", accent: "#38BDF8" },
        },
      }),
    });
    for (const scheme of ["light", "dark"]) {
      for (const role of ["fg", "muted", "link", "focus"]) {
        assert.equal(lightFail.palette[scheme][role], SHIPPED_TOKENS.palette[scheme][role], `${scheme}.${role}`);
        assert.equal(lightFail.sources[`palette.${scheme}.${role}`], "default");
        const notice = lightFail.notices.find((n) => n.kind === "contrast" && n.scheme === scheme && n.role === role);
        assert.ok(notice, `missing contrast notice for ${scheme}.${role}`);
        assert.match(notice.text, new RegExp(`${scheme} ${role}: pair ${role} on (?:bg|panel) has contrast \\d+\\.\\d{2}:1`));
      }
    }
    assert.equal(lightFail.palette.light.accent, "#0066CC");
    assert.equal(lightFail.palette.dark.accent, "#38BDF8");
  });

  test("enforces 3:1 on focus while enforcing 4.5:1 on link (3.5:1 color passes focus and fails link)", () => {
    const mid = "#87867F";
    const res = brand({ userConfig: JSON.stringify({ palette: { light: { focus: mid, link: mid } } }) });
    assert.equal(res.palette.light.focus, mid);
    assert.equal(res.sources["palette.light.focus"], "userConfig");
    assert.equal(res.palette.light.link, SHIPPED_TOKENS.palette.light.link);
    assert.equal(res.sources["palette.light.link"], "default");
    assert.ok(res.notices.some((n) => n.kind === "contrast" && n.role === "link" && n.scheme === "light"));
  });

  test("drops bad dark foreground without dropping valid dark bg/panel, and accepts full high-contrast light bg+muted pair", () => {
    const dark = brand({
      userConfig: JSON.stringify({
        palette: { dark: { bg: "#0B0D12", panel: "#1A1D24", muted: "#222222" } },
      }),
    });
    assert.equal(dark.palette.dark.bg, "#0B0D12");
    assert.equal(dark.palette.dark.panel, "#1A1D24");
    assert.equal(dark.palette.dark.muted, SHIPPED_TOKENS.palette.dark.muted);
    assert.equal(dark.notices.length, 1);

    const lightPair = brand({
      userConfig: JSON.stringify({
        palette: { light: { bg: "#FFFFFF", panel: "#F8FAFC", muted: "#595954" } },
      }),
    });
    assert.deepEqual(lightPair.notices, []);
    assert.equal(lightPair.palette.light.bg, "#FFFFFF");
    assert.equal(lightPair.palette.light.panel, "#F8FAFC");
    assert.equal(lightPair.palette.light.muted, "#595954");

    const lightBgOnly = brand({ userConfig: JSON.stringify({ palette: { light: { bg: "#FFFFFF" } } }) });
    assert.equal(lightBgOnly.palette.light.bg, SHIPPED_TOKENS.palette.light.bg);
    assert.ok(lightBgOnly.notices.some((n) => n.kind === "contrast" && n.role === "bg" && n.pair === "muted on bg"));
  });
});

describe("branding CLI", () => {
  const run = (args, env = {}) => spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", ...env } });

  test("branding subcommand prints JSON and layer attribution lines", () => {
    const { dir } = repo({ [TEAM]: [["branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', ""].join("\n"), true] });
    const out = run(["branding"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(out.status, 0, out.stderr);
    const [json, ...lines] = out.stdout.trimEnd().split("\n");
    const parsed = JSON.parse(json);
    assert.equal(parsed.palette.light.accent, "#1D4ED8");
    assert.equal(parsed.sources["palette.light.accent"], "team");
    assert.deepEqual(lines, ["branding: palette.light.accent (team)"]);
  });

  test("resolve --branding-option includes branding and deduplicates shared notices", () => {
    const { dir, commit } = repo({ [TEAM]: [["medium: file", "branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', ""].join("\n"), true] });
    commit();
    const out = run(["resolve", "--producer", "planning", "--option", "auto", "--branding-option", "", "--team-ref", "no-such-ref"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(out.status, 0, out.stderr);
    const [json, ...lines] = out.stdout.trimEnd().split("\n");
    const parsed = JSON.parse(json);
    assert.equal(parsed.medium, "artifact");
    assert.equal(parsed.branding.palette.light.accent, SHIPPED_TOKENS.palette.light.accent);
    assert.equal(lines.filter((l) => l.includes("no-such-ref")).length, 1);
  });

  test("every registered copy resolves branding cleanly", () => {
    const manifest = readFileSync(join(HERE, "..", "scripts", "shared-copies.txt"), "utf8");
    const copies = [...manifest.matchAll(/^lib\/view-settings\.mjs (\S+)$/gm)].map(([, copy]) => copy);
    assert.ok(copies.length > 0, "no view-settings copy registered");
    for (const copy of copies) {
      const out = spawnSync(process.execPath, [join(HERE, "..", copy), "branding"], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PROJECT_DIR: EMPTY_HOME } });
      assert.equal(out.status, 0, `${copy}: ${out.stderr}`);
      assert.equal(out.stdout.split("\n")[1], "branding: default (shipped tokens)", copy);
    }
  });
});
