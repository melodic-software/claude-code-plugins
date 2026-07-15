#!/usr/bin/env node

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

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
const DEFAULT_CONFIG_PATH = ".github/runner-policy.json";
const POLICY_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "policy.schema.json");
const REPOSITORY_POLICY_SCHEMA_PATH = path.join(MODULE_DIRECTORY, "repository-policy.schema.json");
const POLICY_SCHEMA = parseUniqueJson(
  await readFile(POLICY_SCHEMA_PATH, "utf8"),
  `policy schema at ${POLICY_SCHEMA_PATH}`,
);
const REPOSITORY_POLICY_SCHEMA = parseUniqueJson(
  await readFile(REPOSITORY_POLICY_SCHEMA_PATH, "utf8"),
  `repository policy schema at ${REPOSITORY_POLICY_SCHEMA_PATH}`,
);
const SCHEMA_VALIDATOR = new Ajv2020({
  allErrors: false,
  strict: true,
  validateFormats: false,
});
const validatePolicyStructure = SCHEMA_VALIDATOR.compile(POLICY_SCHEMA);
const validateRepositoryPolicyStructure = SCHEMA_VALIDATOR.compile(REPOSITORY_POLICY_SCHEMA);
const RUNNER_OUTPUT =
  /^\s*\$\{\{\s*needs\.(?<selectorId>[A-Za-z0-9_-]+)\.outputs\.runner\s*\|\|\s*'(?<fallback>[^'\r\n]+)'\s*}}\s*$/;
const REQUIRED_RUNNER_OUTPUT =
  /^\s*\$\{\{\s*needs\.(?<selectorId>[A-Za-z0-9_-]+)\.outputs\.runner\s*}}\s*$/;
const MATRIX_OUTPUT = /^\$\{\{ matrix\.([A-Za-z0-9_-]+) }}$/;
const FULL_SHA = /^[0-9a-f]{40}$/i;
const REUSABLE_WORKFLOW_PATH =
  /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/;
const LOCAL_REUSABLE_WORKFLOW = /^\.\/\.github\/workflows\/([A-Za-z0-9_.-]+\.ya?ml)$/;
const GITHUB_REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}\/[A-Za-z0-9_.-]+$/;
const EXACT_GITHUB_TOKEN_EXPRESSIONS = new Set([
  `\${{ secrets.GITHUB_TOKEN }}`,
  `\${{ github.token }}`,
]);

function jsonPointerLocation(location, instancePath) {
  return `${location}${instancePath
    .split("/")
    .slice(1)
    .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
    .join("")}`;
}

function validateStructure(value, validator, location) {
  if (validator(value)) {
    return;
  }
  const [error] = validator.errors;
  let errorLocation = jsonPointerLocation(location, error.instancePath);
  if (error.keyword === "additionalProperties") {
    errorLocation += `.${error.params.additionalProperty}`;
  } else if (error.keyword === "propertyNames") {
    errorLocation += `.${error.params.propertyName}`;
  }
  throw new ConfigurationError(`${errorLocation} ${error.message}`);
}

