export const MARKER = "conflict-record ";
const SHA = /^[0-9a-f]{40}$/;
// GitHub caps check-run output.text at 65,535 characters: https://docs.github.com/en/rest/checks/runs#create-a-check-run
export const MAX_LENGTH = 16_384;

export const recordLine = (record) => `${MARKER}${JSON.stringify(record)}`;

export function conflictRecord(base, paths) {
  if (!SHA.test(String(base ?? "")) || !Array.isArray(paths) || paths.length === 0 || !paths.every((path) => typeof path === "string" && path !== "")) {
    return null;
  }
  const record = { base, paths: [...paths] };
  return recordLine(record).length <= MAX_LENGTH ? record : null;
}

export function readConflictRecord(text) {
  const line = String(text ?? "")
    .split("\n")
    .find((row) => row.startsWith(MARKER));
  if (line === undefined) {
    return null;
  }
  try {
    const parsed = JSON.parse(line.slice(MARKER.length));
    return conflictRecord(parsed?.base, parsed?.paths);
  } catch {
    return null;
  }
}
