#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

import Ajv2020 from "ajv/dist/2020.js";
import { parseDocument } from "yaml";

export class ConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigurationError";
  }
}

export function parseUniqueJson(source, location) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    schema: "json",
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new ConfigurationError(
      `${location} has duplicate object members or ambiguous structure: ${document.errors[0].message}`,
    );
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new ConfigurationError(`${location} is not valid JSON: ${error.message}`);
  }
}

const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_POLICY_PATH = path.join(MODULE_DIRECTORY, "policy.json");
const POLICY_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "policy.schema.json");
const POLICY_SCHEMA = parseUniqueJson(
  await readFile(POLICY_SCHEMA_PATH, "utf8"),
  `pr convention policy schema at ${POLICY_SCHEMA_PATH}`,
);
const SCHEMA_VALIDATOR = new Ajv2020({
  allErrors: false,
  strict: true,
  validateFormats: false,
});
const validatePolicyStructure = SCHEMA_VALIDATOR.compile(POLICY_SCHEMA);

function finding(rule, field, message) {
  return { rule, field, message };
}

function jsonPointerLocation(location, instancePath) {
  return `${location}${instancePath
    .split("/")
    .slice(1)
    .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
    .join("")}`;
}

export function validatePolicy(value, location = "policy") {
  if (validatePolicyStructure(value)) {
    return value;
  }
  const [error] = validatePolicyStructure.errors;
  let errorLocation = jsonPointerLocation(location, error.instancePath);
  if (error.keyword === "additionalProperties") {
    errorLocation += `.${error.params.additionalProperty}`;
  }
  throw new ConfigurationError(`${errorLocation} ${error.message}`);
}

export function buildTitlePattern(policy) {
  const types = policy.title.allowedTypes.map((type) =>
    type.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"),
  );
  const scope = policy.title.requireScope ? "\\([^)]+\\)" : "(?:\\([^)]+\\))?";
  const breaking = "!?";
  return new RegExp(`^(${types.join("|")})${scope}${breaking}: .+$`, "u");
}

export function validateTitle(title, policy) {
  const findings = [];
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    findings.push(finding("title-empty", "title", "PR title must not be empty."));
    return findings;
  }
  const pattern = buildTitlePattern(policy);
  if (!pattern.test(trimmed)) {
    const allowed = policy.title.allowedTypes.join(", ");
    findings.push(
      finding(
        "title-not-conventional",
        "title",
        `PR title must follow Conventional Commits with an allowed type (${allowed}).`,
      ),
    );
  }
  return findings;
}

export function stripRenderedHtmlComments(text) {
  const lines = text.split(/\r?\n/);
  const output = [];
  let commentOpen = false;
  let fence = null;
  let inlineTicks = null;

  function hasClosingTickRun(startLine, startColumn, ticks) {
    for (let lineIndex = startLine; lineIndex < lines.length; lineIndex += 1) {
      const candidate = lines[lineIndex];
      if (lineIndex > startLine && candidate.trim() === "") return false;
      let column = lineIndex === startLine ? startColumn : 0;
      while (column < candidate.length) {
        if (candidate[column] !== "`") {
          column += 1;
          continue;
        }
        let end = column + 1;
        while (candidate[end] === "`") end += 1;
        if (end - column === ticks) return true;
        column = end;
      }
    }
    return false;
  }

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex];
    if (!commentOpen && inlineTicks === null) {
      const marker = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
      if (fence !== null) {
        output.push("");
        if (
          marker !== null &&
          marker[1][0] === fence.char &&
          marker[1].length >= fence.length &&
          /^\s*$/.test(marker[2])
        ) {
          fence = null;
        }
        continue;
      }
      if (marker !== null && !(marker[1][0] === "`" && marker[2].includes("`"))) {
        fence = { char: marker[1][0], length: marker[1].length };
        output.push("");
        continue;
      }
      if (/^(?: {4}|\t)/.test(line)) {
        output.push("");
        continue;
      }
    }

    let rendered = "";
    for (let index = 0; index < line.length; ) {
      if (commentOpen) {
        const close = line.indexOf("-->", index);
        if (close === -1) {
          index = line.length;
          continue;
        }
        commentOpen = false;
        index = close + 3;
        continue;
      }

      if (line[index] === "`") {
        let end = index + 1;
        while (line[end] === "`") end += 1;
        const ticks = end - index;
        const wasInline = inlineTicks !== null;
        if (!wasInline && hasClosingTickRun(lineIndex, end, ticks)) {
          inlineTicks = ticks;
        } else if (inlineTicks === ticks) inlineTicks = null;
        if (!wasInline && inlineTicks === null) {
          rendered += line.slice(index, end);
        }
        index = end;
        continue;
      }

      if (inlineTicks === null && line.startsWith("<!--", index)) {
        commentOpen = true;
        index += 4;
        continue;
      }

      if (inlineTicks === null) rendered += line[index];
      index += 1;
    }
    output.push(rendered);
  }

  return output.join("\n");
}

