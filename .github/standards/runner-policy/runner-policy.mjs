#!/usr/bin/env node
// SYNC-MANAGED FILE — DO NOT EDIT IN THE CONSUMING REPOSITORY.
// Source of truth: melodic-software/standards,
// components/runner-policy/runner-policy.mjs (the `runner-policy`
// component in distribution/sync-manifest.yml). Downstream edits are
// overwritten by the next sync PR; change the component upstream, or move the
// component to `locally-owned` in the manifest to customize.

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";
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

const MODULE_DIRECTORY = import.meta.dirname;
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
const MATRIX_OUTPUT = /^\$\{\{ matrix\.([A-Za-z0-9_-]+) }}$/;
const FULL_SHA = /^[0-9a-f]{40}$/i;
const MAIN_FLOAT_PREFIX = "melodic-software/ci-workflows/";
const LOCAL_REUSABLE_WORKFLOW = /^\.\/\.github\/workflows\/([A-Za-z0-9_.-]+\.ya?ml)$/;
const GITHUB_REPOSITORY = /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}\/[A-Za-z0-9_.-]+$/;
const EXACT_GITHUB_TOKEN_EXPRESSIONS = new Set([
  `\${{ secrets.GITHUB_TOKEN }}`,
  `\${{ github.token }}`,
]);
const VISIBILITY_SCOPED_REUSABLE_WORKFLOW_PATHS = new Set([
  "melodic-software/ci-workflows/.github/workflows/claude-review.yml",
  "melodic-software/ci-workflows/.github/workflows/claude-security-review.yml",
  "melodic-software/ci-workflows/.github/workflows/pr-review.yml",
  "melodic-software/ci-workflows/.github/workflows/pr-review-security.yml",
]);
const PUBLIC_REPOSITORY_DENYLISTED_REUSABLE_INPUTS = new Set(["standards-ref"]);
const PUBLIC_REPOSITORY_DENYLISTED_REUSABLE_SECRETS = new Set([
  "STANDARDS_REVIEW_APP_ID",
  "STANDARDS_REVIEW_APP_PRIVATE_KEY",
]);

// The shared object-shape check behind every "must be a mapping" decision in
// this analyzer. It admits any non-null, non-array object, which under the
// core schema means a decoded YAML mapping — but an explicit `!!set`/`!!omap`/
// `!!timestamp`/`!!binary` tag or a `%YAML 1.1` directive also decodes to an
// object this admits. Tag-shape rejection is deliberately not performed here;
// it belongs at the parse boundary, not at 48 individual gates.
function isMapping(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

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
  } else if (error.propertyName !== undefined) {
    errorLocation += `.${error.propertyName}`;
  }
  throw new ConfigurationError(`${errorLocation} ${error.message}`);
}

