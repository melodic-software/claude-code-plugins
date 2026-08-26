#!/usr/bin/env node

// Deterministic prerequisite resolver for v1 routine identities on a named
// scheduling surface. Reads the generated identity-prerequisite emission —
// never leaf prose. No agent session. Never persists a verdict; never writes
// config. Wall-clock-free JSON on stdout so consecutive runs are byte-identical.
//
// Liveness (engine health-check taxonomy row): fail-loud on internal failure
// (non-zero exit, never a verdict-shaped fallback).
//
// Usage:
//   node resolve-prerequisites.mjs --repo <dir> --surface <id>
//        [--emission <path>] [--machine-context]
// Exit 0 = resolution emitted; 1 = usage / internal failure.

import {
  readdirSync,
  readFileSync,
  statSync,
} from "node:fs";
import { dirname, join, sep } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const DEFAULT_EMISSION = join(
  SCRIPT_DIR,
  "..",
  "..",
  "..",
  "generated",
  "identity-prerequisites.json",
);

const SCHEMA_VERSION = 1;

const DEPENDENCY_MANIFESTS = [
  "package.json",
  "package-lock.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "go.mod",
  "Cargo.toml",
  "pyproject.toml",
  "requirements.txt",
  "Pipfile",
  "Gemfile",
  "composer.json",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
];

const CI_MARKERS = [
  ".github/workflows",
  ".gitlab-ci.yml",
  "azure-pipelines.yml",
  ".circleci/config.yml",
  "Jenkinsfile",
  "bitbucket-pipelines.yml",
];

function usage(message) {
  if (message) console.error(message);
  console.error(
    "usage: node resolve-prerequisites.mjs --repo <dir> --surface <id> [--emission <path>] [--machine-context]",
  );
  process.exit(1);
}

function parseArgs(argv) {
  let repo = null;
  let surface = null;
  let emission = null;
  let machineContext = false;
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--repo") {
      repo = argv[++i];
      continue;
    }
    if (arg === "--surface") {
      surface = argv[++i];
      continue;
    }
    if (arg === "--emission") {
      emission = argv[++i];
      continue;
    }
    if (arg === "--machine-context") {
      machineContext = true;
      continue;
    }
    usage(`unknown argument: ${arg}`);
  }
  if (!repo || !surface) usage("`--repo` and `--surface` are required");
  return { repo, surface, emission: emission ?? DEFAULT_EMISSION, machineContext };
}

function posixJoin(...parts) {
  return join(...parts).split(sep).join("/");
}

function readJson(path) {
  try {
    return { ok: true, value: JSON.parse(readFileSync(path, "utf8")) };
  } catch (error) {
    if (error && error.code === "ENOENT") return { ok: false, reason: "absent" };
    return { ok: false, reason: "unreadable", detail: String(error.message ?? error) };
  }
}

function pathExists(path) {
  try {
    statSync(path);
    return true;
  } catch {
    return false;
  }
}

function listDir(path) {
  try {
    return readdirSync(path);
  } catch {
    return null;
  }
}