function validatePolicy(value) {
  validateStructure(value, validatePolicyStructure, "policy");

  const approvedHostedRunnerLabels = new Set(value.approvedHostedRunnerLabels);
  const forbiddenHostedRunnerLabels = new Set(
    value.forbiddenHostedRunnerLabels.map((label) => label.toLowerCase()),
  );
  const knownGitHubHostedRunnerLabels = new Set([
    ...value.approvedHostedRunnerLabels.map((label) => label.toLowerCase()),
    ...forbiddenHostedRunnerLabels,
  ]);

  const managedLabelRegexes = value.managedLabelPatterns.map((pattern, index) => {
    try {
      return new RegExp(pattern, "i");
    } catch (error) {
      throw new ConfigurationError(
        `policy.managedLabelPatterns[${index}] is not a valid regular expression: ${error.message}`,
      );
    }
  });

  const selectorWorkflowPaths = new Set(value.selectorWorkflowPaths);
  const validateSelectorReference = (reference, location) => {
    const parsed = parseReusableWorkflowReference(reference);
    if (!parsed || !selectorWorkflowPaths.has(parsed.workflow) || !FULL_SHA.test(parsed.revision)) {
      throw new ConfigurationError(
        `${location} entry ${JSON.stringify(reference)} must be an approved selector path pinned to a full 40-character SHA`,
      );
    }
  };
  for (const reference of value.approvedSelectorReferences) {
    validateSelectorReference(reference, "policy.approvedSelectorReferences");
  }

  const globallyApprovedSelectorReferences = new Set(value.approvedSelectorReferences);
  const approvedSelectorReferencesByRepositoryOwner = new Map();
  const scopedSelectorOwnersByReference = new Map();
  for (const [owner, references] of Object.entries(
    value.approvedSelectorReferencesByRepositoryOwner,
  )) {
    for (const reference of references) {
      validateSelectorReference(
        reference,
        `policy.approvedSelectorReferencesByRepositoryOwner.${owner}`,
      );
      if (globallyApprovedSelectorReferences.has(reference)) {
        throw new ConfigurationError(
          `selector reference ${JSON.stringify(reference)} cannot be both globally and owner-scoped approved`,
        );
      }
      const owners = scopedSelectorOwnersByReference.get(reference) ?? new Set();
      owners.add(owner);
      scopedSelectorOwnersByReference.set(reference, owners);
    }
    approvedSelectorReferencesByRepositoryOwner.set(owner, new Set(references));
  }

  const approvedReusableWorkflowContracts = new Map();
  for (const [reference, contract] of Object.entries(value.approvedReusableWorkflowContracts)) {
    const parsed = parseReusableWorkflowReference(reference);
    if (
      !parsed ||
      !REUSABLE_WORKFLOW_PATH.test(parsed.workflow) ||
      !FULL_SHA.test(parsed.revision) ||
      selectorWorkflowPaths.has(parsed.workflow)
    ) {
      throw new ConfigurationError(
        `policy.approvedReusableWorkflowContracts key ${JSON.stringify(reference)} must be a non-selector reusable workflow path pinned to a full 40-character SHA`,
      );
    }
    if (contract.routing === "runner-input") {
      if (!contract.allowedInputs.includes(contract.runnerInput)) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.allowedInputs must include ${contract.runnerInput}`,
        );
      }
      if (Object.hasOwn(contract, "selectorResultInput")) {
        if (contract.selectorResultInput === contract.runnerInput) {
          throw new ConfigurationError(
            `reusable workflow contract ${reference}.selectorResultInput must be a canonical input name distinct from runnerInput`,
          );
        }
        if (!contract.allowedInputs.includes(contract.selectorResultInput)) {
          throw new ConfigurationError(
            `reusable workflow contract ${reference}.allowedInputs must include ${contract.selectorResultInput}`,
          );
        }
      }
    } else {
      const unknownLabel = contract.fixedRunsOn.find(
        (label) => !knownGitHubHostedRunnerLabels.has(label.toLowerCase()),
      );
      if (unknownLabel) {
        throw new ConfigurationError(
          `hosted-only reusable workflow contract ${reference}.fixedRunsOn contains unrecognized GitHub-hosted label ${unknownLabel}`,
        );
      }
    }
    approvedReusableWorkflowContracts.set(reference, {
      routing: contract.routing,
      ...(contract.runnerInput ? { runnerInput: contract.runnerInput } : {}),
      ...(contract.selectorResultInput
        ? { selectorResultInput: contract.selectorResultInput }
        : {}),
      allowedInputs: new Set(contract.allowedInputs),
      allowedSecrets: contract.allowedSecrets,
      allowedSecretNames: new Set(Object.keys(contract.allowedSecrets)),
      ...(contract.fixedRunsOn ? { fixedRunsOn: new Set(contract.fixedRunsOn) } : {}),
    });
  }

  const canonicalInputNames = new Set(Object.keys(value.canonicalSelectorInputs));
  for (const name of Object.keys(value.optionalCanonicalSelectorInputs)) {
    if (canonicalInputNames.has(name)) {
      throw new ConfigurationError(
        `policy optional selector input ${name} duplicates a required canonical input`,
      );
    }
  }

  if (!approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.default)) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.default must be an approved hosted runner label",
    );
  }
  if (
    approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.failureSentinel) ||
    forbiddenHostedRunnerLabels.has(
      value.governedReusableRunnerInput.failureSentinel.toLowerCase(),
    ) ||
    managedLabelRegexes.some((pattern) =>
      pattern.test(value.governedReusableRunnerInput.failureSentinel),
    )
  ) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.failureSentinel must remain outside every hosted and managed runner label set",
    );
  }
  const hostedMatrixAxes = new Map();
  for (const expression of value.hostedMatrixExpressions) {
    const match = MATRIX_OUTPUT.exec(expression);
    hostedMatrixAxes.set(match[1], expression);
  }

  return {
    ...value,
    selectorWorkflowPaths,
    approvedSelectorReferences: new Set(value.approvedSelectorReferences),
    approvedSelectorReferencesByRepositoryOwner,
    scopedSelectorOwnersByReference,
    approvedReusableWorkflowContracts,
    canonicalSelectorInputNames: new Set([
      ...Object.keys(value.canonicalSelectorInputs),
      ...Object.keys(value.optionalCanonicalSelectorInputs),
    ]),
    canonicalSelectorSecretNames: new Set(Object.keys(value.canonicalSelectorSecrets)),
    approvedHostedRunnerLabels,
    hostedMatrixAxes,
    forbiddenHostedRunnerLabels,
    hostedExceptionReasons: new Set(value.hostedExceptionReasons),
    localCredentialActions: new Set(value.localCredentialActions),
    managedLabelRegexes,
  };
}

function validateRepositoryConfig(value, policy) {
  validateStructure(value, validateRepositoryPolicyStructure, "repository config");

  const exceptions = new Map();
  for (const [key, exception] of Object.entries(value.exceptions)) {
    if (!policy.hostedExceptionReasons.has(exception.reason)) {
      throw new ConfigurationError(
        `exception ${key} reason must be one of: ${[...policy.hostedExceptionReasons].join(", ")}`,
      );
    }
    exceptions.set(key, exception);
  }

  return { ...value, exceptions };
}

async function readJson(filePath, location) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    throw new ConfigurationError(`${location} could not be read at ${filePath}: ${error.message}`);
  }
  return parseUniqueJson(source, `${location} at ${filePath}`);
}

function parseWorkflow(source, file) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new Error(document.errors.map((error) => error.message).join("; "));
  }
  const workflow = document.toJS({ maxAliasCount: 0 });
  if (workflow === null || typeof workflow !== "object" || Array.isArray(workflow)) {
    throw new Error(`${file} must contain a workflow mapping`);
  }
  if (workflow.jobs === null || typeof workflow.jobs !== "object" || Array.isArray(workflow.jobs)) {
    throw new Error(`${file} must contain a jobs mapping`);
  }
  return workflow;
}

function stringsIn(value) {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap(stringsIn);
  }
  if (value !== null && typeof value === "object") {
    return Object.values(value).flatMap(stringsIn);
  }
  return [];
}

function normalizeNeeds(value) {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value) && value.every((item) => typeof item === "string")) {
    return value;
  }
  return [];
}

function parseReusableWorkflowReference(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  const separator = value.lastIndexOf("@");
  if (separator < 1) {
    return undefined;
  }
  return { workflow: value.slice(0, separator), revision: value.slice(separator + 1) };
}

function parseLocalReusableWorkflowReference(value) {
  if (typeof value !== "string" || !value.startsWith("./")) {
    return { attempted: false };
  }
  const match = LOCAL_REUSABLE_WORKFLOW.exec(value);
  if (!match) {
    return {
      attempted: true,
      reason:
        "repository-local reusable workflows must use the exact path ./.github/workflows/<file>.yml without traversal or subdirectories",
    };
  }
  return { attempted: true, file: `.github/workflows/${match[1]}` };
}

function workflowCallDeclaration(workflow) {
  if (workflow.on === "workflow_call") {
    return {};
  }
  if (Array.isArray(workflow.on)) {
    return workflow.on.includes("workflow_call") ? {} : undefined;
  }
  if (
    workflow.on === null ||
    typeof workflow.on !== "object" ||
    !Object.hasOwn(workflow.on, "workflow_call")
  ) {
    return undefined;
  }
  const declaration = workflow.on.workflow_call;
  if (declaration === null) {
    return {};
  }
  if (typeof declaration !== "object" || Array.isArray(declaration)) {
    return {};
  }
  return declaration;
}

function isWorkflowCallExclusive(workflow) {
  if (workflow.on === "workflow_call") {
    return true;
  }
  if (Array.isArray(workflow.on)) {
    return workflow.on.length === 1 && workflow.on[0] === "workflow_call";
  }
  return (
    workflow.on !== null &&
    typeof workflow.on === "object" &&
    !Array.isArray(workflow.on) &&
    Object.keys(workflow.on).length === 1 &&
    Object.hasOwn(workflow.on, "workflow_call")
  );
}

function validateLocalCallMapping(job, calledWorkflow) {
  const declaration = workflowCallDeclaration(calledWorkflow);
  if (declaration === undefined) {
    return "the repository-local workflow does not declare on.workflow_call";
  }

  const declaredInputs = declaration.inputs ?? {};
  if (
    declaredInputs === null ||
    typeof declaredInputs !== "object" ||
    Array.isArray(declaredInputs)
  ) {
    return "the repository-local workflow has an invalid workflow_call.inputs mapping";
  }
  const inputs = job.with ?? {};
  if (inputs === null || typeof inputs !== "object" || Array.isArray(inputs)) {
    return "repository-local reusable workflow inputs must be an explicit mapping";
  }
  const extraInputs = Object.keys(inputs).filter((name) => !Object.hasOwn(declaredInputs, name));
  if (extraInputs.length > 0) {
    return `the repository-local reusable workflow call has undeclared inputs: ${extraInputs.join(", ")}`;
  }
  const missingInputs = Object.entries(declaredInputs)
    .filter(
      ([name, input]) =>
        input !== null &&
        typeof input === "object" &&
        !Array.isArray(input) &&
        input.required === true &&
        !Object.hasOwn(inputs, name),
    )
    .map(([name]) => name);
  if (missingInputs.length > 0) {
    return `the repository-local reusable workflow call omits required inputs: ${missingInputs.join(", ")}`;
  }

  if (job.secrets === "inherit") {
    return "repository-local reusable workflows must not use secrets: inherit";
  }
  const declaredSecrets = declaration.secrets ?? {};
  if (
    declaredSecrets === null ||
    typeof declaredSecrets !== "object" ||
    Array.isArray(declaredSecrets)
  ) {
    return "the repository-local workflow has an invalid workflow_call.secrets mapping";
  }
  const secrets = job.secrets ?? {};
  if (secrets === null || typeof secrets !== "object" || Array.isArray(secrets)) {
    return "repository-local reusable workflow secrets must be an explicit mapping";
  }
  const extraSecrets = Object.keys(secrets).filter((name) => !Object.hasOwn(declaredSecrets, name));
  if (extraSecrets.length > 0) {
    return `the repository-local reusable workflow call has undeclared secrets: ${extraSecrets.join(", ")}`;
  }
  const missingSecrets = Object.entries(declaredSecrets)
    .filter(
      ([name, secret]) =>
        secret !== null &&
        typeof secret === "object" &&
        !Array.isArray(secret) &&
        secret.required === true &&
        !Object.hasOwn(secrets, name),
    )
    .map(([name]) => name);
  if (missingSecrets.length > 0) {
    return `the repository-local reusable workflow call omits required secrets: ${missingSecrets.join(", ")}`;
  }
  return undefined;
}

function localCallReaches(startFile, soughtFile, workflowIndex, visited = new Set()) {
  if (startFile === soughtFile) {
    return true;
  }
  if (visited.has(startFile)) {
    return false;
  }
  visited.add(startFile);
  const record = workflowIndex.get(startFile);
  if (!record?.workflow) {
    return false;
  }
  for (const job of Object.values(record.workflow.jobs)) {
    const reference = parseLocalReusableWorkflowReference(job?.uses);
    if (reference.file && localCallReaches(reference.file, soughtFile, workflowIndex, visited)) {
      return true;
    }
  }
  return false;
}

function localWorkflowRoutingMode(record, policy, workflowIndex, visited = new Set()) {
  if (visited.has(record.file)) {
    return "internal-routing";
  }
  visited.add(record.file);
  let internalRouting = false;
  for (const job of Object.values(record.workflow.jobs)) {
    if (selectorStatus(job, policy).isSelector) {
      internalRouting = true;
      continue;
    }
    if (typeof job?.["runs-on"] === "string") {
      const runner = job["runs-on"];
      const route = RUNNER_OUTPUT.exec(runner);
      if (
        runner === policy.governedReusableRunnerInput.expression ||
        route !== null ||
        rawManagedLabel(runner, policy)
      ) {
        internalRouting = true;
      }
    }
    const external =
      typeof job?.uses === "string"
        ? policy.approvedReusableWorkflowContracts.get(job.uses)
        : undefined;
    if (external?.routing === "runner-input") {
      internalRouting = true;
    }
    const local = parseLocalReusableWorkflowReference(job?.uses);
    if (local.file) {
      const nested = workflowIndex.get(local.file);
      if (!nested?.workflow) {
        internalRouting = true;
      } else if (localWorkflowRoutingMode(nested, policy, workflowIndex, visited) !== "hosted") {
        internalRouting = true;
      }
    }
  }
  visited.delete(record.file);

  const runnerDeclaration =
    record.workflow.on?.workflow_call?.inputs?.[policy.governedReusableRunnerInput.name];
  if (runnerDeclaration !== undefined && internalRouting) {
    const status = governedReusableRunnerStatus(record.workflow, policy);
    return status.approved ? "runner-input" : "invalid-runner-input";
  }
  return internalRouting ? "internal-routing" : "hosted";
}

function localReusableWorkflowStatus(callerFile, job, policy, workflowIndex) {
  const reference = parseLocalReusableWorkflowReference(job?.uses);
  if (!reference.attempted) {
    return { isLocal: false, approved: false };
  }
  if (!reference.file) {
    return { isLocal: true, approved: false, reason: reference.reason };
  }
  const record = workflowIndex.get(reference.file);
  if (!record) {
    return {
      isLocal: true,
      approved: false,
      reason: `repository-local reusable workflow ${reference.file} does not exist`,
    };
  }
  if (!record.workflow) {
    return {
      isLocal: true,
      approved: false,
      reason: `repository-local reusable workflow ${reference.file} is not a parsed regular workflow file`,
    };
  }
  if (localCallReaches(reference.file, callerFile, workflowIndex)) {
    return {
      isLocal: true,
      approved: false,
      reason: `repository-local reusable workflow call creates a recursion cycle through ${reference.file}`,
    };
  }
  const mappingError = validateLocalCallMapping(job, record.workflow);
  if (mappingError) {
    return { isLocal: true, approved: false, reason: mappingError };
  }
  const routing = localWorkflowRoutingMode(record, policy, workflowIndex);
  if (routing === "invalid-runner-input") {
    return {
      isLocal: true,
      approved: false,
      reason:
        "repository-local runner-input workflows must use workflow_call exclusively and declare either the governed optional runner default or a required runner with no default",
    };
  }
  const runnerInput =
    routing === "runner-input" ? governedReusableRunnerStatus(record.workflow, policy) : undefined;
  return {
    isLocal: true,
    approved: true,
    record,
    routing,
    ...(runnerInput?.mode ? { runnerInputMode: runnerInput.mode } : {}),
  };
}

function permissionCapability(workflow, job, inherited = "may-write") {
  const declaration = Object.hasOwn(job, "permissions")
    ? job.permissions
    : Object.hasOwn(workflow, "permissions")
      ? workflow.permissions
      : undefined;
  if (declaration === undefined) {
    return inherited;
  }
  const requestsOnlyRead =
    declaration === "read-all" ||
    (declaration !== null &&
      typeof declaration === "object" &&
      !Array.isArray(declaration) &&
      Object.values(declaration).every((access) => access === "read" || access === "none"));
  if (requestsOnlyRead || inherited === "read-only") {
    return "read-only";
  }
  return "may-write";
}

function auditLocalPermissionFlow({
  localStatus,
  inherited,
  policy,
  workflowIndex,
  config,
  consumedExceptions,
  visited,
}) {
  const record = localStatus.record;
  const visitKey = `${record.file}\0${inherited}`;
  if (visited.has(visitKey)) {
    return [];
  }
  visited.add(visitKey);
  const findings = [];
  for (const [jobId, job] of Object.entries(record.workflow.jobs)) {
    if (job === null || typeof job !== "object" || Array.isArray(job)) {
      continue;
    }
    const capability = permissionCapability(record.workflow, job, inherited);
    const nested = localReusableWorkflowStatus(record.file, job, policy, workflowIndex);
    if (nested.approved) {
      findings.push(
        ...auditLocalPermissionFlow({
          localStatus: nested,
          inherited: capability,
          policy,
          workflowIndex,
          config,
          consumedExceptions,
          visited,
        }),
      );
      continue;
    }

    const selector = selectorStatus(job, policy);
    const target = selector.isSelector
      ? undefined
      : runnerTargetStatus(
          jobId,
          job,
          record.workflow.jobs,
          record.workflow,
          policy,
          record.file,
          workflowIndex,
        );
    const localExecution =
      target?.kind === "selector-output" ||
      target?.kind === "reusable-input" ||
      target?.kind === "transparent-local-reusable";
    if (localExecution && capability !== "read-only") {
      findings.push(
        finding(
          "local-reusable-permissions",
          record.file,
          jobId,
          "a locally routable called job can inherit write-capable caller permissions; declare an explicit read-only job permission mapping",
        ),
      );
      continue;
    }

    const hostedExecution =
      selector.approved ||
      target?.kind === "hosted-literal" ||
      target?.kind === "hosted-matrix" ||
      target?.kind === "hosted-reusable" ||
      target?.kind === "hosted-local-reusable";
    if (hostedExecution && capability !== "read-only") {
      const key = `${record.file}#${jobId}`;
      const exception = config.exceptions.get(key);
      if (!exception) {
        findings.push(
          finding(
            "hosted-exception-required",
            record.file,
            jobId,
            "a fixed-hosted called job inherits write-capable caller permissions and requires a privileged-control-plane exception",
          ),
        );
      } else {
        consumedExceptions.add(key);
        if (exception.reason !== "privileged-control-plane") {
          findings.push(
            finding(
              "hosted-exception-category",
              record.file,
              jobId,
              `inherited write-capable caller permissions require exception reason privileged-control-plane, not ${exception.reason}`,
            ),
          );
        }
      }
    }
  }
  return findings;
}

