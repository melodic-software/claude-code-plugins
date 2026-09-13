# Bash/Shell security checklist

Loaded on demand by this plugin's `security-reviewer` agent when the change set touches shell
scripts. The OWASP table and the cross-ecosystem list in the agent body are the floor for every
review; these are the ecosystem-specific additions that floor does not cover.

- **Command injection**: unquoted variables in command arguments, `eval` with user input
- **Path injection**: glob expansion of untrusted filenames
- **Secrets in logs**: tokens echoed to stdout/stderr