// Minimal YAML scalar read for `enabled: <bool>` — no full YAML dependency.
function readEnabledFlag(yamlText) {
  const match = yamlText.match(/^\s*enabled\s*:\s*(true|false)\s*(?:#.*)?$/m);
  if (!match) return null;
  return match[1] === "true";
}

function loadEmission(path) {
  const raw = readFileSync(path, "utf8");
  const parsed = JSON.parse(raw);
  if (!parsed || parsed.schema_version !== SCHEMA_VERSION || !Array.isArray(parsed.identities)) {
    throw new Error(`emission at ${path} is missing schema_version ${SCHEMA_VERSION} identities[]`);
  }
  return parsed;
}

function loadBinding(repoRoot) {
  const path = join(repoRoot, ".claude", "autonomy", "binding.json");
  const result = readJson(path);
  if (!result.ok) {
    return {
      present: false,
      path: posixJoin(".claude", "autonomy", "binding.json"),
      reason: result.reason,
      declarations: [],
      surfaces: {},
    };
  }
  const binding = result.value;
  const section =
    binding.prerequisite_resolution ?? binding.prerequisites ?? null;
  const declarations = Array.isArray(section?.declarations)
    ? section.declarations
    : [];
  const surfaces = {};
  for (const key of ["triggers", "routines"]) {
    const map = binding[key]?.surfaces;
    if (map && typeof map === "object") {
      for (const [id, value] of Object.entries(map)) {
        if (surfaces[id] === undefined) surfaces[id] = value;
      }
    }
  }
  return {
    present: true,
    path: posixJoin(".claude", "autonomy", "binding.json"),
    declarations,
    surfaces,
    section,
  };
}

function declarationFor(binding, surface, identity, need) {
  const matches = binding.declarations.filter((d) => {
    if (d.surface && d.surface !== surface) return false;
    if (need === undefined) {
      // Identity-level: only declarations that name the identity and omit need.
      if (!d.identity || d.identity !== identity) return false;
      if (d.need) return false;
      return true;
    }
    if (d.identity && d.identity !== identity) return false;
    if (d.need && d.need !== need) return false;
    // A declaration with neither identity nor need is surface-wide for all needs.
    return true;
  });
  matches.sort((a, b) => {
    const score = (d) =>
      (d.identity ? 4 : 0) + (d.need ? 2 : 0) + (d.surface ? 1 : 0);
    return score(b) - score(a);
  });
  return matches[0] ?? null;
}

function probeTracker(repoRoot) {
  const bindingPath = join(repoRoot, ".work-item-tracker.json");
  const bindingRead = readJson(bindingPath);
  if (!bindingRead.ok) {
    return {
      result: "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "work-item-tracker",
        path: ".work-item-tracker.json",
        detail: bindingRead.reason,
      },
    };
  }
  const provider = bindingRead.value?.provider;
  if (typeof provider !== "string" || provider.length === 0) {
    return {
      result: "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "work-item-tracker",
        path: ".work-item-tracker.json",
        detail: "provider missing",
      },
    };
  }
  const capsRel = posixJoin(
    "tools",
    "work-item-tracker",
    "adapters",
    provider,
    "capabilities.json",
  );
  const capsPath = join(repoRoot, "tools", "work-item-tracker", "adapters", provider, "capabilities.json");
  if (!pathExists(capsPath)) {
    // Presence-gated composition fallback: binding exists but adapter caps
    // cannot be established → unresolvable (unknown), not absent.
    return {
      result: "unresolvable",
      ran: false,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "work-item-tracker",
        path: capsRel,
        detail: "adapter capabilities.json absent; composition fallback",
      },
    };
  }
  return {
    result: "present",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      seam: "work-item-tracker",
      path: `.work-item-tracker.json+${capsRel}`,
    },
  };
}

function probeCiConfig(repoRoot) {
  for (const marker of CI_MARKERS) {
    const abs = join(repoRoot, ...marker.split("/"));
    if (pathExists(abs)) {
      return {
        result: "present",
        ran: true,
        provenance: {
          kind: "probe",
          probe_class: "repo-file",
          owner: "resolution-contract",
          path: marker,
        },
      };
    }
  }
  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      owner: "resolution-contract",
      path: CI_MARKERS[0],
      detail: "no CI-config marker found",
    },
  };
}

function probeDependencyManifests(repoRoot) {
  for (const name of DEPENDENCY_MANIFESTS) {
    if (pathExists(join(repoRoot, name))) {
      return {
        result: "present",
        ran: true,
        provenance: {
          kind: "probe",
          probe_class: "repo-file",
          path: name,
        },
      };
    }
  }
  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      path: "package.json",
      detail: "no dependency/build manifest found",
    },
  };
}