function exactCanonicalMap(actual, required, optional, allowedNames, location) {
  if (actual === null || typeof actual !== "object" || Array.isArray(actual)) {
    return `${location} must be an explicit mapping`;
  }
  const actualNames = Object.keys(actual);
  const unexpected = actualNames.filter((name) => !allowedNames.has(name));
  if (unexpected.length > 0) {
    return `${location} has unapproved properties: ${unexpected.join(", ")}`;
  }
  for (const [name, expected] of Object.entries(required)) {
    if (actual[name] !== expected) {
      return `${location}.${name} must be exactly ${JSON.stringify(expected)}`;
    }
  }
  for (const [name, expected] of Object.entries(optional)) {
    if (Object.hasOwn(actual, name) && actual[name] !== expected) {
      return `${location}.${name} must be exactly ${JSON.stringify(expected)}`;
    }
  }
  return undefined;
}

function selectorStatus(job, policy) {
  const reference = parseReusableWorkflowReference(job?.uses);
  if (!reference || !policy.selectorWorkflowPaths.has(reference.workflow)) {
    return { isSelector: false, approved: false };
  }
  if (!FULL_SHA.test(reference.revision)) {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector reusable workflow must be pinned to a full 40-character SHA",
    };
  }
  if (!policy.approvedSelectorReferences.has(job.uses)) {
    const scopedOwners = policy.scopedSelectorOwnersByReference.get(job.uses);
    if (scopedOwners) {
      return {
        approved: false,
        isSelector: true,
        reason: policy.repositoryOwner
          ? `the selector path@SHA is not approved for repository owner ${policy.repositoryOwner}`
          : "the selector path@SHA is owner-scoped, but trustworthy repository owner evidence is unavailable",
      };
    }
    return {
      approved: false,
      isSelector: true,
      reason:
        policy.approvedSelectorReferences.size === 0
          ? "no reviewed selector path@SHA is currently approved"
          : "the selector path@SHA is not in the reviewed approval allowlist",
    };
  }
  if (job.secrets === "inherit") {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector must not use secrets: inherit",
    };
  }
  if (job.secrets === null || typeof job.secrets !== "object" || Array.isArray(job.secrets)) {
    return {
      approved: false,
      isSelector: true,
      reason: "the selector must receive an explicit observer-private-key secret",
    };
  }
  const secretError = exactCanonicalMap(
    job.secrets,
    policy.canonicalSelectorSecrets,
    {},
    policy.canonicalSelectorSecretNames,
    "selector secrets",
  );
  if (secretError) {
    return {
      approved: false,
      isSelector: true,
      reason: secretError,
    };
  }
  const inputError = exactCanonicalMap(
    job.with,
    policy.canonicalSelectorInputs,
    policy.optionalCanonicalSelectorInputs,
    policy.canonicalSelectorInputNames,
    "selector inputs",
  );
  if (inputError) {
    return {
      approved: false,
      isSelector: true,
      reason: inputError,
    };
  }
  return { approved: true, isSelector: true };
}

function reusableWorkflowStatus(job, policy) {
  if (typeof job?.uses !== "string") {
    return { isReusable: false, approved: false };
  }
  const contract = policy.approvedReusableWorkflowContracts.get(job.uses);
  if (!contract) {
    return {
      isReusable: true,
      approved: false,
      reason: "the reusable workflow path@SHA has no reviewed runner-input contract",
    };
  }
  if (job.secrets === "inherit") {
    return {
      isReusable: true,
      approved: false,
      reason: "reviewed reusable workflows must not use secrets: inherit",
    };
  }
  const secrets = job.secrets === undefined ? {} : job.secrets;
  const secretError = exactCanonicalMap(
    secrets,
    contract.allowedSecrets,
    {},
    contract.allowedSecretNames,
    "reusable workflow secrets",
  );
  if (secretError) {
    return { isReusable: true, approved: false, reason: secretError };
  }
  const inputs = job.with === undefined ? {} : job.with;
  if (inputs === null || typeof inputs !== "object" || Array.isArray(inputs)) {
    return {
      isReusable: true,
      approved: false,
      reason: "the reviewed reusable workflow inputs must be an explicit mapping",
    };
  }
  const unexpected = Object.keys(inputs).filter((name) => !contract.allowedInputs.has(name));
  if (unexpected.length > 0) {
    return {
      isReusable: true,
      approved: false,
      reason: `the reusable workflow call has inputs absent from its reviewed contract: ${unexpected.join(", ")}`,
    };
  }
  if (contract.routing === "hosted-only") {
    return { isReusable: true, approved: true, contract };
  }
  if (!Object.hasOwn(inputs, contract.runnerInput)) {
    return {
      isReusable: true,
      approved: false,
      reason: `the reviewed reusable workflow must receive its ${contract.runnerInput} input explicitly`,
    };
  }
  return { isReusable: true, approved: true, contract };
}