function extractSection(text, heading) {
  const headingRe = new RegExp(
    `^##\\s+${heading.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`,
    "iu",
  );
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((line) => headingRe.test(line.trim()));
  if (start === -1) return null;
  const level = lines[start].trim().match(/^(#{1,6})\s+\S/u)[1].length;
  const rest = lines.slice(start + 1);
  const end = rest.findIndex((line) => {
    const match = /^(#{1,6})\s+\S/u.exec(line.trim());
    return match !== null && match[1].length <= level;
  });
  return (end === -1 ? rest : rest.slice(0, end)).join("\n").trim();
}

function buildNoIssuePattern(markers) {
  const escaped = markers.map((marker) => marker.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  return new RegExp(`\\b(?:${escaped.join("|")})\\b`, "iu");
}

function buildClosingKeywordPattern(keywords) {
  const alternatives = keywords.map((keyword) => {
    const lower = keyword.toLowerCase();
    const escapeRegex = (value) => value.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");
    if (lower.endsWith("es")) {
      return `${escapeRegex(lower.slice(0, -2))}(?:e[sd]?|es)`;
    }
    if (lower.endsWith("s")) {
      return `${escapeRegex(lower.slice(0, -1))}[sd]?`;
    }
    return `${escapeRegex(lower)}(?:e[sd]?|s)?`;
  });
  return new RegExp(
    `\\b(?:${alternatives.join("|")})\\s*:?\\s*(?:[\\w.-]+\\/[\\w.-]+)?#\\d+\\b`,
    "iu",
  );
}

export function validateBody(body, policy) {
  const findings = [];
  const rendered = stripRenderedHtmlComments(body ?? "");

  for (const section of policy.body.requiredSections) {
    const content = extractSection(rendered, section);
    if (content === null) {
      findings.push(finding("section-missing", "body", `Missing a "## ${section}" section.`));
    } else if (content.length === 0) {
      findings.push(finding("section-empty", "body", `The "## ${section}" section is empty.`));
    }
  }

  const closingKeywordPattern = buildClosingKeywordPattern(policy.body.closingKeywords);
  const noIssuePattern = buildNoIssuePattern(policy.body.noIssueMarkers);
  if (!closingKeywordPattern.test(rendered) && !noIssuePattern.test(rendered)) {
    const keywords = policy.body.closingKeywords.join("/");
    findings.push(
      finding(
        "closing-keyword-missing",
        "body",
        `Missing a native closing keyword (${keywords} #N). If this PR closes no GitHub issue, state "${policy.body.noIssueMarkers[0]}" in the body instead.`,
      ),
    );
  }

  return findings;
}

export function validatePullRequest({ title, body }, policy) {
  return [...validateTitle(title, policy), ...validateBody(body, policy)].sort((left, right) =>
    [left.field, left.rule, left.message]
      .join("\0")
      .localeCompare([right.field, right.rule, right.message].join("\0")),
  );
}

export function parseArguments(argv) {
  try {
    const { values } = parseArgs({
      args: argv,
      allowPositionals: false,
      options: {
        body: { type: "string" },
        json: { default: false, type: "boolean" },
        policy: { default: DEFAULT_POLICY_PATH, type: "string" },
        title: { type: "string" },
      },
      strict: true,
    });
    if (values.title === undefined) {
      throw new ConfigurationError("--title is required.");
    }
    return {
      title: values.title,
      body: values.body ?? "",
      policyPath: values.policy,
      json: values.json,
    };
  } catch (error) {
    throw new ConfigurationError(error instanceof Error ? error.message : String(error));
  }
}

async function loadPolicy(policyPath) {
  let source;
  try {
    source = await readFile(policyPath, "utf8");
  } catch (error) {
    throw new ConfigurationError(`policy could not be read at ${policyPath}: ${error.message}`);
  }
  return validatePolicy(
    parseUniqueJson(source, `policy at ${policyPath}`),
    `policy at ${policyPath}`,
  );
}

async function main() {
  try {
    const { json, policyPath, ...pullRequest } = parseArguments(process.argv.slice(2));
    const policy = await loadPolicy(policyPath);
    const findings = validatePullRequest(pullRequest, policy);
    if (json) {
      process.stdout.write(`${JSON.stringify({ findings, ok: findings.length === 0 }, null, 2)}\n`);
    } else if (findings.length === 0) {
      process.stdout.write("PR convention policy passed.\n");
    } else {
      for (const item of findings) {
        process.stderr.write(`${item.field}: ${item.rule}: ${item.message}\n`);
      }
    }
    process.exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`pr-convention-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