function probeEcosystems(repoRoot) {
  const dir = join(repoRoot, ".claude", "ecosystems");
  const entries = listDir(dir);
  if (entries === null) {
    // Fallback: inference from build files (never bundled defaults).
    const inferred = probeDependencyManifests(repoRoot);
    if (inferred.result === "present") {
      return {
        result: "present",
        ran: true,
        provenance: {
          kind: "probe",
          probe_class: "repo-file",
          seam: "toolchain",
          path: inferred.provenance.path,
          detail: "ecosystems dir absent; inferred from build files",
          rung: "repo-inferred",
        },
      };
    }
    return {
      result: "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "toolchain",
        path: ".claude/ecosystems",
        detail: "absent; build-file inference also negative",
      },
    };
  }

  const teamFiles = entries.filter(
    (name) => name.endsWith(".yaml") && !name.endsWith(".local.yaml"),
  );
  const localOnly = entries.filter((name) => name.endsWith(".local.yaml"));

  if (teamFiles.length === 0 && localOnly.length > 0) {
    return {
      result: "unresolvable",
      ran: false,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "toolchain",
        path: ".claude/ecosystems/*.local.yaml",
        detail: "uncommitted personal layer only; scheduled runs cannot establish",
        rung: "uncommitted",
      },
    };
  }

  let configured = 0;
  let disabled = 0;
  for (const name of teamFiles) {
    const text = readFileSync(join(dir, name), "utf8");
    const enabled = readEnabledFlag(text);
    if (enabled === false) {
      disabled += 1;
      continue;
    }
    configured += 1;
  }

  if (configured > 0) {
    return {
      result: "present",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "toolchain",
        path: ".claude/ecosystems",
        detail: `${configured} enabled ecosystem file(s)`,
        rung: "consumer-authored",
      },
    };
  }

  if (disabled > 0) {
    return {
      result: "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        seam: "toolchain",
        path: ".claude/ecosystems",
        detail: "ecosystem files present but enabled: false (not configured)",
        rung: "consumer-authored",
      },
    };
  }

  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      seam: "toolchain",
      path: ".claude/ecosystems",
      detail: "no ecosystem yaml files",
    },
  };
}

function probeSourceTree(repoRoot) {
  const candidates = ["src", "lib", "app", "pkg", "cmd"];
  for (const name of candidates) {
    if (pathExists(join(repoRoot, name))) {
      return {
        result: "present",
        ran: true,
        provenance: {
          kind: "probe",
          probe_class: "repo-file",
          path: name,
        },
      };
    }
  }
  // Any non-dotfile besides manifests counts.
  const entries = listDir(repoRoot) ?? [];
  const codeish = entries.filter(
    (name) =>
      !name.startsWith(".") &&
      !["README.md", "LICENSE", "CHANGELOG.md"].includes(name),
  );
  if (codeish.length > 0) {
    return {
      result: "present",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        path: codeish[0],
      },
    };
  }
  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      path: "src",
      detail: "no source tree markers",
    },
  };
}

function probeDocumentationCorpus(repoRoot) {
  if (pathExists(join(repoRoot, "docs"))) {
    return {
      result: "present",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        path: "docs",
      },
    };
  }
  const rootMd = (listDir(repoRoot) ?? []).filter((n) => n.endsWith(".md"));
  if (rootMd.length > 0 && pathExists(join(repoRoot, "src"))) {
    return {
      result: "present",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        path: rootMd[0],
      },
    };
  }
  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      path: "docs",
      detail: "documentation corpus not established",
    },
  };
}

function probeActivitySignals(repoRoot) {
  // Collates CI + tracker + git — absence of any one is negative per leaf.
  const ci = probeCiConfig(repoRoot);
  const tracker = probeTracker(repoRoot);
  if (ci.result === "present" && tracker.result === "present") {
    return {
      result: "present",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        path: "ci+tracker",
        detail: "CI-config and tracker binding both present",
      },
    };
  }
  if (ci.result === "absent" || tracker.result === "absent") {
    return {
      result: "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "repo-file",
        path: "ci+tracker",
        detail: `ci=${ci.result}; tracker=${tracker.result}`,
      },
    };
  }
  return {
    result: "unresolvable",
    ran: false,
    provenance: {
      kind: "probe",
      probe_class: "repo-file",
      path: "ci+tracker",
      detail: `ci=${ci.result}; tracker=${tracker.result}`,
    },
  };
}

function probeMcp(repoRoot) {
  const mcpPath = join(repoRoot, ".mcp.json");
  const presence = pathExists(mcpPath);
  const enablement = {
    result: "unresolvable",
    ran: false,
    detail:
      "enablement gate only partly resolvable from committed surfaces; compose config-audit when installed",
  };
  // Presence-gated claude-config seam: look for committed settings keys.
  const settingsPath = join(repoRoot, ".claude", "settings.json");
  const settings = readJson(settingsPath);
  if (settings.ok) {
    const s = settings.value;
    if (s.enableAllProjectMcpServers === true) {
      enablement.result = "present";
      enablement.ran = true;
      enablement.detail = "enableAllProjectMcpServers=true";
    } else if (Array.isArray(s.enabledMcpjsonServers)) {
      enablement.result = s.enabledMcpjsonServers.length > 0 ? "present" : "absent";
      enablement.ran = true;
      enablement.detail = "enabledMcpjsonServers from committed settings";
    } else {
      enablement.detail =
        "committed settings lack enablement keys; unprobeable overlay/user scope";
    }
  }
  return {
    presence: {
      result: presence ? "present" : "absent",
      ran: true,
      provenance: {
        kind: "probe",
        probe_class: "harness-context",
        path: ".mcp.json",
      },
    },
    enablement: {
      result: enablement.result,
      ran: enablement.ran,
      provenance: {
        kind: "probe",
        probe_class: "harness-context",
        seam: "config-audit",
        path: ".claude/settings.json",
        detail: enablement.detail,
      },
    },
  };
}