function normalizedConditionExpression(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.replace(/\s+/g, " ").trim();
  const wrapper = /^\$\{\{ (.*) }}$/.exec(normalized);
  return wrapper?.[1];
}

function selfHostedSelectorConditionStatus(job, selectorId) {
  const cancellation = cancellationSafeConditionStatus(job.if);
  if (!cancellation.approved) {
    return cancellation;
  }
  const expression = normalizedConditionExpression(job.if);
  const suffix = [
    `needs.${selectorId}.result == 'success'`,
    `needs.${selectorId}.outputs.route == 'self-hosted'`,
    `needs.${selectorId}.outputs.runner != ''`,
    `needs.${selectorId}.outputs.runner == vars.CI_SELF_HOSTED_LABEL`,
  ].join(" && ");
  if (expression !== `!cancelled() && ${suffix}` && !expression?.endsWith(` && ${suffix}`)) {
    return {
      approved: false,
      reason:
        "required local runner inputs must be guarded by selector success, the exact self-hosted route, a nonempty runner, and the governed self-hosted label",
    };
  }
  return { approved: true };
}

function unroutableFailureStatus(jobId, target, job, jobs, policy) {
  if (target !== policy.governedReusableRunnerInput.failureSentinel) {
    return undefined;
  }
  const prerequisites = normalizeNeeds(job.needs);
  if (prerequisites.length !== 1) {
    return {
      approved: false,
      reason: `${jobId} must declare exactly one selector job in needs to use the unroutable failure sentinel`,
    };
  }
  const [selectorId] = prerequisites;
  const selector = jobs[selectorId];
  const selectorResult = selectorStatus(selector, policy);
  if (!selectorResult.isSelector || !selectorResult.approved) {
    return {
      approved: false,
      reason: selectorResult.reason ?? `${selectorId} does not call an approved selector workflow`,
    };
  }
  const expectedCondition =
    `!cancelled() && (needs.${selectorId}.result != 'success' || ` +
    `!(needs.${selectorId}.outputs.route == 'self-hosted' && ` +
    `needs.${selectorId}.outputs.runner != '' && ` +
    `needs.${selectorId}.outputs.runner == vars.CI_SELF_HOSTED_LABEL))`;
  if (normalizedConditionExpression(job.if) !== expectedCondition) {
    return {
      approved: false,
      reason:
        "the unroutable failure sentinel requires the exact complement of a successful governed self-hosted selector route",
    };
  }
  const allowedJobKeys = new Set([
    "name",
    "needs",
    "if",
    "runs-on",
    "timeout-minutes",
    "permissions",
    "steps",
  ]);
  const extraJobKeys = Object.keys(job).filter((key) => !allowedJobKeys.has(key));
  if (extraJobKeys.length > 0) {
    return {
      approved: false,
      reason: `the unroutable failure sentinel job has forbidden keys: ${extraJobKeys.join(", ")}`,
    };
  }
  if (
    job["timeout-minutes"] !== 1 ||
    job.permissions === null ||
    typeof job.permissions !== "object" ||
    Array.isArray(job.permissions) ||
    Object.keys(job.permissions).length !== 0
  ) {
    return {
      approved: false,
      reason: "the unroutable failure sentinel job requires timeout-minutes: 1 and permissions: {}",
    };
  }
  if (!Array.isArray(job.steps) || job.steps.length !== 1) {
    return {
      approved: false,
      reason: "the unroutable failure sentinel job requires exactly one rejecting shell step",
    };
  }
  const [step] = job.steps;
  const stepKeys =
    step !== null && typeof step === "object" && !Array.isArray(step) ? Object.keys(step) : [];
  const lines = typeof step?.run === "string" ? step.run.trim().split(/\r?\n/) : [];
  if (
    stepKeys.some((key) => key !== "name" && key !== "run") ||
    typeof step?.name !== "string" ||
    step.name.trim() === "" ||
    lines.length !== 2 ||
    !/^echo "::error::[A-Za-z0-9][A-Za-z0-9 .:_-]*"$/.test(lines[0].trim()) ||
    lines[1].trim() !== "exit 1"
  ) {
    return {
      approved: false,
      reason:
        "the unroutable failure sentinel step must only emit a static error annotation and exit 1",
    };
  }
  return { approved: true, selectorId };
}

function routeStatus(jobId, target, job, jobs, policy, reusableContract, localRunnerInputMode) {
  const fallbackMatch = RUNNER_OUTPUT.exec(target);
  const requiredMatch = REQUIRED_RUNNER_OUTPUT.exec(target);
  const configuredDefault = policy.governedReusableRunnerInput.default;
  const usesOptionalDefault =
    fallbackMatch !== null && fallbackMatch.groups.fallback === configuredDefault;
  const usesRequiredInput = requiredMatch !== null && localRunnerInputMode === "required";
  if (!usesOptionalDefault && !usesRequiredInput) {
    return {
      attempted: target.includes("outputs.runner"),
      approved: false,
      reason: `runner routing must use exactly needs.<selector-job>.outputs.runner || '${configuredDefault}', or a raw selector output passed to a required no-default repository-local runner input`,
    };
  }

  const selectorId = (fallbackMatch ?? requiredMatch).groups.selectorId;
  if (!normalizeNeeds(job.needs).includes(selectorId)) {
    return {
      attempted: true,
      approved: false,
      reason: `${jobId} must declare ${selectorId} in needs`,
    };
  }
  const selector = jobs[selectorId];
  if (selector === null || typeof selector !== "object" || Array.isArray(selector)) {
    return { attempted: true, approved: false, reason: `${selectorId} is not a workflow job` };
  }
  const status = selectorStatus(selector, policy);
  if (!status.isSelector) {
    return {
      attempted: true,
      approved: false,
      reason: `${selectorId} does not call an approved selector workflow`,
    };
  }
  if (!status.approved) {
    return { attempted: true, approved: false, reason: status.reason };
  }
  const condition = usesRequiredInput
    ? selfHostedSelectorConditionStatus(job, selectorId)
    : reusableContract?.selectorResultInput
      ? failClosedSelectorConditionStatus(job, selectorId, reusableContract.selectorResultInput)
      : cancellationSafeConditionStatus(job.if);
  if (!condition.approved) {
    return { attempted: true, approved: false, reason: condition.reason };
  }
  return {
    attempted: true,
    approved: true,
    selectorId,
    mode: usesRequiredInput ? "required-no-default" : "optional-default",
  };
}

function failClosedSelectorConditionStatus(job, selectorId, selectorResultInput) {
  const prerequisites = normalizeNeeds(job.needs);
  if (prerequisites.length !== 1 || prerequisites[0] !== selectorId) {
    return {
      approved: false,
      reason: `fail-closed selector-result reporters must declare exactly needs: ${selectorId} so the reported result covers every prerequisite`,
    };
  }
  const alwaysCondition = `\${{ always() }}`;
  if (job.if !== alwaysCondition) {
    return {
      approved: false,
      reason: `fail-closed selector-result reporters must declare exactly if: ${alwaysCondition} so every prerequisite outcome materializes the required check`,
    };
  }
  const expectedResult = `\${{ needs.${selectorId}.result }}`;
  if (job.with?.[selectorResultInput] !== expectedResult) {
    return {
      approved: false,
      reason: `fail-closed selector-result reporters must pass ${selectorResultInput}: ${expectedResult}`,
    };
  }
  return { approved: true };
}