export function validatePolicy(value) {
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

  // `managedLabelPatterns` is a DETECTION surface: deliberately loose so every
  // label-shaped string is caught and refused. It is the wrong gate for
  // ADMISSION, which needs the opposite bias, so the labels a job may name
  // directly are an explicit reviewed set, exactly like the hosted ones. Every
  // entry must itself read as a managed label and must not be a hosted label,
  // so this set can never quietly admit an arbitrary or hosted target.
  const approvedManagedRunnerLabels = new Set(value.approvedManagedRunnerLabels);
  for (const label of approvedManagedRunnerLabels) {
    if (label !== label.trim()) {
      throw new ConfigurationError(
        `policy.approvedManagedRunnerLabels entry ${JSON.stringify(label)} must not carry surrounding whitespace`,
      );
    }
    if (knownGitHubHostedRunnerLabels.has(label.toLowerCase())) {
      throw new ConfigurationError(
        `policy.approvedManagedRunnerLabels entry ${JSON.stringify(label)} is a GitHub-hosted runner label`,
      );
    }
    if (!managedLabelRegexes.some((pattern) => pattern.test(label))) {
      throw new ConfigurationError(
        `policy.approvedManagedRunnerLabels entry ${JSON.stringify(label)} must match a managed label pattern`,
      );
    }
  }

  const approvedReusableWorkflowContracts = new Map();
  for (const [reference, contract] of Object.entries(value.approvedReusableWorkflowContracts)) {
    if (contract.routing === "runner-input") {
      if (!contract.allowedInputs.includes(contract.runnerInput)) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.allowedInputs must include ${contract.runnerInput}`,
        );
      }
      if (
        Object.hasOwn(contract, "allowedCallerPermissions") &&
        !Object.values(contract.allowedCallerPermissions).includes("write")
      ) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.allowedCallerPermissions must include at least one write permission`,
        );
      }
      // A floor may only require read. GitHub downgrades write grants to read
      // (and write-only scopes to none) on forked and Dependabot pull requests
      // unless repository settings permit otherwise, so a caller's declared
      // write is not the access the callee receives -- a statically checked
      // write floor would pass exactly the callers it exists to catch. A write
      // obligation belongs in allowedCallerPermissions, whose waiver is
      // reviewed against the calling job rather than inferred from a
      // declaration. The schema keeps the value domain (a floor names a real
      // grant); this rule lives here so the author of a rejected contract is
      // told why, the same split allowedCallerPermissions' write requirement
      // already uses in the opposite direction.
      if (Object.hasOwn(contract, "minimumCallerPermissions")) {
        const writeScopes = Object.entries(contract.minimumCallerPermissions)
          .filter(([, access]) => access !== "read")
          .map(([scope]) => scope)
          .sort((left, right) => left.localeCompare(right));
        if (writeScopes.length > 0) {
          throw new ConfigurationError(
            `reusable workflow contract ${reference}.minimumCallerPermissions must require read access only (${writeScopes.join(", ")}); GitHub downgrades caller write grants on forked and Dependabot pull requests, so a write floor cannot be proven from the caller's declaration — use allowedCallerPermissions for a write obligation`,
          );
        }
      }
      // The two caller-permission terms are independent — a ceiling and a
      // floor — but a contract naming both must be satisfiable: the exact
      // waiver is the only mapping any caller may present, so a waiver that
      // falls short of the floor admits nothing at all.
      if (
        Object.hasOwn(contract, "minimumCallerPermissions") &&
        Object.hasOwn(contract, "allowedCallerPermissions")
      ) {
        const shortfall = minimumPermissionShortfall(
          contract.allowedCallerPermissions,
          contract.minimumCallerPermissions,
          `reusable workflow contract ${reference}.allowedCallerPermissions`,
        );
        if (shortfall) {
          throw new ConfigurationError(
            `${shortfall}, which its own minimumCallerPermissions requires`,
          );
        }
      }
      if (contract.role && !contract.allowedInputs.includes("role")) {
        throw new ConfigurationError(
          `reusable workflow contract ${reference}.allowedInputs must include role when role is declared`,
        );
      }
      if (Object.hasOwn(contract, "allowedCallerPermissions")) {
        // A secret maps to its own name, or, for a contract that declares a
        // funding role, to that role's prefixed name: several roles can then
        // share one repository, and the role is a reviewed literal.
        const prefix = contract.role ? `${contract.role.toUpperCase().replaceAll("-", "_")}_` : "";
        for (const [name, expression] of Object.entries(contract.allowedSecrets)) {
          const expected = `\${{ secrets.${name} }}`;
          const roleNamed = prefix ? `\${{ secrets.${prefix}${name} }}` : expected;
          if (
            !/^[A-Za-z_][A-Za-z0-9_]*$/u.test(name) ||
            (expression !== expected && expression !== roleNamed)
          ) {
            throw new ConfigurationError(
              `reusable workflow contract ${reference}.allowedSecrets.${name} must be exactly ${JSON.stringify(expected)}${prefix ? ` or ${JSON.stringify(roleNamed)}` : ""} when allowedCallerPermissions is present`,
            );
          }
        }
      }
      // Every runner-input contract's reviewed secret mapping feeds a
      // fleet-routed caller whose secrets: block the generic credential
      // scan then trusts, so each value must be one exact whole named-secret
      // expression (the workflow_call input name may differ from the
      // repository secret name) — a transformed or indirect expression would
      // ride the reviewed boundary onto the fleet.
      for (const [name, expression] of Object.entries(contract.allowedSecrets)) {
        if (typeof expression !== "string" || !EXACT_NAMED_SECRET_EXPRESSION.test(expression)) {
          throw new ConfigurationError(
            `reusable workflow contract ${reference}.allowedSecrets.${name} must be exactly one whole \${{ secrets.<NAME> }} expression`,
          );
        }
      }
    }
    const unknownLabel = contract.fixedRunsOn?.find(
      (label) => !knownGitHubHostedRunnerLabels.has(label.toLowerCase()),
    );
    if (unknownLabel) {
      throw new ConfigurationError(
        `${contract.routing} reusable workflow contract ${reference}.fixedRunsOn contains unrecognized GitHub-hosted label ${unknownLabel}`,
      );
    }
    approvedReusableWorkflowContracts.set(reference, {
      routing: contract.routing,
      ...(contract.runnerInput ? { runnerInput: contract.runnerInput } : {}),
      ...(contract.role ? { role: contract.role } : {}),
      allowedInputs: new Set(contract.allowedInputs),
      allowedSecrets: contract.allowedSecrets,
      allowedSecretNames: new Set(Object.keys(contract.allowedSecrets)),
      ...(contract.allowedCallerPermissions
        ? {
            allowedCallerPermissions: Object.freeze({
              ...contract.allowedCallerPermissions,
            }),
            allowedCallerPermissionNames: new Set(Object.keys(contract.allowedCallerPermissions)),
          }
        : {}),
      ...(contract.minimumCallerPermissions
        ? {
            minimumCallerPermissions: Object.freeze({
              ...contract.minimumCallerPermissions,
            }),
          }
        : {}),
      ...(contract.fixedRunsOn ? { fixedRunsOn: new Set(contract.fixedRunsOn) } : {}),
      approvedShas: new Set(contract.approvedShas ?? []),
    });
  }

  if (!approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.default)) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.default must be an approved hosted runner label",
    );
  }
  if (!new Set(value.fallbackLabelAllowlist).has(value.governedReusableRunnerInput.default)) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.default must be in policy.fallbackLabelAllowlist",
    );
  }
  // Every allowlist member is an executable fallback route, so each
  // must be a label this policy already recognizes as routable.
  for (const label of value.fallbackLabelAllowlist) {
    if (
      !approvedHostedRunnerLabels.has(label) &&
      !managedLabelRegexes.some((pattern) => pattern.test(label))
    ) {
      throw new ConfigurationError(
        `policy.fallbackLabelAllowlist entry ${JSON.stringify(label)} must be an approved hosted runner label or match a managed label pattern`,
      );
    }
  }
  if (!approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.failureSentinel)) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.failureSentinel must be an approved hosted runner label",
    );
  }
  if (
    approvedHostedRunnerLabels.has(value.governedReusableRunnerInput.failureSentinelMarker) ||
    forbiddenHostedRunnerLabels.has(
      value.governedReusableRunnerInput.failureSentinelMarker.toLowerCase(),
    ) ||
    managedLabelRegexes.some((pattern) =>
      pattern.test(value.governedReusableRunnerInput.failureSentinelMarker),
    )
  ) {
    throw new ConfigurationError(
      "policy.governedReusableRunnerInput.failureSentinelMarker must remain outside every hosted and managed runner label set",
    );
  }
  const hostedMatrixAxes = new Map();
  for (const expression of value.hostedMatrixExpressions) {
    const match = MATRIX_OUTPUT.exec(expression);
    hostedMatrixAxes.set(match[1], expression);
  }

  return {
    ...value,
    approvedReusableWorkflowContracts,
    approvedHostedRunnerLabels,
    hostedMatrixAxes,
    forbiddenHostedRunnerLabels,
    hostedExceptionReasons: new Set(value.hostedExceptionReasons),
    localCredentialActions: new Set(value.localCredentialActions),
    managedLabelRegexes,
    approvedManagedRunnerLabels,
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

  const localRoutingGrants = new Map();
  for (const [key, grant] of Object.entries(value.localRoutingGrants ?? {})) {
    if (exceptions.has(key)) {
      throw new ConfigurationError(
        `${key} cannot declare both a hosted exception and a local-routing grant; granted fleet routing and excepted hosted execution are mutually exclusive`,
      );
    }
    const admitsAnything =
      Object.values(grant.permissions).includes("write") ||
      Object.hasOwn(grant, "environment") ||
      Object.hasOwn(grant, "secrets") ||
      Object.hasOwn(grant, "credentialActions");
    if (!admitsAnything) {
      throw new ConfigurationError(
        `local-routing grant ${key} admits nothing beyond the ordinary read-only local boundary; declare a write permission, environment, secret, or credential action, or remove the grant`,
      );
    }
    // GitHub evaluates expression-valued environment names (vars, needs,
    // matrix contexts), so an expression could change the protected
    // environment without any grant-inventory diff; only a literal name is
    // an exact reviewed surface.
    if (Object.hasOwn(grant, "environment") && grant.environment.includes("${{")) {
      throw new ConfigurationError(
        `local-routing grant ${key} must name one literal deployment environment, not an expression`,
      );
    }
    for (const name of grant.secrets ?? []) {
      if (name.toUpperCase() === "GITHUB_TOKEN") {
        throw new ConfigurationError(
          `local-routing grant ${key} must not name GITHUB_TOKEN as a secret; the GitHub-provided token is admitted by the grant's exact permissions mapping`,
        );
      }
    }
    for (const reference of grant.credentialActions ?? []) {
      const action = reference.split("@", 1)[0];
      if (!policy.localCredentialActions.has(action)) {
        throw new ConfigurationError(
          `local-routing grant ${key} names credential action ${action}, which is not in policy.localCredentialActions`,
        );
      }
    }
    localRoutingGrants.set(key, grant);
  }

  const requiredReusableCallInputs = new Map();
  for (const [key, entry] of Object.entries(value.requiredReusableCallInputs ?? {})) {
    requiredReusableCallInputs.set(key, entry);
  }

  return { ...value, exceptions, localRoutingGrants, requiredReusableCallInputs };
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
  const workflow = parseYamlMapping(source, file);
  if (!isMapping(workflow.jobs)) {
    throw new Error(`${file} must contain a jobs mapping`);
  }
  return workflow;
}