function probeAdvisoryDatabase(_repoRoot, _surface, machineContext) {
  // Curated advisory source is not established by repo-file presence alone.
  if (!machineContext) {
    return {
      result: "unresolvable",
      ran: false,
      provenance: {
        kind: "probe",
        probe_class: "harness-context",
        path: "advisory-database",
        detail: "curated source reachability not established without declaration or --machine-context",
      },
    };
  }
  return {
    result: "unresolvable",
    ran: false,
    provenance: {
      kind: "probe",
      probe_class: "machine-context",
      path: "advisory-database",
      detail: "machine-context probe for curated advisory source not implemented as a network fetch",
    },
  };
}

function probeUpstreamChangelog(_repoRoot, _surface, machineContext) {
  if (!machineContext) {
    return {
      result: "unresolvable",
      ran: false,
      provenance: {
        kind: "probe",
        probe_class: "harness-context",
        path: "upstream-changelog",
        detail: "upstream release-note reachability unprobeable on committed surfaces alone",
      },
    };
  }
  return {
    result: "unresolvable",
    ran: false,
    provenance: {
      kind: "probe",
      probe_class: "machine-context",
      path: "upstream-changelog",
      detail: "machine-context network reachability not asserted by this resolver",
    },
  };
}

function probeMergePath(repoRoot, surface, binding) {
  const recorded = binding.surfaces[surface];
  if (recorded) {
    // A recorded scheduling surface that is not advisory-only can carry merge
    // policy dispositions when the security binding stamps them; presence of
    // the surface is the repo-local half of the question.
    const mergeCapable =
      recorded.merge_policy_capable === true ||
      recorded.class === "temporal";
    if (mergeCapable) {
      return {
        result: "present",
        ran: true,
        provenance: {
          kind: "probe",
          probe_class: "harness-context",
          path: binding.path,
          detail: `surface ${surface} recorded in binding`,
        },
      };
    }
  }
  if (!binding.present) {
    return {
      result: "unresolvable",
      ran: false,
      provenance: {
        kind: "probe",
        probe_class: "harness-context",
        path: binding.path,
        detail: "binding absent; merge-path disposition unestablished",
      },
    };
  }
  return {
    result: "absent",
    ran: true,
    provenance: {
      kind: "probe",
      probe_class: "harness-context",
      path: binding.path,
      detail: `surface ${surface} not recorded as merge-capable`,
    },
  };
}

function runNeedProbe(needId, ctx) {
  switch (needId) {
    case "tracker":
      return probeTracker(ctx.repoRoot);
    case "ci_config":
      return probeCiConfig(ctx.repoRoot);
    case "dependency_manifests":
      return probeDependencyManifests(ctx.repoRoot);
    case "ecosystems":
      return probeEcosystems(ctx.repoRoot);
    case "source_tree":
      return probeSourceTree(ctx.repoRoot);
    case "documentation_corpus":
      return probeDocumentationCorpus(ctx.repoRoot);
    case "activity_signals":
      return probeActivitySignals(ctx.repoRoot);
    case "advisory_database":
      return probeAdvisoryDatabase(ctx.repoRoot, ctx.surface, ctx.machineContext);
    case "upstream_changelog":
      return probeUpstreamChangelog(ctx.repoRoot, ctx.surface, ctx.machineContext);
    case "merge_path":
      return probeMergePath(ctx.repoRoot, ctx.surface, ctx.binding);
    default:
      return {
        result: "unresolvable",
        ran: false,
        provenance: {
          kind: "probe",
          probe_class: "repo-file",
          path: needId,
          detail: `unknown need id ${needId}`,
        },
      };
  }
}