function cancellationSafeConditionStatus(value) {
  if (typeof value !== "string") {
    return {
      approved: false,
      reason: `selector-routed jobs must declare if: \${{ !cancelled() }} so selector failure falls back without overriding cancellation`,
    };
  }
  const wrapper = /^\s*\$\{\{([\s\S]*)}}\s*$/.exec(value);
  if (!wrapper) {
    return {
      approved: false,
      reason: `selector-routed job conditions must use the exact \${{ !cancelled() }} expression contract`,
    };
  }
  const expression = wrapper[1].trim();
  if (expression === "!cancelled()") {
    return { approved: true };
  }
  const prefix = "!cancelled()";
  if (!expression.startsWith(prefix)) {
    return {
      approved: false,
      reason:
        "selector-routed job conditions must begin with !cancelled() as the first top-level conjunction",
    };
  }
  const remainder = expression.slice(prefix.length).trim();
  if (!remainder.startsWith("&&") || remainder.slice(2).trim() === "") {
    return {
      approved: false,
      reason:
        "selector-routed job conditions must be !cancelled() or combine an existing condition with top-level &&",
    };
  }

  let depth = 0;
  let quote;
  for (let index = 2; index < remainder.length; index += 1) {
    const character = remainder[index];
    if (quote) {
      if (character === quote) {
        if (remainder[index + 1] === quote) {
          index += 1;
        } else {
          quote = undefined;
        }
      }
      continue;
    }
    if (character === "'" || character === '"') {
      quote = character;
      continue;
    }
    if (character === "(") {
      depth += 1;
      continue;
    }
    if (character === ")") {
      depth -= 1;
      if (depth < 0) {
        return {
          approved: false,
          reason: "selector-routed job condition has unbalanced parentheses",
        };
      }
      continue;
    }
    if (depth === 0 && remainder.slice(index, index + 2) === "||") {
      return {
        approved: false,
        reason:
          "selector-routed job conditions cannot use top-level || because cancellation could start the workload",
      };
    }
  }
  if (quote || depth !== 0) {
    return {
      approved: false,
      reason: "selector-routed job condition has an unbalanced quoted string or parentheses",
    };
  }
  return { approved: true };
}

function governedReusableRunnerStatus(workflow, policy) {
  const contract = policy.governedReusableRunnerInput;
  if (
    workflow.on === null ||
    typeof workflow.on !== "object" ||
    Array.isArray(workflow.on) ||
    Object.keys(workflow.on).length !== 1 ||
    !Object.hasOwn(workflow.on, "workflow_call")
  ) {
    return {
      approved: false,
      reason: `${contract.expression} is allowed only when workflow_call is the exclusive trigger`,
    };
  }
  const workflowCall = workflow.on?.workflow_call;
  const declaration = workflowCall?.inputs?.[contract.name];
  if (declaration === null || typeof declaration !== "object" || Array.isArray(declaration)) {
    return {
      approved: false,
      reason: `${contract.expression} requires on.workflow_call.inputs.${contract.name}`,
    };
  }
  const optionalDefault =
    declaration.type === "string" &&
    declaration.default === contract.default &&
    (declaration.required === undefined || declaration.required === false);
  const requiredNoDefault =
    declaration.type === "string" &&
    declaration.required === true &&
    !Object.hasOwn(declaration, "default");
  if (!optionalDefault && !requiredNoDefault) {
    return {
      approved: false,
      reason: `on.workflow_call.inputs.${contract.name} must be either an optional string defaulting to ${contract.default} or a required string with no default`,
    };
  }
  return { approved: true, mode: requiredNoDefault ? "required" : "optional-default" };
}

function hostedMatrixStatus(job, target, policy) {
  const match = MATRIX_OUTPUT.exec(target);
  if (!match) {
    return undefined;
  }
  const axis = match[1];
  if (!policy.hostedMatrixAxes.has(axis)) {
    return {
      approved: false,
      reason: `${target} is not an approved hosted-runner matrix expression`,
    };
  }
  const matrix = job.strategy?.matrix;
  if (matrix === null || typeof matrix !== "object" || Array.isArray(matrix)) {
    return { approved: false, reason: `${target} requires a static strategy.matrix mapping` };
  }
  if (Object.hasOwn(matrix, "include") || Object.hasOwn(matrix, "exclude")) {
    return {
      approved: false,
      reason: `${target} cannot be proven hosted when matrix include/exclude is present`,
    };
  }
  const values = matrix[axis];
  if (
    !Array.isArray(values) ||
    values.length === 0 ||
    values.some(
      (value) => typeof value !== "string" || !policy.approvedHostedRunnerLabels.has(value),
    )
  ) {
    return {
      approved: false,
      reason: `${target} must resolve only from the approved hosted-runner label allowlist`,
    };
  }
  return { approved: true };
}

function runnerTargetStatus(jobId, job, jobs, workflow, policy, file, workflowIndex) {
  const local = localReusableWorkflowStatus(file, job, policy, workflowIndex);
  if (local.isLocal && !local.approved) {
    return { approved: false, kind: "invalid", reason: local.reason };
  }
  if (local.approved && local.routing === "hosted") {
    return { approved: true, kind: "hosted-local-reusable" };
  }
  if (local.approved && local.routing === "internal-routing") {
    return { approved: true, kind: "transparent-local-reusable" };
  }
  const reusable = reusableWorkflowStatus(job, policy);
  if (!local.approved && reusable.isReusable && !reusable.approved) {
    return { approved: false, kind: "invalid", reason: reusable.reason };
  }
  if (
    !local.approved &&
    reusable.approved &&
    reusable.contract.selectorResultInput &&
    workflowCallDeclaration(workflow) !== undefined
  ) {
    return {
      approved: false,
      kind: "invalid",
      reason:
        "repository-local reusable workflows cannot wrap a selector-result reporting contract; the selector-owning workflow must call that reviewed contract directly",
    };
  }
  if (!local.approved && reusable.approved && reusable.contract.routing === "hosted-only") {
    return { approved: true, kind: "hosted-reusable" };
  }
  const target = local.approved
    ? job.with[policy.governedReusableRunnerInput.name]
    : reusable.approved
      ? job.with[reusable.contract.runnerInput]
      : job?.["runs-on"];
  if (typeof target !== "string") {
    return {
      approved: false,
      kind: "invalid",
      reason: "runs-on (or a reusable workflow runner input) must be a governed string target",
    };
  }

  const unroutableFailure = unroutableFailureStatus(jobId, target, job, jobs, policy);
  if (unroutableFailure) {
    return {
      approved: unroutableFailure.approved,
      kind: unroutableFailure.approved ? "unroutable-failure" : "invalid",
      route: { attempted: true, selectorId: unroutableFailure.selectorId },
      ...(unroutableFailure.reason ? { reason: unroutableFailure.reason } : {}),
    };
  }

  const route = routeStatus(
    jobId,
    target,
    job,
    jobs,
    policy,
    !local.approved && reusable.approved ? reusable.contract : undefined,
    local.approved ? local.runnerInputMode : undefined,
  );
  if (route.approved) {
    return { approved: true, kind: "selector-output", route };
  }
  if (route.attempted) {
    return { approved: false, kind: "invalid", reason: route.reason, route };
  }

  if (target === policy.governedReusableRunnerInput.expression) {
    const status = governedReusableRunnerStatus(workflow, policy);
    return {
      approved: status.approved,
      kind: status.approved ? "reusable-input" : "invalid",
      ...(status.reason ? { reason: status.reason } : {}),
    };
  }

  const matrix = hostedMatrixStatus(job, target, policy);
  if (matrix) {
    return {
      approved: matrix.approved,
      kind: matrix.approved ? "hosted-matrix" : "invalid",
      ...(matrix.reason ? { reason: matrix.reason } : {}),
    };
  }

  if (target.includes("${{") || target.includes("}}")) {
    return {
      approved: false,
      kind: "invalid",
      reason: `runner expression ${JSON.stringify(target)} is not an approved routing contract`,
    };
  }
  if (policy.approvedHostedRunnerLabels.has(target)) {
    return { approved: true, kind: "hosted-literal" };
  }
  return {
    approved: false,
    kind: "invalid",
    reason: `runner target ${JSON.stringify(target)} is not in the approved hosted-runner label allowlist`,
  };
}

function rawRunnerStrings(job, includeReusableInputs) {
  return stringsIn({
    matrix: job?.strategy?.matrix,
    reusableInputs: includeReusableInputs ? job?.with : undefined,
    runsOn: job?.["runs-on"],
  });
}

function rawManagedLabel(value, policy) {
  const trimmed = value.trim();
  if (trimmed.toLowerCase().includes("self-hosted")) {
    return true;
  }
  if (/CI_(?:SELF_HOSTED_LABEL|MANAGED_RUNNER)/i.test(trimmed)) {
    return true;
  }
  return policy.managedLabelRegexes.some((pattern) => pattern.test(trimmed));
}

function effectivePermissions(workflow, job) {
  return Object.hasOwn(job, "permissions") ? job.permissions : workflow.permissions;
}

