# Python security checklist

Loaded on demand by this plugin's `security-reviewer` agent when the change set touches Python
code. The OWASP table and the cross-ecosystem list in the agent body are the floor for every
review; these are the ecosystem-specific additions that floor does not cover.

- **Injection**: `subprocess` with `shell=True`, `eval()`, `exec()`, `pickle.loads()` on untrusted data
- **Path traversal**: unvalidated user input in `os.path.join`
- **Dependency confusion**: private package index configuration
