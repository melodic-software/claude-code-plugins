// Parses a $GITHUB_OUTPUT file in the two forms the runner documents:
// `name=value` and the multiline `name<<DELIMITER` ... `DELIMITER` block.
export function readOutputs(text) {
  const outputs = {};
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === "") {
      continue;
    }
    const heredoc = line.match(/^([^=<]+)<<(.+)$/);
    if (heredoc) {
      const [, name, delimiter] = heredoc;
      const body = [];
      index += 1;
      while (index < lines.length && lines[index] !== delimiter) {
        body.push(lines[index]);
        index += 1;
      }
      if (index >= lines.length) {
        throw new Error(`unterminated output ${name}`);
      }
      outputs[name] = body.join("\n");
      continue;
    }
    const separator = line.indexOf("=");
    outputs[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return outputs;
}