function resolveNeed(need, identity, ctx) {
  const decl = declarationFor(ctx.binding, ctx.surface, identity, need.id);
  const probe = runNeedProbe(need.id, ctx);
  const findings = [];
  let effective = probe.result;
  let provenance = {
    ...probe.provenance,
    surface: ctx.surface,
  };

  if (decl) {
    const declState = decl.state;
    const rung = decl.rung ?? "repo-local";
    if (declState === "absent" || declState === "disabled") {
      // Declaration narrows: disables even when probe finds present.
      effective = "absent";
      provenance = {
        kind: "declaration",
        rung,
        state: declState,
        need: need.id,
        surface: ctx.surface,
        probe_result: probe.result,
        probe_ran: probe.ran,
      };
    } else if (declState === "present") {
      if (probe.ran && probe.result === "absent") {
        effective = "absent";
        findings.push({
          kind: "declaration-probe-contradiction",
          need: need.id,
          detail:
            "declaration asserts present; probe ran and returned negative — probe caps declaration",
        });
        provenance = {
          kind: "probe",
          ...probe.provenance,
          surface: ctx.surface,
          declaration_state: declState,
          declaration_rung: rung,
        };
      } else if (!probe.ran || probe.result === "unresolvable") {
        // Probe could not run — declaration stands, qualified.
        effective = "conditional";
        provenance = {
          kind: "declaration",
          rung,
          state: declState,
          need: need.id,
          surface: ctx.surface,
          probe_result: probe.result,
          probe_ran: probe.ran,
          unprobeable: true,
        };
      } else {
        effective = "present";
        provenance = {
          kind: "declaration",
          rung,
          state: declState,
          need: need.id,
          surface: ctx.surface,
          probe_result: probe.result,
          probe_ran: probe.ran,
        };
      }
    }
  }

  return {
    need: need.id,
    probe_class: need.probe_class,
    result: effective,
    provenance,
    findings,
  };
}

function aggregateVerdict(signalResults) {
  const results = signalResults.map((s) => s.result);
  if (results.includes("absent")) return "unsupported";
  if (results.includes("conditional")) return "conditional";
  if (results.includes("unresolvable")) return "unknown";
  if (results.every((r) => r === "present")) return "supported";
  return "unknown";
}

function resolveIdentity(record, ctx) {
  const signals = [];
  const findings = [];
  for (const need of record.needs) {
    const resolved = resolveNeed(need, record.identity, ctx);
    signals.push({
      need: resolved.need,
      probe_class: resolved.probe_class,
      result: resolved.result,
      provenance: resolved.provenance,
    });
    for (const finding of resolved.findings) findings.push(finding);
  }

  // Identity-level disable declaration.
  const identityDecl = declarationFor(ctx.binding, ctx.surface, record.identity, undefined);
  if (
    identityDecl &&
    !identityDecl.need &&
    (identityDecl.state === "disabled" || identityDecl.state === "absent")
  ) {
    findings.push({
      kind: "identity-disabled-by-declaration",
      detail: `declaration state=${identityDecl.state}`,
    });
    return {
      identity: record.identity,
      verdict: "unsupported",
      signals,
      findings,
    };
  }

  return {
    identity: record.identity,
    verdict: aggregateVerdict(signals),
    signals,
    findings,
  };
}

function stableStringify(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const repoRoot = args.repo;
    if (!pathExists(repoRoot) || !statSync(repoRoot).isDirectory()) {
      throw new Error(`--repo ${repoRoot} is not a directory`);
    }

    const emission = loadEmission(args.emission);
    const binding = loadBinding(repoRoot);
    const mcp = probeMcp(repoRoot);

    const ctx = {
      repoRoot,
      surface: args.surface,
      machineContext: args.machineContext,
      binding,
    };

    const identities = emission.identities
      .map((record) => resolveIdentity(record, ctx))
      .sort((a, b) => a.identity.localeCompare(b.identity));

    const output = {
      schema_version: SCHEMA_VERSION,
      surface: args.surface,
      identities,
      harness: {
        mcp_presence: mcp.presence.result,
        mcp_enablement: mcp.enablement.result,
        mcp_presence_provenance: mcp.presence.provenance,
        mcp_enablement_provenance: mcp.enablement.provenance,
      },
      liveness: {
        taxonomy_row: "engine health-check",
        conformance:
          "fail-loud on internal failure (non-zero exit); never a verdict-shaped fallback",
      },
    };

    process.stdout.write(stableStringify(output));
  } catch (error) {
    console.error(`resolve-prerequisites: ${error.message}`);
    process.exit(1);
  }
}

main();
