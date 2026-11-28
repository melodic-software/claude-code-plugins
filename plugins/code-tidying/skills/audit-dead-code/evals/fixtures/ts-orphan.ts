export function parseLegacyManifest(text: string): string[] {
  return text.split("\n").filter((line) => line.length > 0);
}