function permissionHostedRequirement(workflow, job, { requireExplicitReadOnly = false } = {}) {
  const permissions = effectivePermissions(workflow, job);
  if (permissions === "write-all") {
    return {
      reason: "privileged-control-plane",
      description: "write-all GITHUB_TOKEN permissions",
      rule: "privileged-hosted-only",
    };
  }
  if (permissions === "read-all") {
    return undefined;
  }
  if (permissions === null || typeof permissions !== "object" || Array.isArray(permissions)) {
    if (requireExplicitReadOnly) {
      return {
        reason: "privileged-control-plane",
        description:
          permissions === undefined
            ? "omitted GITHUB_TOKEN permissions with repository/organization-defined defaults"
            : "GITHUB_TOKEN permissions that are not explicitly read-only",
        rule: "privileged-hosted-only",
      };
    }
    return undefined;
  }
  const writable = Object.entries(permissions)
    .filter(([, access]) => access === "write")
    .map(([scope]) => scope)
    .sort((left, right) => left.localeCompare(right));
  if (writable.length === 0) {
    if (requireExplicitReadOnly && !hasStaticallyReadOnlyPermissions(workflow, job)) {
      return {
        reason: "privileged-control-plane",
        description: "GITHUB_TOKEN permissions that are not explicitly read-only",
        rule: "privileged-hosted-only",
      };
    }
    return undefined;
  }
  return {
    reason: "privileged-control-plane",
    description: `write GITHUB_TOKEN permissions (${writable.join(", ")})`,
    rule: "privileged-hosted-only",
  };
}

function isExpressionWordCharacter(codeUnit) {
  return (
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    codeUnit === 95 ||
    (codeUnit >= 97 && codeUnit <= 122)
  );
}

function isExpressionPropertyNameStart(codeUnit) {
  return (
    (codeUnit >= 65 && codeUnit <= 90) || codeUnit === 95 || (codeUnit >= 97 && codeUnit <= 122)
  );
}

function skipExpressionWhitespace(value, cursor, end) {
  while (cursor < end && value[cursor].trim() === "") {
    cursor += 1;
  }
  return cursor;
}

function findExpressionEnd(value, cursor) {
  let quote;
  while (cursor < value.length) {
    const character = value[cursor];
    if (quote !== undefined) {
      if (character === quote) {
        if (value[cursor + 1] === quote) {
          cursor += 2;
          continue;
        }
        quote = undefined;
      }
      cursor += 1;
      continue;
    }
    if (character === "'" || character === '"') {
      quote = character;
      cursor += 1;
      continue;
    }
    if (character === "}" && value[cursor + 1] === "}") {
      return cursor;
    }
    cursor += 1;
  }
  return value.length;
}

function skipExpressionQuotedLiteral(value, cursor, end) {
  const quote = value[cursor];
  cursor += 1;
  while (cursor < end) {
    if (value[cursor] === quote) {
      if (value[cursor + 1] === quote) {
        cursor += 2;
        continue;
      }
      return cursor + 1;
    }
    cursor += 1;
  }
  return end;
}

function staticExpressionIndex(value, cursor, end) {
  cursor = skipExpressionWhitespace(value, cursor, end);
  if (value[cursor] !== "'") {
    return undefined;
  }
  cursor += 1;
  let literal = "";
  while (cursor < end) {
    if (value[cursor] === "'") {
      if (value[cursor + 1] === "'") {
        literal += "'";
        cursor += 2;
        continue;
      }
      cursor = skipExpressionWhitespace(value, cursor + 1, end);
      return value[cursor] === "]" ? literal : undefined;
    }
    literal += value[cursor];
    cursor += 1;
  }
  return undefined;
}

function expressionContainsCredentialReference(value, cursor, end) {
  let previousSignificant;
  while (cursor < end) {
    const character = value[cursor];
    if (character.trim() === "") {
      cursor += 1;
      continue;
    }
    if (character === "'" || character === '"') {
      cursor = skipExpressionQuotedLiteral(value, cursor, end);
      previousSignificant = character;
      continue;
    }

    const previousIsWord =
      previousSignificant !== undefined &&
      isExpressionWordCharacter(previousSignificant.charCodeAt(0));
    const previousIsPropertyDereference = previousSignificant === ".";
    const secretsEnd = cursor + "secrets".length;
    if (
      !previousIsWord &&
      !previousIsPropertyDereference &&
      secretsEnd <= end &&
      value.startsWith("secrets", cursor) &&
      (secretsEnd === end || !isExpressionWordCharacter(value.charCodeAt(secretsEnd)))
    ) {
      return true;
    }

    const githubEnd = cursor + "github".length;
    if (
      !previousIsWord &&
      !previousIsPropertyDereference &&
      githubEnd <= end &&
      value.startsWith("github", cursor) &&
      (githubEnd === end || !isExpressionWordCharacter(value.charCodeAt(githubEnd)))
    ) {
      let property = skipExpressionWhitespace(value, githubEnd, end);
      if (property < end && value[property] === ".") {
        property = skipExpressionWhitespace(value, property + 1, end);
        const propertyStart = property;
        if (!isExpressionPropertyNameStart(value.charCodeAt(property))) {
          return true;
        }
        while (
          property < end &&
          (isExpressionWordCharacter(value.charCodeAt(property)) || value[property] === "-")
        ) {
          property += 1;
        }
        if (property === propertyStart || value.slice(propertyStart, property) === "token") {
          return true;
        }
      } else if (property < end && value[property] === "[") {
        const index = staticExpressionIndex(value, property + 1, end);
        if (index === undefined || index === "token") {
          return true;
        }
      } else {
        return true;
      }
    }

    previousSignificant = character;
    cursor += 1;
  }
  return false;
}

function stringContainsCredentialExpression(value) {
  const normalized = value.toLowerCase();
  let cursor = 0;
  while (cursor < normalized.length) {
    const start = normalized.indexOf("${{", cursor);
    if (start === -1) {
      return false;
    }
    const expressionStart = start + "${{".length;
    const expressionEnd = findExpressionEnd(normalized, expressionStart);
    if (expressionContainsCredentialReference(normalized, expressionStart, expressionEnd)) {
      return true;
    }
    if (expressionEnd === normalized.length) {
      return false;
    }
    cursor = expressionEnd + "}}".length;
  }
  return false;
}

function containsCredentialExpression(value) {
  return stringsIn(value).some(stringContainsCredentialExpression);
}

function conditionContainsCredentialReference(value) {
  if (typeof value !== "string") {
    return false;
  }
  const normalized = value.toLowerCase();
  return expressionContainsCredentialReference(normalized, 0, normalized.length);
}

function hasStaticallyReadOnlyPermissions(workflow, job) {
  const permissions = effectivePermissions(workflow, job);
  if (permissions === "read-all") {
    return true;
  }
  if (permissions === null || typeof permissions !== "object" || Array.isArray(permissions)) {
    return false;
  }
  return Object.values(permissions).every((access) => access === "read" || access === "none");
}

function localCredentialRequirement(workflow, job) {
  if (containsCredentialExpression(workflow.env)) {
    return "a credential expression in workflow-level env";
  }
  const { steps, if: jobCondition, ...jobWithoutSteps } = job;
  if (conditionContainsCredentialReference(jobCondition)) {
    return "a credential expression in a job condition";
  }
  if (containsCredentialExpression(jobWithoutSteps)) {
    return "a credential expression outside a narrow step env/with value";
  }
  if (!Array.isArray(steps)) {
    return undefined;
  }
  const readOnly = hasStaticallyReadOnlyPermissions(workflow, job);
  for (const step of steps) {
    if (step === null || typeof step !== "object" || Array.isArray(step)) {
      continue;
    }
    const { env, if: stepCondition, with: inputs, ...stepWithoutCredentialMappings } = step;
    if (conditionContainsCredentialReference(stepCondition)) {
      return "a credential expression in a step condition";
    }
    if (containsCredentialExpression(stepWithoutCredentialMappings)) {
      return "a credential expression outside a narrow step env/with value";
    }
    for (const mapping of [env, inputs]) {
      if (mapping === null || typeof mapping !== "object" || Array.isArray(mapping)) {
        if (containsCredentialExpression(mapping)) {
          return "a transformed or indirect credential expression";
        }
        continue;
      }
      for (const value of Object.values(mapping)) {
        if (!containsCredentialExpression(value)) {
          continue;
        }
        if (typeof value === "string" && EXACT_GITHUB_TOKEN_EXPRESSIONS.has(value) && readOnly) {
          continue;
        }
        return EXACT_GITHUB_TOKEN_EXPRESSIONS.has(value)
          ? "GitHub-provided token use without statically read-only permissions"
          : "an unapproved or transformed credential expression";
      }
    }
  }
  return undefined;
}

function credentialAction(job, policy) {
  if (!Array.isArray(job.steps)) {
    return undefined;
  }
  for (const step of job.steps) {
    if (step === null || typeof step !== "object" || Array.isArray(step)) {
      continue;
    }
    if (typeof step.uses !== "string") {
      continue;
    }
    const action = step.uses.split("@", 1)[0].toLowerCase();
    if (policy.localCredentialActions.has(action)) {
      return action;
    }
  }
  return undefined;
}