function parseYamlMapping(source, file) {
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
  const value = document.toJS({ maxAliasCount: 0 });
  if (!isMapping(value)) {
    throw new Error(`${file} must contain a workflow mapping`);
  }
  return value;
}

function stringsIn(value) {
  if (typeof value === "string") {
    return [value];
  }
  if (Array.isArray(value)) {
    return value.flatMap(stringsIn);
  }
  if (isMapping(value)) {
    return Object.values(value).flatMap(stringsIn);
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

// Contracts key on the workflow path. A melodic-software/ci-workflows reusable
// may be called at @main; any caller may pin a SHA the contract lists in
// approvedShas. An unlisted SHA is refused because GitHub serves a commit
// pushed to any fork under the parent repository path. Every other ref (a tag
// or another branch) is not approved.
function reusableWorkflowContract(uses, policy) {
  const parsed = parseReusableWorkflowReference(uses);
  const contract = parsed && policy.approvedReusableWorkflowContracts.get(parsed.workflow);
  if (!contract) {
    return { reason: "the reusable workflow path has no reviewed runner-input contract" };
  }
  const floats = parsed.workflow.startsWith(MAIN_FLOAT_PREFIX);
  if (floats && parsed.revision === "main") {
    return { contract };
  }
  if (FULL_SHA.test(parsed.revision)) {
    if (contract.approvedShas.has(parsed.revision.toLowerCase())) {
      return { contract };
    }
    return {
      reason: `the reusable workflow ref @${parsed.revision} is not an approved commit for ${parsed.workflow}; use ${floats ? "@main" : "a SHA listed in its approvedShas"}`,
    };
  }
  return {
    reason: `the reusable workflow ref @${parsed.revision} is not approved; use ${floats ? "@main or " : ""}an approved full commit SHA`,
  };
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
  if (!isMapping(workflow.on) || !Object.hasOwn(workflow.on, "workflow_call")) {
    return undefined;
  }
  const declaration = workflow.on.workflow_call;
  if (declaration === null) {
    return {};
  }
  if (!isMapping(declaration)) {
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
    isMapping(workflow.on) &&
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
  if (!isMapping(declaredInputs)) {
    return "the repository-local workflow has an invalid workflow_call.inputs mapping";
  }
  const inputs = job.with ?? {};
  if (!isMapping(inputs)) {
    return "repository-local reusable workflow inputs must be an explicit mapping";
  }
  const extraInputs = Object.keys(inputs).filter((name) => !Object.hasOwn(declaredInputs, name));
  if (extraInputs.length > 0) {
    return `the repository-local reusable workflow call has undeclared inputs: ${extraInputs.join(", ")}`;
  }
  const missingInputs = Object.entries(declaredInputs)
    .filter(
      ([name, input]) =>
        isMapping(input) && input.required === true && !Object.hasOwn(inputs, name),
    )
    .map(([name]) => name);
  if (missingInputs.length > 0) {
    return `the repository-local reusable workflow call omits required inputs: ${missingInputs.join(", ")}`;
  }

  if (job.secrets === "inherit") {
    return "repository-local reusable workflows must not use secrets: inherit";
  }
  const declaredSecrets = declaration.secrets ?? {};
  if (!isMapping(declaredSecrets)) {
    return "the repository-local workflow has an invalid workflow_call.secrets mapping";
  }
  const secrets = job.secrets ?? {};
  if (!isMapping(secrets)) {
    return "repository-local reusable workflow secrets must be an explicit mapping";
  }
  const extraSecrets = Object.keys(secrets).filter((name) => !Object.hasOwn(declaredSecrets, name));
  if (extraSecrets.length > 0) {
    return `the repository-local reusable workflow call has undeclared secrets: ${extraSecrets.join(", ")}`;
  }
  const missingSecrets = Object.entries(declaredSecrets)
    .filter(
      ([name, secret]) =>
        isMapping(secret) && secret.required === true && !Object.hasOwn(secrets, name),
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
    if (typeof job?.["runs-on"] === "string") {
      const runner = job["runs-on"];
      if (
        runner === policy.governedReusableRunnerInput.expression ||
        rawManagedLabel(runner, policy)
      ) {
        internalRouting = true;
      }
    }
    const external = reusableWorkflowContract(job?.uses, policy).contract;
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
  return {
    isLocal: true,
    approved: true,
    record,
    routing,
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
    (isMapping(declaration) &&
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
    if (!isMapping(job)) {
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

    const target = runnerTargetStatus(job, record.workflow, policy, record.file, workflowIndex);
    // A called job that names the fleet label literally executes on the
    // persistent host. Before the fleet label was a routing target it
    // classified `invalid` here, matching neither this test nor the hosted one
    // below, so the whole flow pass fell through and emitted nothing: a called
    // job inheriting write-capable caller permissions ran on the fleet with no
    // finding at all.
    const localExecution =
      locallyRoutedTarget(target) ||
      target.kind === "reusable-input" ||
      target.kind === "transparent-local-reusable";
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
      target.kind === "hosted-literal" ||
      target.kind === "hosted-matrix" ||
      target.kind === "hosted-reusable" ||
      target.kind === "hosted-local-reusable";
    if (hostedExecution && capability !== "read-only") {
      // The direct audit of this same job classifies a declared packages-only
      // write map (with no other privileged surface) as publication — with the
      // structural container categories taking precedence over that downgrade;
      // this flow pass must demand the same category or the two checks
      // contradict each other on one exception key. Anything else — a broader
      // declared map, an additional privileged surface, or an undeclared map
      // that merely inherits the caller's write capability — stays privileged.
      const declaredRequirement = privilegedHostedRequirement(
        record.workflow,
        job,
        target,
        policy,
        undefined,
        undefined,
        undefined,
      );
      let requiredReason = "privileged-control-plane";
      if (declaredRequirement?.reason === "publication") {
        const structuralRequirement = structuralHostedRequirement(job);
        requiredReason = structuralRequirement ? structuralRequirement.reason : "publication";
      }
      const key = `${record.file}#${jobId}`;
      const exception = config.exceptions.get(key);
      if (!exception) {
        findings.push(
          finding(
            "hosted-exception-required",
            record.file,
            jobId,
            `a fixed-hosted called job inherits write-capable caller permissions and requires a ${requiredReason} exception`,
          ),
        );
      } else {
        consumedExceptions.add(key);
        if (exception.reason !== requiredReason) {
          findings.push(
            finding(
              "hosted-exception-category",
              record.file,
              jobId,
              `inherited write-capable caller permissions require exception reason ${requiredReason}, not ${exception.reason}`,
            ),
          );
        }
      }
    }
  }
  return findings;
}

function canonicalExpectation(expected) {
  return Array.isArray(expected)
    ? `one of ${JSON.stringify(expected)}`
    : `exactly ${JSON.stringify(expected)}`;
}

function exactCanonicalMap(actual, required, optional, allowedNames, location) {
  if (!isMapping(actual)) {
    return `${location} must be an explicit mapping`;
  }
  const actualNames = Object.keys(actual);
  const unexpected = actualNames.filter((name) => !allowedNames.has(name));
  if (unexpected.length > 0) {
    return `${location} has unapproved properties: ${unexpected.join(", ")}`;
  }
  // A canonical value is either one exact governed expression or an exact set of
  // them (e.g. the default and review-tier self-hosted-label variables). Set
  // membership stays fail-closed: any expression outside the reviewed set is
  // rejected, and a single-string value keeps identical exact-match behavior.
  for (const [name, expected] of Object.entries(required)) {
    const allowed = Array.isArray(expected) ? expected : [expected];
    if (!allowed.includes(actual[name])) {
      return `${location}.${name} must be ${canonicalExpectation(expected)}`;
    }
  }
  for (const [name, expected] of Object.entries(optional)) {
    const allowed = Array.isArray(expected) ? expected : [expected];
    if (Object.hasOwn(actual, name) && !allowed.includes(actual[name])) {
      return `${location}.${name} must be ${canonicalExpectation(expected)}`;
    }
  }
  return undefined;
}

const PERMISSION_ACCESS_RANK = { none: 0, read: 1, write: 2 };

// GITHUB_TOKEN access is ordered (none < read < write), so a caller granting
// more than a reviewed floor still satisfies it. A scope the caller does not
// name is granted nothing; read-all and write-all grant every scope at that
// level.
function grantedPermissionAccess(permissions, scope) {
  if (permissions === "write-all") {
    return "write";
  }
  if (permissions === "read-all") {
    return "read";
  }
  const access = permissions[scope];
  return Object.hasOwn(PERMISSION_ACCESS_RANK, access) ? access : "none";
}

// A called workflow can only narrow the caller's token, never widen it, so a
// caller granting less than the callee requests cannot do the work the
// reviewed contract was approved for. The comparison stays ordered even
// though a floor may only require read: a caller granting write clears a read
// floor, because GitHub's event-time downgrade lands on read at worst.
// Omitted permissions resolve to repository- or organization-defined defaults
// this surface cannot read, so they can never prove the floor and fail
// closed. Scopes are reported in sorted order so the message does not depend
// on how the contract was authored.
function minimumPermissionShortfall(permissions, minimum, location) {
  if (permissions !== "read-all" && permissions !== "write-all" && !isMapping(permissions)) {
    return `${location} must be an explicit mapping, read-all, or write-all to prove the reviewed minimum ${JSON.stringify(minimum)}`;
  }
  for (const scope of Object.keys(minimum).sort((left, right) => left.localeCompare(right))) {
    const granted = grantedPermissionAccess(permissions, scope);
    if (PERMISSION_ACCESS_RANK[granted] < PERMISSION_ACCESS_RANK[minimum[scope]]) {
      return `${location}.${scope} must grant at least ${JSON.stringify(minimum[scope])}; the grant is ${JSON.stringify(granted)}`;
    }
  }
  return undefined;
}

function reusableWorkflowStatus(job, policy, workflow) {
  if (typeof job?.uses !== "string") {
    return { isReusable: false, approved: false };
  }
  const { contract, reason } = reusableWorkflowContract(job.uses, policy);
  if (!contract) {
    return { isReusable: true, approved: false, reason };
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
  if (!isMapping(inputs)) {
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
  if (contract.role && inputs.role !== contract.role) {
    return {
      isReusable: true,
      approved: false,
      reason: `the reviewed reusable workflow must receive role: ${contract.role} as a literal`,
    };
  }
  if (contract.allowedCallerPermissions) {
    const permissionError = exactCanonicalMap(
      effectivePermissions(workflow, job),
      contract.allowedCallerPermissions,
      {},
      contract.allowedCallerPermissionNames,
      "reusable workflow caller permissions",
    );
    if (permissionError) {
      return { isReusable: true, approved: false, reason: permissionError };
    }
  }
  if (contract.minimumCallerPermissions) {
    const shortfall = minimumPermissionShortfall(
      effectivePermissions(workflow, job),
      contract.minimumCallerPermissions,
      "reusable workflow caller permissions",
    );
    if (shortfall) {
      return { isReusable: true, approved: false, reason: shortfall };
    }
  }
  return { isReusable: true, approved: true, contract };
}

function governedReusableRunnerStatus(workflow, policy) {
  const contract = policy.governedReusableRunnerInput;
  if (
    !isMapping(workflow.on) ||
    Object.keys(workflow.on).length !== 1 ||
    !Object.hasOwn(workflow.on, "workflow_call")
  ) {
    return {
      approved: false,
      reason: `${contract.expression} is allowed only when workflow_call is the exclusive trigger`,
    };
  }
  const workflowCall = workflow.on.workflow_call;
  const declaration = workflowCall?.inputs?.[contract.name];
  if (!isMapping(declaration)) {
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
  if (!isMapping(matrix)) {
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

function runnerTargetStatus(job, workflow, policy, file, workflowIndex) {
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
  const reusable = reusableWorkflowStatus(job, policy, workflow);
  if (!local.approved && reusable.isReusable && !reusable.approved) {
    return { approved: false, kind: "invalid", reason: reusable.reason };
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
  // A literal governed fleet label is the only routing target that reaches the
  // managed fleet on an enrolled private repository. Admission is exact
  // membership in the reviewed `approvedManagedRunnerLabels` set, mirroring the
  // hosted-literal check below, and deliberately NOT a `managedLabelPatterns`
  // match: that pattern is a deliberately loose detection surface, so reusing
  // it here would admit any unreviewed near-miss
  // (`melodic-anything-ubuntu-24.04-x64`) or an adjacent-text string
  // (`bogus/melodic-review-ubuntu-24.04-x64`) with the same trust as the real
  // fleet label. The check also sits AFTER the expression catch-all above, so a
  // `${{ … }}` expression that merely mentions the label is not a literal.
  // Approval is unconditional here and the routing gate below
  // (`routingEnabled`) refuses it on a public or non-enrolled repository, so
  // the public case keeps reporting `public-self-hosted-routing` rather than a
  // generic contract failure.
  // Compared without trimming, exactly as the hosted-literal check below is, and
  // exactly as validatePolicy requires of every set entry: a padded label is a
  // different string from the reviewed one and is not admitted.
  if (policy.approvedManagedRunnerLabels.has(target)) {
    return { approved: true, kind: "managed-literal", label: target };
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

// The one way a job reaches the managed fleet: on an enrolled private
// repository, the governed fleet label written literally. Keeping it behind a
// named predicate is what stops the grant-applicability test and the
// grant-consumption test from drifting apart.
function locallyRoutedTarget(target) {
  return target?.kind === "managed-literal";
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
  if (!isMapping(permissions)) {
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
  // packages is registry-publication authority, not repository/organization
  // state: a job whose only write scope is packages belongs to the durable
  // publication category, so artifact provenance can stay on hosted
  // infrastructure after the control-plane reasons retire. Any additional
  // write scope keeps the job in the privileged category.
  if (writable.length === 1 && writable[0] === "packages") {
    return {
      reason: "publication",
      description: "write GITHUB_TOKEN permissions (packages)",
      rule: "privileged-hosted-only",
    };
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
  if (!isMapping(permissions)) {
    return false;
  }
  return Object.values(permissions).every((access) => access === "read" || access === "none");
}

// The one exact spelling a local-routing grant admits for a named secret,
// mirroring EXACT_GITHUB_TOKEN_EXPRESSIONS and the allowedSecrets contract
// rule: bracket aliases, case variants, added whitespace, and any transform
// stay outside every grant.
const EXACT_NAMED_SECRET_EXPRESSION = /^\$\{\{ secrets\.([A-Za-z_][A-Za-z0-9_]*) \}\}$/;

function grantedSecretName(value, secretNames) {
  const match = EXACT_NAMED_SECRET_EXPRESSION.exec(value);
  return match !== null && secretNames.has(match[1]) ? match[1] : undefined;
}

function localCredentialRequirement(
  workflow,
  job,
  grantAllowance,
  { admitGitHubToken = false } = {},
) {
  if (containsCredentialExpression(workflow.env)) {
    return "a credential expression in workflow-level env";
  }
  const { steps, if: jobCondition, ...jobWithoutSteps } = job;
  if (conditionContainsCredentialReference(jobCondition)) {
    return "a credential expression in a job condition";
  }
  // A grant admits complete job-level env values under the same exact-
  // expression rules as step env values (a granted write-token job commonly
  // exports its token once at job scope); every other job field keeps the
  // ordinary boundary, and without a grant job-level env stays inside it.
  const { env: jobEnv, ...jobOutsideEnv } = jobWithoutSteps;
  if (
    containsCredentialExpression(grantAllowance === undefined ? jobWithoutSteps : jobOutsideEnv)
  ) {
    return "a credential expression outside a narrow step env/with value";
  }
  const readOnly = hasStaticallyReadOnlyPermissions(workflow, job);
  const credentialMappingRequirement = (mapping) => {
    if (!isMapping(mapping)) {
      if (containsCredentialExpression(mapping)) {
        return "a transformed or indirect credential expression";
      }
      return undefined;
    }
    for (const value of Object.values(mapping)) {
      if (!containsCredentialExpression(value)) {
        continue;
      }
      if (
        typeof value === "string" &&
        EXACT_GITHUB_TOKEN_EXPRESSIONS.has(value) &&
        // A grant pins the job's exact effective permission map, so the
        // GitHub-provided token those permissions describe is admitted even
        // when the pinned map holds a write scope. admitGitHubToken extends
        // the same reasoning to the publication category: the packages-only
        // permission map the exception reviews is exactly the capability the
        // GitHub-provided token carries, so referencing that token adds no
        // credential surface beyond the already-categorized permissions.
        (readOnly || grantAllowance !== undefined || admitGitHubToken)
      ) {
        continue;
      }
      const grantedName =
        grantAllowance !== undefined && typeof value === "string"
          ? grantedSecretName(value, grantAllowance.secretNames)
          : undefined;
      if (grantedName !== undefined) {
        grantAllowance.usedSecretNames.add(grantedName);
        continue;
      }
      return EXACT_GITHUB_TOKEN_EXPRESSIONS.has(value)
        ? "GitHub-provided token use without statically read-only permissions"
        : "an unapproved or transformed credential expression";
    }
    return undefined;
  };
  if (grantAllowance !== undefined && jobEnv !== undefined) {
    const jobEnvRequirement = credentialMappingRequirement(jobEnv);
    if (jobEnvRequirement) {
      return jobEnvRequirement;
    }
  }
  if (!Array.isArray(steps)) {
    return undefined;
  }
  for (const step of steps) {
    if (!isMapping(step)) {
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
      const requirement = credentialMappingRequirement(mapping);
      if (requirement) {
        return requirement;
      }
    }
  }
  return undefined;
}

// Returns the step's full, unmodified `uses:` value (owner/repo action plus
// its `@ref`) when that action is a policy-listed credential-minting action,
// or undefined otherwise. This is the one place that decides whether a step
// mints credentials.
function credentialActionUses(step, policy) {
  if (!isMapping(step)) {
    return undefined;
  }
  if (typeof step.uses !== "string") {
    return undefined;
  }
  const action = step.uses.split("@", 1)[0].toLowerCase();
  return policy.localCredentialActions.has(action) ? step.uses : undefined;
}

function privilegedHostedRequirement(workflow, job, target, policy, localCall, grant, grantUsage) {
  const reusable = reusableWorkflowStatus(job, policy, workflow);
  const reviewedCallerPermissions =
    locallyRoutedTarget(target) &&
    reusable.approved &&
    reusable.contract.allowedCallerPermissions !== undefined;
  // An approved runner-input contract governs the caller's secrets: block the
  // same way an approved hosted-only contract does: reusableWorkflowStatus
  // has already rejected any deviation from the reviewed name-to-expression
  // map, so the generic credential scan omits only that property. This keeps
  // a statically read-only secret-forwarding caller admissible without a
  // caller-permission waiver; allowedCallerPermissions remains the only
  // write-capable waiver.
  const reviewedSecretBoundary = locallyRoutedTarget(target) && reusable.approved;
  // A local-routing grant admits only a directly declared, genuinely
  // fleet-routed job: a fixed hosted target keeps the ordinary privileged
  // rules and exception inventory, mirroring the allowedCallerPermissions
  // waiver's scope. A reusable-call job never takes the grant path — its
  // caller permissions flow into an external workflow whose behavior only the
  // central contract review sees, so
  // allowedCallerPermissions stays the sole write-capable waiver for callers
  // and a grant keyed to such a job surfaces as local-routing-grant-drift.
  const grantApplies =
    grant !== undefined && locallyRoutedTarget(target) && typeof job.uses !== "string";
  // The publication downgrade holds only while packages:write is the job's
  // entire privileged surface: a deployment environment, credential
  // expression, or credential-minting action found below still demands the
  // privileged category, so the weaker requirement is held until every later
  // check passes rather than returned at the permission check. The one
  // admission is the exact GitHub-provided token expression, which carries
  // only the already-categorized packages-only permission map.
  let publicationRequirement;
  if (grantApplies) {
    const permissionError = exactCanonicalMap(
      effectivePermissions(workflow, job),
      grant.permissions,
      {},
      new Set(Object.keys(grant.permissions)),
      "job permissions",
    );
    if (permissionError) {
      return {
        reason: "privileged-control-plane",
        description: `GITHUB_TOKEN permissions outside the reviewed local-routing grant (${permissionError})`,
        rule: "privileged-hosted-only",
      };
    }
  } else {
    const permissionRequirement =
      localCall?.approved || reviewedCallerPermissions
        ? undefined
        : permissionHostedRequirement(workflow, job, {
            requireExplicitReadOnly: locallyRoutedTarget(target),
          });
    if (permissionRequirement?.reason === "publication") {
      publicationRequirement = permissionRequirement;
    } else if (permissionRequirement) {
      return permissionRequirement;
    }
  }

  // Exact hosted-only reusable secret mappings are governed by
  // approvedReusableWorkflowContracts rather than this local-workload
  // boundary. A pending publication downgrade still scans the caller outside
  // that reviewed secrets mapping first: a contract allowlists input names,
  // not values, so a credential expression smuggled through a `with:` value
  // would otherwise ride the weaker category.
  if (target?.kind === "hosted-reusable") {
    if (publicationRequirement === undefined) {
      return undefined;
    }
    const boundaryJob = Object.fromEntries(
      Object.entries(job).filter(([name]) => name !== "secrets"),
    );
    const callerCredentialRequirement = localCredentialRequirement(
      workflow,
      boundaryJob,
      undefined,
      {
        admitGitHubToken: true,
      },
    );
    if (callerCredentialRequirement) {
      return {
        reason: "privileged-control-plane",
        description: callerCredentialRequirement,
        rule: "privileged-hosted-only",
      };
    }
    return publicationRequirement;
  }

  if (
    grantApplies &&
    Object.hasOwn(grant, "environment") &&
    job.environment !== grant.environment
  ) {
    return {
      reason: "privileged-control-plane",
      description:
        "a deployment environment declaration that does not match the reviewed local-routing grant",
      rule: "privileged-hosted-only",
    };
  }
  if (
    Object.hasOwn(job, "environment") &&
    !(grantApplies && job.environment === grant.environment)
  ) {
    return {
      reason: "privileged-control-plane",
      description: grantApplies
        ? "a deployment environment outside the reviewed local-routing grant"
        : "a deployment environment",
      rule: "privileged-hosted-only",
    };
  }

  const credentialJob = reviewedSecretBoundary
    ? Object.fromEntries(Object.entries(job).filter(([name]) => name !== "secrets"))
    : job;
  const grantAllowance = grantApplies
    ? { secretNames: new Set(grant.secrets ?? []), usedSecretNames: new Set() }
    : undefined;
  const credentialRequirement = localCredentialRequirement(
    workflow,
    credentialJob,
    grantAllowance,
    {
      admitGitHubToken: publicationRequirement !== undefined,
    },
  );
  if (credentialRequirement) {
    return {
      reason: "privileged-control-plane",
      description: credentialRequirement,
      rule: "privileged-hosted-only",
    };
  }

  const usedCredentialActions = new Set();
  if (Array.isArray(job.steps)) {
    for (const step of job.steps) {
      const uses = credentialActionUses(step, policy);
      if (uses === undefined) {
        continue;
      }
      // A grant pins the full ref, not the action name: the same action at a
      // different ref is different credential-minting code, which must not
      // reach the fleet on a workflow-only change.
      const reference = uses.toLowerCase();
      if (!(grantApplies && (grant.credentialActions ?? []).includes(reference))) {
        return {
          reason: "privileged-control-plane",
          description: `credential-minting action ${uses.split("@", 1)[0].toLowerCase()}`,
          rule: "privileged-hosted-only",
        };
      }
      usedCredentialActions.add(reference);
    }
  }

  // A named allowance the job never exercises is latent pre-approval: a later
  // workflow-only change could start consuming the secret or minting action
  // without any grant-inventory diff. Report it so the admitted job's surface
  // and the reviewed inventory stay exactly equal.
  if (grantApplies && grantUsage !== undefined) {
    grantUsage.unused = [
      ...(grant.secrets ?? [])
        .filter((name) => !grantAllowance.usedSecretNames.has(name))
        .map((name) => `secret ${name}`),
      ...(grant.credentialActions ?? [])
        .filter((action) => !usedCredentialActions.has(action))
        .map((action) => `credential-minting action ${action}`),
    ];
  }

  return publicationRequirement;
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

function visibilityScopedReusableContractFindings(
  contracts,
  { visibility, repositoryVisibility, policyFile },
) {
  const findings = [];
  for (const [reference, contract] of contracts) {
    if (!VISIBILITY_SCOPED_REUSABLE_WORKFLOW_PATHS.has(reference)) {
      continue;
    }
    const denylistedInputs = [...contract.allowedInputs].filter((name) =>
      PUBLIC_REPOSITORY_DENYLISTED_REUSABLE_INPUTS.has(name),
    );
    const denylistedSecrets = new Set(
      [...contract.allowedSecretNames].filter((name) =>
        PUBLIC_REPOSITORY_DENYLISTED_REUSABLE_SECRETS.has(name),
      ),
    );
    for (const expression of Object.values(contract.allowedSecrets)) {
      const match = EXACT_NAMED_SECRET_EXPRESSION.exec(expression);
      if (match !== null && PUBLIC_REPOSITORY_DENYLISTED_REUSABLE_SECRETS.has(match[1])) {
        denylistedSecrets.add(match[1]);
      }
    }
    if (denylistedInputs.length === 0 && denylistedSecrets.size === 0) {
      continue;
    }
    const listed = [...denylistedInputs, ...denylistedSecrets]
      .sort((left, right) => left.localeCompare(right))
      .join(", ");
    if (!repositoryVisibility) {
      findings.push(
        finding(
          "visibility-evidence-required",
          policyFile,
          undefined,
          `reusable workflow contract ${reference} lists visibility-scoped surface (${listed}); CI_REPOSITORY_VISIBILITY is required`,
        ),
      );
      continue;
    }
    if (visibility === "public") {
      findings.push(
        finding(
          "visibility-scoped-reusable-contract",
          policyFile,
          undefined,
          `reusable workflow contract ${reference} lists visibility-scoped surface (${listed}) while this repository is public; shared contracts cannot enable sensitive inputs for private consumers only`,
        ),
      );
    }
  }
  return findings;
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
    if (!isMapping(job)) {
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
  const policy = { ...basePolicy, repositoryOwner };
  const findings = [];
  const consumedExceptions = new Set();
  const consumedLocalRoutingGrants = new Set();
  const consumedRequiredReusableCallInputs = new Set();
  const workflowIndex = await repositoryWorkflowIndex(resolvedRoot);
  findings.push(
    ...visibilityScopedReusableContractFindings(policy.approvedReusableWorkflowContracts, {
      visibility: config.visibility,
      repositoryVisibility,
      policyFile: path.relative(resolvedRoot, resolvedPolicy) || path.basename(resolvedPolicy),
    }),
  );
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

    for (const [jobId, job] of Object.entries(workflow.jobs)) {
      if (!isMapping(job)) {
        findings.push(finding("job-shape", file, jobId, "job must be a mapping"));
        continue;
      }
      const key = `${file}#${jobId}`;
      const exception = config.exceptions.get(key);
      const grant = config.localRoutingGrants.get(key);
      const requiredCallInputs = config.requiredReusableCallInputs.get(key);
      const localCall = localReusableWorkflowStatus(file, job, policy, workflowIndex);
      const reusable = reusableWorkflowStatus(job, policy, workflow);
      const target = runnerTargetStatus(job, workflow, policy, file, workflowIndex);
      const runnerStrings = rawRunnerStrings(job, true);
      const routingEnabled = config.visibility === "private" && config.selfHostedCi;
      const seedLocalPermissionFlow =
        !isWorkflowCallExclusive(workflow) || !localIncomingFiles.has(file);
      if (routingEnabled && localCall.approved && seedLocalPermissionFlow) {
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
      const grantUsage = grant ? { unused: [] } : undefined;
      const privilegedHosted = routingEnabled
        ? privilegedHostedRequirement(workflow, job, target, policy, localCall, grant, grantUsage)
        : undefined;
      // A held publication downgrade must not mask the structural container
      // categories: a containerized packages-only publisher stays in the
      // job-container/service-container inventory. Privileged requirements
      // keep their ordinary precedence over structural ones.
      const structuralHosted = structuralHostedRequirement(job);
      const hostedRequirement =
        privilegedHosted?.reason === "publication"
          ? (structuralHosted ?? privilegedHosted)
          : (privilegedHosted ?? structuralHosted);
      // Must stay the exact complement of grantApplies: a grant that admits a
      // job but is never marked consumed here fires exception-inventory drift
      // on the same pull request that admitted it.
      if (
        grant &&
        routingEnabled &&
        locallyRoutedTarget(target) &&
        typeof job.uses !== "string" &&
        !hostedRequirement
      ) {
        consumedLocalRoutingGrants.add(key);
        if (grantUsage.unused.length > 0) {
          findings.push(
            finding(
              "local-routing-grant-drift",
              file,
              jobId,
              `local-routing grant ${key} names ${grantUsage.unused.join(", ")} the job does not exercise; remove or narrow it`,
            ),
          );
        }
      }
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

      // macOS runners are free only on a public repository and bill at the
      // macOS rate on a private one, so no private repository may name one,
      // whatever its enrollment, routing or exception inventory says. The
      // visibility here is the event-checked inventory value. A value counts
      // when any token, split on whitespace, commas, brackets and quotes, is
      // shaped like a macOS label, so a JSON array a reusable workflow passes
      // to fromJSON is caught; an expression `runs-on` is left to
      // runner-target-contract.
      if (config.visibility === "private") {
        for (const runner of runnerStrings) {
          if (runner.split(/[\s,[\]"']+/).some((token) => /^macos(-|$)/i.test(token))) {
            findings.push(
              finding(
                "private-macos-runner",
                file,
                jobId,
                `${JSON.stringify(runner.trim())} is a macOS runner, which bills on a private repository; macOS labels are public-only`,
              ),
            );
          }
        }
      }

      for (const runner of runnerStrings) {
        // The one skip is the label this job routes on, and only for that
        // exact string. It is conditioned on routingEnabled so a public or
        // non-enrolled repository still reports the raw pin, and it covers a
        // `with:` runner value as well as a literal `runs-on` because
        // rawRunnerStrings reads both: without that, an approved reusable call
        // whose runner input is the fleet label would report its own admitted
        // target as a raw pin.
        if (routingEnabled && target.kind === "managed-literal" && runner === target.label) {
          continue;
        }
        if (rawManagedLabel(runner, policy)) {
          hasRawManagedLabel = true;
          findings.push(
            finding(
              "raw-self-hosted-label",
              file,
              jobId,
              `raw managed runner target ${JSON.stringify(runner.trim())} is forbidden; name a label from policy.approvedManagedRunnerLabels`,
            ),
          );
        }
      }

      if (
        !target.approved &&
        ((!hasForbiddenHostedLabel && !hasRawManagedLabel) || typeof job.uses === "string")
      ) {
        findings.push(finding("runner-target-contract", file, jobId, target.reason));
      }

      if (requiredCallInputs) {
        // Required inputs govern the cross-repository contract call only. A
        // repository-local wrapper may accept the named input without
        // forwarding it to the reviewed external workflow.
        if (reusable.isReusable && !localCall.isLocal) {
          consumedRequiredReusableCallInputs.add(key);
          const { contract } = reusableWorkflowContract(job.uses, policy);
          if (contract) {
            for (const name of requiredCallInputs.requiredInputs) {
              if (!contract.allowedInputs.has(name)) {
                throw new ConfigurationError(
                  `requiredReusableCallInputs ${key} names input ${name}, which is not in the reviewed contract for ${job.uses}`,
                );
              }
            }
          }
          const inputs = job.with === undefined ? {} : job.with;
          if (!isMapping(inputs)) {
            findings.push(
              finding(
                "required-reusable-call-input",
                file,
                jobId,
                `the reusable workflow call omits repository-required inputs: ${requiredCallInputs.requiredInputs.join(", ")} (configured at ${key})`,
              ),
            );
          } else {
            const missingInputs = requiredCallInputs.requiredInputs.filter(
              (name) => !Object.hasOwn(inputs, name),
            );
            if (missingInputs.length > 0) {
              findings.push(
                finding(
                  "required-reusable-call-input",
                  file,
                  jobId,
                  `the reusable workflow call omits repository-required inputs: ${missingInputs.join(", ")} (configured at ${key})`,
                ),
              );
            }
          }
        }
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
          target.kind !== "hosted-literal" &&
          target.kind !== "hosted-matrix" &&
          target.kind !== "hosted-reusable" &&
          target.kind !== "hosted-local-reusable"
        ) {
          // The suffix is per rule, not shared. A grant never suppresses a
          // structural requirement (THREAT-MODEL.md), so a job container or
          // services on the fleet must not read as if writing one would satisfy
          // it; only the privileged category has a grant as an alternative to an
          // exception.
          findings.push(
            finding(
              hostedRequirement.rule,
              file,
              jobId,
              hostedRequirement.rule === "structural-hosted-only"
                ? `${hostedRequirement.description} cannot use fleet-label routing`
                : `${hostedRequirement.description} requires a reviewed localRoutingGrants entry or a hosted exception`,
            ),
          );
        }
      }

      if (!routingEnabled) {
        if (locallyRoutedTarget(target)) {
          findings.push(
            finding(
              config.visibility === "public"
                ? "public-self-hosted-routing"
                : "self-hosted-routing-disabled",
              file,
              jobId,
              "this repository is not permitted to route work to the managed local-runner fleet",
            ),
          );
        }
        continue;
      }

      // An enrolled private repository may name the governed fleet label
      // directly. Everything that makes such a job privileged has already been
      // reported above through hostedRequirement, so an admitted fleet literal
      // needs no exception entry, unless it is the runner input of a reviewed
      // reusable whose contract records fixedRunsOn: those jobs ignore the
      // input and spend GitHub-hosted minutes, so the call needs an exception.
      if (target.kind === "managed-literal" && target.approved) {
        const fixedRunsOn = reusable.approved ? reusable.contract.fixedRunsOn : undefined;
        if (!fixedRunsOn || hostedRequirement) {
          if (fixedRunsOn && exception) {
            consumedExceptions.add(key);
          }
          continue;
        }
        if (!exception) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `${job.uses} runs jobs on GitHub-hosted ${[...fixedRunsOn].join(", ")} whatever runner it is given; declare ${key} in .github/runner-policy.json`,
            ),
          );
          continue;
        }
        consumedExceptions.add(key);
        // The fixed jobs run hosted, so the exception takes the category the
        // same call would need with a hosted runner input.
        const hostedCall = privilegedHostedRequirement(
          workflow,
          job,
          { kind: "hosted-reusable" },
          policy,
        );
        const requiredReason =
          hostedCall?.reason === "publication"
            ? (structuralHosted ?? hostedCall).reason
            : (hostedCall ?? structuralHosted)?.reason;
        if (requiredReason && exception.reason !== requiredReason) {
          findings.push(
            finding(
              "hosted-exception-category",
              file,
              jobId,
              `${job.uses} runs jobs on GitHub-hosted ${[...fixedRunsOn].join(", ")} and requires exception reason ${requiredReason}, not ${exception.reason}`,
            ),
          );
        }
        continue;
      }
      if (target.kind === "reusable-input") {
        continue;
      }
      if (target.kind === "hosted-local-reusable" || target.kind === "transparent-local-reusable") {
        continue;
      }
      if (target.kind === "invalid") {
        if (exception) {
          consumedExceptions.add(key);
        } else if (!hostedRequirement) {
          findings.push(
            finding(
              "hosted-exception-required",
              file,
              jobId,
              `eligible private job must name the governed fleet label or declare ${key} in .github/runner-policy.json`,
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
            `eligible private job must name the governed fleet label or declare ${key} in .github/runner-policy.json`,
          ),
        );
      } else if (exception) {
        consumedExceptions.add(key);
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

  for (const key of config.localRoutingGrants.keys()) {
    if (!consumedLocalRoutingGrants.has(key)) {
      findings.push(
        finding(
          "local-routing-grant-drift",
          key.split("#", 1)[0],
          key.includes("#") ? key.slice(key.indexOf("#") + 1) : undefined,
          `configured local-routing grant ${key} is unused; remove or correct it`,
        ),
      );
    }
  }

  for (const key of config.requiredReusableCallInputs.keys()) {
    if (!consumedRequiredReusableCallInputs.has(key)) {
      findings.push(
        finding(
          "required-reusable-call-input-drift",
          key.split("#", 1)[0],
          key.includes("#") ? key.slice(key.indexOf("#") + 1) : undefined,
          `configured requiredReusableCallInputs entry ${key} is unused; remove or correct it`,
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

export function parseArguments(argv, environment = process.env) {
  try {
    const { values } = parseArgs({
      args: argv,
      allowPositionals: false,
      options: {
        config: { default: DEFAULT_CONFIG_PATH, type: "string" },
        json: { default: false, type: "boolean" },
        policy: { default: DEFAULT_POLICY_PATH, type: "string" },
        "repository-visibility": { type: "string" },
        root: { default: process.cwd(), type: "string" },
      },
      strict: true,
    });
    return {
      root: values.root,
      configPath: values.config,
      policyPath: values.policy,
      repositoryVisibility: values["repository-visibility"] ?? environment.CI_REPOSITORY_VISIBILITY,
      githubRepository: environment.GITHUB_REPOSITORY,
      json: values.json,
    };
  } catch (error) {
    throw new ConfigurationError(error instanceof Error ? error.message : String(error));
  }
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
