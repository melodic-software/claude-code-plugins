/** MCP stdio transport: diagnostics only on stderr (never stdout / console). */
export function writeStderr(message: string): void {
  process.stderr.write(`${message}\n`);
}