function privilegedHostedRequirement(workflow, job, selector, target, policy, localCall) {
  const permissionRequirement = localCall?.approved
    ? undefined
    : permissionHostedRequirement(workflow, job, {
        requireExplicitReadOnly: target?.kind === "selector-output",
      });
  if (permissionRequirement) {
    return permissionRequirement;
  }

  // The selector's one exact observer secret is part of its reviewed hosted
  // reusable-workflow contract. Exact hosted-only reusable secret mappings are
  // likewise governed by approvedReusableWorkflowContracts rather than this
  // local-workload boundary.
  if (selector.isSelector || target?.kind === "hosted-reusable") {
    return undefined;
  }

  if (Object.hasOwn(job, "environment")) {
    return {
      reason: "privileged-control-plane",
      description: "a deployment environment",
      rule: "privileged-hosted-only",
    };
  }

  const credentialRequirement = localCredentialRequirement(workflow, job);
  if (credentialRequirement) {
    return {
      reason: "privileged-control-plane",
      description: credentialRequirement,
      rule: "privileged-hosted-only",
    };
  }

  const action = credentialAction(job, policy);
  if (action) {
    return {
      reason: "privileged-control-plane",
      description: `credential-minting action ${action}`,
      rule: "privileged-hosted-only",
    };
  }

  return undefined;
}

function structuralHostedRequirement(job) {
  const hasJobContainer = Object.hasOwn(job, "container");
  const hasServices = Object.hasOwn(job, "services");
  if (!hasJobContainer && !hasServices) {
    return undefined;
  }
  if (hasJobContainer) {
    return {
      reason: "job-container",
      description: hasServices ? "job container and services" : "job container",
      rule: "structural-hosted-only",
    };
  }
  return {
    reason: "service-container",
    description: "services",
    rule: "structural-hosted-only",
  };
}

function finding(rule, file, job, message) {
  return { rule, file, ...(job ? { job } : {}), message };
}

const COMMENT_HEX_TOKENS = /(?<=^|[^0-9a-f])[0-9a-f]{7,40}(?=[^0-9a-f]|$)/giu;

// A hex run reads as a short-SHA claim only when it mixes digits and letters
// (or is a full 40-character SHA): all-letter runs are ordinary English words
// ("acceded") and all-digit runs are dates or counters, and flagging either
// would fail closed on prose.
function isShaClaim(token) {
  return token.length === 40 || (/[0-9]/u.test(token) && /[a-f]/iu.test(token));
}

// Extract the pin and trailing comment from parsed workflow `uses` scalar
// nodes, so YAML properties such as anchors remain supported while examples
// inside run blocks or comments can never masquerade as executable references.
function pinnedUsesEntries(source, workflow) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    strict: true,
    uniqueKeys: true,
  });
  const lineStarts = [0];
  for (const match of source.matchAll(/\n/gu)) {
    lineStarts.push(match.index + 1);
  }
  const lineIndexAt = (offset) => {
    let low = 0;
    let high = lineStarts.length;
    while (low + 1 < high) {
      const middle = Math.floor((low + high) / 2);
      if (lineStarts[middle] <= offset) low = middle;
      else high = middle;
    }
    return low;
  };

  const entries = [];
  for (const [jobId, job] of Object.entries(workflow?.jobs ?? {})) {
    if (job === null || typeof job !== "object" || Array.isArray(job)) {
      continue;
    }
    const paths = [["jobs", jobId, "uses"]];
    if (Array.isArray(job.steps)) {
      for (const index of job.steps.keys()) {
        paths.push(["jobs", jobId, "steps", index, "uses"]);
      }
    }
    for (const parts of paths) {
      const node = document.getIn(parts, true);
      const pinned =
        typeof node?.value === "string" && node.value.match(/@(?<sha>[0-9a-f]{40})$/iu);
      if (!pinned || !Array.isArray(node.range)) {
        continue;
      }
      const trailing = source.slice(node.range[1], node.range[2] ?? node.range[1]);
      const comment = trailing.match(/^\s+#\s*(?<comment>[^\r\n]*)(?:\r?\n)?$/u);
      if (comment) {
        entries.push({
          comment: comment.groups.comment,
          line: lineIndexAt(node.range[0]) + 1,
          sha: pinned.groups.sha,
        });
      }
    }
  }
  return entries;
}

function pinProvenanceFindings(source, file, workflow) {
  const findings = [];
  for (const { comment, line, sha } of pinnedUsesEntries(source, workflow)) {
    for (const token of comment.match(COMMENT_HEX_TOKENS) ?? []) {
      if (isShaClaim(token) && !sha.toLowerCase().startsWith(token.toLowerCase())) {
        findings.push(
          finding(
            "pin-provenance-drift",
            file,
            undefined,
            `line ${line}: pin comment claims commit ${token}, but the ` +
              `reference pins ${sha.slice(0, 12)}; update the provenance ` +
              "comment in the same change as the pin",
          ),
        );
      }
    }
  }
  return findings;
}

async function repositoryWorkflowIndex(root) {
  const directory = path.join(root, ".github", "workflows");
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === "ENOENT") {
      return new Map();
    }
    throw error;
  }
  const records = new Map();
  for (const entry of entries
    .filter((candidate) => /\.ya?ml$/i.test(candidate.name))
    .sort((left, right) => left.name.localeCompare(right.name))) {
    const file = `.github/workflows/${entry.name}`;
    const absoluteFile = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) {
      records.set(file, {
        file,
        absoluteFile,
        error: `${file} must be a regular file; workflow symlinks are forbidden`,
      });
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    let source;
    try {
      source = await readFile(absoluteFile, "utf8");
      records.set(file, {
        file,
        absoluteFile,
        source,
        workflow: parseWorkflow(source, file),
      });
    } catch (error) {
      records.set(file, { file, absoluteFile, source, error: error.message });
    }
  }
  return records;
}

function resolveRepositoryOwner(config, githubRepository) {
  // Checked-in repositoryOwner is part of the data being audited. It may
  // corroborate external identity, but must never grant an owner-scoped
  // approval when GitHub/caller identity evidence is absent.
  if (githubRepository === undefined) {
    return undefined;
  }
  if (typeof githubRepository !== "string" || !GITHUB_REPOSITORY.test(githubRepository)) {
    throw new ConfigurationError("GITHUB_REPOSITORY evidence must be an owner/repository name");
  }
  const githubOwner = githubRepository.slice(0, githubRepository.indexOf("/")).toLowerCase();
  const configuredOwner = config.repositoryOwner?.toLowerCase();
  if (configuredOwner && githubOwner !== configuredOwner) {
    throw new ConfigurationError(
      `GITHUB_REPOSITORY owner evidence is ${githubOwner}, but .github/runner-policy.json declares ${configuredOwner}`,
    );
  }
  return githubOwner;
}

