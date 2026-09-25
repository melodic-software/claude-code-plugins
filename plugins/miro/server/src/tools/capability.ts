// Narrows the SDK's board-item union to members carrying `method` as a callable, so a tool
// can reject an item kind it cannot handle before calling into it.
export function hasCapability<T, K extends PropertyKey>(
  value: T,
  method: K,
): value is Extract<T, Record<K, (...args: never[]) => unknown>> {
  return method in (value as object) && typeof (value as Record<K, unknown>)[method] === "function";
}