export async function auditRepository({
  root = process.cwd(),
  configPath = DEFAULT_CONFIG_PATH,
  policyPath = DEFAULT_POLICY_PATH,
  repositoryVisibility,
  githubRepository,
} = {}) {
  const resolvedRoot = path.resolve(root);
  const resolvedConfig = path.isAbsolute(configPath)
    ? configPath
    : path.join(resolvedRoot, configPath);
  const resolvedPolicy = path.isAbsolute(policyPath)
    ? policyPath
    : path.join(resolvedRoot, policyPath);
  const basePolicy = validatePolicy(await readJson(resolvedPolicy, "runner policy"));
  const config = validateRepositoryConfig(
    await readJson(resolvedConfig, "repository runner config"),
    basePolicy,
  );
  if (repositoryVisibility) {
    if (!new Set(["public", "private"]).has(repositoryVisibility)) {
      throw new ConfigurationError('repository visibility evidence must be "public" or "private"');
    }
    if (repositoryVisibility !== config.visibility) {
      throw new ConfigurationError(
        `repository visibility evidence is ${repositoryVisibility}, but .github/runner-policy.json declares ${config.visibility}`,
      );
    }
  }
  const repositoryOwner = resolveRepositoryOwner(config, githubRepository);
  const policy = {
    ...basePolicy,
    repositoryOwner,
    approvedSelectorReferences: new Set([
      ...basePolicy.approvedSelectorReferences,
      ...(basePolicy.approvedSelectorReferencesByRepositoryOwner.get(repositoryOwner) ?? []),
    ]),
  };
  const findings = [];
  const consumedExceptions = new Set();
  const workflowIndex = await repositoryWorkflowIndex(resolvedRoot);
  const localPermissionVisits = new Set();
  const localIncomingFiles = new Set();
  for (const record of workflowIndex.values()) {
    if (!record.workflow) {
      continue;
    }
    for (const job of Object.values(record.workflow.jobs)) {
      const reference = parseLocalReusableWorkflowReference(job?.uses);
      if (reference.file) {
        localIncomingFiles.add(reference.file);
      }
    }
  }

  for (const record of workflowIndex.values()) {
    const { file, workflow } = record;
    if (record.source) {
      findings.push(...pinProvenanceFindings(record.source, file, workflow));
    }
    if (!workflow) {
      findings.push(finding("workflow-parse", file, undefined, record.error));
      continue;
    }

    const requiredNoDefaultCallers = new Map();
    const approvedFailureSentinels = new Map();
    for (const [jobId, job] of Object.entries(workflow.jobs)) {
      if (job === null || typeof job !== "object" || Array.isArray(job)) {
        findings.push(finding("job-shape", file, jobId, "job must be a mapping"));
        continue;
      }
      const key = `${file}#${jobId}`;
      const exception = config.exceptions.get(key);
      const selector = selectorStatus(job, policy);
      const localCall = selector.isSelector
        ? undefined
        : localReusableWorkflowStatus(file, job, policy, workflowIndex);
      const target = selector.isSelector
        ? undefined
        : runnerTargetStatus(jobId, job, workflow.jobs, workflow, policy, file, workflowIndex);
      const attemptsSelectorRoute =
        target !== undefined && Object.hasOwn(target, "route") && target.route.attempted === true;
      const runnerStrings = rawRunnerStrings(job, !selector.isSelector);
      const routingEnabled = config.visibility === "private" && config.selfHostedCi;
      if (
        routingEnabled &&
        target?.kind === "selector-output" &&
        target.approved &&
        target.route.mode === "required-no-default"
      ) {
        const callers = requiredNoDefaultCallers.get(target.route.selectorId) ?? [];
        callers.push(jobId);
        requiredNoDefaultCallers.set(target.route.selectorId, callers);
      }
      if (routingEnabled && target?.kind === "unroutable-failure" && target.approved) {
        const sentinels = approvedFailureSentinels.get(target.route.selectorId) ?? [];
        sentinels.push(jobId);
        approvedFailureSentinels.set(target.route.selectorId, sentinels);
      }
      const seedLocalPermissionFlow =
        !isWorkflowCallExclusive(workflow) || !localIncomingFiles.has(file);
      if (routingEnabled && localCall?.approved && seedLocalPermissionFlow) {
        findings.push(
          ...auditLocalPermissionFlow({
            localStatus: localCall,
            inherited: permissionCapability(workflow, job),
            policy,
            workflowIndex,
            config,
            consumedExceptions,
            visited: localPermissionVisits,
          }),
        );
      }
      const privilegedHosted = routingEnabled
        ? privilegedHostedRequirement(workflow, job, selector, target, policy, localCall)
        : undefined;
      const hostedRequirement = privilegedHosted ?? structuralHostedRequirement(job);
      let hasForbiddenHostedLabel = false;
      let hasRawManagedLabel = false;

      for (const runner of runnerStrings) {
        const forbiddenLabel = [...policy.forbiddenHostedRunnerLabels].find((label) =>
          runner.toLowerCase().includes(label),
        );
        if (forbiddenLabel) {
          hasForbiddenHostedLabel = true;
          findings.push(
            finding(
              "explicit-hosted-runner",
              file,
              jobId,
              `${JSON.stringify(forbiddenLabel)} is forbidden; pin the hosted image explicitly (ubuntu-24.04)`,
            ),
          );
        }
      }

      for (const runner of runnerStrings) {
        if (rawManagedLabel(runner, policy)) {
          hasRawManagedLabel = true;
          findings.push(
            finding(
              "raw-self-hosted-label",
              file,
              jobId,
              `raw managed runner target ${JSON.stringify(runner.trim())} is forbidden; consume the approved selector output`,
            ),
          );
        }
      }

      if (
        target &&
        !target.approved &&
        ((!hasForbiddenHostedLabel && !hasRawManagedLabel) || typeof job.uses === "string") &&
        !attemptsSelectorRoute
      ) {
        findings.push(finding("runner-target-contract", file, jobId, target.reason));
      }

      if (hostedRequirement) {
        if (!exception) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `${hostedRequirement.description} requires a hosted exception with reason ${hostedRequirement.reason}`,
            ),
          );
        } else {
          consumedExceptions.add(key);
          if (exception.reason !== hostedRequirement.reason) {
            findings.push(
              finding(
                "hosted-exception-category",
                file,
                jobId,
                `${hostedRequirement.description} requires exception reason ${hostedRequirement.reason}, not ${exception.reason}`,
              ),
            );
          }
        }
        if (
          selector.isSelector ||
          (target?.kind !== "hosted-literal" &&
            target?.kind !== "hosted-matrix" &&
            target?.kind !== "hosted-reusable" &&
            target?.kind !== "hosted-local-reusable")
        ) {
          findings.push(
            finding(
              hostedRequirement.rule,
              file,
              jobId,
              `${hostedRequirement.description} cannot use selector or reusable local-runner routing`,
            ),
          );
        }
      }

      if (!routingEnabled) {
        if (selector.isSelector || target?.kind === "selector-output" || attemptsSelectorRoute) {
          findings.push(
            finding(
              config.visibility === "public"
                ? "public-self-hosted-routing"
                : "self-hosted-routing-disabled",
              file,
              jobId,
              "this repository is not permitted to use the local-runner selector",
            ),
          );
        }
        continue;
      }

      if (selector.isSelector) {
        if (!selector.approved) {
          findings.push(finding("selector-pin", file, jobId, selector.reason));
        }
        continue;
      }

      if (target?.kind === "unroutable-failure" && target.approved) {
        continue;
      }
      if (target?.kind === "selector-output" && target.approved) {
        continue;
      }
      if (attemptsSelectorRoute) {
        findings.push(finding("selector-contract", file, jobId, target.reason));
      }
      if (target?.kind === "reusable-input") {
        continue;
      }
      if (
        target?.kind === "hosted-local-reusable" ||
        target?.kind === "transparent-local-reusable"
      ) {
        continue;
      }
      if (target?.kind === "invalid") {
        if (exception) {
          consumedExceptions.add(key);
        } else if (!hostedRequirement && !attemptsSelectorRoute) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `eligible private job must consume the approved selector or declare ${key} in .github/runner-policy.json`,
            ),
          );
        }
        continue;
      }
      if (!exception && !hostedRequirement) {
        findings.push(
          finding(
            "hosted-exception-required",
            file,
            jobId,
            `eligible private job must consume the approved selector or declare ${key} in .github/runner-policy.json`,
          ),
        );
      } else if (exception) {
        consumedExceptions.add(key);
      }
    }

    for (const [selectorId, callerIds] of requiredNoDefaultCallers) {
      const sentinelIds = approvedFailureSentinels.get(selectorId) ?? [];
      if (sentinelIds.length === 1) {
        continue;
      }
      for (const jobId of callerIds) {
        findings.push(
          finding(
            "selector-failure-sentinel-required",
            file,
            jobId,
            `required no-default local runner calls using ${selectorId} require exactly one approved ${policy.governedReusableRunnerInput.failureSentinel} rejection job for the same selector in this workflow; found ${sentinelIds.length}`,
          ),
        );
      }
    }
  }

  for (const key of config.exceptions.keys()) {
    if (!consumedExceptions.has(key)) {
      findings.push(
        finding(
          "exception-inventory-drift",
          key.split("#", 1)[0],
          key.includes("#") ? key.slice(key.indexOf("#") + 1) : undefined,
          `configured exception ${key} is unused; remove or correct it`,
        ),
      );
    }
  }

  const uniqueFindings = new Map();
  for (const item of findings) {
    const key = [item.file, item.job ?? "", item.rule].join("\0");
    if (!uniqueFindings.has(key)) {
      uniqueFindings.set(key, item);
    }
  }
  return [...uniqueFindings.values()].sort((left, right) =>
    [left.file, left.job ?? "", left.rule, left.message]
      .join("\0")
      .localeCompare([right.file, right.job ?? "", right.rule, right.message].join("\0")),
  );
}

function parseArguments(argv) {
  const options = {
    root: process.cwd(),
    configPath: DEFAULT_CONFIG_PATH,
    policyPath: DEFAULT_POLICY_PATH,
    repositoryVisibility: process.env.CI_REPOSITORY_VISIBILITY,
    githubRepository: process.env.GITHUB_REPOSITORY,
    json: argv.includes("--json"),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--json") {
      options.json = true;
      continue;
    }
    if (new Set(["--root", "--config", "--policy", "--repository-visibility"]).has(argument)) {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new ConfigurationError(`${argument} requires a value`);
      }
      index += 1;
      if (argument === "--root") options.root = value;
      if (argument === "--config") options.configPath = value;
      if (argument === "--policy") options.policyPath = value;
      if (argument === "--repository-visibility") options.repositoryVisibility = value;
      continue;
    }
    throw new ConfigurationError(`unknown argument: ${argument}`);
  }
  return options;
}

async function main() {
  try {
    const { json, ...options } = parseArguments(process.argv.slice(2));
    const findings = await auditRepository(options);
    if (json) {
      process.stdout.write(`${JSON.stringify({ findings, ok: findings.length === 0 }, null, 2)}\n`);
    } else if (findings.length === 0) {
      process.stdout.write("Runner policy passed.\n");
    } else {
      for (const item of findings) {
        const location = item.job ? `${item.file}#${item.job}` : item.file;
        process.stderr.write(`${location}: ${item.rule}: ${item.message}\n`);
      }
    }
    process.exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) {
    const output = error instanceof Error ? error.message : String(error);
    process.stderr.write(`runner-policy: ${output}\n`);
    process.exitCode = 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
